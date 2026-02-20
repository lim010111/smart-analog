from __future__ import annotations

import base64
import datetime as dt
import importlib
import os
import tempfile
import uuid
from dataclasses import asdict, dataclass
from pathlib import Path

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import Response
from pydantic import BaseModel, Field

from src.services.ai.briefing import AITodayBriefingService
from src.services.ai.color_schema import ColorRule
from src.services.calendar import CalendarService
from src.services.providers.apple_provider import AppleCalendarProvider
from src.services.providers.google_provider import GoogleCalendarProvider


@dataclass
class WebEvent:
    id: str
    summary: str
    description: str
    start_time: str
    end_time: str
    all_day: bool
    color_hex: str
    provider_color_id: str | None


class NaturalInputRequest(BaseModel):
    text: str = Field(min_length=1, max_length=500)


class CreateEventRequest(BaseModel):
    summary: str = Field(min_length=1, max_length=200)
    start_time: str
    end_time: str
    all_day: bool = False


class ColorRulePayload(BaseModel):
    color_hex: str = Field(min_length=4, max_length=9)
    label: str = Field(min_length=1, max_length=80)
    keywords: list[str] = Field(default_factory=list)


class ColorSchemaRequest(BaseModel):
    rules: list[ColorRulePayload] = Field(default_factory=list)


class BriefingTTSRequest(BaseModel):
    text: str = Field(min_length=1, max_length=2000)
    voice: str | None = None
    model: str | None = None
    instructions: str | None = None
    response_format: str = "wav"


class AppleCredentialsRequest(BaseModel):
    apple_id: str = Field(min_length=3, max_length=200)
    app_password: str = Field(min_length=3, max_length=200)


class WebSettingsRequest(BaseModel):
    theme: str = Field(default="dark")
    event_opacity: int = Field(default=150, ge=0, le=255)
    briefing_enabled: bool = True
    briefing_tts_enabled: bool = False
    widget_pinned: bool = True


WEB_SETTINGS: dict[str, object] = {
    "theme": os.getenv("WEB_THEME_DEFAULT", "dark"),
    "event_opacity": 150,
    "briefing_enabled": True,
    "briefing_tts_enabled": False,
    "widget_pinned": True,
}


def _to_web_event(event) -> WebEvent:
    color_name = ""
    try:
        color_name = event.color.name()
    except Exception:
        color_name = ""

    return WebEvent(
        id=event.id,
        summary=event.summary,
        description=event.description,
        start_time=event.start_time.isoformat(),
        end_time=event.end_time.isoformat(),
        all_day=event.all_day,
        color_hex=color_name,
        provider_color_id=event.provider_color_id,
    )


def _build_calendar_service(provider: str) -> CalendarService:
    service = CalendarService()
    service.set_active_provider(provider)
    return service


def _normalize_theme(value: str) -> str:
    lowered = str(value).strip().lower()
    if lowered in {"dark", "light"}:
        return lowered
    return "dark"


def _require_provider_credentials(calendar: CalendarService) -> None:
    provider = calendar.active_provider
    if provider is None:
        raise HTTPException(
            status_code=400, detail="활성화된 캘린더 제공자가 없습니다."
        )

    if isinstance(provider, GoogleCalendarProvider):
        token_path = str(getattr(provider, "token_path", "token.json"))
        if not os.path.exists(token_path):
            raise HTTPException(
                status_code=401,
                detail="Google 캘린더 인증이 필요합니다. 먼저 캘린더 인증을 진행해주세요.",
            )

    if (
        isinstance(provider, AppleCalendarProvider)
        and not provider.has_saved_credentials()
    ):
        raise HTTPException(
            status_code=401,
            detail="Apple 자격증명이 없습니다. 먼저 Apple 자격증명을 저장해주세요.",
        )


def _allowed_origins() -> list[str]:
    raw = os.getenv("WEB_CORS_ORIGINS", "http://localhost:3000")
    return [origin.strip() for origin in raw.split(",") if origin.strip()]


def _parse_iso_datetime(value: str) -> dt.datetime:
    text = str(value).strip()
    if not text:
        raise ValueError("날짜/시간 값이 필요합니다.")
    if text.endswith("Z"):
        text = f"{text[:-1]}+00:00"
    parsed = dt.datetime.fromisoformat(text)
    if parsed.tzinfo is None:
        local_tz = dt.datetime.now().astimezone().tzinfo
        if local_tz is None:
            local_tz = dt.timezone.utc
        parsed = parsed.replace(tzinfo=local_tz)
    return parsed.astimezone()


