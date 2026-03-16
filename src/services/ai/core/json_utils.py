import json
import re
from typing import Any


def _parse_json_object(candidate: str) -> dict[str, Any]:
    try:
        parsed = json.loads(candidate)
        if isinstance(parsed, dict):
            return parsed
    except Exception:
        return {}
    return {}


def _extract_fenced_blocks(raw_text: str) -> list[str]:
    blocks: list[str] = []
    for matched in re.findall(r"```(?:json)?\s*([\s\S]*?)```", raw_text, flags=re.I):
        block = str(matched).strip()
        if block:
            blocks.append(block)
    return blocks


def _extract_json_objects(raw_text: str) -> list[str]:
    decoder = json.JSONDecoder()
    candidates: list[str] = []
    for index, token in enumerate(raw_text):
        if token != "{":
            continue
        try:
            parsed, consumed = decoder.raw_decode(raw_text[index:])
        except Exception:
            continue
        if isinstance(parsed, dict):
            candidates.append(raw_text[index : index + consumed])
    return candidates


def parse_json_object(raw_text: str) -> dict[str, Any]:
    normalized = str(raw_text or "").strip()
    if not normalized:
        return {}

    direct = _parse_json_object(normalized)
    if direct:
        return direct

    fenced_matches = [
        parsed
        for fenced in _extract_fenced_blocks(normalized)
        if (parsed := _parse_json_object(fenced))
    ]
    if len(fenced_matches) == 1:
        return fenced_matches[0]
    if len(fenced_matches) > 1:
        return {}

    start = normalized.find("{")
    end = normalized.rfind("}")
    if start == -1 or end == -1 or end <= start:
        return {}

    sliced = _parse_json_object(normalized[start : end + 1])
    if sliced:
        return sliced

    embedded_matches = [
        parsed
        for candidate in _extract_json_objects(normalized)
        if (parsed := _parse_json_object(candidate))
    ]
    if len(embedded_matches) == 1:
        return embedded_matches[0]

    return {}
