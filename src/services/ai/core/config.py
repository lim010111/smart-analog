import os
from dataclasses import dataclass

from dotenv import load_dotenv


def read_bool_env(name: str, default: bool = False) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def read_int_env(name: str, default: int) -> int:
    raw = os.getenv(name)
    if raw is None:
        return default
    try:
        return int(raw)
    except ValueError:
        return default


def read_float_env(name: str, default: float) -> float:
    raw = os.getenv(name)
    if raw is None:
        return default
    try:
        return float(raw)
    except ValueError:
        return default


@dataclass(frozen=True)
class OpenAIConfig:
    api_key: str
    model: str
    timeout_seconds: float
    reasoning_effort: str

    @property
    def is_enabled(self) -> bool:
        return bool(self.api_key)


def load_openai_config(
    *,
    api_key_env: str = "OPENAI_API_KEY",
    model_env: str = "OPENAI_MODEL",
    timeout_env: str = "OPENAI_TIMEOUT",
    reasoning_effort_env: str = "OPENAI_REASONING_EFFORT",
    default_model: str = "gpt-5-mini",
    default_timeout: float = 8.0,
    default_reasoning_effort: str = "high",
) -> OpenAIConfig:
    load_dotenv()
    api_key = os.getenv(api_key_env, "").strip()
    model = os.getenv(model_env, default_model).strip() or default_model
    timeout_seconds = read_float_env(timeout_env, default_timeout)
    reasoning_effort = (
        os.getenv(reasoning_effort_env, default_reasoning_effort).strip().lower()
        or default_reasoning_effort
    )
    if reasoning_effort not in {"minimal", "low", "medium", "high"}:
        reasoning_effort = default_reasoning_effort
    return OpenAIConfig(
        api_key=api_key,
        model=model,
        timeout_seconds=timeout_seconds,
        reasoning_effort=reasoning_effort,
    )