def _normalize_response_format(value: str) -> str:
    normalized = str(value).strip().lower()
    if normalized in {"wav", "mp3", "opus", "aac", "flac"}:
        return normalized
    return "wav"


def _mime_type_for_audio(fmt: str) -> str:
    if fmt == "mp3":
        return "audio/mpeg"
    if fmt == "wav":
        return "audio/wav"
    if fmt == "opus":
        return "audio/ogg"
    if fmt == "aac":
        return "audio/aac"
    if fmt == "flac":
        return "audio/flac"
    return "application/octet-stream"


def _synthesize_openai_tts(payload: BriefingTTSRequest) -> tuple[bytes, str]:
    api_key = os.getenv("OPENAI_API_KEY", "").strip()
    if not api_key:
        raise HTTPException(
            status_code=400,
            detail="OPENAI_API_KEY가 설정되지 않았습니다.",
        )

    fmt = _normalize_response_format(payload.response_format)
    timeout = float(os.getenv("OPENAI_TTS_TIMEOUT", "15") or "15")
    model = (
        str(payload.model or "").strip()
        or os.getenv("OPENAI_TTS_MODEL", "gpt-4o-mini-tts").strip()
        or "gpt-4o-mini-tts"
    )
    voice = (
        str(payload.voice or "").strip()
        or os.getenv("OPENAI_TTS_VOICE", "marin").strip()
        or "marin"
    )
    instructions = str(payload.instructions or "").strip()

    try:
        module = importlib.import_module("open" + "ai")
        openai_cls = getattr(module, "OpenAI")
        client = openai_cls(api_key=api_key, timeout=timeout)
    except Exception as error:
        raise HTTPException(
            status_code=500,
            detail=f"OpenAI 클라이언트 초기화에 실패했습니다: {error}",
        ) from error

    tmp_dir = Path(tempfile.gettempdir()) / "clock_widget_web_tts"
    tmp_dir.mkdir(parents=True, exist_ok=True)
    tmp_path = tmp_dir / f"tts_{uuid.uuid4().hex}.{fmt}"

    try:
        request_payload: dict[str, object] = {
            "model": model,
            "voice": voice,
            "input": payload.text,
            "response_format": fmt,
        }
        if instructions:
            request_payload["instructions"] = instructions

        with client.audio.speech.with_streaming_response.create(
            **request_payload,
        ) as response:
            response.stream_to_file(tmp_path)

        audio_bytes = tmp_path.read_bytes()
        if not audio_bytes:
            raise HTTPException(
                status_code=500, detail="생성된 TTS 오디오가 비어 있습니다."
            )
        return (audio_bytes, fmt)
    except HTTPException:
        raise
    except Exception as error:
        raise HTTPException(
            status_code=500,
            detail=f"OpenAI TTS 생성에 실패했습니다: {error}",
        ) from error
    finally:
        try:
            tmp_path.unlink(missing_ok=True)
        except Exception:
            pass


app = FastAPI(title="Clock Widget 웹 API", version="0.2.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=_allowed_origins(),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/api/providers")
def providers() -> dict[str, object]:
    return {
        "default_provider": os.getenv("WEB_DEFAULT_PROVIDER", "google"),
        "providers": ["google", "apple"],
    }


@app.get("/api/providers/status")
def provider_status(
    provider: str = Query(default=os.getenv("WEB_DEFAULT_PROVIDER", "google")),
) -> dict[str, object]:
    try:
        calendar = _build_calendar_service(provider)
        active = calendar.active_provider
        if isinstance(active, GoogleCalendarProvider):
            token_path = str(getattr(active, "token_path", "token.json"))
            authenticated = os.path.exists(token_path)
        elif isinstance(active, AppleCalendarProvider):
            authenticated = active.has_saved_credentials()
        else:
            authenticated = False
    except Exception:
        authenticated = False
    return {
        "provider": provider,
        "authenticated": authenticated,
    }


@app.post("/api/providers/authenticate")
def authenticate_provider(
    provider: str = Query(default=os.getenv("WEB_DEFAULT_PROVIDER", "google")),
) -> dict[str, object]:
    try:
        calendar = _build_calendar_service(provider)
        calendar.authenticate()
        return {
            "provider": provider,
            "authenticated": True,
        }
    except Exception as error:
        raise HTTPException(status_code=400, detail=str(error)) from error


