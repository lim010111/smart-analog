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

    @property
    def is_enabled(self) -> bool:
        return bool(self.api_key)


def load_openai_config(
    *,
    api_key_env: str = "OPENAI_API_KEY",
    model_env: str = "OPENAI_MODEL",
    timeout_env: str = "OPENAI_TIMEOUT",
    default_model: str = "gpt-4o-mini",
    default_timeout: float = 8.0,
) -> OpenAIConfig:
    load_dotenv()
    api_key = os.getenv(api_key_env, "").strip()
    model = os.getenv(model_env, default_model).strip() or default_model
    timeout_seconds = read_float_env(timeout_env, default_timeout)
    return OpenAIConfig(
        api_key=api_key,
        model=model,
        timeout_seconds=timeout_seconds,
    )
