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
    text_format: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    data, _ = request_json_with_error(
        client,
        system_prompt=system_prompt,
        user_payload=user_payload,
        max_output_tokens=max_output_tokens,
        model=model,
        text_format=text_format,
    )
    return data


def request_json_with_error(
    client: OpenAIJSONClient,
    *,
    system_prompt: str,
    user_payload: Mapping[str, Any],
    max_output_tokens: int = 1000,
    model: str | None = None,
    text_format: Mapping[str, Any] | None = None,
) -> tuple[dict[str, Any], str | None]:
    try:
        return (
            client.request_json(
                system_prompt=system_prompt,
                user_payload=user_payload,
                max_output_tokens=max_output_tokens,
                model=model,
                text_format=text_format,
            ),
            None,
        )
    except OpenAIClientError as error:
        return ({}, str(error))
