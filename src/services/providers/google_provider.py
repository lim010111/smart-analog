import os
import sys
import datetime
import pickle
from google.auth.transport.requests import Request
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
from dotenv import load_dotenv
from PySide6.QtGui import QColor

from src.models.event import CalendarEvent
from src.services.providers.base import CalendarProvider


def _get_resource_path(relative_path: str) -> str:
    base_path = getattr(sys, "_MEIPASS", os.path.abspath("."))
    return os.path.join(base_path, relative_path)


env_path = _get_resource_path(".env")
load_dotenv(env_path)

SCOPES = ["https://www.googleapis.com/auth/calendar"]

GOOGLE_COLORS = {
    "1": "#a4bdfc",  # Lavender
    "2": "#7ae148",  # Sage
    "3": "#bdadff",  # Grape
    "4": "#ff887c",  # Flamingo
    "5": "#fbd75b",  # Banana
    "6": "#ffb878",  # Tangerine
    "7": "#46d6db",  # Peacock
    "8": "#e1e1e1",  # Graphite
    "9": "#5484ed",  # Blueberry
    "10": "#51b749",  # Basil
    "11": "#dc2127",  # Tomato
}

GOOGLE_COLOR_ORDER = ["11", "4", "6", "5", "2", "10", "7", "9", "1", "3", "8"]

CLIENT_CONFIG = {
    "installed": {
        "client_id": os.getenv("GOOGLE_CLIENT_ID"),
        "project_id": os.getenv("GOOGLE_PROJECT_ID"),
        "auth_uri": "https://accounts.google.com/o/oauth2/auth",
        "token_uri": "https://oauth2.googleapis.com/token",
        "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
        "client_secret": os.getenv("GOOGLE_CLIENT_SECRET"),
        "redirect_uris": ["http://localhost"],
    }
}


class GoogleCalendarProvider(CalendarProvider):
    def __init__(self, token_path: str = "token.json"):
        self.token_path = token_path
        self.creds = None
        self.service = None

    @property
    def provider_name(self) -> str:
        return "Google"

    def authenticate(self) -> None:
        if os.path.exists(self.token_path):
            with open(self.token_path, "rb") as token:
                self.creds = pickle.load(token)

        if self.creds and not self.creds.has_scopes(SCOPES):
            self.creds = None

        if not self.creds or not self.creds.valid:
            if self.creds and self.creds.expired and self.creds.refresh_token:
                self.creds.refresh(Request())
            else:
                flow = InstalledAppFlow.from_client_config(CLIENT_CONFIG, SCOPES)
                self.creds = flow.run_local_server(port=0)

            with open(self.token_path, "wb") as token:
                pickle.dump(self.creds, token)

        self.service = build("calendar", "v3", credentials=self.creds)

    def is_authenticated(self) -> bool:
        return self.creds is not None and self.creds.valid and self.service is not None

    def get_todays_events(self, max_results: int = 20) -> list[CalendarEvent]:
        if not self.service:
            self.authenticate()
        if not self.service:
            return []
        assert self.service is not None
        service = self.service

        now_local = datetime.datetime.now()
        start_of_day = now_local.replace(hour=0, minute=0, second=0, microsecond=0)
        end_of_day = now_local.replace(hour=23, minute=59, second=59, microsecond=0)

        time_min = (
            start_of_day.astimezone(datetime.timezone.utc)
            .isoformat()
            .replace("+00:00", "Z")
        )
        time_max = (
            end_of_day.astimezone(datetime.timezone.utc)
            .isoformat()
            .replace("+00:00", "Z")
        )

        events_result = (
            service.events()
            .list(
                calendarId="primary",
                timeMin=time_min,
                timeMax=time_max,
                maxResults=max_results,
                singleEvents=True,
                orderBy="startTime",
            )
            .execute()
        )

        items = events_result.get("items", [])
        calendar_events = []

        for item in items:
            start_data = item["start"]
            end_data = item["end"]

            if "dateTime" not in start_data:
                date_str = start_data.get("date")
                if not date_str:
                    continue
                local_tz = datetime.datetime.now().astimezone().tzinfo
                start_date = datetime.date.fromisoformat(date_str)
                start_time = datetime.datetime.combine(
                    start_date, datetime.time.min, tzinfo=local_tz
                )
                end_time = datetime.datetime.combine(
                    start_date, datetime.time.max, tzinfo=local_tz
                )

                color_id = item.get("colorId")
                event_color = None
                if color_id in GOOGLE_COLORS:
                    event_color = QColor(GOOGLE_COLORS[color_id])
                    event_color.setAlpha(180)

                event_args = {
                    "id": item["id"],
                    "summary": item.get("summary", "(제목 없음)"),
                    "start_time": start_time,
                    "end_time": end_time,
                    "all_day": True,
                    "provider_color_id": color_id,
                }
                if event_color:
                    event_args["color"] = event_color

                calendar_events.append(CalendarEvent(**event_args))
                continue

            start_str = start_data["dateTime"]
            end_str = end_data["dateTime"]

            start_time = datetime.datetime.fromisoformat(
                start_str.replace("Z", "+00:00")
            )
            if start_time.tzinfo is None:
                start_time = start_time.replace(tzinfo=datetime.timezone.utc)

            end_time = datetime.datetime.fromisoformat(end_str.replace("Z", "+00:00"))
            if end_time.tzinfo is None:
                end_time = end_time.replace(tzinfo=datetime.timezone.utc)

            color_id = item.get("colorId")
            event_color = None
            if color_id in GOOGLE_COLORS:
                event_color = QColor(GOOGLE_COLORS[color_id])
                event_color.setAlpha(180)

            event_args = {
                "id": item["id"],
                "summary": item.get("summary", "(제목 없음)"),
                "start_time": start_time,
                "end_time": end_time,
                "provider_color_id": color_id,
            }
            if event_color:
                event_args["color"] = event_color

            calendar_events.append(CalendarEvent(**event_args))

        return calendar_events

    def logout(self) -> None:
        self.creds = None
        self.service = None
        if os.path.exists(self.token_path):
            os.remove(self.token_path)

    def supports_event_color_write(self) -> bool:
        return True

    def get_supported_event_colors(self) -> dict[str, str]:
        return {
            color_id: GOOGLE_COLORS[color_id]
            for color_id in GOOGLE_COLOR_ORDER
            if color_id in GOOGLE_COLORS
        }

    def write_event_colors(self, events: list[CalendarEvent]) -> None:
        if not events:
            return
        if not self.service:
            self.authenticate()
        if not self.service:
            return
        assert self.service is not None
        service = self.service

        for event in events:
            color_id = self._color_id_from_hex(event.color.name())
            if not color_id:
                continue
            if event.provider_color_id == color_id:
                continue

            try:
                service.events().patch(
                    calendarId="primary",
                    eventId=event.id,
                    body={"colorId": color_id},
                ).execute()
                event.provider_color_id = color_id
            except Exception:
                continue

    def _color_id_from_hex(self, hex_color: str) -> str | None:
        target = str(hex_color or "").strip().lower()
        for color_id, color_hex in GOOGLE_COLORS.items():
            if color_hex.lower() == target:
                return color_id
        return None
