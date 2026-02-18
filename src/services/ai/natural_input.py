import datetime
from dataclasses import dataclass
from typing import Any

from src.services.ai.core import (
    OpenAIJSONClient,
    load_openai_config,
    read_bool_env,
    read_int_env,
    request_json_or_empty,
)


@dataclass(frozen=True)
class NaturalInputParseResult:
    intent: str
    title: str
    start_time: str | None
    end_time: str | None
    all_day: bool
    confidence: float
    raw: dict[str, Any]


class AINaturalInputService:
    def __init__(self):
        self.enabled = read_bool_env("ENABLE_AI_NATURAL_INPUT", default=False)
        self.max_input_chars = max(
            1,
            read_int_env("OPENAI_NATURAL_INPUT_MAX_CHARS", default=300),
        )

        config = load_openai_config(
            model_env="OPENAI_NATURAL_INPUT_MODEL",
            timeout_env="OPENAI_NATURAL_INPUT_TIMEOUT",
            default_model="gpt-4o-mini",
            default_timeout=8.0,
        )
        self._client = OpenAIJSONClient(config)

    def parse(self, text: str) -> NaturalInputParseResult | None:
        normalized = str(text).strip()
        if not normalized:
            return None
        if not self.enabled or not self._client.is_available():
            return None

        payload = {
            "text": normalized[: self.max_input_chars],
            "timezone": datetime.datetime.now().astimezone().tzname(),
            "now": datetime.datetime.now().astimezone().isoformat(),
            "schema": {
                "intent": "create|update|delete|query|unknown",
                "title": "event title",
                "start_time": "ISO-8601 datetime or null",
                "end_time": "ISO-8601 datetime or null",
                "all_day": "boolean",
                "confidence": "0.0-1.0",
            },
        }

        data = request_json_or_empty(
            self._client,
            system_prompt=(
                "Extract calendar intent from user text. "
                "Return valid JSON only and follow the provided schema exactly."
            ),
            user_payload=payload,
            max_output_tokens=700,
            model=self._client.config.model,
        )
        if not data:
            return None

        return self._to_result(data)

    def _to_result(self, data: dict[str, Any]) -> NaturalInputParseResult | None:
        intent = str(data.get("intent", "unknown")).strip().lower() or "unknown"
        title = str(data.get("title", "")).strip()
        start_time = self._to_optional_string(data.get("start_time"))
        end_time = self._to_optional_string(data.get("end_time"))
        all_day = bool(data.get("all_day", False))
        confidence = self._to_confidence(data.get("confidence"))

        return NaturalInputParseResult(
            intent=intent,
            title=title,
            start_time=start_time,
            end_time=end_time,
            all_day=all_day,
            confidence=confidence,
            raw=data,
        )

    @staticmethod
    def _to_optional_string(value: Any) -> str | None:
        if value is None:
            return None
        text = str(value).strip()
        return text or None

    @staticmethod
    def _to_confidence(value: Any) -> float:
        try:
            numeric = float(value)
        except (TypeError, ValueError):
            return 0.0
        return max(0.0, min(1.0, numeric))
