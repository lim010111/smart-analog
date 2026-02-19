import importlib
import os
import uuid
from pathlib import Path
from typing import Any


class BriefingTTSAdapter:
    def __init__(self):
        self._backend_preference = self._normalize_backend_name(
            os.getenv("AI_TTS_BACKEND", "openai")
        )

        self._available = False
        self._active_backend = "none"
        self._selected_engine_name = ""
        self._unavailable_reason = ""

        self._qt_engine: Any = None
        self._openai_client: Any = None
        self._openai_sound_effect: Any = None

        self._openai_api_key = os.getenv("OPENAI_API_KEY", "").strip()
        self._openai_model = (
            os.getenv("OPENAI_TTS_MODEL", "gpt-4o-mini-tts").strip()
            or "gpt-4o-mini-tts"
        )
        self._openai_voice = os.getenv("OPENAI_TTS_VOICE", "marin").strip() or "marin"
        self._openai_instructions = os.getenv("OPENAI_TTS_INSTRUCTIONS", "").strip()
        self._openai_timeout = self._read_float_env(
            "OPENAI_TTS_TIMEOUT",
            default=15.0,
            min_value=1.0,
        )

        default_cache = Path.home() / ".clock_widget" / "tts_cache"
        cache_path_raw = os.getenv("OPENAI_TTS_AUDIO_CACHE_DIR", "").strip()
        self._openai_cache_dir = (
            Path(cache_path_raw) if cache_path_raw else default_cache
        )
        self._openai_temp_files: list[Path] = []

        self._init_backend()

    @staticmethod
    def _normalize_backend_name(name: str | None) -> str:
        normalized = str(name or "").strip().lower()
        if normalized in {"openai", "qt", "auto"}:
            return normalized
        return "openai"

    @staticmethod
    def _read_float_env(name: str, default: float, min_value: float = 0.1) -> float:
        raw = os.getenv(name)
        if raw is None:
            return default
        try:
            parsed = float(raw)
        except ValueError:
            return default
        return max(min_value, parsed)

    @staticmethod
    def _safe_len(value: Any) -> int:
        try:
            return int(len(value))
        except Exception:
            return 0

    def _init_backend(self) -> None:
        if self._backend_preference == "openai":
            self._init_openai_backend()
            return

        if self._backend_preference == "auto":
            if self._init_openai_backend():
                return
            self._fallback_init_qt()
            return

        self._init_qt_backend()

    def _init_openai_backend(self) -> bool:
        self._openai_client = None
        self._openai_sound_effect = None

        if not self._openai_api_key:
            self._available = False
            self._active_backend = "none"
            self._selected_engine_name = ""
            self._unavailable_reason = (
                "OpenAI TTS unavailable: OPENAI_API_KEY is missing."
            )
            return False

        try:
            module = importlib.import_module("open" + "ai")
            openai_cls = getattr(module, "OpenAI")

            self._openai_client = openai_cls(
                api_key=self._openai_api_key,
                timeout=self._openai_timeout,
            )
            self._active_backend = "openai"
            self._selected_engine_name = (
                f"openai:{self._openai_model}:{self._openai_voice}"
            )
            self._available = True
            self._unavailable_reason = ""
            return True
        except Exception as error:
            self._openai_client = None
            self._openai_sound_effect = None
            self._available = False
            self._active_backend = "none"
            self._selected_engine_name = ""
            self._unavailable_reason = f"OpenAI TTS unavailable: {error}"
            return False

    def _init_qt_backend(self) -> bool:
        self._qt_engine = None
        try:
            from PySide6.QtTextToSpeech import QTextToSpeech

            engines = list(QTextToSpeech.availableEngines())
            if not engines:
                self._available = False
                self._active_backend = "none"
                if not self._unavailable_reason:
                    self._unavailable_reason = "No Qt TTS engine is available."
                return False

            preferred_engines: list[str] = [
                str(e) for e in engines if str(e).lower() != "mock"
            ]
            if not preferred_engines:
                self._available = False
                self._active_backend = "none"
                if not self._unavailable_reason:
                    self._unavailable_reason = (
                        "Only mock Qt TTS backend is available (no real audio backend)."
                    )
                return False

            selected_engine = preferred_engines[0]
            engine = QTextToSpeech(selected_engine)

            if engine is None:
                self._available = False
                self._active_backend = "none"
                if not self._unavailable_reason:
                    self._unavailable_reason = "Failed to initialize Qt TTS engine."
                return False

            state_fn = getattr(engine, "state", None)
            error_reason_fn = getattr(engine, "errorReason", None)
            error_string_fn = getattr(engine, "errorString", None)
            voices_fn = getattr(engine, "availableVoices", None)

            state_value = state_fn() if callable(state_fn) else None
            reason_value = error_reason_fn() if callable(error_reason_fn) else None
            reason_name = str(getattr(reason_value, "name", reason_value))
            error_text = str(
                error_string_fn() if callable(error_string_fn) else ""
            ).strip()
            voices_value = voices_fn() if callable(voices_fn) else []
            voices_count = self._safe_len(voices_value)

            if state_value is None:
                self._available = False
                self._active_backend = "none"
                if not self._unavailable_reason:
                    self._unavailable_reason = "Qt TTS state check is unavailable."
                return False

            state_name = str(getattr(state_value, "name", state_value))
            is_ready = "ready" in state_name.lower()
            has_init_error = "initialization" in reason_name.lower()

            if not is_ready or has_init_error or voices_count == 0:
                self._available = False
                self._active_backend = "none"
                if error_text:
                    self._unavailable_reason = error_text
                elif has_init_error:
                    self._unavailable_reason = "Qt TTS backend initialization failed."
                elif voices_count == 0:
                    self._unavailable_reason = "Qt TTS backend has no available voices."
                else:
                    self._unavailable_reason = "Qt TTS backend is not ready."
                return False

            self._qt_engine = engine
            self._active_backend = "qt"
            self._selected_engine_name = f"qt:{selected_engine}"
            self._available = True
            self._unavailable_reason = ""
            return True
        except Exception as error:
            self._qt_engine = None
            self._available = False
            self._active_backend = "none"
            if not self._unavailable_reason:
                self._unavailable_reason = (
                    f"Qt TextToSpeech module is unavailable: {error}"
                )
            return False

    def is_available(self) -> bool:
        return self._available

    def unavailable_reason(self) -> str:
        return self._unavailable_reason

    def selected_engine_name(self) -> str:
        return self._selected_engine_name

    def backend_name(self) -> str:
        return self._active_backend

    def backend_preference(self) -> str:
        return self._backend_preference

    def speak(self, text: str) -> bool:
        message = str(text).strip()
        if not message:
            return False

        if self._backend_preference in {"openai", "auto"}:
            if self._openai_client is None and not self._init_openai_backend():
                if self._backend_preference == "auto":
                    return self._fallback_to_qt(message)
                return False
            if self._speak_openai(message):
                return True
            if self._backend_preference == "auto":
                return self._fallback_to_qt(message)
            return False

        if not self._available:
            return False

        if self._active_backend == "qt":
            return self._speak_qt(message)

        return False

    def _speak_qt(self, text: str) -> bool:
        engine = self._qt_engine
        if engine is None:
            return False
        try:
            say_fn = getattr(engine, "say", None)
            if not callable(say_fn):
                return False
            say_fn(text)
            return True
        except Exception as error:
            self._unavailable_reason = f"Qt TTS speak failed: {error}"
            return False

    def _speak_openai(self, text: str) -> bool:
        client = self._openai_client
        if client is None:
            self._unavailable_reason = "OpenAI TTS client is not initialized."
            return False

        if not self._ensure_openai_sound_effect():
            return False

        sound_effect = self._openai_sound_effect
        if sound_effect is None:
            self._unavailable_reason = "Qt sound effect backend is unavailable."
            return False

        try:
            from PySide6.QtCore import QUrl

            self._openai_cache_dir.mkdir(parents=True, exist_ok=True)
            path = self._openai_cache_dir / f"openai_tts_{uuid.uuid4().hex}.wav"

            request_payload: dict[str, Any] = {
                "model": self._openai_model,
                "voice": self._openai_voice,
                "input": text,
                "response_format": "wav",
            }
            if self._openai_instructions:
                request_payload["instructions"] = self._openai_instructions

            with client.audio.speech.with_streaming_response.create(
                **request_payload,
            ) as response:
                response.stream_to_file(path)

            sound_effect.stop()
            sound_effect.setSource(QUrl.fromLocalFile(str(path)))
            sound_effect.setLoopCount(1)
            sound_effect.setVolume(1.0)
            sound_effect.play()

            self._track_temp_audio(path)
            self._active_backend = "openai"
            self._selected_engine_name = (
                f"openai:{self._openai_model}:{self._openai_voice}"
            )
            self._available = True
            self._unavailable_reason = ""
            return True
        except Exception as error:
            self._unavailable_reason = f"OpenAI TTS speak failed: {error}"
            return False

    def _ensure_openai_sound_effect(self) -> bool:
        if self._openai_sound_effect is not None:
            return True

        try:
            from PySide6.QtMultimedia import QMediaDevices, QSoundEffect

            outputs = list(QMediaDevices.audioOutputs())
            if not outputs:
                self._unavailable_reason = (
                    "OpenAI TTS unavailable: no audio output device detected."
                )
                return False

            self._openai_sound_effect = QSoundEffect()
            return True
        except Exception as error:
            self._openai_sound_effect = None
            self._unavailable_reason = (
                f"Qt sound effect backend initialization failed: {error}"
            )
            return False

    def _track_temp_audio(self, path: Path) -> None:
        self._openai_temp_files.append(path)
        while len(self._openai_temp_files) > 5:
            old = self._openai_temp_files.pop(0)
            try:
                old.unlink(missing_ok=True)
            except Exception:
                continue

    def _fallback_init_qt(self) -> None:
        previous_reason = self._unavailable_reason.strip()
        if self._init_qt_backend():
            if previous_reason:
                self._unavailable_reason = previous_reason
            return

        current_reason = self._unavailable_reason.strip()
        if previous_reason and current_reason and current_reason != previous_reason:
            self._unavailable_reason = (
                f"{previous_reason}; Qt fallback unavailable: {current_reason}"
            )
        elif previous_reason and not current_reason:
            self._unavailable_reason = previous_reason

    def _fallback_to_qt(self, message: str) -> bool:
        previous_reason = self._unavailable_reason.strip()
        self._init_qt_backend()
        if self._active_backend != "qt":
            current_reason = self._unavailable_reason.strip()
            if previous_reason and current_reason and current_reason != previous_reason:
                self._unavailable_reason = (
                    f"{previous_reason}; Qt fallback unavailable: {current_reason}"
                )
            elif previous_reason and not current_reason:
                self._unavailable_reason = previous_reason
            return False

        if self._speak_qt(message):
            return True

        current_reason = self._unavailable_reason.strip()
        if previous_reason and current_reason and current_reason != previous_reason:
            self._unavailable_reason = (
                f"{previous_reason}; Qt fallback speak failed: {current_reason}"
            )
        elif previous_reason and not current_reason:
            self._unavailable_reason = previous_reason
        return False

    def stop(self) -> None:
        if self._active_backend == "qt":
            engine = self._qt_engine
            if engine is None:
                return
            try:
                stop_fn = getattr(engine, "stop", None)
                if callable(stop_fn):
                    stop_fn()
            except Exception:
                return
            return

        if self._active_backend == "openai":
            sound_effect = self._openai_sound_effect
            if sound_effect is None:
                return
            try:
                sound_effect.stop()
            except Exception:
                return
