from collections.abc import Iterable

from PySide6.QtGui import QColor

from src.models.event import CalendarEvent
from src.services.ai.color_schema import CustomColorSchema
from src.services.ai.core import (
    OpenAIJSONClient,
    load_openai_config,
    read_bool_env,
    read_int_env,
    request_json_or_empty,
)


class AIEventColorService:
    def __init__(self):
        self.enabled = read_bool_env("ENABLE_AI_EVENT_COLOR", default=False)
        self.max_titles = max(1, read_int_env("OPENAI_COLOR_MAX_TITLES", default=30))

        openai_config = load_openai_config(
            model_env="OPENAI_COLOR_MODEL",
            timeout_env="OPENAI_COLOR_TIMEOUT",
            default_model="gpt-5-nano",
            default_timeout=8.0,
        )
        self._openai_client = OpenAIJSONClient(openai_config)
        self.api_key = openai_config.api_key
        self.model = openai_config.model
        self.timeout_seconds = openai_config.timeout_seconds

        self._custom_schema = CustomColorSchema()
        self._supported_palette: list[str] = []

    @property
    def custom_schema(self) -> CustomColorSchema:
        return self._custom_schema

    def reload_schema(self) -> None:
        self._custom_schema.load()
        if self._supported_palette:
            self._custom_schema.restrict_to_palette(self._supported_palette)

    def set_supported_palette(self, palette: list[str]) -> None:
        normalized: list[str] = []
        seen: set[str] = set()
        for value in palette:
            color_hex = str(value or "").strip().lower()
            if not color_hex or color_hex in seen:
                continue
            seen.add(color_hex)
            normalized.append(color_hex)
        self._supported_palette = normalized
        self._custom_schema.restrict_to_palette(self._supported_palette)

    def get_supported_palette(self) -> list[str]:
        return list(self._supported_palette)

    def apply(self, events: list[CalendarEvent]) -> list[CalendarEvent]:
        if (
            not events
            or not self.enabled
            or not self._supported_palette
            or self._custom_schema.is_empty
        ):
            return events

        titles = self._collect_titles(events)
        if not titles:
            return events

        categories = self._classify_titles(titles)
        self._apply_categories(events, categories)
        return events

    def _collect_titles(self, events: Iterable[CalendarEvent]) -> list[str]:
        unique_titles: list[str] = []
        seen: set[str] = set()

        for event in events:
            title = str(event.summary).strip()
            if not title:
                continue

            lowered = title.lower()
            if lowered in seen:
                continue

            seen.add(lowered)
            unique_titles.append(title)

        return unique_titles[: self.max_titles]

    def _classify_titles(self, titles: list[str]) -> dict[str, str]:
        if self._openai_client.is_available():
            categories = self._classify_with_openai(titles)
            if categories:
                return categories

        return self._classify_with_keywords(titles)

    def _classify_with_openai(self, titles: list[str]) -> dict[str, str]:
        prompt = {
            "titles": titles,
            "allowed_categories": sorted(
                self._custom_schema.to_category_colors().keys()
            ),
            "instructions": (
                "Classify each title into exactly one category from allowed_categories. "
                "Use 'unmatched' when no category clearly fits. "
                "Do not invent categories. "
                "Return strict JSON only with shape: "
                "{'items':[{'title':'...','category':'...'}]}"
            ),
        }

        data = request_json_or_empty(
            self._openai_client,
            system_prompt=(
                "Task: classify Korean/English calendar event titles for color mapping. "
                "Rules: "
                "1) Use only values in allowed_categories. "
                "2) Choose one category per input title. "
                "3) Preserve the exact input title text in output. "
                "4) If uncertain, ambiguous, or multi-topic, pick 'unmatched'. "
                "5) Never output text outside JSON. "
                "Output JSON object only: {'items':[{'title':str,'category':str}]}."
            ),
            user_payload=prompt,
            max_output_tokens=500,
            model=self.model,
        )
        if not data:
            return {}

        items = data.get("items")
        if not isinstance(items, list):
            return {}

        categories: dict[str, str] = {}
        for item in items:
            if not isinstance(item, dict):
                continue
            title = str(item.get("title", "")).strip()
            category = self._normalize_category(item.get("category"))
            if title and category:
                categories[title.lower()] = category

        return categories

    def _classify_with_keywords(self, titles: list[str]) -> dict[str, str]:
        schema_rules = self._custom_schema.to_keyword_rules()

        categories: dict[str, str] = {}
        for title in titles:
            lowered = title.lower()
            categories[lowered] = "unmatched"

            for category, keywords in schema_rules.items():
                if any(keyword in lowered for keyword in keywords):
                    categories[lowered] = category
                    break

        return categories

    def _normalize_category(self, value: object) -> str:
        category = str(value or "").strip().lower()
        allowed = set(self._custom_schema.to_category_colors().keys())
        if category in allowed:
            return category
        return "unmatched"

    def _apply_categories(
        self,
        events: list[CalendarEvent],
        categories_by_title: dict[str, str],
    ) -> None:
        schema_colors = self._custom_schema.to_category_colors()
        for event in events:
            title = str(event.summary).strip().lower()
            category = categories_by_title.get(title, "unmatched")
            hex_color = schema_colors.get(category)
            if not hex_color:
                continue
            if hex_color.lower() not in self._supported_palette:
                continue
            color = QColor(hex_color)
            color.setAlpha(180)
            event.color = color
