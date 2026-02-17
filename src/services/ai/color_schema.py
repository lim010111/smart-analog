import json
import os
from dataclasses import dataclass, field


SCHEMA_FILE = "color_schema.json"


@dataclass
class ColorRule:
    color_hex: str
    label: str
    keywords: list[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "color_hex": self.color_hex,
            "label": self.label,
            "keywords": self.keywords,
        }

    @classmethod
    def from_dict(cls, data: dict) -> "ColorRule":
        return cls(
            color_hex=str(data.get("color_hex", "#8a8f98")),
            label=str(data.get("label", "")),
            keywords=list(data.get("keywords", [])),
        )


class CustomColorSchema:
    def __init__(self, schema_path: str | None = None):
        self.schema_path = schema_path or SCHEMA_FILE
        self.rules: list[ColorRule] = []
        self.load()

    def load(self) -> None:
        if not os.path.exists(self.schema_path):
            self.rules = []
            return

        try:
            with open(self.schema_path, encoding="utf-8") as f:
                data = json.load(f)
        except (json.JSONDecodeError, OSError):
            self.rules = []
            return

        raw_rules = data.get("rules", [])
        if not isinstance(raw_rules, list):
            self.rules = []
            return

        self.rules = [ColorRule.from_dict(r) for r in raw_rules if isinstance(r, dict)]

    def save(self) -> None:
        data = {"rules": [rule.to_dict() for rule in self.rules]}
        with open(self.schema_path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

    def to_category_colors(self) -> dict[str, str]:
        return {
            self._rule_key(rule): rule.color_hex
            for rule in self.rules
            if rule.label.strip()
        }

    def to_keyword_rules(self) -> dict[str, tuple[str, ...]]:
        return {
            self._rule_key(rule): tuple(rule.keywords)
            for rule in self.rules
            if rule.label.strip() and rule.keywords
        }

    @staticmethod
    def _rule_key(rule: ColorRule) -> str:
        return f"custom_{rule.label.strip().lower().replace(' ', '_')}"

    @property
    def is_empty(self) -> bool:
        return len(self.rules) == 0
