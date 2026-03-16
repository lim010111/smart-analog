import importlib
import json
from collections.abc import Mapping
from typing import Any

from src.services.ai.core.config import OpenAIConfig
from src.services.ai.core.errors import (
    OpenAIClientUnavailableError,
    OpenAIRequestError,
    OpenAIResponseFormatError,
)
from src.services.ai.core.json_utils import parse_json_object
from src.services.ai.core.tracing import traceable_span, wrap_openai_client


class OpenAIJSONClient:
    def __init__(self, config: OpenAIConfig):
        self._config = config

    @property
    def config(self) -> OpenAIConfig:
        return self._config

    def is_available(self) -> bool:
        return self._config.is_enabled

    @traceable_span(
        name="ai.openai.request_json",
        run_type="chain",
        tags=["openai", "responses", "json"],
    )
    def request_json(
        self,
        *,
        system_prompt: str,
        user_payload: Mapping[str, Any],
        max_output_tokens: int = 1000,
        model: str | None = None,
        text_format: Mapping[str, Any] | None = None,
    ) -> dict[str, Any]:
        if not self._config.api_key:
            raise OpenAIClientUnavailableError("OPENAI_API_KEY is missing.")

        sdk_client = self._create_sdk_client()
        resolved_model = (model or self._config.model).strip() or self._config.model

        try:
            request_kwargs: dict[str, Any] = {
                "model": resolved_model,
                "max_output_tokens": max_output_tokens,
                "input": [
                    {
                        "role": "system",
                        "content": system_prompt,
                    },
                    {
                        "role": "user",
                        "content": json.dumps(dict(user_payload), ensure_ascii=False),
                    },
                ],
            }
            if self._is_gpt5_model(resolved_model):
                request_kwargs["reasoning"] = {
                    "effort": self._config.reasoning_effort,
                }
            if text_format:
                request_kwargs["text"] = {
                    "format": dict(text_format),
                }

            response = sdk_client.responses.create(
                **request_kwargs,
            )
        except Exception as error:
            raise OpenAIRequestError(f"OpenAI request failed: {error}") from error

        status = str(getattr(response, "status", "") or "").strip().lower()
        if status == "incomplete":
            incomplete_details = getattr(response, "incomplete_details", None)
            reason = str(getattr(incomplete_details, "reason", "") or "").strip()
            if not reason:
                reason = "unknown"
            raise OpenAIResponseFormatError(f"OpenAI response incomplete: {reason}")

        refusal = self._extract_refusal_text(response)
        if refusal:
            raise OpenAIResponseFormatError(
                f"OpenAI refusal: {self._clip_for_error(refusal)}"
            )

        raw_text = self._extract_output_text(response)
        if not raw_text:
            output_types = self._describe_output_types(response)
            raise OpenAIResponseFormatError(
                "OpenAI response did not include output_text. "
                f"status={status or 'unknown'} output={output_types}"
            )

        parsed = parse_json_object(raw_text)
        if not parsed:
            snippet = self._clip_for_error(raw_text)
            raise OpenAIResponseFormatError(
                f"OpenAI response was not valid JSON. raw={snippet}"
            )

        return parsed

    def _create_sdk_client(self):
        try:
            module = importlib.import_module("open" + "ai")
            openai_cls = getattr(module, "OpenAI")
        except Exception as error:
            raise OpenAIClientUnavailableError(
                "OpenAI SDK is not available."
            ) from error

        try:
            client = openai_cls(
                api_key=self._config.api_key,
                timeout=self._config.timeout_seconds,
            )
            return wrap_openai_client(
                client,
                component="core-openai-json-client",
                tags=["openai", "responses"],
                metadata={"model": self._config.model},
            )
        except Exception as error:
            raise OpenAIClientUnavailableError(
                f"OpenAI client initialization failed: {error}"
            ) from error

    @staticmethod
    def _is_gpt5_model(model: str) -> bool:
        return model.strip().lower().startswith("gpt-5")

    @staticmethod
    def _extract_output_text(response: object) -> str:
        primary = str(getattr(response, "output_text", "") or "").strip()
        if primary:
            return primary

        output = getattr(response, "output", None)
        if not isinstance(output, list):
            return ""

        chunks: list[str] = []
        for item in output:
            item_type = str(getattr(item, "type", "") or "").strip().lower()
            if item_type and item_type != "message":
                continue
            content = getattr(item, "content", None)
            if not isinstance(content, list):
                continue
            for block in content:
                block_type = str(getattr(block, "type", "") or "").strip().lower()
                if block_type and block_type not in {"output_text", "text"}:
                    continue
                text = getattr(block, "text", None)
                if isinstance(text, str) and text.strip():
                    chunks.append(text.strip())

        return "\n".join(chunks).strip()

    @staticmethod
    def _clip_for_error(raw_text: str, limit: int = 240) -> str:
        normalized = " ".join(str(raw_text).split())
        if len(normalized) <= limit:
            return normalized
        return f"{normalized[:limit]}..."

    @staticmethod
    def _extract_refusal_text(response: object) -> str:
        output = getattr(response, "output", None)
        if not isinstance(output, list):
            return ""

        refusals: list[str] = []
        for item in output:
            if str(getattr(item, "type", "") or "").strip().lower() != "message":
                continue
            content = getattr(item, "content", None)
            if not isinstance(content, list):
                continue
            for block in content:
                block_type = str(getattr(block, "type", "") or "").strip().lower()
                if block_type != "refusal":
                    continue
                text = str(getattr(block, "refusal", "") or "").strip()
                if text:
                    refusals.append(text)

        return "\n".join(refusals).strip()

    @staticmethod
    def _describe_output_types(response: object) -> str:
        output = getattr(response, "output", None)
        if not isinstance(output, list):
            return "none"

        output_types = [
            str(getattr(item, "type", "") or "unknown").strip().lower() or "unknown"
            for item in output
        ]
        if not output_types:
            return "empty"
        return ",".join(output_types)
