import json
import os
from collections.abc import Mapping
from dataclasses import dataclass


SCHEMA_FILE = "color_schema.json"


@dataclass
class ColorRule:
    color_hex: str
    label: str

    def to_dict(self) -> dict[str, str]:
        return {
            "color_hex": self.color_hex,
            "label": self.label,
        }

    @classmethod
    def from_dict(cls, data: Mapping[str, object]) -> "ColorRule":
        return cls(
            color_hex=str(data.get("color_hex", "#8a8f98")),
            label=str(data.get("label", "")),
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

    def restrict_to_palette(self, palette: list[str]) -> None:
        allowed = {
            str(color).strip().lower() for color in palette if str(color).strip()
        }
        if not allowed:
            self.rules = []
            return

        filtered: list[ColorRule] = []
        for rule in self.rules:
            color_hex = str(rule.color_hex).strip().lower()
            if color_hex in allowed:
                filtered.append(rule)
        self.rules = filtered

    def to_category_colors(self) -> dict[str, str]:
        return {
            self._rule_key(rule): rule.color_hex
            for rule in self.rules
            if rule.label.strip()
        }

    @staticmethod
    def _rule_key(rule: ColorRule) -> str:
        return f"custom_{rule.label.strip().lower().replace(' ', '_')}"

    @property
    def is_empty(self) -> bool:
        return len(self.rules) == 0
