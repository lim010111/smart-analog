from __future__ import annotations

import src.compat.qt_stub  # noqa: F401 - PySide6 headless stubs

import base64
import datetime as dt
import importlib
import os
import pickle
import tempfile
import threading
import time
import uuid
from contextlib import contextmanager
from urllib.parse import urlsplit
from dataclasses import asdict, dataclass
from pathlib import Path

from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, Response
from google_auth_oauthlib.flow import Flow
from pydantic import BaseModel, Field

from src.services.ai.briefing import AITodayBriefingService
from src.services.ai.color_schema import ColorRule
from src.services.calendar import CalendarService
from src.services.providers.apple_provider import AppleCalendarProvider
from src.services.providers.google_provider import (
    SCOPES as GOOGLE_SCOPES,
    GoogleCalendarProvider,
)


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
    clock_opacity: int = Field(default=100, ge=0, le=100)
    briefing_enabled: bool = True
    briefing_tts_enabled: bool = False
    widget_pinned: bool = True


WEB_SETTINGS: dict[str, object] = {
    "theme": os.getenv("WEB_THEME_DEFAULT", "dark"),
    "event_opacity": 150,
    "clock_opacity": 100,
    "briefing_enabled": True,
    "briefing_tts_enabled": False,
    "widget_pinned": True,
}

GOOGLE_OAUTH_PENDING: dict[str, tuple[str, float]] = {}
GOOGLE_OAUTH_TTL_SECONDS = 600
OAUTHLIB_TRANSPORT_LOCK = threading.RLock()

ColorApplyValue = bool | int | float | str | None

COLOR_APPLY_LOCK = threading.Lock()
COLOR_APPLY_STATE: dict[str, dict[str, ColorApplyValue]] = {}


def _get_color_apply_state(provider: str) -> dict[str, ColorApplyValue]:
    if provider in COLOR_APPLY_STATE:
        return COLOR_APPLY_STATE[provider]

    state: dict[str, ColorApplyValue] = {
        "running": False,
        "rerun_requested": False,
        "last_started_at": None,
        "last_finished_at": None,
        "last_processed": 0,
        "last_updated": 0,
        "last_error": "",
    }
    COLOR_APPLY_STATE[provider] = state
    return state


def _day_range_local(target_date: dt.date) -> tuple[dt.datetime, dt.datetime]:
    local_tz = dt.datetime.now().astimezone().tzinfo
    if local_tz is None:
        local_tz = dt.timezone.utc
    start_of_day = dt.datetime.combine(target_date, dt.time.min, tzinfo=local_tz)
    end_of_day = dt.datetime.combine(target_date, dt.time.max, tzinfo=local_tz)
    return start_of_day, end_of_day


def _today_range_local() -> tuple[dt.datetime, dt.datetime]:
    return _day_range_local(dt.datetime.now().astimezone().date())


def _run_background_color_apply(
    provider: str,
    max_results: int | None,
    page_size: int,
) -> None:
    while True:
        processed = 0
        updated = 0
        error_text = ""

        try:
            calendar = _build_calendar_service(provider)
            _require_provider_credentials(calendar)
            if calendar.can_write_event_colors():
                processed, updated = calendar.sync_ai_colors_for_all_events(
                    max_results=max_results,
                    page_size=page_size,
                    throttle_seconds=0.05,
                )
        except Exception as error:
            error_text = str(error)

        with COLOR_APPLY_LOCK:
            state = _get_color_apply_state(provider)
            state["last_processed"] = int(processed)
            state["last_updated"] = int(updated)
            state["last_error"] = error_text
            state["last_finished_at"] = time.time()

            rerun_requested = bool(state.get("rerun_requested"))
            if not rerun_requested:
                state["running"] = False
                return

            state["rerun_requested"] = False
            state["last_started_at"] = time.time()


