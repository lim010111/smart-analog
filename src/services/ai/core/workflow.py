from collections.abc import Mapping
from typing import Any

from src.services.ai.core.client import OpenAIJSONClient
from src.services.ai.core.errors import OpenAIClientError


def request_json_or_empty(
    client: OpenAIJSONClient,
    *,
    system_prompt: str,
    user_payload: Mapping[str, Any],
    max_output_tokens: int = 1000,
    model: str | None = None,
) -> dict[str, Any]:
    try:
        return client.request_json(
            system_prompt=system_prompt,
            user_payload=user_payload,
            max_output_tokens=max_output_tokens,
            model=model,
        )
    except OpenAIClientError:
        return {}
