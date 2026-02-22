"""Lightweight PySide6 stubs for headless / web deployment.

Import this module BEFORE any PySide6-dependent module to register
mock Qt classes in sys.modules when PySide6 is not installed.

Usage (top of web backend main.py):
    import src.compat.qt_stub  # noqa: F401
"""

from __future__ import annotations

import sys
from types import ModuleType


class _QColor:
    """Minimal QColor replacement for headless environments."""

    def __init__(self, *args, **kwargs):
        self._r = 100
        self._g = 150
        self._b = 255
        self._a = 180

        if not args:
            return

        if len(args) == 1:
            arg = args[0]
            if isinstance(arg, str):
                self._parse_hex(arg)
            elif isinstance(arg, _QColor):
                self._r, self._g, self._b, self._a = (
                    arg._r,
                    arg._g,
                    arg._b,
                    arg._a,
                )
            return

        if len(args) >= 3:
            self._r = int(args[0])
            self._g = int(args[1])
            self._b = int(args[2])
            if len(args) >= 4:
                self._a = int(args[3])

    def _parse_hex(self, hex_str: str) -> None:
        h = hex_str.lstrip("#")
        if len(h) >= 6:
            self._r = int(h[0:2], 16)
            self._g = int(h[2:4], 16)
            self._b = int(h[4:6], 16)
        if len(h) == 8:
            self._a = int(h[6:8], 16)

    def name(self) -> str:
        return f"#{self._r:02x}{self._g:02x}{self._b:02x}"

    def red(self) -> int:
        return self._r

    def green(self) -> int:
        return self._g

    def blue(self) -> int:
        return self._b

    def alpha(self) -> int:
        return self._a

    def setAlpha(self, value: int) -> None:
        self._a = int(value)

    def __repr__(self) -> str:
        return f"QColor({self._r}, {self._g}, {self._b}, {self._a})"


def _make_module(name: str, attrs: dict[str, object] | None = None) -> ModuleType:
    mod = ModuleType(name)
    if attrs:
        for k, v in attrs.items():
            setattr(mod, k, v)
    return mod


def _make_stub_class(name: str) -> type:
    return type(name, (), {"__init__": lambda self, *a, **kw: None})


def install() -> None:
    """Register PySide6 stub modules if PySide6 is not available."""
    try:
        import PySide6  # noqa: F401

        return
    except ImportError:
        pass

    sys.modules.setdefault("PySide6", _make_module("PySide6"))

    sys.modules.setdefault(
        "PySide6.QtGui",
        _make_module("PySide6.QtGui", {"QColor": _QColor}),
    )

    qt_core = _make_module("PySide6.QtCore")
    for attr in (
        "Qt",
        "QTimer",
        "QTime",
        "QPoint",
        "QPointF",
        "QRect",
        "QUrl",
        "QThread",
        "Signal",
    ):
        setattr(qt_core, attr, _make_stub_class(attr))
    sys.modules.setdefault("PySide6.QtCore", qt_core)

    qt_widgets = _make_module("PySide6.QtWidgets")
    for attr in ("QWidget", "QApplication", "QMessageBox"):
        setattr(qt_widgets, attr, _make_stub_class(attr))
    sys.modules.setdefault("PySide6.QtWidgets", qt_widgets)

    sys.modules.setdefault(
        "PySide6.QtTextToSpeech",
        _make_module(
            "PySide6.QtTextToSpeech",
            {"QTextToSpeech": _make_stub_class("QTextToSpeech")},
        ),
    )

    sys.modules.setdefault(
        "PySide6.QtMultimedia",
        _make_module(
            "PySide6.QtMultimedia",
            {
                "QMediaDevices": _make_stub_class("QMediaDevices"),
                "QSoundEffect": _make_stub_class("QSoundEffect"),
            },
        ),
    )


install()
