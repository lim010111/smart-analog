import os
import json
import datetime
import uuid
import caldav
from caldav.elements import ical as caldav_ical
from caldav.lib.error import AuthorizationError
from PySide6.QtGui import QColor

from src.models.event import CalendarEvent
from src.services.providers.base import CalendarProvider

ICLOUD_CALDAV_URL = "https://caldav.icloud.com"
CREDENTIALS_FILE = "apple_credentials.json"

DEFAULT_CALENDAR_COLOR = QColor(100, 150, 255, 180)


class AppleCalendarProvider(CalendarProvider):
    def __init__(self, credentials_path: str = CREDENTIALS_FILE):
        self.credentials_path = credentials_path
        self.client: caldav.DAVClient | None = None
        self.principal = None
        self._apple_id: str | None = None
        self._app_password: str | None = None

    @property
    def provider_name(self) -> str:
        return "Apple"

    def authenticate(self) -> None:
        if not self._apple_id or not self._app_password:
            self._load_credentials()

        if not self._apple_id or not self._app_password:
            raise ValueError(
                "Apple ID credentials not configured. "
                "Use set_credentials() or create apple_credentials.json."
            )

        auth_errors: list[Exception] = []
        for password in self._candidate_passwords(self._app_password):
            try:
                self.client = caldav.DAVClient(
                    url=ICLOUD_CALDAV_URL,
                    username=self._apple_id,
                    password=password,
                )
                self.principal = self.client.principal()
                self._app_password = password
                self._save_credentials()
                return
            except AuthorizationError as error:
                auth_errors.append(error)

        self.logout()
        raise ValueError(
            "iCloud authentication failed. Check these items:\n"
            "1) Apple ID email is correct\n"
            "2) Two-factor authentication is enabled on Apple account\n"
            "3) Use a newly generated App-Specific Password from account.apple.com"
        )

    def is_authenticated(self) -> bool:
        return self.client is not None and self.principal is not None

    def set_credentials(self, apple_id: str, app_password: str) -> None:
        self._apple_id = self._normalize_apple_id(apple_id)
        self._app_password = app_password.strip()

    def has_saved_credentials(self) -> bool:
        return os.path.exists(self.credentials_path)

    def get_todays_events(self, max_results: int = 20) -> list[CalendarEvent]:
        if not self.is_authenticated():
            self.authenticate()

        now_local = datetime.datetime.now().astimezone()
        start_of_day = now_local.replace(hour=0, minute=0, second=0, microsecond=0)
        end_of_day = now_local.replace(hour=23, minute=59, second=59, microsecond=0)

        calendar_events: list[CalendarEvent] = []
        principal = self.principal
        if not principal:
            return calendar_events
        try:
            calendars = principal.calendars()
        except AuthorizationError:
            self._clear_auth_state()
            raise

        for cal in calendars:
            cal_color = self._extract_calendar_color(cal)

            try:
                results = cal.search(
                    start=start_of_day,
                    end=end_of_day,
                    event=True,
                    expand=True,
                )
            except AuthorizationError:
                self._clear_auth_state()
                raise
            except Exception:
                continue

            for event_obj in results:
                try:
                    parsed = self._parse_vevent(event_obj, cal_color)
                    if parsed:
                        calendar_events.append(parsed)
                except Exception:
                    continue

        calendar_events.sort(key=lambda e: e.start_time)
        return calendar_events[:max_results]

    def _parse_vevent(self, event_obj, cal_color: QColor) -> CalendarEvent | None:
        ical = event_obj.icalendar_instance
        vevents = ical.walk("VEVENT")
        if not vevents:
            return None

        vevent = vevents[0]

        dtstart = vevent.get("DTSTART")
        dtend = vevent.get("DTEND")

        if dtstart is None:
            return None
        dtstart = dtstart.dt

        # 종일 일정 처리 (date 타입은 시간 정보가 없음)
        if isinstance(dtstart, datetime.date) and not isinstance(
            dtstart, datetime.datetime
        ):
            local_tz = datetime.datetime.now().astimezone().tzinfo
            start_time = datetime.datetime.combine(
                dtstart, datetime.time.min, tzinfo=local_tz
            )
            end_time = datetime.datetime.combine(
                dtstart, datetime.time.max, tzinfo=local_tz
            )
            summary = str(vevent.get("SUMMARY", "(제목 없음)"))
            uid = str(vevent.get("UID", summary))
            return CalendarEvent(
                id=uid,
                summary=summary,
                start_time=start_time,
                end_time=end_time,
                color=cal_color,
                all_day=True,
            )

        if dtend is not None:
            dtend = dtend.dt
        else:
            duration = vevent.get("DURATION")
            if duration is not None:
                dtend = dtstart + duration.dt
            else:
                dtend = dtstart + datetime.timedelta(hours=1)

        if dtstart.tzinfo is None:
            dtstart = dtstart.replace(tzinfo=datetime.timezone.utc)
        if dtend.tzinfo is None:
            dtend = dtend.replace(tzinfo=datetime.timezone.utc)

        summary = str(vevent.get("SUMMARY", "(제목 없음)"))
        uid = str(vevent.get("UID", summary))

        return CalendarEvent(
            id=uid,
            summary=summary,
            start_time=dtstart,
            end_time=dtend,
            color=cal_color,
        )

    def _extract_calendar_color(self, cal) -> QColor:
        try:
            # CalDAV 캘린더의 calendar-color 속성 (Apple 사용)
            color_prop = cal.get_properties([caldav_ical.CalendarColor()])
            color_val = color_prop.get("{http://apple.com/ns/ical/}calendar-color", "")
            if color_val:
                # "#RRGGBBAA" 또는 "#RRGGBB" 형식
                hex_color = color_val.strip()
                if len(hex_color) == 9:
                    return QColor(hex_color[:7])
                elif len(hex_color) >= 7:
                    return QColor(hex_color)
        except Exception:
            pass
        return QColor(DEFAULT_CALENDAR_COLOR)

    def _load_credentials(self) -> None:
        if not os.path.exists(self.credentials_path):
            return
        try:
            with open(self.credentials_path, "r") as f:
                data = json.load(f)
            self._apple_id = self._normalize_apple_id(data.get("apple_id", ""))
            self._app_password = str(data.get("app_password", "")).strip()
        except Exception:
            pass

    def _save_credentials(self) -> None:
        if not self._apple_id or not self._app_password:
            return
        data = {
            "apple_id": self._apple_id,
            "app_password": self._app_password,
        }
        with open(self.credentials_path, "w") as f:
            json.dump(data, f, indent=2)

    def _normalize_apple_id(self, apple_id: str) -> str:
        return str(apple_id).strip().lower()

    def _candidate_passwords(self, raw_password: str) -> list[str]:
        cleaned = str(raw_password).strip()
        collapsed = cleaned.replace("-", "").replace(" ", "")
        if collapsed and collapsed != cleaned:
            return [cleaned, collapsed]
        return [cleaned]

    def _clear_auth_state(self) -> None:
        self.client = None
        self.principal = None

    def logout(self) -> None:
        self._clear_auth_state()
        self._apple_id = None
        self._app_password = None
        if os.path.exists(self.credentials_path):
            os.remove(self.credentials_path)

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

        if not self.is_authenticated():
            self.authenticate()

        principal = self.principal
        if not principal:
            return None

        try:
            calendars = principal.calendars()
        except AuthorizationError:
            self._clear_auth_state()
            raise
        except Exception:
            return None

        if not calendars:
            return None

        target_calendar = calendars[0]
        cal_color = self._extract_calendar_color(target_calendar)

        start_value = self._ensure_tz(start_time)
        end_value = self._ensure_tz(end_time)
        if end_value <= start_value:
            end_value = start_value + datetime.timedelta(hours=1)

        if all_day:
            start_date = start_value.date()
            end_date = end_value.date()
            if end_date <= start_date:
                end_date = start_date + datetime.timedelta(days=1)
            ical_data = self._build_all_day_ical(title, start_date, end_date)
        else:
            ical_data = self._build_timed_ical(title, start_value, end_value)

        try:
            saved_event = target_calendar.save_event(ical_data)
        except AuthorizationError:
            self._clear_auth_state()
            raise
        except Exception:
            return None

        try:
            parsed = self._parse_vevent(saved_event, cal_color)
            if parsed:
                return parsed
        except Exception:
            pass

        event_id = str(getattr(saved_event, "url", "") or "").strip()
        if not event_id:
            event_id = f"apple-{uuid.uuid4().hex}"

        fallback_end = end_value
        if all_day:
            local_tz = datetime.datetime.now().astimezone().tzinfo
            if local_tz is None:
                local_tz = datetime.timezone.utc
            fallback_start = datetime.datetime.combine(
                start_value.date(), datetime.time.min, tzinfo=local_tz
            )
            fallback_end = datetime.datetime.combine(
                start_value.date(), datetime.time.max, tzinfo=local_tz
            )
        else:
            fallback_start = start_value

        return CalendarEvent(
            id=event_id,
            summary=title,
            start_time=fallback_start,
            end_time=fallback_end,
            color=cal_color,
            all_day=all_day,
        )

    def _build_timed_ical(
        self,
        summary: str,
        start_time: datetime.datetime,
        end_time: datetime.datetime,
    ) -> str:
        uid = f"{uuid.uuid4()}@clock-widget"
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        start_utc = start_time.astimezone(datetime.timezone.utc).strftime(
            "%Y%m%dT%H%M%SZ"
        )
        end_utc = end_time.astimezone(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        escaped_summary = self._escape_ics_text(summary)

        lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Clock Widget//AI Natural Input//EN",
            "CALSCALE:GREGORIAN",
            "BEGIN:VEVENT",
            f"UID:{uid}",
            f"DTSTAMP:{stamp}",
            f"DTSTART:{start_utc}",
            f"DTEND:{end_utc}",
            f"SUMMARY:{escaped_summary}",
            "END:VEVENT",
            "END:VCALENDAR",
        ]
        return "\r\n".join(lines) + "\r\n"

    def _build_all_day_ical(
        self,
        summary: str,
        start_date: datetime.date,
        end_date: datetime.date,
    ) -> str:
        uid = f"{uuid.uuid4()}@clock-widget"
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        escaped_summary = self._escape_ics_text(summary)

        lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Clock Widget//AI Natural Input//EN",
            "CALSCALE:GREGORIAN",
            "BEGIN:VEVENT",
            f"UID:{uid}",
            f"DTSTAMP:{stamp}",
            f"DTSTART;VALUE=DATE:{start_date.strftime('%Y%m%d')}",
            f"DTEND;VALUE=DATE:{end_date.strftime('%Y%m%d')}",
            f"SUMMARY:{escaped_summary}",
            "END:VEVENT",
            "END:VCALENDAR",
        ]
        return "\r\n".join(lines) + "\r\n"

    @staticmethod
    def _escape_ics_text(value: str) -> str:
        text = str(value)
        text = text.replace("\\", "\\\\")
        text = text.replace("\n", "\\n")
        text = text.replace(";", "\\;")
        text = text.replace(",", "\\,")
        return text

    @staticmethod
    def _ensure_tz(value: datetime.datetime) -> datetime.datetime:
        if value.tzinfo is not None:
            return value
        local_tz = datetime.datetime.now().astimezone().tzinfo
        if local_tz is None:
            local_tz = datetime.timezone.utc
        return value.replace(tzinfo=local_tz)
