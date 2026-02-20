import datetime
import re
from dataclasses import dataclass
from typing import Any

from src.services.ai.core import (
    OpenAIJSONClient,
    load_openai_config,
    read_bool_env,
    read_float_env,
    read_int_env,
    request_json_or_empty,
)

SUPPORTED_INTENTS = {"create", "unknown"}
GENERIC_TITLE_TOKENS = {
    "데이트",
    "약속",
    "모임",
    "미팅",
    "회의",
    "식사",
    "점심",
    "저녁",
    "운동",
    "스터디",
    "공부",
    "업무",
    "일정",
    "약속잡기",
}
COMPANION_STOPWORDS = {
    "오늘",
    "내일",
    "모레",
    "글피",
    "이번주",
    "다음주",
    "다다음주",
    "오전",
    "오후",
    "저녁",
    "아침",
    "점심",
    "새벽",
}
KOREAN_WEEKDAY_BY_TOKEN = {
    "월요일": 0,
    "화요일": 1,
    "수요일": 2,
    "목요일": 3,
    "금요일": 4,
    "토요일": 5,
    "일요일": 6,
}
KOREAN_WEEKDAY_NAMES = [
    "월요일",
    "화요일",
    "수요일",
    "목요일",
    "금요일",
    "토요일",
    "일요일",
]


@dataclass(frozen=True)
class NaturalInputParseResult:
    intent: str
    title: str
    start_time: datetime.datetime | None
    end_time: datetime.datetime | None
    all_day: bool
    confidence: float
    raw: dict[str, Any]
    note: str | None = None


