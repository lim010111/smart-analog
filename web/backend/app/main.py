from __future__ import annotations

import datetime as dt
import os
from dataclasses import asdict, dataclass

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware

from src.services.ai.briefing import AITodayBriefingService
from src.services.calendar import CalendarService


@dataclass
class WebEvent:
    id: str
    summary: str
    description: str
    start_time: str
    end_time: str
    all_day: bool


def _to_web_event(event) -> WebEvent:
    return WebEvent(
        id=event.id,
        summary=event.summary,
        description=event.description,
        start_time=event.start_time.isoformat(),
        end_time=event.end_time.isoformat(),
        all_day=event.all_day,
    )


def _build_calendar_service(provider: str) -> CalendarService:
    service = CalendarService()
    service.set_active_provider(provider)
    return service


def _allowed_origins() -> list[str]:
    raw = os.getenv("WEB_CORS_ORIGINS", "http://localhost:3000")
    return [origin.strip() for origin in raw.split(",") if origin.strip()]


app = FastAPI(title="Clock Widget Web API", version="0.1.0")
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


@app.get("/api/events/today")
def today_events(
    provider: str = Query(default=os.getenv("WEB_DEFAULT_PROVIDER", "google")),
    max_results: int = Query(default=20, ge=1, le=200),
) -> dict[str, object]:
    try:
        calendar = _build_calendar_service(provider)
        events = calendar.get_todays_events(max_results=max_results)
        payload = [asdict(_to_web_event(event)) for event in events]
        return {
            "provider": provider,
            "date": dt.date.today().isoformat(),
            "count": len(payload),
            "events": payload,
        }
    except Exception as error:
        raise HTTPException(status_code=500, detail=str(error)) from error


@app.get("/api/briefing/today")
def today_briefing(
    provider: str = Query(default=os.getenv("WEB_DEFAULT_PROVIDER", "google")),
    max_results: int = Query(default=20, ge=1, le=200),
    force: bool = Query(default=True),
) -> dict[str, object]:
    try:
        calendar = _build_calendar_service(provider)
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
    except Exception as error:
        raise HTTPException(status_code=500, detail=str(error)) from error
