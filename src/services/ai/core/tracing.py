import importlib
import os
import warnings
from collections.abc import Callable, Iterable
from functools import wraps
from typing import TypeVar, cast

T = TypeVar("T")
F = TypeVar("F", bound=Callable[..., object])
_WARNED_KEYS: set[str] = set()
_dotenv_loaded = False


def _load_dotenv_once() -> None:
    global _dotenv_loaded
    if _dotenv_loaded:
        return

    try:
        dotenv_module = importlib.import_module("dotenv")
        load_dotenv = getattr(dotenv_module, "load_dotenv")
        load_dotenv()
    except Exception:
        pass

    _dotenv_loaded = True


def _is_langsmith_tracing_enabled() -> bool:
    _load_dotenv_once()
    raw_env = os.getenv("LANGSMITH_TRACING")
    if raw_env is None:
        return bool(os.getenv("LANGSMITH_API_KEY", "").strip())

    raw = raw_env.strip().lower()
    return raw in {"1", "true", "yes", "on"}


def _has_langsmith_api_key() -> bool:
    _load_dotenv_once()
    return bool(os.getenv("LANGSMITH_API_KEY", "").strip())


def _warn_once(key: str, message: str) -> None:
    if key in _WARNED_KEYS:
        return
    _WARNED_KEYS.add(key)
    warnings.warn(message, RuntimeWarning, stacklevel=2)


def wrap_openai_client(
    client: T,
    *,
    component: str,
    tags: Iterable[str] | None = None,
    metadata: dict[str, object] | None = None,
) -> T:
    if not _is_langsmith_tracing_enabled():
        return client

    if not _has_langsmith_api_key():
        _warn_once(
            "langsmith_missing_api_key",
            "LANGSMITH_TRACING is enabled but LANGSMITH_API_KEY is missing; "
            "LangSmith monitoring is disabled.",
        )
        return client

    try:
        wrappers_module = importlib.import_module("langsmith.wrappers")
        wrap_openai = getattr(wrappers_module, "wrap_openai")
    except Exception:
        _warn_once(
            "langsmith_wrapper_import_failed",
            "LangSmith wrapper import failed while LANGSMITH_TRACING is enabled; "
            "LangSmith monitoring is disabled for OpenAI clients.",
        )
        return client

    normalized_tags = ["clock-widget", "ai", component]
    if tags:
        normalized_tags.extend(str(tag).strip() for tag in tags if str(tag).strip())

    tracing_extra: dict[str, object] = {
        "tags": normalized_tags,
        "metadata": {
            "component": component,
            **(metadata or {}),
        },
    }
    wrapped_client = wrap_openai(client, tracing_extra=tracing_extra)
    return cast(T, wrapped_client)


def traceable_span(
    *,
    name: str,
    run_type: str = "chain",
    tags: Iterable[str] | None = None,
    metadata: dict[str, object] | None = None,
) -> Callable[[F], F]:
    def decorator(func: F) -> F:
        try:
            langsmith_module = importlib.import_module("langsmith")
            traceable = getattr(langsmith_module, "traceable")
        except Exception:
            _warn_once(
                "langsmith_traceable_import_failed",
                "LangSmith import failed while LANGSMITH_TRACING is enabled; "
                "LangSmith traceable spans are disabled.",
            )
            return func

        normalized_tags = ["clock-widget", "ai"]
        if tags:
            normalized_tags.extend(str(tag).strip() for tag in tags if str(tag).strip())

        traced = traceable(
            name=name,
            run_type=run_type,
            tags=normalized_tags,
            metadata=metadata or {},
        )(func)

        @wraps(func)
        def runtime_checked(*args, **kwargs):
            if not _is_langsmith_tracing_enabled():
                return func(*args, **kwargs)

            if not _has_langsmith_api_key():
                _warn_once(
                    "langsmith_missing_api_key_traceable",
                    "LANGSMITH_TRACING is enabled but LANGSMITH_API_KEY is missing; "
                    "LangSmith traceable spans are disabled.",
                )
                return func(*args, **kwargs)

            return traced(*args, **kwargs)

        return cast(F, runtime_checked)

    return decorator