@app.post("/api/providers/apple/credentials")
def set_apple_credentials(request: AppleCredentialsRequest) -> dict[str, object]:
    try:
        calendar = _build_calendar_service("apple")
        provider = calendar.active_provider
        if not isinstance(provider, AppleCalendarProvider):
            raise HTTPException(
                status_code=500, detail="Apple 제공자가 활성화되어 있지 않습니다."
            )
        provider.set_credentials(request.apple_id, request.app_password)
        provider.authenticate()
        return {
            "provider": "apple",
            "authenticated": True,
        }
    except HTTPException:
        raise
    except Exception as error:
        raise HTTPException(status_code=400, detail=str(error)) from error


@app.post("/api/providers/logout")
def logout_provider(
    provider: str = Query(default=os.getenv("WEB_DEFAULT_PROVIDER", "google")),
) -> dict[str, object]:
    try:
        calendar = _build_calendar_service(provider)
        calendar.logout()
        return {
            "provider": provider,
            "logged_out": True,
        }
    except Exception as error:
        raise HTTPException(status_code=400, detail=str(error)) from error


@app.get("/api/settings")
def get_settings() -> dict[str, object]:
    return {
        "theme": WEB_SETTINGS["theme"],
        "event_opacity": WEB_SETTINGS["event_opacity"],
        "briefing_enabled": WEB_SETTINGS["briefing_enabled"],
        "briefing_tts_enabled": WEB_SETTINGS["briefing_tts_enabled"],
        "widget_pinned": WEB_SETTINGS["widget_pinned"],
    }


@app.put("/api/settings")
def update_settings(request: WebSettingsRequest) -> dict[str, object]:
    WEB_SETTINGS["theme"] = _normalize_theme(request.theme)
    WEB_SETTINGS["event_opacity"] = int(request.event_opacity)
    WEB_SETTINGS["briefing_enabled"] = bool(request.briefing_enabled)
    WEB_SETTINGS["briefing_tts_enabled"] = bool(request.briefing_tts_enabled)
    WEB_SETTINGS["widget_pinned"] = bool(request.widget_pinned)
    return get_settings()


@app.get("/api/events/today")
def today_events(
    provider: str = Query(default=os.getenv("WEB_DEFAULT_PROVIDER", "google")),
    max_results: int = Query(default=20, ge=1, le=200),
) -> dict[str, object]:
    try:
        calendar = _build_calendar_service(provider)
        _require_provider_credentials(calendar)
        events = calendar.get_todays_events(max_results=max_results)
        payload = [asdict(_to_web_event(event)) for event in events]
        return {
            "provider": provider,
            "date": dt.date.today().isoformat(),
            "count": len(payload),
            "events": payload,
        }
    except HTTPException:
        raise
    except ValueError as error:
        raise HTTPException(status_code=401, detail=str(error)) from error
    except Exception as error:
        raise HTTPException(status_code=500, detail=str(error)) from error


@app.post("/api/events/create")
def create_event(
    request: CreateEventRequest,
    provider: str = Query(default=os.getenv("WEB_DEFAULT_PROVIDER", "google")),
) -> dict[str, object]:
    try:
        start_time = _parse_iso_datetime(request.start_time)
        end_time = _parse_iso_datetime(request.end_time)
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error

    try:
        calendar = _build_calendar_service(provider)
        _require_provider_credentials(calendar)
        if not calendar.can_create_events():
            raise HTTPException(
                status_code=400,
                detail=f"제공자 '{provider}'는 일정 생성을 지원하지 않습니다.",
            )

        created = calendar.active_provider.create_event(
            summary=request.summary,
            start_time=start_time,
            end_time=end_time,
            all_day=request.all_day,
        )
        if not created:
            raise HTTPException(status_code=500, detail="일정 생성에 실패했습니다.")

        return {
            "provider": provider,
            "event": asdict(_to_web_event(created)),
        }
    except HTTPException:
        raise
    except ValueError as error:
        raise HTTPException(status_code=401, detail=str(error)) from error
    except Exception as error:
        raise HTTPException(status_code=500, detail=str(error)) from error


