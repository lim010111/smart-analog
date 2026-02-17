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
    DEFAULT_CATEGORY_COLORS: dict[str, str] = {
        "meeting": "#4f83ff",
        "deep_work": "#6f59d9",
        "personal": "#3cb371",
        "health": "#f45b69",
        "finance": "#f2a93b",
        "travel": "#38b7a6",
        "study": "#5c7cfa",
        "social": "#ff7a59",
        "other": "#8a8f98",
    }

    DEFAULT_KEYWORD_RULES: dict[str, tuple[str, ...]] = {
        "meeting": (
            "meeting",
            "sync",
            "standup",
            "1:1",
            "회의",
            "미팅",
            "콜",
            "인터뷰",
        ),
        "deep_work": (
            "focus",
            "coding",
            "review",
            "개발",
            "코딩",
            "리뷰",
            "집중",
            "작업",
        ),
        "personal": ("family", "home", "개인", "가족", "집", "약속"),
        "health": ("hospital", "clinic", "doctor", "운동", "헬스", "병원", "검진"),
        "finance": ("payment", "invoice", "tax", "bank", "결제", "세금", "은행"),
        "travel": ("flight", "train", "trip", "travel", "출장", "여행", "비행"),
        "study": ("study", "class", "course", "lecture", "공부", "강의", "수업"),
        "social": (
            "lunch",
            "dinner",
            "coffee",
            "party",
            "점심",
            "저녁",
            "식사",
            "모임",
        ),
    }

    ALLOWED_CATEGORIES = set(DEFAULT_CATEGORY_COLORS.keys())

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

    @property
    def _effective_category_colors(self) -> dict[str, str]:
        colors = dict(self.DEFAULT_CATEGORY_COLORS)
        colors.update(self._custom_schema.to_category_colors())
        return colors

    @property
    def _effective_keyword_rules(self) -> dict[str, tuple[str, ...]]:
        rules = dict(self.DEFAULT_KEYWORD_RULES)
        rules.update(self._custom_schema.to_keyword_rules())
        return rules

    @property
    def _allowed_categories(self) -> set[str]:
        return set(self._effective_category_colors.keys())

    def reload_schema(self) -> None:
        self._custom_schema.load()

    def apply(self, events: list[CalendarEvent]) -> list[CalendarEvent]:
        if not events or not self.enabled:
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
            "allowed_categories": sorted(self._allowed_categories),
            "instructions": (
                "Classify each title into one category. "
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
                            "If uncertain, use 'other'. "
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
        custom_rules = self._custom_schema.to_keyword_rules()

        categories: dict[str, str] = {}
        for title in titles:
            lowered = title.lower()
            categories[lowered] = "other"

            for category, keywords in custom_rules.items():
                if any(keyword in lowered for keyword in keywords):
                    categories[lowered] = category
                    break
            else:
                for category, keywords in self.DEFAULT_KEYWORD_RULES.items():
                    if any(keyword in lowered for keyword in keywords):
                        categories[lowered] = category
                        break

        return categories

    def _normalize_category(self, value: object) -> str:
        category = str(value or "").strip().lower()
        if category in self._allowed_categories:
            return category
        return "other"

    def _apply_categories(
        self,
        events: list[CalendarEvent],
        categories_by_title: dict[str, str],
    ) -> None:
        effective_colors = self._effective_category_colors
        for event in events:
            title = str(event.summary).strip().lower()
            category = categories_by_title.get(title, "other")
            hex_color = effective_colors.get(
                category, self.DEFAULT_CATEGORY_COLORS["other"]
            )
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
