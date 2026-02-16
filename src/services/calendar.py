from src.models.event import CalendarEvent
from src.services.ai import AIEventColorService
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

    @property
    def active_provider(self) -> CalendarProvider | None:
        if self._active_provider_key:
            return self._providers.get(self._active_provider_key)
        return None

    @property
    def active_provider_key(self) -> str | None:
        return self._active_provider_key

    def get_provider(self, key: str) -> CalendarProvider | None:
        return self._providers.get(key)

    def set_active_provider(self, key: str) -> CalendarProvider:
        if key not in self._providers:
            if key not in PROVIDER_REGISTRY:
                raise ValueError(f"Unknown provider: {key}")
            self._providers[key] = PROVIDER_REGISTRY[key]()

        self._active_provider_key = key
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

        events = provider.get_todays_events(max_results)
        return self._ai_event_color_service.apply(events)

    def logout(self) -> None:
        provider = self.active_provider
        if not provider:
            return
        provider.logout()
        if self._active_provider_key:
            self._providers.pop(self._active_provider_key, None)
        self._active_provider_key = None
