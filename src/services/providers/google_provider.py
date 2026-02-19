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
    "1": "#a4bdfc",
    "2": "#7ae148",
    "3": "#bdadff",
    "4": "#ff887c",
    "5": "#fbd75b",
    "6": "#ffb878",
    "7": "#46d6db",
    "8": "#e1e1e1",
    "9": "#5484ed",
    "10": "#51b749",
    "11": "#dc2127",
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

    def authenticate(self, interactive: bool = True) -> None:
        if os.path.exists(self.token_path):
            with open(self.token_path, "rb") as token:
                self.creds = pickle.load(token)

        if self.creds and not self.creds.has_scopes(SCOPES):
            self.creds = None

        if not self.creds or not self.creds.valid:
            if self.creds and self.creds.expired and self.creds.refresh_token:
                self.creds.refresh(Request())
            else:
                if not interactive:
                    raise ValueError(
                        "Google provider is not authenticated. "
                        "Run explicit provider authentication first."
                    )
                flow = InstalledAppFlow.from_client_config(CLIENT_CONFIG, SCOPES)
                self.creds = flow.run_local_server(port=0)

            with open(self.token_path, "wb") as token:
                pickle.dump(self.creds, token)

        self.service = build("calendar", "v3", credentials=self.creds)

    def is_authenticated(self) -> bool:
        return self.creds is not None and self.creds.valid and self.service is not None

    def get_todays_events(self, max_results: int = 20) -> list[CalendarEvent]:
        now_local = datetime.datetime.now()
        start_of_day = now_local.replace(hour=0, minute=0, second=0, microsecond=0)
        end_of_day = now_local.replace(hour=23, minute=59, second=59, microsecond=0)
        return self.get_events_in_range(
            start_of_day,
            end_of_day,
            max_results=max_results,
            page_size=min(max_results, 250),
        )

    def get_events_in_range(
        self,
        start_time: datetime.datetime | None,
        end_time: datetime.datetime | None,
        max_results: int | None = None,
        page_size: int = 250,
    ) -> list[CalendarEvent]:
        if not self.service:
            self.authenticate(interactive=False)
        if not self.service:
            return []
        assert self.service is not None
        service = self.service

        safe_page_size = max(1, min(page_size, 2500))

        list_args = {
            "calendarId": "primary",
            "maxResults": safe_page_size,
            "singleEvents": True,
        }

        if start_time:
            list_args["timeMin"] = self._to_google_time(start_time)
            list_args["orderBy"] = "startTime"
        if end_time:
            list_args["timeMax"] = self._to_google_time(end_time)

        calendar_events: list[CalendarEvent] = []
        page_token: str | None = None

        while True:
            call_args = dict(list_args)
            if page_token:
                call_args["pageToken"] = page_token

            events_result = service.events().list(**call_args).execute()
            items = events_result.get("items", [])

            for item in items:
                parsed = self._item_to_calendar_event(item)
                if parsed:
                    calendar_events.append(parsed)
                    if max_results is not None and len(calendar_events) >= max_results:
                        return calendar_events

            page_token = events_result.get("nextPageToken")
            if not page_token:
                break

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

    def write_event_colors(self, events: list[CalendarEvent]) -> int:
        if not events:
            return 0
        if not self.service:
            self.authenticate(interactive=False)
        if not self.service:
            return 0
        assert self.service is not None
        service = self.service
        updated_count = 0

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
                updated_count += 1
            except Exception:
                continue

        return updated_count

    def supports_event_create(self) -> bool:
        return True

    def create_event(
        self,
        summary: str,
        start_time: datetime.datetime,
        end_time: datetime.datetime,
        all_day: bool = False,
    ) -> CalendarEvent | None:
        title = str(summary).strip()
        if not title:
            return None

        if not self.service:
            self.authenticate(interactive=False)
        if not self.service:
            return None
        assert self.service is not None
        service = self.service

        start_value = self._ensure_tz(start_time)
        end_value = self._ensure_tz(end_time)
        if end_value <= start_value:
            end_value = start_value + datetime.timedelta(minutes=60)

        body: dict[str, object] = {"summary": title}
        if all_day:
            start_date = start_value.date()
            end_date = end_value.date()
            if end_date <= start_date:
                end_date = start_date + datetime.timedelta(days=1)
            body["start"] = {"date": start_date.isoformat()}
            body["end"] = {"date": end_date.isoformat()}
        else:
            body["start"] = {"dateTime": start_value.isoformat()}
            body["end"] = {"dateTime": end_value.isoformat()}

        try:
            created = service.events().insert(calendarId="primary", body=body).execute()
        except Exception:
            return None

        parsed = self._item_to_calendar_event(created)
        if parsed:
            return parsed

        event_id = str(created.get("id", "")).strip()
        if not event_id:
            return None
        return CalendarEvent(
            id=event_id,
            summary=title,
            start_time=start_value,
            end_time=end_value,
            all_day=all_day,
        )

    def _color_id_from_hex(self, hex_color: str) -> str | None:
        target = str(hex_color or "").strip().lower()
        for color_id, color_hex in GOOGLE_COLORS.items():
            if color_hex.lower() == target:
                return color_id
        return None

    def _to_google_time(self, value: datetime.datetime) -> str:
        value = self._ensure_tz(value)
        return (
            value.astimezone(datetime.timezone.utc).isoformat().replace("+00:00", "Z")
        )

    def _ensure_tz(self, value: datetime.datetime) -> datetime.datetime:
        if value.tzinfo is not None:
            return value
        local_tz = datetime.datetime.now().astimezone().tzinfo
        if local_tz is None:
            local_tz = datetime.timezone.utc
        return value.replace(tzinfo=local_tz)

    def _item_to_calendar_event(self, item: dict) -> CalendarEvent | None:
        start_data = item.get("start", {})
        end_data = item.get("end", {})

        if "dateTime" not in start_data:
            date_str = start_data.get("date")
            if not date_str:
                return None
            local_tz = datetime.datetime.now().astimezone().tzinfo
            start_date = datetime.date.fromisoformat(date_str)
            start_time = datetime.datetime.combine(
                start_date, datetime.time.min, tzinfo=local_tz
            )
            end_time = datetime.datetime.combine(
                start_date, datetime.time.max, tzinfo=local_tz
            )
            all_day = True
        else:
            start_str = start_data["dateTime"]
            end_str = end_data.get("dateTime", start_str)
            start_time = datetime.datetime.fromisoformat(
                start_str.replace("Z", "+00:00")
            )
            if start_time.tzinfo is None:
                start_time = start_time.replace(tzinfo=datetime.timezone.utc)
            end_time = datetime.datetime.fromisoformat(end_str.replace("Z", "+00:00"))
            if end_time.tzinfo is None:
                end_time = end_time.replace(tzinfo=datetime.timezone.utc)
            all_day = False

        color_id = item.get("colorId")
        event_color = None
        if color_id in GOOGLE_COLORS:
            event_color = QColor(GOOGLE_COLORS[color_id])
            event_color.setAlpha(180)

        event_args = {
            "id": item.get("id", ""),
            "summary": item.get("summary", "(제목 없음)"),
            "description": str(item.get("description", "") or "").strip(),
            "start_time": start_time,
            "end_time": end_time,
            "all_day": all_day,
            "provider_color_id": color_id,
        }
        if event_color:
            event_args["color"] = event_color

        if not event_args["id"]:
            return None
        return CalendarEvent(**event_args)