@app.post("/api/events/natural-input/parse")
def parse_natural_input(
    request: NaturalInputRequest,
    provider: str = Query(default=os.getenv("WEB_DEFAULT_PROVIDER", "google")),
) -> dict[str, object]:
    try:
        calendar = _build_calendar_service(provider)
        parser = calendar.ai_natural_input_service
        if not parser.is_ready():
            return {
                "provider": provider,
                "ready": False,
                "reason": parser.get_unavailable_reason(),
                "result": None,
            }

        result = parser.parse(request.text)
        if not result:
            return {
                "provider": provider,
                "ready": True,
                "result": None,
            }

        return {
            "provider": provider,
            "ready": True,
            "result": {
                "intent": result.intent,
                "title": result.title,
                "start_time": (
                    result.start_time.isoformat() if result.start_time else None
                ),
                "end_time": result.end_time.isoformat() if result.end_time else None,
                "all_day": result.all_day,
                "confidence": result.confidence,
                "note": result.note,
                "raw": result.raw,
            },
        }
    except Exception as error:
        raise HTTPException(status_code=500, detail=str(error)) from error


@app.post("/api/events/natural-input/create")
def create_event_from_natural_input(
    request: NaturalInputRequest,
    provider: str = Query(default=os.getenv("WEB_DEFAULT_PROVIDER", "google")),
) -> dict[str, object]:
    try:
        calendar = _build_calendar_service(provider)
        _require_provider_credentials(calendar)
        parser = calendar.ai_natural_input_service
        if not parser.is_ready():
            raise HTTPException(
                status_code=400,
                detail=parser.get_unavailable_reason(),
            )

        parsed = parser.parse(request.text)
        if not parsed:
            raise HTTPException(
                status_code=400, detail="자연어 입력 파싱에 실패했습니다."
            )

        created = calendar.create_event_from_natural_input(parsed)
        if not created:
            return {
                "provider": provider,
                "parsed": {
                    "intent": parsed.intent,
                    "title": parsed.title,
                    "start_time": (
                        parsed.start_time.isoformat() if parsed.start_time else None
                    ),
                    "end_time": parsed.end_time.isoformat()
                    if parsed.end_time
                    else None,
                    "all_day": parsed.all_day,
                    "confidence": parsed.confidence,
                    "note": parsed.note,
                },
                "created": None,
            }

        return {
            "provider": provider,
            "parsed": {
                "intent": parsed.intent,
                "title": parsed.title,
                "start_time": (
                    parsed.start_time.isoformat() if parsed.start_time else None
                ),
                "end_time": parsed.end_time.isoformat() if parsed.end_time else None,
                "all_day": parsed.all_day,
                "confidence": parsed.confidence,
                "note": parsed.note,
            },
            "created": asdict(_to_web_event(created)),
        }
    except HTTPException:
        raise
    except ValueError as error:
        raise HTTPException(status_code=401, detail=str(error)) from error
    except Exception as error:
        raise HTTPException(status_code=500, detail=str(error)) from error


@app.get("/api/briefing/today")
def today_briefing(
    provider: str = Query(default=os.getenv("WEB_DEFAULT_PROVIDER", "google")),
    max_results: int = Query(default=20, ge=1, le=200),
    force: bool = Query(default=True),
) -> dict[str, object]:
    try:
        if not bool(WEB_SETTINGS["briefing_enabled"]):
            return {
                "provider": provider,
                "generated_at": dt.datetime.now().astimezone().isoformat(),
                "briefing": "",
                "event_count": 0,
                "disabled": True,
            }

        calendar = _build_calendar_service(provider)
        _require_provider_credentials(calendar)
        events = calendar.get_todays_events(max_results=max_results)

        briefing_service = AITodayBriefingService()
        text = briefing_service.generate_today_briefing(
            events,
            now=dt.datetime.now().astimezone(),
            force=force,
        )

        return {
            "provider": provider,
            "generated_at": dt.datetime.now().astimezone().isoformat(),
            "briefing": text,
            "event_count": len(events),
        }
    except HTTPException:
        raise
    except ValueError as error:
        raise HTTPException(status_code=401, detail=str(error)) from error
    except Exception as error:
        raise HTTPException(status_code=500, detail=str(error)) from error


@app.post("/api/briefing/tts")
def briefing_tts(request: BriefingTTSRequest) -> Response:
    if not bool(WEB_SETTINGS["briefing_tts_enabled"]):
        raise HTTPException(
            status_code=400, detail="설정에서 브리핑 TTS가 비활성화되어 있습니다."
        )
    audio_bytes, fmt = _synthesize_openai_tts(request)
    return Response(
        content=audio_bytes,
        media_type=_mime_type_for_audio(fmt),
        headers={"Content-Disposition": f"inline; filename=briefing.{fmt}"},
    )


