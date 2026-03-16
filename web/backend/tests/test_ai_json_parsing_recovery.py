from src.services.ai.core.errors import OpenAIResponseFormatError
from src.services.ai.core.client import OpenAIJSONClient
from src.services.ai.core.config import OpenAIConfig
from src.services.ai.core.json_utils import parse_json_object
from src.services.ai.core.workflow import request_json_with_error
from src.services.ai.natural_input import AINaturalInputService


def test_parse_json_object_reads_fenced_json_block() -> None:
    raw = """
Here is the result.
```json
{"intent":"create","title":"신촌 알바","all_day":false}
```
"""

    parsed = parse_json_object(raw)

    assert parsed.get("intent") == "create"
    assert parsed.get("title") == "신촌 알바"


def test_parse_json_object_reads_embedded_object_in_text() -> None:
    raw = 'Result: {"intent":"create","confidence":0.91} trailing'

    parsed = parse_json_object(raw)

    assert parsed.get("intent") == "create"
    assert parsed.get("confidence") == 0.91


def test_parse_json_object_rejects_multiple_embedded_objects() -> None:
    raw = 'prefix {"intent":"create"} middle {"intent":"unknown"}'

    parsed = parse_json_object(raw)

    assert parsed == {}


def test_request_json_with_error_returns_error_message() -> None:
    class _FailingClient(OpenAIJSONClient):
        def __init__(self):
            super().__init__(
                OpenAIConfig(
                    api_key="test",
                    model="gpt-5-mini",
                    timeout_seconds=1.0,
                    reasoning_effort="minimal",
                )
            )

        def request_json(self, **_kwargs):
            raise OpenAIResponseFormatError("OpenAI response was not valid JSON.")

    data, error = request_json_with_error(
        _FailingClient(),
        system_prompt="prompt",
        user_payload={"text": "내일 오전 9시부터 12시반까지 신촌에서 알바"},
    )

    assert data == {}
    assert error == "OpenAI response was not valid JSON."


def test_request_json_with_error_passes_text_format() -> None:
    captured: dict[str, object] = {}

    class _CapturingClient(OpenAIJSONClient):
        def __init__(self):
            super().__init__(
                OpenAIConfig(
                    api_key="test",
                    model="gpt-5-mini",
                    timeout_seconds=1.0,
                    reasoning_effort="minimal",
                )
            )

        def request_json(self, **kwargs):
            captured.update(kwargs)
            return {"ok": True}

    data, error = request_json_with_error(
        _CapturingClient(),
        system_prompt="prompt",
        user_payload={"text": "x"},
        text_format={"type": "json_schema", "name": "x", "schema": {}},
    )

    assert data == {"ok": True}
    assert error is None
    assert captured.get("text_format") == {
        "type": "json_schema",
        "name": "x",
        "schema": {},
    }


def test_natural_input_retries_without_text_format(monkeypatch) -> None:
    calls: list[dict[str, object]] = []

    def _fake_request_json_with_error(*_args, **kwargs):
        calls.append(kwargs)
        if len(calls) == 1:
            return ({}, "schema-format-error")
        return (
            {
                "intent": "create",
                "title": "신촌 알바",
                "start_time": "2026-03-14T09:00:00+09:00",
                "end_time": "2026-03-14T12:30:00+09:00",
                "duration_minutes": 210,
                "all_day": False,
                "confidence": 0.92,
            },
            None,
        )

    monkeypatch.setattr(
        "src.services.ai.natural_input.request_json_with_error",
        _fake_request_json_with_error,
    )
    monkeypatch.setattr(
        "src.services.ai.natural_input.AINaturalInputService._is_local_fast_path_candidate",
        lambda _self, _text: False,
    )

    service = AINaturalInputService()
    service.enabled = True
    service._client = OpenAIJSONClient(
        OpenAIConfig(
            api_key="test",
            model="gpt-5-mini",
            timeout_seconds=1.0,
            reasoning_effort="minimal",
        )
    )

    result = service.parse("내일 오전 9시부터 12시반까지 신촌에서 알바")

    assert result is not None
    assert result.intent == "create"
    assert len(calls) == 2
    assert calls[0].get("text_format") is not None
    assert calls[1].get("text_format") is None


def test_natural_input_local_rule_fallback_after_ai_failures(monkeypatch) -> None:
    calls: list[dict[str, object]] = []

    def _always_fail(*_args, **kwargs):
        calls.append(kwargs)
        return (
            {},
            "OpenAI response did not include output_text. status=completed output=reasoning",
        )

    monkeypatch.setattr(
        "src.services.ai.natural_input.request_json_with_error",
        _always_fail,
    )
    monkeypatch.setattr(
        "src.services.ai.natural_input.AINaturalInputService._is_local_fast_path_candidate",
        lambda _self, _text: False,
    )

    service = AINaturalInputService()
    service.enabled = True
    service._client = OpenAIJSONClient(
        OpenAIConfig(
            api_key="test",
            model="gpt-5-mini",
            timeout_seconds=1.0,
            reasoning_effort="minimal",
        )
    )

    result = service.parse("내일 오전 9시부터 12시반까지 신촌에서 알바")

    assert result is not None
    assert result.intent == "create"
    assert result.title == "신촌에서 알바"
    assert result.start_time is not None
    assert result.end_time is not None
    assert result.start_time.hour == 9
    assert result.start_time.minute == 0
    assert result.end_time.hour == 12
    assert result.end_time.minute == 30
    assert result.end_time.date() == result.start_time.date()
    assert result.end_time > result.start_time
    assert len(calls) == 1


def test_natural_input_local_start_duration_fallback(monkeypatch) -> None:
    def _always_fail(*_args, **_kwargs):
        return ({}, "OpenAI response incomplete: max_output_tokens")

    monkeypatch.setattr(
        "src.services.ai.natural_input.request_json_with_error",
        _always_fail,
    )

    service = AINaturalInputService()
    service.enabled = True
    service._client = OpenAIJSONClient(
        OpenAIConfig(
            api_key="test",
            model="gpt-5-mini",
            timeout_seconds=1.0,
            reasoning_effort="minimal",
        )
    )

    result = service.parse("내일 오후 2시에 30분 회의 일정 추가해줘")

    assert result is not None
    assert result.intent == "create"
    assert result.title == "회의"
    assert result.start_time is not None
    assert result.end_time is not None
    assert result.start_time.hour == 14
    assert result.end_time.hour == 14
    assert result.end_time.minute == 30


def test_natural_input_local_fast_path_for_korean_hour_word_sentence(
    monkeypatch,
) -> None:
    def _must_not_call_openai(*_args, **_kwargs):
        raise AssertionError("OpenAI call should be skipped on local fast path")

    monkeypatch.setattr(
        "src.services.ai.natural_input.request_json_with_error",
        _must_not_call_openai,
    )

    service = AINaturalInputService()
    service.enabled = True
    service._client = OpenAIJSONClient(
        OpenAIConfig(
            api_key="test",
            model="gpt-5-mini",
            timeout_seconds=1.0,
            reasoning_effort="minimal",
        )
    )

    result = service.parse("내일 한 시에 민지랑 홍대입구역에서 보기")

    assert result is not None
    assert result.intent == "create"
    assert result.title.startswith("민지랑")
    assert result.start_time is not None
    assert result.end_time is not None
    assert result.start_time.hour == 13
    assert result.start_time.minute == 0
    assert result.end_time > result.start_time
