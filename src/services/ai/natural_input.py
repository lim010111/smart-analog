import datetime
import re
from dataclasses import dataclass
from typing import Any
from zoneinfo import ZoneInfo

from src.services.ai.core import (
    OpenAIJSONClient,
    load_openai_config,
    read_bool_env,
    read_float_env,
    read_int_env,
    request_json_with_error,
)
from src.services.ai.core.tracing import traceable_span

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
KOREAN_HOUR_WORDS = {
    "한": 1,
    "하나": 1,
    "두": 2,
    "둘": 2,
    "세": 3,
    "셋": 3,
    "네": 4,
    "넷": 4,
    "다섯": 5,
    "여섯": 6,
    "일곱": 7,
    "여덟": 8,
    "아홉": 9,
    "열": 10,
    "열한": 11,
    "열두": 12,
}

NATURAL_INPUT_RESPONSE_FORMAT: dict[str, Any] = {
    "type": "json_schema",
    "name": "natural_input_parse_result",
    "strict": True,
    "schema": {
        "type": "object",
        "additionalProperties": False,
        "required": [
            "intent",
            "title",
            "start_time",
            "end_time",
            "duration_minutes",
            "all_day",
            "confidence",
        ],
        "properties": {
            "intent": {
                "type": "string",
                "enum": ["create", "unknown"],
            },
            "title": {"type": "string"},
            "start_time": {
                "anyOf": [
                    {"type": "string"},
                    {"type": "null"},
                ]
            },
            "end_time": {
                "anyOf": [
                    {"type": "string"},
                    {"type": "null"},
                ]
            },
            "duration_minutes": {
                "anyOf": [
                    {"type": "integer"},
                    {"type": "null"},
                ]
            },
            "all_day": {"type": "boolean"},
            "confidence": {"type": "number"},
        },
    },
}