@app.post("/api/briefing/tts/base64")
def briefing_tts_base64(request: BriefingTTSRequest) -> dict[str, str]:
    if not bool(WEB_SETTINGS["briefing_tts_enabled"]):
        raise HTTPException(
            status_code=400, detail="설정에서 브리핑 TTS가 비활성화되어 있습니다."
        )
    audio_bytes, fmt = _synthesize_openai_tts(request)
    encoded = base64.b64encode(audio_bytes).decode("ascii")
    return {
        "audio_base64": encoded,
        "format": fmt,
        "mime_type": _mime_type_for_audio(fmt),
    }


@app.get("/api/colors/palette")
def color_palette(
    provider: str = Query(default=os.getenv("WEB_DEFAULT_PROVIDER", "google")),
) -> dict[str, object]:
    try:
        calendar = _build_calendar_service(provider)
        _require_provider_credentials(calendar)
        return {
            "provider": provider,
            "can_write": calendar.can_write_event_colors(),
            "palette": calendar.get_supported_ai_colors(),
        }
    except HTTPException:
        raise
    except ValueError as error:
        raise HTTPException(status_code=401, detail=str(error)) from error
    except Exception as error:
        raise HTTPException(status_code=500, detail=str(error)) from error


@app.get("/api/colors/schema")
def get_color_schema(
    provider: str = Query(default=os.getenv("WEB_DEFAULT_PROVIDER", "google")),
) -> dict[str, object]:
    try:
        calendar = _build_calendar_service(provider)
        _require_provider_credentials(calendar)
        service = calendar.ai_event_color_service
        service.reload_schema()
        return {
            "provider": provider,
            "rules": [
                {
                    "color_hex": rule.color_hex,
                    "label": rule.label,
                    "keywords": rule.keywords,
                }
                for rule in service.custom_schema.rules
            ],
        }
    except HTTPException:
        raise
    except ValueError as error:
        raise HTTPException(status_code=401, detail=str(error)) from error
    except Exception as error:
        raise HTTPException(status_code=500, detail=str(error)) from error


@app.put("/api/colors/schema")
def update_color_schema(
    request: ColorSchemaRequest,
    provider: str = Query(default=os.getenv("WEB_DEFAULT_PROVIDER", "google")),
) -> dict[str, object]:
    try:
        calendar = _build_calendar_service(provider)
        _require_provider_credentials(calendar)
        service = calendar.ai_event_color_service

        rules: list[ColorRule] = []
        for item in request.rules:
            rules.append(
                ColorRule(
                    color_hex=item.color_hex.strip().lower(),
                    label=item.label.strip(),
                    keywords=[kw.strip().lower() for kw in item.keywords if kw.strip()],
                )
            )

        service.custom_schema.rules = rules
        service.custom_schema.save()
        service.reload_schema()

        return {
            "provider": provider,
            "saved_count": len(service.custom_schema.rules),
        }
    except HTTPException:
        raise
    except ValueError as error:
        raise HTTPException(status_code=401, detail=str(error)) from error
    except Exception as error:
        raise HTTPException(status_code=500, detail=str(error)) from error


@app.post("/api/colors/apply-all")
def apply_colors_all(
    provider: str = Query(default=os.getenv("WEB_DEFAULT_PROVIDER", "google")),
    max_results: int | None = Query(default=None, ge=1),
    page_size: int = Query(default=250, ge=1, le=2500),
) -> dict[str, object]:
    try:
        calendar = _build_calendar_service(provider)
        _require_provider_credentials(calendar)
        if not calendar.can_write_event_colors():
            raise HTTPException(
                status_code=400,
                detail=f"제공자 '{provider}'는 일정 색상 쓰기를 지원하지 않습니다.",
            )

        total, updated = calendar.sync_ai_colors_for_all_events(
            max_results=max_results,
            page_size=page_size,
            throttle_seconds=0.05,
        )
        return {
            "provider": provider,
            "processed": total,
            "updated": updated,
        }
    except HTTPException:
        raise
    except ValueError as error:
        raise HTTPException(status_code=401, detail=str(error)) from error
    except Exception as error:
        raise HTTPException(status_code=500, detail=str(error)) from error
