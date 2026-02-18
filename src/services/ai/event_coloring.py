import json
import importlib
import os
from collections.abc import Iterable

from dotenv import load_dotenv
from PySide6.QtGui import QColor

from src.models.event import CalendarEvent
from src.services.ai.color_schema import ColorRule, CustomColorSchema


def _to_bool(value: str | None, default: bool = False) -> bool:
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


class AIEventColorService:
    def __init__(self):
        load_dotenv()
        self.enabled = _to_bool(os.getenv("ENABLE_AI_EVENT_COLOR"), default=False)
        self.api_key = os.getenv("OPENAI_API_KEY", "").strip()
        self.model = os.getenv("OPENAI_COLOR_MODEL", "gpt-4o-mini").strip()
        self.timeout_seconds = float(os.getenv("OPENAI_COLOR_TIMEOUT", "8"))
        self.max_titles = int(os.getenv("OPENAI_COLOR_MAX_TITLES", "30"))
        self._custom_schema = CustomColorSchema()

    @property
    def custom_schema(self) -> CustomColorSchema:
        return self._custom_schema

    def reload_schema(self) -> None:
        self._custom_schema.load()

    def apply(self, events: list[CalendarEvent]) -> list[CalendarEvent]:
        if not events or not self.enabled or self._custom_schema.is_empty:
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
        if self.api_key:
            categories = self._classify_with_openai(titles)
            if categories:
                return categories

        return self._classify_with_keywords(titles)

    def _get_openai_client(self):
        try:
            module_name = "open" + "ai"
            openai_module = importlib.import_module(module_name)
            OpenAI = getattr(openai_module, "OpenAI")
            return OpenAI(api_key=self.api_key, timeout=self.timeout_seconds)
        except Exception:
            return None

    def _classify_with_openai(self, titles: list[str]) -> dict[str, str]:
        client = self._get_openai_client()
        if not client:
            return {}

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

        try:
            response = client.responses.create(
                model=self.model,
                max_output_tokens=500,
                input=[
                    {
                        "role": "system",
                        "content": (
                            "You classify calendar event titles. "
                            "Use only allowed_categories. "
                            "If uncertain, use 'unmatched'. "
                            "Respond with valid JSON only."
                        ),
                    },
                    {
                        "role": "user",
                        "content": json.dumps(prompt, ensure_ascii=False),
                    },
                ],
            )
        except Exception:
            return {}

        raw_text = getattr(response, "output_text", "")
        if not raw_text:
            return {}

        data = self._parse_json_object(raw_text)
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

    def _parse_json_object(self, raw_text: str) -> dict:
        try:
            parsed = json.loads(raw_text)
            if isinstance(parsed, dict):
                return parsed
        except Exception:
            pass

        start = raw_text.find("{")
        end = raw_text.rfind("}")
        if start == -1 or end == -1 or end <= start:
            return {}

        try:
            parsed = json.loads(raw_text[start : end + 1])
            if isinstance(parsed, dict):
                return parsed
        except Exception:
            return {}

        return {}

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
            color = QColor(hex_color)
            color.setAlpha(180)
            event.color = color

    def generate_keywords_for_rules(self, rules: list[ColorRule]) -> list[ColorRule]:
        if not self.api_key or not rules:
            return rules

        client = self._get_openai_client()
        if not client:
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

        try:
            response = client.responses.create(
                model=self.model,
                max_output_tokens=1000,
                input=[
                    {
                        "role": "system",
                        "content": (
                            "You generate keywords for calendar event categories. "
                            "Keywords should be short, lowercase words or phrases "
                            "that commonly appear in calendar event titles. "
                            "Include both Korean and English keywords. "
                            "Respond with valid JSON only."
                        ),
                    },
                    {
                        "role": "user",
                        "content": json.dumps(prompt, ensure_ascii=False),
                    },
                ],
            )
        except Exception:
            return rules

        raw_text = getattr(response, "output_text", "")
        if not raw_text:
            return rules

        data = self._parse_json_object(raw_text)
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
