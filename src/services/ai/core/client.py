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


class OpenAIJSONClient:
    def __init__(self, config: OpenAIConfig):
        self._config = config

    @property
    def config(self) -> OpenAIConfig:
        return self._config

    def is_available(self) -> bool:
        return self._config.is_enabled

    def request_json(
        self,
        *,
        system_prompt: str,
        user_payload: Mapping[str, Any],
        max_output_tokens: int = 1000,
        model: str | None = None,
    ) -> dict[str, Any]:
        if not self._config.api_key:
            raise OpenAIClientUnavailableError("OPENAI_API_KEY is missing.")

        sdk_client = self._create_sdk_client()
        resolved_model = (model or self._config.model).strip() or self._config.model

        try:
            response = sdk_client.responses.create(
                model=resolved_model,
                max_output_tokens=max_output_tokens,
                input=[
                    {
                        "role": "system",
                        "content": system_prompt,
                    },
                    {
                        "role": "user",
                        "content": json.dumps(dict(user_payload), ensure_ascii=False),
                    },
                ],
            )
        except Exception as error:
            raise OpenAIRequestError(f"OpenAI request failed: {error}") from error

        raw_text = str(getattr(response, "output_text", "") or "").strip()
        if not raw_text:
            raise OpenAIResponseFormatError(
                "OpenAI response did not include output_text."
            )

        parsed = parse_json_object(raw_text)
        if not parsed:
            raise OpenAIResponseFormatError("OpenAI response was not valid JSON.")

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
            return openai_cls(
                api_key=self._config.api_key,
                timeout=self._config.timeout_seconds,
            )
        except Exception as error:
            raise OpenAIClientUnavailableError(
                f"OpenAI client initialization failed: {error}"
            ) from error
