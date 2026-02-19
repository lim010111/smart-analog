import datetime
import time

from src.models.event import CalendarEvent
from src.services.ai import (
    AIEventColorService,
    AITodayBriefingService,
    AINaturalInputService,
    NaturalInputParseResult,
)
from src.services.providers.base import CalendarProvider
from src.services.providers.google_provider import GoogleCalendarProvider
from src.services.providers.apple_provider import AppleCalendarProvider


PROVIDER_REGISTRY: dict[str, type[CalendarProvider]] = {
    "google": GoogleCalendarProvider,
    "apple": AppleCalendarProvider,
}


class CalendarService:
    def __init__(self):
        self._providers: dict[str, CalendarProvider] = {}
        self._active_provider_key: str | None = None
        self._ai_event_color_service = AIEventColorService()
        self._ai_today_briefing_service = AITodayBriefingService()
        self._ai_natural_input_service = AINaturalInputService()

    @property
    def active_provider(self) -> CalendarProvider | None:
        if self._active_provider_key:
            return self._providers.get(self._active_provider_key)
        return None

    @property
    def active_provider_key(self) -> str | None:
        return self._active_provider_key

    @property
    def ai_event_color_service(self) -> AIEventColorService:
        return self._ai_event_color_service

    @property
    def ai_today_briefing_service(self) -> AITodayBriefingService:
        return self._ai_today_briefing_service

    @property
    def ai_natural_input_service(self) -> AINaturalInputService:
        return self._ai_natural_input_service

    def get_provider(self, key: str) -> CalendarProvider | None:
        return self._providers.get(key)

    def set_active_provider(self, key: str) -> CalendarProvider:
        if key not in self._providers:
            if key not in PROVIDER_REGISTRY:
                raise ValueError(f"Unknown provider: {key}")
            self._providers[key] = PROVIDER_REGISTRY[key]()

        self._active_provider_key = key
        self._sync_ai_palette_with_provider(self._providers[key])
        return self._providers[key]

    def authenticate(self) -> None:
        provider = self.active_provider
        if not provider:
            raise RuntimeError("No active calendar provider selected.")
        provider.authenticate()

    def get_todays_events(self, max_results: int = 20) -> list[CalendarEvent]:
        provider = self.active_provider
        if not provider:
            return []

        self._sync_ai_palette_with_provider(provider)

        events = provider.get_todays_events(max_results)
        if not provider.supports_event_color_write():
            return events

        updated_events = self._ai_event_color_service.apply(events)
        provider.write_event_colors(updated_events)
        return updated_events

    def sync_ai_colors_for_range(
        self,
        start_time: datetime.datetime | None,
        end_time: datetime.datetime | None,
        max_results: int | None = None,
        page_size: int = 250,
        throttle_seconds: float = 0.05,
    ) -> tuple[int, int]:
        provider = self.active_provider
        if not provider:
            return (0, 0)

        if not provider.supports_event_color_write():
            return (0, 0)

        self._sync_ai_palette_with_provider(provider)

        events = provider.get_events_in_range(
            start_time,
            end_time,
            max_results=max_results,
            page_size=page_size,
        )
        if not events:
            return (0, 0)

        chunk_size = max(1, getattr(self._ai_event_color_service, "max_titles", 30))
        updated_total = 0

        for index in range(0, len(events), chunk_size):
            chunk = events[index : index + chunk_size]
            self._ai_event_color_service.apply(chunk)
            updated_total += provider.write_event_colors(chunk)
            if throttle_seconds > 0:
                time.sleep(throttle_seconds)

        return (len(events), updated_total)

    def sync_ai_colors_for_all_events(
        self,
        max_results: int | None = None,
        page_size: int = 250,
        throttle_seconds: float = 0.05,
    ) -> tuple[int, int]:
        return self.sync_ai_colors_for_range(
            start_time=None,
            end_time=None,
            max_results=max_results,
            page_size=page_size,
            throttle_seconds=throttle_seconds,
        )

    def get_supported_ai_colors(self) -> list[str]:
        provider = self.active_provider
        if not provider:
            return []
        return [
            color.lower()
            for color in provider.get_supported_event_colors().values()
            if str(color).strip()
        ]

    def can_write_event_colors(self) -> bool:
        provider = self.active_provider
        return provider.supports_event_color_write() if provider else False

    def can_create_events(self) -> bool:
        provider = self.active_provider
        return provider.supports_event_create() if provider else False

    def create_event_from_natural_input(
        self,
        parsed: NaturalInputParseResult,
    ) -> CalendarEvent | None:
        provider = self.active_provider
        if not provider:
            return None
        if not provider.supports_event_create():
            return None

        if parsed.intent != "create":
            return None
        if not parsed.title.strip():
            return None
        if parsed.start_time is None or parsed.end_time is None:
            return None

        return provider.create_event(
            summary=parsed.title,
            start_time=parsed.start_time,
            end_time=parsed.end_time,
            all_day=parsed.all_day,
        )

    def _sync_ai_palette_with_provider(self, provider: CalendarProvider) -> None:
        palette = [
            color.lower()
            for color in provider.get_supported_event_colors().values()
            if str(color).strip()
        ]
        self._ai_event_color_service.set_supported_palette(palette)

    def logout(self) -> None:
        provider = self.active_provider
        if not provider:
            return
        provider.logout()
        if self._active_provider_key:
            self._providers.pop(self._active_provider_key, None)
        self._active_provider_key = None
