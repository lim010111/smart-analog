import datetime
import json
from pathlib import Path

from src.models.event import CalendarEvent
from src.services.ai.core import (
    OpenAIJSONClient,
    load_openai_config,
    read_bool_env,
    read_int_env,
    request_json_or_empty,
)


class AITodayBriefingService:
    def __init__(self):
        self.default_enabled = read_bool_env("ENABLE_AI_TODAY_BRIEFING", default=False)
        self.default_tts_enabled = read_bool_env(
            "ENABLE_AI_TODAY_BRIEFING_TTS", default=False
        )
        self.max_events = max(1, read_int_env("OPENAI_BRIEFING_MAX_EVENTS", default=20))
        self._refresh_slot_minutes = max(
            1,
            read_int_env("OPENAI_BRIEFING_REFRESH_SLOT_MINUTES", default=15),
        )

        config = load_openai_config(
            model_env="OPENAI_BRIEFING_MODEL",
            timeout_env="OPENAI_BRIEFING_TIMEOUT",
            default_model="gpt-5-mini",
            default_timeout=8.0,
        )
        self._client = OpenAIJSONClient(config)

        self._settings_path = (
            Path.home() / ".clock_widget" / "ai_briefing_settings.json"
        )
        self._enabled = self.default_enabled
        self._tts_enabled = self.default_tts_enabled
        self._load_settings()

        self._cached_date: datetime.date | None = None
        self._cached_signature = ""
        self._cached_slot = ""
        self._cached_text = ""

    def is_enabled(self) -> bool:
        return self._enabled

    def set_enabled(self, enabled: bool) -> None:
        self._enabled = bool(enabled)
        self._save_settings()

    def is_tts_enabled(self) -> bool:
        return self._tts_enabled

    def set_tts_enabled(self, enabled: bool) -> None:
        self._tts_enabled = bool(enabled)
        self._save_settings()

    def generate_today_briefing(
        self,
        events: list[CalendarEvent],
        now: datetime.datetime | None = None,
        force: bool = False,
    ) -> str:
        local_now = now or datetime.datetime.now().astimezone()
        today = local_now.date()
        relevant_events = self._select_relevant_events(events, local_now)
        signature = self._build_signature(relevant_events)
        slot = self._build_slot_key(local_now)

        if (
            not force
            and self._cached_text
            and self._cached_date == today
            and self._cached_signature == signature
            and self._cached_slot == slot
        ):
            return self._cached_text

        limited_events = self._normalize_events(relevant_events)

        text = ""
        if self._client.is_available():
            text = self._generate_with_openai(limited_events, local_now)
        if not text:
            text = self._generate_fallback(limited_events, local_now)

        self._cached_date = today
        self._cached_signature = signature
        self._cached_slot = slot
        self._cached_text = text
        return text

    def _generate_with_openai(
        self,
        events: list[dict[str, str | bool]],
        now: datetime.datetime,
    ) -> str:
        payload = {
            "today": now.date().isoformat(),
            "now": now.isoformat(),
            "timezone": str(now.tzinfo) if now.tzinfo else "local",
            "briefing_scope": "ongoing_and_upcoming_from_now",
            "events": events,
            "schema": {
                "briefing": (
                    "Korean natural-language summary in 1-2 sentences. "
                    "Focus only on ongoing/upcoming plans from now. "
                    "Mention notable schedule clusters and meaningful free-time gaps. "
                    "If event descriptions add practical context, include it briefly."
                )
            },
        }
        response = request_json_or_empty(
            self._client,
            system_prompt=(
                "Task: generate a concise Korean daily briefing for the remaining day. "
                "Scope: only ongoing/upcoming events from now; ignore completed events. "
                "Style: natural, practical, 1-2 sentences, no markdown. "
                "Rules: "
                "1) Prioritize near-term events and overlaps. "
                "2) Mention meaningful free-time gaps when present. "
                "3) Use event description details only when they add useful context. "
                "4) Do not invent facts beyond input data. "
                "5) Output JSON only with key 'briefing'."
            ),
            user_payload=payload,
            max_output_tokens=450,
            model=self._client.config.model,
        )
        briefing = str(response.get("briefing", "")).strip()
        return briefing

    def _generate_fallback(
        self,
        events: list[dict[str, str | bool]],
        now: datetime.datetime,
    ) -> str:
        if not events:
            return "현재 시각 이후로 예정된 일정이 없습니다. 남은 시간을 정리해보세요."

        starts: list[datetime.datetime] = []
        for event in events:
            start_raw = str(event.get("start_time", "")).strip()
            if not start_raw:
                continue
            try:
                starts.append(datetime.datetime.fromisoformat(start_raw))
            except ValueError:
                continue

        morning = sum(1 for dt in starts if dt.hour < 12)
        afternoon = sum(1 for dt in starts if dt.hour >= 12)

        gap_hours = self._largest_gap_hours(events, now)
        if gap_hours >= 2.0:
            gap_phrase = f"오후에 약 {gap_hours:.1f}시간의 공백이 있어요"
        elif gap_hours >= 1.0:
            gap_phrase = f"중간에 약 {gap_hours:.1f}시간의 짧은 공백이 있어요"
        else:
            gap_phrase = "일정이 비교적 촘촘하게 배치되어 있어요"

        detail_phrase = ""
        for event in events:
            detail = str(event.get("description", "") or "").strip()
            if detail:
                clipped = detail[:60]
                if len(detail) > 60:
                    clipped = f"{clipped}..."
                detail_phrase = f" 참고로 다음 일정 설명은 '{clipped}' 입니다."
                break

        return (
            f"남은 일정은 오전 {morning}개, 오후 {afternoon}개입니다. "
            f"{gap_phrase}.{detail_phrase}"
        )

    def _largest_gap_hours(
        self,
        events: list[dict[str, str | bool]],
        now: datetime.datetime,
    ) -> float:
        timeline: list[tuple[datetime.datetime, datetime.datetime]] = []
        for event in events:
            start_raw = str(event.get("start_time", "")).strip()
            end_raw = str(event.get("end_time", "")).strip()
            if not start_raw or not end_raw:
                continue
            try:
                start = datetime.datetime.fromisoformat(start_raw)
                end = datetime.datetime.fromisoformat(end_raw)
            except ValueError:
                continue
            if end <= start:
                continue
            timeline.append((start, end))

        if not timeline:
            return 0.0

        timeline.sort(key=lambda pair: pair[0])
        pointer = now
        max_gap = datetime.timedelta(0)
        for start, end in timeline:
            if start > pointer:
                max_gap = max(max_gap, start - pointer)
            if end > pointer:
                pointer = end

        return round(max_gap.total_seconds() / 3600.0, 1)

    def _build_signature(self, events: list[CalendarEvent]) -> str:
        keys = [
            (
                f"{e.id}|{e.summary}|{e.description}|"
                f"{e.start_time.isoformat()}|{e.end_time.isoformat()}"
            )
            for e in events
        ]
        keys.sort()
        return "\n".join(keys)

    def _build_slot_key(self, now: datetime.datetime) -> str:
        slot_start_minute = (
            now.minute // self._refresh_slot_minutes
        ) * self._refresh_slot_minutes
        return f"{now.date().isoformat()}-{now.hour:02d}:{slot_start_minute:02d}"

    def _select_relevant_events(
        self,
        events: list[CalendarEvent],
        now: datetime.datetime,
    ) -> list[CalendarEvent]:
        relevant: list[CalendarEvent] = []
        for event in events:
            if event.end_time >= now:
                relevant.append(event)
        relevant.sort(key=lambda e: e.start_time)
        return relevant

    def _normalize_events(
        self,
        events: list[CalendarEvent],
    ) -> list[dict[str, str | bool]]:
        normalized: list[dict[str, str | bool]] = []
        for event in events[: self.max_events]:
            normalized.append(
                {
                    "summary": event.summary,
                    "description": event.description,
                    "start_time": event.start_time.isoformat(),
                    "end_time": event.end_time.isoformat(),
                    "all_day": event.all_day,
                }
            )
        return normalized

    def _load_settings(self) -> None:
        try:
            if not self._settings_path.exists():
                return
            with self._settings_path.open("r", encoding="utf-8") as f:
                data = json.load(f)
            self._enabled = bool(data.get("enabled", self.default_enabled))
            self._tts_enabled = bool(data.get("tts_enabled", self.default_tts_enabled))
        except Exception:
            self._enabled = self.default_enabled
            self._tts_enabled = self.default_tts_enabled

    def _save_settings(self) -> None:
        try:
            self._settings_path.parent.mkdir(parents=True, exist_ok=True)
            payload = {
                "enabled": self._enabled,
                "tts_enabled": self._tts_enabled,
            }
            with self._settings_path.open("w", encoding="utf-8") as f:
                json.dump(payload, f, ensure_ascii=False, indent=2)
        except Exception:
            return