class AINaturalInputService:
    def __init__(self):
        self.enabled = read_bool_env("ENABLE_AI_NATURAL_INPUT", default=False)
        self.max_input_chars = max(
            1,
            read_int_env("OPENAI_NATURAL_INPUT_MAX_CHARS", default=300),
        )
        self.default_duration_minutes = max(
            15,
            read_int_env("OPENAI_NATURAL_INPUT_DEFAULT_DURATION_MINUTES", default=60),
        )
        self.min_confidence = max(
            0.0,
            min(
                1.0,
                read_float_env("OPENAI_NATURAL_INPUT_MIN_CONFIDENCE", default=0.6),
            ),
        )

        config = load_openai_config(
            model_env="OPENAI_NATURAL_INPUT_MODEL",
            timeout_env="OPENAI_NATURAL_INPUT_TIMEOUT",
            default_model="gpt-5-mini",
            default_timeout=8.0,
        )
        self._client = OpenAIJSONClient(config)

    def is_ready(self) -> bool:
        return self.enabled and self._client.is_available()

    def get_unavailable_reason(self) -> str:
        if not self.enabled:
            return "ENABLE_AI_NATURAL_INPUT is false."
        if not self._client.is_available():
            return "OPENAI_API_KEY is missing."
        return ""

    def parse(self, text: str) -> NaturalInputParseResult | None:
        normalized = str(text).strip()
        if not normalized:
            return None
        if not self.is_ready():
            return None

        payload = {
            "text": normalized[: self.max_input_chars],
            "timezone": datetime.datetime.now().astimezone().tzname(),
            "now": datetime.datetime.now().astimezone().isoformat(),
            "schema": {
                "intent": "create|unknown",
                "title": (
                    "specific event title preserving key person/context when present "
                    "(e.g., '민지랑 데이트', not only '데이트')"
                ),
                "start_time": "ISO-8601 datetime or null",
                "end_time": "ISO-8601 datetime or null",
                "all_day": "boolean",
                "confidence": "0.0-1.0",
            },
            "rules": {
                "timezone": "Interpret relative dates/times in the provided local timezone.",
                "intent_policy": "If required fields are missing or ambiguous, choose 'unknown'.",
                "title_policy": "Prefer concise but specific title; preserve companion/person context.",
                "timed_default": "If start exists but end is missing, infer end using default duration.",
                "all_day_policy": "For all-day intent, use all_day=true and date-based bounds.",
            },
        }

        data = request_json_or_empty(
            self._client,
            system_prompt=(
                "Task: extract calendar creation intent from Korean/English user text. "
                "Return JSON only and follow the schema exactly. "
                "Rules: "
                "1) intent must be 'create' or 'unknown'. "
                "2) If date/time is unclear for reliable creation, set intent='unknown'. "
                "3) Keep title concise but specific; preserve person/companion context when present. "
                "4) Use ISO-8601 datetimes with timezone when available; otherwise null. "
                "5) Set confidence in [0.0, 1.0] reflecting extraction certainty. "
                "6) Do not add any keys beyond schema fields."
            ),
            user_payload=payload,
            max_output_tokens=700,
            model=self._client.config.model,
        )
        if not data:
            return self._unknown_result(
                raw={},
                note="AI response was empty or invalid JSON.",
            )

        return self._to_result(normalized, data)

    def _to_result(
        self, source_text: str, data: dict[str, Any]
    ) -> NaturalInputParseResult:
        note_parts: list[str] = []

        raw_intent = str(data.get("intent", "unknown")).strip().lower() or "unknown"
        intent = raw_intent if raw_intent in SUPPORTED_INTENTS else "unknown"
        if intent != raw_intent:
            note_parts.append(f"Unsupported intent '{raw_intent}' -> unknown")

        title = str(data.get("title", "")).strip()
        title, title_note = self._enrich_title(source_text, title)
        if title_note:
            note_parts.append(title_note)

        start_time = self._to_optional_datetime(data.get("start_time"))
        end_time = self._to_optional_datetime(data.get("end_time"))
        all_day = bool(data.get("all_day", False))
        confidence = self._to_confidence(data.get("confidence"))

        if confidence < self.min_confidence:
            intent = "unknown"
            note_parts.append(
                f"Confidence {confidence:.2f} below threshold {self.min_confidence:.2f}"
            )

        if all_day:
            start_time, end_time, range_note = self._normalize_all_day_range(
                start_time, end_time
            )
        else:
            start_time, end_time, range_note = self._normalize_timed_range(
                start_time, end_time
            )
        if range_note:
            note_parts.append(range_note)

        weekday_index = self._extract_weekday_index(source_text)
        if (
            weekday_index is not None
            and start_time is not None
            and not self._has_explicit_date(source_text)
        ):
            start_time, end_time, weekday_note = self._apply_weekday_correction(
                source_text,
                weekday_index,
                start_time,
                end_time,
                all_day,
            )
            if weekday_note:
                note_parts.append(weekday_note)

        if intent == "create":
            if not title:
                intent = "unknown"
                note_parts.append("Missing title for create intent")
            if start_time is None:
                intent = "unknown"
                note_parts.append("Missing start_time for create intent")

        return NaturalInputParseResult(
            intent=intent,
            title=title,
            start_time=start_time,
            end_time=end_time,
            all_day=all_day,
            confidence=confidence,
            raw=data,
            note="; ".join(note_parts) if note_parts else None,
        )

    def _enrich_title(self, source_text: str, title: str) -> tuple[str, str | None]:
        normalized_title = str(title).strip()
        if not normalized_title:
            return (normalized_title, None)
        if not self._is_generic_title(normalized_title):
            return (normalized_title, None)

        companion_phrase = self._extract_companion_phrase(source_text)
        if not companion_phrase:
            return (normalized_title, None)
        if companion_phrase in normalized_title:
            return (normalized_title, None)

        enriched_title = f"{companion_phrase} {normalized_title}".strip()
        note = f"Title enriched with companion context: {companion_phrase}"
        return (enriched_title, note)

    @staticmethod
    def _is_generic_title(title: str) -> bool:
        normalized = re.sub(r"\s+", "", str(title)).lower()
        return normalized in GENERIC_TITLE_TOKENS

    @staticmethod
    def _extract_companion_phrase(source_text: str) -> str | None:
        patterns = [
            r"([가-힣A-Za-z]{2,20})\s*(랑|와|과)",
            r"([가-힣A-Za-z]{2,20})\s*와\s*함께",
        ]

        for pattern in patterns:
            match = re.search(pattern, source_text)
            if not match:
                continue

            name = str(match.group(1)).strip()
            if not name or name in COMPANION_STOPWORDS:
                continue

            if "함께" in pattern:
                return f"{name}와"

            particle = (
                str(match.group(2)).strip()
                if match.lastindex and match.lastindex >= 2
                else "랑"
            )
            if not particle:
                particle = "랑"
            return f"{name}{particle}"

        return None

    @staticmethod
    def _extract_weekday_index(text: str) -> int | None:
        for token, weekday in KOREAN_WEEKDAY_BY_TOKEN.items():
            if token in text:
                return weekday

        matched = re.search(r"([월화수목금토일])\s*요일", text)
        if not matched:
            return None

        token = f"{matched.group(1)}요일"
        return KOREAN_WEEKDAY_BY_TOKEN.get(token)

    @staticmethod
    def _has_explicit_date(text: str) -> bool:
        patterns = [
            r"\d{4}-\d{1,2}-\d{1,2}",
            r"\d{4}/\d{1,2}/\d{1,2}",
            r"\d{1,2}\s*월\s*\d{1,2}\s*일",
            r"\d{1,4}\s*년",
        ]
        return any(re.search(pattern, text) for pattern in patterns)

    def _apply_weekday_correction(
        self,
        source_text: str,
        weekday_index: int,
        start_time: datetime.datetime,
        end_time: datetime.datetime | None,
        all_day: bool,
    ) -> tuple[datetime.datetime, datetime.datetime | None, str | None]:
        target_date = self._resolve_weekday_date(source_text, weekday_index)
        if target_date is None:
            return (start_time, end_time, None)

        original_date = start_time.date()
        if original_date == target_date:
            return (start_time, end_time, None)

        if all_day:
            tzinfo = start_time.tzinfo or datetime.timezone.utc
            corrected_start = datetime.datetime.combine(
                target_date,
                datetime.time.min,
                tzinfo=tzinfo,
            )
            corrected_end = corrected_start + datetime.timedelta(days=1)
            note = (
                f"Weekday '{self._weekday_name(weekday_index)}' corrected from {original_date.isoformat()} "
                f"to {target_date.isoformat()}"
            )
            return (corrected_start, corrected_end, note)

        duration = datetime.timedelta(minutes=self.default_duration_minutes)
        if end_time is not None and end_time > start_time:
            duration = end_time - start_time

        corrected_start = start_time.replace(
            year=target_date.year,
            month=target_date.month,
            day=target_date.day,
        )
        corrected_end = corrected_start + duration
        note = (
            f"Weekday '{self._weekday_name(weekday_index)}' corrected from {original_date.isoformat()} "
            f"to {target_date.isoformat()}"
        )
        return (corrected_start, corrected_end, note)

    @staticmethod
    def _weekday_name(index: int) -> str:
        if 0 <= index < len(KOREAN_WEEKDAY_NAMES):
            return KOREAN_WEEKDAY_NAMES[index]
        return str(index)

    @staticmethod
    def _resolve_weekday_date(
        source_text: str, weekday_index: int
    ) -> datetime.date | None:
        now = datetime.datetime.now().astimezone().date()
        normalized = source_text.replace(" ", "")
        week_start = now - datetime.timedelta(days=now.weekday())

        if "다다음주" in normalized:
            return week_start + datetime.timedelta(days=14 + weekday_index)

        if "다음주" in normalized:
            return week_start + datetime.timedelta(days=7 + weekday_index)

        if "이번주" in normalized or "금주" in normalized:
            return week_start + datetime.timedelta(days=weekday_index)

        delta = (weekday_index - now.weekday()) % 7
        return now + datetime.timedelta(days=delta)

    @staticmethod
    def _unknown_result(raw: dict[str, Any], note: str) -> NaturalInputParseResult:
        return NaturalInputParseResult(
            intent="unknown",
            title="",
            start_time=None,
            end_time=None,
            all_day=False,
            confidence=0.0,
            raw=raw,
            note=note,
        )

    @staticmethod
    def _to_optional_datetime(value: Any) -> datetime.datetime | None:
        if value is None:
            return None

        text = str(value).strip()
        if not text:
            return None

        normalized = text
        if normalized.endswith("Z"):
            normalized = normalized[:-1] + "+00:00"

        try:
            parsed = datetime.datetime.fromisoformat(normalized)
        except ValueError:
            return None

        if parsed.tzinfo is None:
            local_tz = datetime.datetime.now().astimezone().tzinfo
            if local_tz is None:
                local_tz = datetime.timezone.utc
            parsed = parsed.replace(tzinfo=local_tz)

        return parsed.astimezone()

    @staticmethod
    def _to_confidence(value: Any) -> float:
        try:
            numeric = float(value)
        except (TypeError, ValueError):
            return 0.0
        return max(0.0, min(1.0, numeric))

    def _normalize_timed_range(
        self,
        start_time: datetime.datetime | None,
        end_time: datetime.datetime | None,
    ) -> tuple[datetime.datetime | None, datetime.datetime | None, str | None]:
        duration = datetime.timedelta(minutes=self.default_duration_minutes)
        note: str | None = None

        if start_time is None and end_time is None:
            return (None, None, "Missing both start_time and end_time")

        if start_time is None and end_time is not None:
            start_time = end_time - duration
            note = "start_time missing, estimated from end_time"

        if end_time is None and start_time is not None:
            end_time = start_time + duration
            note = "end_time missing, estimated default duration"

        if start_time is None or end_time is None:
            return (start_time, end_time, note)

        if end_time <= start_time:
            end_time = start_time + duration
            note = "end_time not after start_time, adjusted to default duration"

        return (start_time, end_time, note)

    @staticmethod
    def _start_of_day(value: datetime.datetime) -> datetime.datetime:
        return value.replace(hour=0, minute=0, second=0, microsecond=0)

    def _normalize_all_day_range(
        self,
        start_time: datetime.datetime | None,
        end_time: datetime.datetime | None,
    ) -> tuple[datetime.datetime | None, datetime.datetime | None, str | None]:
        note: str | None = None

        if start_time is None and end_time is None:
            return (None, None, "Missing all-day date")

        if start_time is None and end_time is not None:
            start_time = end_time
            note = "start_time missing for all-day event, inferred from end_time"

        if start_time is not None:
            start_time = self._start_of_day(start_time)

        if end_time is None and start_time is not None:
            end_time = start_time + datetime.timedelta(days=1)
            note = "end_time missing for all-day event, set to next day"
        elif end_time is not None:
            end_time = self._start_of_day(end_time)

        if start_time is None or end_time is None:
            return (start_time, end_time, note)

        if end_time <= start_time:
            end_time = start_time + datetime.timedelta(days=1)
            note = "all-day end_time adjusted to next day"

        return (start_time, end_time, note)