def _start_or_queue_background_color_apply(
    provider: str,
    max_results: int | None,
    page_size: int,
) -> dict[str, bool]:
    with COLOR_APPLY_LOCK:
        state = _get_color_apply_state(provider)
        if bool(state.get("running")):
            state["rerun_requested"] = True
            return {
                "background_started": False,
                "background_queued": True,
            }

        state["running"] = True
        state["rerun_requested"] = False
        state["last_error"] = ""
        state["last_started_at"] = time.time()

    worker = threading.Thread(
        target=_run_background_color_apply,
        args=(provider, max_results, page_size),
        daemon=True,
        name=f"color-apply-{provider}",
    )
    worker.start()

    return {
        "background_started": True,
        "background_queued": False,
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


def _cleanup_google_oauth_pending() -> None:
    now = time.time()
    expired = [
        state
        for state, (_, created_at) in GOOGLE_OAUTH_PENDING.items()
        if now - created_at > GOOGLE_OAUTH_TTL_SECONDS
    ]
    for state in expired:
        GOOGLE_OAUTH_PENDING.pop(state, None)


def _google_client_id() -> str:
    value = os.getenv("GOOGLE_CLIENT_ID", "").strip()
    if value:
        return value
    raise HTTPException(
        status_code=400, detail="GOOGLE_CLIENT_ID가 설정되지 않았습니다."
    )


def _google_client_secret() -> str:
    value = os.getenv("GOOGLE_CLIENT_SECRET", "").strip()
    if value:
        return value
    raise HTTPException(
        status_code=400,
        detail="GOOGLE_CLIENT_SECRET이 설정되지 않았습니다.",
    )


def _google_project_id() -> str:
    value = os.getenv("GOOGLE_PROJECT_ID", "").strip()
    if value:
        return value
    return "calendar-analog-clock-web"


def _build_google_redirect_uri(request: Request) -> str:
    explicit = os.getenv("WEB_GOOGLE_REDIRECT_URI", "").strip()
    if explicit:
        return explicit

    host = (
        os.getenv("WEB_PUBLIC_HOST", "").strip()
        or request.headers.get("x-forwarded-host", "").strip()
        or request.headers.get("host", "").strip()
        or request.url.netloc
    )
    proto = (
        os.getenv("WEB_PUBLIC_SCHEME", "").strip()
        or request.headers.get("x-forwarded-proto", "").strip()
        or request.url.scheme
    )
    if not host:
        raise HTTPException(
            status_code=400,
            detail="공개 호스트를 확인할 수 없습니다. WEB_PUBLIC_HOST를 설정해주세요.",
        )
    host = _normalize_host(host)
    if proto == "http" and not _is_localhost_host(host):
        proto = "https"
    return f"{proto}://{host}/api/providers/google/callback"


def _normalize_host(raw_host: str) -> str:
    host = str(raw_host or "").strip()
    if not host:
        return ""

    # Fly/Load balancer can send Host like "example.com, proxy.internal".
    host = host.split(",", 1)[0].strip()

    # Strip default ports to avoid strict matching mismatch with Google OAuth
    if host.startswith("["):
        # IPv6 host like [2001:db8::1]:443
        if host.count("]") == 1 and host.endswith("]"):
            return host
        if "]:" in host:
            base, port = host.rsplit(":", 1)
            if port in {"80", "443"}:
                return base
            return host
        return host

    if ":" in host:
        base, port = host.rsplit(":", 1)
        if port in {"80", "443"}:
            return base
    return host


def _is_localhost_host(host: str) -> bool:
    normalized = _normalize_host(host)
    candidate = normalized

    if candidate.startswith("[") and "]" in candidate:
        candidate = candidate[1 : candidate.index("]")]
    elif ":" in candidate and candidate.count(":") == 1:
        candidate = candidate.split(":", 1)[0]

    return candidate in {"localhost", "127.0.0.1", "::1"}


def _is_local_insecure_redirect_uri(redirect_uri: str) -> bool:
    parsed = urlsplit(str(redirect_uri).strip())
    host = parsed.hostname or ""
    return parsed.scheme == "http" and _is_localhost_host(host)


@contextmanager
def _oauthlib_local_insecure_transport(redirect_uri: str):
    if not _is_local_insecure_redirect_uri(redirect_uri):
        yield
        return

    with OAUTHLIB_TRANSPORT_LOCK:
        previous = os.environ.get("OAUTHLIB_INSECURE_TRANSPORT")
        os.environ["OAUTHLIB_INSECURE_TRANSPORT"] = "1"
        try:
            yield
        finally:
            if previous is None:
                os.environ.pop("OAUTHLIB_INSECURE_TRANSPORT", None)
            else:
                os.environ["OAUTHLIB_INSECURE_TRANSPORT"] = previous


@contextmanager
def _oauthlib_relax_token_scope():
    with OAUTHLIB_TRANSPORT_LOCK:
        previous = os.environ.get("OAUTHLIB_RELAX_TOKEN_SCOPE")
        os.environ["OAUTHLIB_RELAX_TOKEN_SCOPE"] = "1"
        try:
            yield
        finally:
            if previous is None:
                os.environ.pop("OAUTHLIB_RELAX_TOKEN_SCOPE", None)
            else:
                os.environ["OAUTHLIB_RELAX_TOKEN_SCOPE"] = previous


def _build_public_request_url(request: Request) -> str:
    host = (
        os.getenv("WEB_PUBLIC_HOST", "").strip()
        or request.headers.get("x-forwarded-host", "").strip()
        or request.headers.get("host", "").strip()
        or request.url.netloc
    )
    proto = (
        os.getenv("WEB_PUBLIC_SCHEME", "").strip()
        or request.headers.get("x-forwarded-proto", "").strip()
        or request.url.scheme
    )
    if not host:
        raise HTTPException(
            status_code=400,
            detail="공개 호스트를 확인할 수 없습니다. WEB_PUBLIC_HOST를 설정해주세요.",
        )
    host = _normalize_host(host)
    if proto == "http" and not _is_localhost_host(host):
        proto = "https"
    path = request.url.path
    query = request.url.query
    if query:
        return f"{proto}://{host}{path}?{query}"
    return f"{proto}://{host}{path}"


def _build_google_web_client_config(redirect_uri: str) -> dict[str, object]:
    return {
        "web": {
            "client_id": _google_client_id(),
            "project_id": _google_project_id(),
            "auth_uri": "https://accounts.google.com/o/oauth2/auth",
            "token_uri": "https://oauth2.googleapis.com/token",
            "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
            "client_secret": _google_client_secret(),
            "redirect_uris": [redirect_uri],
            "javascript_origins": [],
        }
    }


def _google_token_path() -> str:
    provider = GoogleCalendarProvider()
    return str(getattr(provider, "token_path", "token.json"))


def _google_callback_html(success: bool, message: str) -> str:
    escaped = message.replace("<", "&lt;").replace(">", "&gt;")
    status = "success" if success else "error"
    return f"""
<!doctype html>
<html lang=\"ko\">
<head>
  <meta charset=\"utf-8\" />
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
  <title>Google 인증 결과</title>
  <style>
    body {{ font-family: sans-serif; margin: 0; padding: 24px; background: #f7f8fa; color: #121417; }}
    .box {{ max-width: 520px; margin: 40px auto; padding: 20px; border-radius: 12px; background: #fff; border: 1px solid #e5e8ef; }}
    .ok {{ color: #0b7a37; }}
    .fail {{ color: #c22a2a; }}
    p {{ line-height: 1.5; }}
  </style>
</head>
<body>
  <div class=\"box\">
    <h2 class=\"{"ok" if success else "fail"}\">{"인증 완료" if success else "인증 실패"}</h2>
    <p>{escaped}</p>
    <p>이 창은 자동으로 닫힙니다.</p>
  </div>
  <script>
    (function() {{
      try {{
        if (window.opener) {{
          window.opener.postMessage({{ source: 'google-oauth', status: '{status}' }}, '*');
        }}
      }} catch (_) {{}}
      setTimeout(function() {{ window.close(); }}, 500);
    }})();
  </script>
</body>
</html>
"""


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


def _parse_iso_date(value: str) -> dt.date:
    text = str(value).strip()
    if not text:
        raise ValueError("날짜 값이 필요합니다.")
    return dt.date.fromisoformat(text)


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
    if provider == "google":
        raise HTTPException(
            status_code=400,
            detail="Google 인증은 /api/providers/google/auth-url 엔드포인트를 사용해주세요.",
        )

    try:
        calendar = _build_calendar_service(provider)
        calendar.authenticate()
        return {
            "provider": provider,
            "authenticated": True,
        }
    except Exception as error:
        raise HTTPException(status_code=400, detail=str(error)) from error


@app.post("/api/providers/google/auth-url")
def google_auth_url(request: Request) -> dict[str, object]:
    _cleanup_google_oauth_pending()

    redirect_uri = _build_google_redirect_uri(request)
    client_id = _google_client_id()
    with _oauthlib_local_insecure_transport(redirect_uri):
        flow = Flow.from_client_config(
            _build_google_web_client_config(redirect_uri),
            scopes=GOOGLE_SCOPES,
        )
        flow.redirect_uri = redirect_uri

        auth_url, state = flow.authorization_url(
            access_type="offline",
            include_granted_scopes="true",
            prompt="consent",
        )
    GOOGLE_OAUTH_PENDING[state] = (redirect_uri, time.time())

    return {
        "provider": "google",
        "auth_url": auth_url,
        "state": state,
        "redirect_uri": redirect_uri,
        "client_id": client_id,
    }


@app.get("/api/providers/google/callback")
def google_auth_callback(
    request: Request,
    state: str = Query(default=""),
) -> HTMLResponse:
    _cleanup_google_oauth_pending()

    received_state = str(state).strip()
    if not received_state:
        return HTMLResponse(
            content=_google_callback_html(False, "state 값이 누락되었습니다."),
            status_code=400,
        )

    pending = GOOGLE_OAUTH_PENDING.pop(received_state, None)
    if pending is None:
        return HTMLResponse(
            content=_google_callback_html(
                False,
                "인증 세션이 만료되었거나 유효하지 않습니다. 다시 인증을 시도해주세요.",
            ),
            status_code=400,
        )

    redirect_uri, _ = pending

    try:
        with (
            _oauthlib_local_insecure_transport(redirect_uri),
            _oauthlib_relax_token_scope(),
        ):
            flow = Flow.from_client_config(
                _build_google_web_client_config(redirect_uri),
                scopes=GOOGLE_SCOPES,
                state=received_state,
            )
            flow.redirect_uri = redirect_uri
            flow.fetch_token(authorization_response=_build_public_request_url(request))

        if not flow.credentials.has_scopes(GOOGLE_SCOPES):
            raise ValueError(
                "Google 인증에 필요한 캘린더 권한이 누락되었습니다. 권한을 다시 승인해주세요."
            )

        token_path = _google_token_path()
        with open(token_path, "wb") as token_file:
            pickle.dump(flow.credentials, token_file)
    except Exception as error:
        return HTMLResponse(
            content=_google_callback_html(
                False, f"Google 인증 토큰 저장 실패: {error}"
            ),
            status_code=400,
        )

    return HTMLResponse(
        content=_google_callback_html(True, "Google 캘린더 인증이 완료되었습니다."),
        status_code=200,
    )


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
        "clock_opacity": WEB_SETTINGS["clock_opacity"],
        "briefing_enabled": WEB_SETTINGS["briefing_enabled"],
        "briefing_tts_enabled": WEB_SETTINGS["briefing_tts_enabled"],
        "widget_pinned": WEB_SETTINGS["widget_pinned"],
    }


