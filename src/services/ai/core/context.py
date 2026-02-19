from dataclasses import dataclass

from src.models.event import CalendarEvent


@dataclass(frozen=True)
class EventContext:
    event_id: str
    summary: str
    description: str
    start_time: str
    end_time: str
    all_day: bool

    @classmethod
    def from_event(cls, event: CalendarEvent) -> "EventContext":
        return cls(
            event_id=event.id,
            summary=event.summary,
            description=event.description,
            start_time=event.start_time.isoformat(),
            end_time=event.end_time.isoformat(),
            all_day=event.all_day,
        )

    def to_dict(self) -> dict[str, str | bool]:
        return {
            "id": self.event_id,
            "summary": self.summary,
            "description": self.description,
            "start_time": self.start_time,
            "end_time": self.end_time,
            "all_day": self.all_day,
        }


def build_event_context(events: list[CalendarEvent]) -> list[EventContext]:
    contexts: list[EventContext] = []
    for event in events:
        if not event.id:
            continue
        contexts.append(EventContext.from_event(event))
    return contexts


def event_context_to_dicts(events: list[CalendarEvent]) -> list[dict[str, str | bool]]:
    return [context.to_dict() for context in build_event_context(events)]
