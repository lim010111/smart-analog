from collections.abc import Iterable

from PySide6.QtGui import QColor

from src.models.event import CalendarEvent
from src.services.ai.color_schema import ColorRule, CustomColorSchema
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
            default_model="gpt-4o-mini",
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
                "Classify each title into one category. "
                "If no category fits, use 'unmatched'. "
                "Return strict JSON with this shape: "
                "{'items':[{'title':'...','category':'...'}]}"
            ),
        }

        data = request_json_or_empty(
            self._openai_client,
            system_prompt=(
                "You classify calendar event titles. "
                "Use only allowed_categories. "
                "If uncertain, use 'unmatched'. "
                "Respond with valid JSON only."
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

    def generate_keywords_for_rules(self, rules: list[ColorRule]) -> list[ColorRule]:
        if not self._openai_client.is_available() or not rules:
            return rules

        labels = [rule.label for rule in rules if rule.label.strip()]
        if not labels:
            return rules

        prompt = {
            "categories": labels,
            "instructions": (
                "For each category label, generate 5-10 keywords (Korean and English) "
                "that calendar event titles in that category would typically contain. "
                "Return strict JSON: "
                "{'items':[{'label':'...','keywords':['kw1','kw2',...]}]}"
            ),
        }

        data = request_json_or_empty(
            self._openai_client,
            system_prompt=(
                "You generate keywords for calendar event categories. "
                "Keywords should be short, lowercase words or phrases "
                "that commonly appear in calendar event titles. "
                "Include both Korean and English keywords. "
                "Respond with valid JSON only."
            ),
            user_payload=prompt,
            max_output_tokens=1000,
            model=self.model,
        )
        if not data:
            return rules

        items = data.get("items")
        if not isinstance(items, list):
            return rules

        keywords_by_label: dict[str, list[str]] = {}
        for item in items:
            if not isinstance(item, dict):
                continue
            label = str(item.get("label", "")).strip()
            keywords = item.get("keywords", [])
            if label and isinstance(keywords, list):
                keywords_by_label[label] = [
                    str(kw).strip().lower()
                    for kw in keywords
                    if isinstance(kw, str) and kw.strip()
                ]

        for rule in rules:
            generated = keywords_by_label.get(rule.label, [])
            if generated:
                rule.keywords = generated

        return rules