@app.put("/api/settings")
def update_settings(request: WebSettingsRequest) -> dict[str, object]:
    WEB_SETTINGS["theme"] = _normalize_theme(request.theme)
    WEB_SETTINGS["event_opacity"] = int(request.event_opacity)
    WEB_SETTINGS["clock_opacity"] = int(request.clock_opacity)
    WEB_SETTINGS["briefing_enabled"] = bool(request.briefing_enabled)
    WEB_SETTINGS["briefing_tts_enabled"] = bool(request.briefing_tts_enabled)
    WEB_SETTINGS["widget_pinned"] = bool(request.widget_pinned)
    return get_settings()


@app.get("/api/events/today")
def today_events(
    provider: str = Query(default=os.getenv("WEB_DEFAULT_PROVIDER", "google")),
    max_results: int = Query(default=20, ge=1, le=200),
    date: str | None = Query(default=None),
) -> dict[str, object]:
    target_date = dt.datetime.now().astimezone().date()
    if date:
        try:
            target_date = _parse_iso_date(date)
        except ValueError as error:
            raise HTTPException(status_code=400, detail=str(error)) from error

    try:
        calendar = _build_calendar_service(provider)
        _require_provider_credentials(calendar)
        start_of_day, end_of_day = _day_range_local(target_date)
        active_provider = calendar.active_provider
        if active_provider is None:
            raise HTTPException(
                status_code=400,
                detail=f"제공자 '{provider}'가 활성화되지 않았습니다.",
            )

        events = active_provider.get_events_in_range(
            start_time=start_of_day,
            end_time=end_of_day,
            max_results=max_results,
            page_size=min(max_results, 250),
        )
        if calendar.can_write_event_colors() and events:
            calendar.ai_event_color_service.apply(events)
            active_provider.write_event_colors(events)

        payload = [asdict(_to_web_event(event)) for event in events]
        return {
            "provider": provider,
            "date": target_date.isoformat(),
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

        active_provider = calendar.active_provider
        if active_provider is None:
            raise HTTPException(
                status_code=400,
                detail=f"제공자 '{provider}'가 활성화되지 않았습니다.",
            )

        created = active_provider.create_event(
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

        today_start, today_end = _today_range_local()
        today_total, today_updated = calendar.sync_ai_colors_for_range(
            start_time=today_start,
            end_time=today_end,
            max_results=None,
            page_size=page_size,
            throttle_seconds=0.0,
        )

        background = _start_or_queue_background_color_apply(
            provider=provider,
            max_results=max_results,
            page_size=page_size,
        )

        return {
            "provider": provider,
            "processed": today_total,
            "updated": today_updated,
            "processed_today": today_total,
            "updated_today": today_updated,
            "background_started": background["background_started"],
            "background_queued": background["background_queued"],
        }
    except HTTPException:
        raise
    except ValueError as error:
        raise HTTPException(status_code=401, detail=str(error)) from error
    except Exception as error:
        raise HTTPException(status_code=500, detail=str(error)) from error


@app.get("/api/colors/apply-status")
def get_apply_colors_status(
    provider: str = Query(default=os.getenv("WEB_DEFAULT_PROVIDER", "google")),
) -> dict[str, object]:
    with COLOR_APPLY_LOCK:
        state = _get_color_apply_state(provider)
        last_processed_raw = state.get("last_processed", 0)
        last_updated_raw = state.get("last_updated", 0)
        last_processed = (
            int(last_processed_raw)
            if isinstance(last_processed_raw, (int, float))
            else 0
        )
        last_updated = (
            int(last_updated_raw) if isinstance(last_updated_raw, (int, float)) else 0
        )
        return {
            "provider": provider,
            "running": bool(state.get("running", False)),
            "queued": bool(state.get("rerun_requested", False)),
            "last_started_at": state.get("last_started_at"),
            "last_finished_at": state.get("last_finished_at"),
            "last_processed": last_processed,
            "last_updated": last_updated,
            "last_error": str(state.get("last_error", "")),
        }
