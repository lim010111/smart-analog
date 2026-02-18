class BriefingTTSAdapter:
    def __init__(self):
        self._engine = None
        self._available = False
        self._selected_engine_name = ""
        self._unavailable_reason = ""
        self._init_engine()

    def _init_engine(self) -> None:
        try:
            from PySide6.QtTextToSpeech import QTextToSpeech

            engines = list(QTextToSpeech.availableEngines())
            if not engines:
                self._engine = None
                self._available = False
                self._unavailable_reason = "No Qt TTS engine is available."
                return

            preferred_engines = [e for e in engines if str(e).lower() != "mock"]
            if not preferred_engines:
                self._engine = None
                self._available = False
                self._unavailable_reason = (
                    "Only mock TTS backend is available (no real audio backend)."
                )
                return

            selected_engine = preferred_engines[0]
            engine = QTextToSpeech(selected_engine)
            self._engine = engine
            self._selected_engine_name = str(selected_engine)

            if engine is None:
                self._available = False
                self._unavailable_reason = "Failed to initialize Qt TTS engine."
                return

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
            voices_count = len(voices_fn()) if callable(voices_fn) else 0

            if state_value is None:
                self._available = False
                self._unavailable_reason = "Qt TTS state check is unavailable."
                return

            state_name = str(getattr(state_value, "name", state_value))
            is_ready = "ready" in state_name.lower()
            has_init_error = "initialization" in reason_name.lower()

            if not is_ready or has_init_error or voices_count == 0:
                self._available = False
                if error_text:
                    self._unavailable_reason = error_text
                elif has_init_error:
                    self._unavailable_reason = "Qt TTS backend initialization failed."
                elif voices_count == 0:
                    self._unavailable_reason = "Qt TTS backend has no available voices."
                else:
                    self._unavailable_reason = "Qt TTS backend is not ready."
                self._engine = None
                return

            self._available = True
            self._unavailable_reason = ""
        except Exception:
            self._engine = None
            self._available = False
            self._selected_engine_name = ""
            self._unavailable_reason = "Qt TextToSpeech module is unavailable."

    def is_available(self) -> bool:
        return self._available and self._engine is not None

    def unavailable_reason(self) -> str:
        return self._unavailable_reason

    def selected_engine_name(self) -> str:
        return self._selected_engine_name

    def speak(self, text: str) -> bool:
        if not self.is_available():
            return False
        engine = self._engine
        if engine is None:
            return False
        message = str(text).strip()
        if not message:
            return False
        try:
            say_fn = getattr(engine, "say", None)
            if not callable(say_fn):
                return False
            say_fn(message)
            return True
        except Exception:
            return False

    def stop(self) -> None:
        if not self.is_available():
            return
        engine = self._engine
        if engine is None:
            return
        try:
            stop_fn = getattr(engine, "stop", None)
            if not callable(stop_fn):
                return
            stop_fn()
        except Exception:
            return