NATURAL_INPUT_SYSTEM_PROMPT = (
    "Task: extract calendar creation intent from Korean/English user text. "
    "Return JSON only and follow the schema exactly. "
    "Rules: "
    "1) intent must be 'create' or 'unknown'. "
    "2) If date/time is unclear for reliable creation, set intent='unknown'. "
    "3) Keep title concise but specific; preserve person/companion context when present. "
    "4) Use ISO-8601 datetimes with timezone when available; otherwise null. "
    "5) Extract duration_minutes when duration is explicitly stated. "
    "6) If duration crosses midnight, end_time must roll over to next day. "
    "7) Set confidence in [0.0, 1.0] reflecting extraction certainty. "
    "8) Do not add any keys beyond schema fields."
)


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
        self.max_output_tokens = max(
            64,
            read_int_env("OPENAI_NATURAL_INPUT_MAX_OUTPUT_TOKENS", default=180),
        )

        config = load_openai_config(
            model_env="OPENAI_NATURAL_INPUT_MODEL",
            timeout_env="OPENAI_NATURAL_INPUT_TIMEOUT",
            reasoning_effort_env="OPENAI_NATURAL_INPUT_REASONING_EFFORT",
            default_model="gpt-5-mini",
            default_timeout=8.0,
            default_reasoning_effort="minimal",
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

    @traceable_span(
        name="ai.natural_input.parse",
        run_type="chain",
        tags=["natural-input"],
    )
    def parse(self, text: str) -> NaturalInputParseResult | None:
        normalized = str(text).strip()
        if not normalized:
            return None
        if not self.is_ready():
            return None

        if self._is_local_fast_path_candidate(normalized):
            fast_local = self._parse_with_local_rules(
                normalized,
                upstream_note="",
                mode="fast",
            )
            if fast_local is not None:
                return fast_local

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
                "duration_minutes": "integer minutes or null",
                "all_day": "boolean",
                "confidence": "0.0-1.0",
            },
            "rules": {
                "timezone": "Interpret relative dates/times in the provided local timezone.",
                "intent_policy": "If required fields are missing or ambiguous, choose 'unknown'.",
                "title_policy": "Prefer concise but specific title; preserve companion/person context.",
                "timed_default": "If start exists but end is missing, infer end using duration_minutes if available, otherwise default duration.",
                "all_day_policy": "For all-day intent, use all_day=true and date-based bounds.",
                "rollover_policy": "If timed duration passes midnight, set end_time to the next day (do not truncate).",
                "duration_policy": "When user says duration (e.g., 두시간, 3시간반), set duration_minutes and keep end_time consistent with it.",
            },
            "examples": [
                {
                    "text": "오늘 친구랑 저녁 11시에 게임 약속, 세시간 정도 할 예정",
                    "output": {
                        "intent": "create",
                        "title": "친구랑 게임 약속",
                        "start_time": "today 23:00 in local timezone",
                        "end_time": "next day 02:00 in local timezone",
                        "duration_minutes": 180,
                        "all_day": False,
                        "confidence": 0.9,
                    },
                }
            ],
        }

        data, request_error = request_json_with_error(
            self._client,
            system_prompt=NATURAL_INPUT_SYSTEM_PROMPT,
            user_payload=payload,
            max_output_tokens=self.max_output_tokens,
            model=self._client.config.model,
            text_format=NATURAL_INPUT_RESPONSE_FORMAT,
        )
        if not data:
            fallback_data: dict[str, Any] = {}
            fallback_error: str | None = None
            if self._should_retry_without_schema(request_error):
                fallback_data, fallback_error = request_json_with_error(
                    self._client,
                    system_prompt=NATURAL_INPUT_SYSTEM_PROMPT,
                    user_payload=payload,
                    max_output_tokens=min(self.max_output_tokens + 60, 300),
                    model=self._client.config.model,
                )
                if fallback_data:
                    return self._to_result(normalized, fallback_data)

            failures = [
                str(value).strip()
                for value in (request_error, fallback_error)
                if str(value).strip()
            ]
            note = " | ".join(dict.fromkeys(failures))
            local_result = self._parse_with_local_rules(
                normalized,
                note,
                mode="fallback",
            )
            if local_result is not None:
                return local_result
            if not note:
                note = "AI response was empty or invalid JSON."
            return self._unknown_result(
                raw={},
                note=note,
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
        explicit_duration_minutes = self._extract_duration_minutes_from_ai(
            data.get("duration_minutes")
        )
        if explicit_duration_minutes is None:
            explicit_duration_minutes = self._extract_duration_minutes(source_text)

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
                start_time,
                end_time,
                explicit_duration_minutes=explicit_duration_minutes,
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

    def _parse_with_local_rules(
        self,
        source_text: str,
        upstream_note: str,
        mode: str,
    ) -> NaturalInputParseResult | None:
        normalized_source = self._normalize_local_text_for_time(source_text)
        parsed_range = self._extract_local_korean_time_range(normalized_source)
        if parsed_range is None:
            parsed_range = self._extract_local_start_with_duration(normalized_source)
        if parsed_range is None:
            return None

        start_time, end_time, span_text = parsed_range
        title = self._extract_local_title(normalized_source, span_text)
        if not title:
            return None

        local_raw = {
            "intent": "create",
            "title": title,
            "start_time": start_time.isoformat(),
            "end_time": end_time.isoformat(),
            "duration_minutes": max(
                1,
                int((end_time - start_time).total_seconds() // 60),
            ),
            "all_day": False,
            "confidence": max(self.min_confidence, 0.72),
        }
        base_result = self._to_result(normalized_source, local_raw)
        if base_result.intent != "create":
            return None

        mode_label = "Local rule fast path used"
        if mode != "fast":
            mode_label = "Local rule fallback used after AI parse failure"

        note_parts = [
            mode_label,
            f"AI error: {upstream_note}" if upstream_note else "",
            base_result.note or "",
        ]
        merged_note = "; ".join(part for part in note_parts if part)

        return NaturalInputParseResult(
            intent=base_result.intent,
            title=base_result.title,
            start_time=base_result.start_time,
            end_time=base_result.end_time,
            all_day=base_result.all_day,
            confidence=base_result.confidence,
            raw=local_raw,
            note=merged_note or None,
        )

    @staticmethod
    def _resolve_local_relative_date(
        source_text: str, tzinfo: datetime.tzinfo
    ) -> datetime.date:
        normalized = source_text.replace(" ", "")
        today = datetime.datetime.now(tzinfo).date()
        if "글피" in normalized:
            return today + datetime.timedelta(days=3)
        if "모레" in normalized:
            return today + datetime.timedelta(days=2)
        if "내일" in normalized:
            return today + datetime.timedelta(days=1)
        return today

    @staticmethod
    def _preferred_local_timezone(source_text: str) -> datetime.tzinfo:
        if re.search(r"[가-힣]", source_text):
            return ZoneInfo("Asia/Seoul")
        local_tz = datetime.datetime.now().astimezone().tzinfo
        return local_tz or datetime.timezone.utc

    @staticmethod
    def _to_local_clock(
        hour: int,
        minute: int,
        meridiem: str | None,
        source_text: str,
    ) -> tuple[int, int]:
        normalized_meridiem = AINaturalInputService._infer_meridiem_from_context(
            source_text,
            hour,
            meridiem,
        )
        base_hour = int(hour)
        base_minute = int(minute)

        if normalized_meridiem == "오전":
            if base_hour == 12:
                return (0, base_minute)
            return (base_hour, base_minute)

        if normalized_meridiem == "오후":
            if base_hour == 12:
                return (12, base_minute)
            return (base_hour + 12, base_minute)

        if base_hour >= 24:
            return (base_hour % 24, base_minute)
        return (base_hour, base_minute)

    @staticmethod
    def _infer_meridiem_from_context(
        source_text: str,
        hour: int,
        meridiem: str | None,
    ) -> str:
        explicit = (meridiem or "").strip()
        if explicit in {"오전", "오후"}:
            return explicit

        text = str(source_text)
        if "새벽" in text or "아침" in text:
            return "오전"
        if "오후" in text or "저녁" in text or "밤" in text:
            return "오후"
        if hour == 12:
            return "오후"
        if 1 <= hour <= 7:
            return "오후"
        return ""

    def _extract_local_korean_time_range(
        self, source_text: str
    ) -> tuple[datetime.datetime, datetime.datetime, str] | None:
        pattern = re.compile(
            r"(?P<start_ampm>오전|오후)?\s*(?P<start_hour>\d{1,2})시"
            r"(?P<start_half>반)?(?:(?P<start_min>\d{1,2})분)?\s*(?:부터|~|-)\s*"
            r"(?P<end_ampm>오전|오후)?\s*(?P<end_hour>\d{1,2})시"
            r"(?P<end_half>반)?(?:(?P<end_min>\d{1,2})분)?\s*(?:까지)?"
        )
        matched = pattern.search(source_text)
        if matched is None:
            return None

        start_minute = int(matched.group("start_min") or "0")
        end_minute = int(matched.group("end_min") or "0")
        if matched.group("start_half"):
            start_minute += 30
        if matched.group("end_half"):
            end_minute += 30

        start_ampm = matched.group("start_ampm")
        end_ampm = matched.group("end_ampm")
        if not end_ampm:
            if start_ampm == "오전" and int(matched.group("end_hour")) == 12:
                end_ampm = "오후"
            else:
                end_ampm = start_ampm

        start_hour, start_minute = self._to_local_clock(
            int(matched.group("start_hour")),
            start_minute,
            start_ampm,
            source_text,
        )
        end_hour, end_minute = self._to_local_clock(
            int(matched.group("end_hour")),
            end_minute,
            end_ampm,
            source_text,
        )

        tzinfo = self._preferred_local_timezone(source_text)
        target_date = self._resolve_local_relative_date(source_text, tzinfo)
        start_time = datetime.datetime.combine(
            target_date,
            datetime.time(hour=start_hour, minute=start_minute),
            tzinfo=tzinfo,
        )
        end_time = datetime.datetime.combine(
            target_date,
            datetime.time(hour=end_hour, minute=end_minute),
            tzinfo=tzinfo,
        )

        if end_time <= start_time:
            end_time += datetime.timedelta(days=1)

        return (start_time, end_time, matched.group(0))

    def _extract_local_start_with_duration(
        self, source_text: str
    ) -> tuple[datetime.datetime, datetime.datetime, str] | None:
        pattern = re.compile(
            r"(?P<ampm>오전|오후)?\s*(?P<hour>\d{1,2})시"
            r"(?P<half>반)?(?:(?P<minute>\d{1,2})분)?\s*(?:에)?"
        )
        matched = pattern.search(source_text)
        if matched is None:
            return None

        span_text = matched.group(0)
        if "부터" in source_text[max(0, matched.start() - 4) : matched.end() + 4]:
            return None

        minute = int(matched.group("minute") or "0")
        if matched.group("half"):
            minute += 30

        hour, minute = self._to_local_clock(
            int(matched.group("hour")),
            minute,
            matched.group("ampm"),
            source_text,
        )
        tzinfo = self._preferred_local_timezone(source_text)
        target_date = self._resolve_local_relative_date(source_text, tzinfo)
        start_time = datetime.datetime.combine(
            target_date,
            datetime.time(hour=hour, minute=minute),
            tzinfo=tzinfo,
        )

        duration_minutes = self._extract_duration_minutes(source_text)
        if duration_minutes is None:
            without_time = source_text.replace(span_text, " ")
            minute_match = re.search(r"(?P<mins>\d{1,3})분", without_time)
            if minute_match:
                duration_minutes = int(minute_match.group("mins"))
        if duration_minutes is None:
            duration_minutes = self.default_duration_minutes
        end_time = start_time + datetime.timedelta(minutes=duration_minutes)
        return (start_time, end_time, span_text)

    @staticmethod
    def _extract_local_title(source_text: str, time_span_text: str) -> str:
        title = source_text.replace(time_span_text, " ")
        for token in ("오늘", "내일", "모레", "글피", "오전", "오후", "부터", "까지"):
            title = title.replace(token, " ")
        title = re.sub(
            r"\d{1,2}시간(?:반)?(?:\d{1,2}분)?|"
            r"(한|하나|두|둘|세|셋|네|넷|다섯|여섯|일곱|여덟|아홉|열)시간(?:반)?(?:\d{1,2}분)?|"
            r"\d{1,3}분",
            " ",
            title,
        )
        title = re.sub(
            r"\s*(일정\s*)?(추가해줘|추가해 줘|추가|생성해줘|생성해 줘|만들어줘|만들어 줘|등록해줘|등록해 줘)\s*$",
            "",
            title,
        )
        title = re.sub(
            r"\s*(보기로|보기|만나기로|만나기|만남)\s*$",
            "",
            title,
        )
        title = re.sub(r"\s+", " ", title).strip(" .,!?")
        return title[:80].strip()

    @staticmethod
    def _should_retry_without_schema(request_error: str | None) -> bool:
        if not request_error:
            return False
        text = str(request_error).strip().lower()
        if not text:
            return False

        schema_hints = (
            "json_schema",
            "schema",
            "text.format",
            "response format",
            "unknown parameter",
            "invalid type",
            "unsupported",
        )
        return any(hint in text for hint in schema_hints)

    @staticmethod
    def _is_local_fast_path_candidate(source_text: str) -> bool:
        text = str(source_text).strip()
        if not text:
            return False
        if not re.search(r"[가-힣]", text):
            return False

        has_time = bool(
            re.search(
                r"(오늘|내일|모레|글피|다음주|이번주|다다음주|"
                r"월요일|화요일|수요일|목요일|금요일|토요일|일요일|"
                r"오전|오후|\d{1,2}\s*시|한\s*시|두\s*시|세\s*시|네\s*시)",
                text,
            )
        )
        if not has_time:
            return False

        has_event_context = bool(
            re.search(
                r"(랑|와|과|약속|회의|미팅|알바|보기|만나|식사|점심|저녁|운동|스터디|일정)",
                text,
            )
        )
        return has_event_context

    @staticmethod
    def _normalize_local_text_for_time(source_text: str) -> str:
        normalized = str(source_text)
        replacements = sorted(
            KOREAN_HOUR_WORDS.items(),
            key=lambda item: len(item[0]),
            reverse=True,
        )
        for word, hour in replacements:
            pattern = re.compile(rf"(?<![가-힣A-Za-z0-9]){re.escape(word)}\s*시")
            normalized = pattern.sub(f"{hour}시", normalized)
        return normalized

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

    @staticmethod
    def _extract_duration_minutes(source_text: str) -> int | None:
        normalized = re.sub(r"\s+", "", str(source_text))
        if not normalized:
            return None

        digit_match = re.search(
            r"(?P<hours>\d{1,2})시간(?:(?P<half>반))?(?:(?P<mins>\d{1,2})분)?",
            normalized,
        )
        if digit_match:
            hours = int(digit_match.group("hours"))
            minutes = int(digit_match.group("mins") or "0")
            if digit_match.group("half"):
                minutes += 30
            total = (hours * 60) + minutes
            return total if total > 0 else None

        word_match = re.search(
            r"(?P<word>한|하나|두|둘|세|셋|네|넷|다섯|여섯|일곱|여덟|아홉|열)시간"
            r"(?:(?P<half>반))?(?:(?P<mins>\d{1,2})분)?",
            normalized,
        )
        if word_match:
            word = str(word_match.group("word"))
            hours = KOREAN_HOUR_WORDS.get(word)
            if hours is None:
                return None
            minutes = int(word_match.group("mins") or "0")
            if word_match.group("half"):
                minutes += 30
            total = (hours * 60) + minutes
            return total if total > 0 else None

        return None

    @staticmethod
    def _extract_duration_minutes_from_ai(value: Any) -> int | None:
        if value is None:
            return None
        try:
            minutes = int(str(value).strip())
        except (TypeError, ValueError):
            return None
        if minutes <= 0:
            return None
        if minutes > 24 * 60:
            return None
        return minutes

    def _normalize_timed_range(
        self,
        start_time: datetime.datetime | None,
        end_time: datetime.datetime | None,
        explicit_duration_minutes: int | None = None,
    ) -> tuple[datetime.datetime | None, datetime.datetime | None, str | None]:
        duration_minutes = explicit_duration_minutes or self.default_duration_minutes
        duration = datetime.timedelta(minutes=duration_minutes)
        note: str | None = None

        if start_time is None and end_time is None:
            return (None, None, "Missing both start_time and end_time")

        if start_time is None and end_time is not None:
            start_time = end_time - duration
            note = "start_time missing, estimated from end_time"

        if end_time is None and start_time is not None:
            end_time = start_time + duration
            if explicit_duration_minutes is not None:
                note = f"end_time missing, estimated from explicit duration ({duration_minutes} minutes)"
            else:
                note = "end_time missing, estimated default duration"

        if start_time is None or end_time is None:
            return (start_time, end_time, note)

        if explicit_duration_minutes is not None and end_time > start_time:
            expected_end = start_time + duration
            difference_minutes = abs(
                int((end_time - expected_end).total_seconds() / 60)
            )
            if difference_minutes >= 5:
                end_time = expected_end
                note = f"end_time adjusted to explicit duration ({duration_minutes} minutes)"

        if end_time <= start_time:
            end_time = start_time + duration
            if explicit_duration_minutes is not None:
                note = f"end_time not after start_time, adjusted to explicit duration ({duration_minutes} minutes)"
            else:
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
