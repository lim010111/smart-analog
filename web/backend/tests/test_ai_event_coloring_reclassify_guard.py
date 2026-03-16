from __future__ import annotations

import datetime as dt
import tempfile
import unittest
from importlib import import_module
from pathlib import Path

QColor = getattr(import_module("PySide6.QtGui"), "QColor")
CalendarEvent = getattr(import_module("src.models.event"), "CalendarEvent")
ColorRule = getattr(import_module("src.services.ai.color_schema"), "ColorRule")
CustomColorSchema = getattr(
    import_module("src.services.ai.color_schema"),
    "CustomColorSchema",
)
AIEventColorService = getattr(
    import_module("src.services.ai.event_coloring"),
    "AIEventColorService",
)


class AIEventColorServiceReclassifyGuardTest(unittest.TestCase):
    def _build_service(self):
        service = AIEventColorService()
        service.enabled = True
        service._supported_palette = ["#dc2127"]

        temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(temp_dir.cleanup)
        schema_path = Path(temp_dir.name) / "color_schema.test.json"
        service._custom_schema = CustomColorSchema(schema_path=str(schema_path))
        service._custom_schema.rules = [
            ColorRule(color_hex="#dc2127", label="Work"),
        ]
        return service

    def test_apply_skips_only_ai_locked_events(self) -> None:
        service = self._build_service()

        manual_color = QColor("#5484ed")
        manual_color.setAlpha(180)

        provider_colored = CalendarEvent(
            id="event-provider-colored",
            summary="Planning",
            description="",
            start_time=dt.datetime(2026, 3, 6, 9, 0),
            end_time=dt.datetime(2026, 3, 6, 10, 0),
            color=manual_color,
            provider_color_id="9",
        )
        ai_locked = CalendarEvent(
            id="event-ai-locked",
            summary="DoNotReclassify",
            description="",
            start_time=dt.datetime(2026, 3, 6, 9, 30),
            end_time=dt.datetime(2026, 3, 6, 10, 30),
            provider_color_id="11",
            ai_color_locked=True,
        )
        pending = CalendarEvent(
            id="event-pending",
            summary="Standup",
            description="",
            start_time=dt.datetime(2026, 3, 6, 10, 0),
            end_time=dt.datetime(2026, 3, 6, 10, 30),
        )

        classified_titles: list[str] = []

        def fake_classify(titles: list[str]) -> dict[str, str]:
            classified_titles.extend(titles)
            return {
                "planning": "custom_work",
                "standup": "custom_work",
            }

        service._classify_titles = fake_classify  # type: ignore[method-assign]

        _ = service.apply([provider_colored, ai_locked, pending])

        self.assertEqual(classified_titles, ["Planning", "Standup"])
        self.assertEqual(provider_colored.color.name().lower(), "#dc2127")
        self.assertEqual(pending.color.name().lower(), "#dc2127")
        self.assertEqual(pending.color.alpha(), 180)
        self.assertTrue(provider_colored.ai_color_locked)
        self.assertTrue(provider_colored.ai_color_lock_pending_write)
        self.assertTrue(pending.ai_color_locked)
        self.assertTrue(pending.ai_color_lock_pending_write)
        self.assertTrue(ai_locked.ai_color_locked)
        self.assertFalse(ai_locked.ai_color_lock_pending_write)

    def test_apply_does_not_classify_when_all_events_already_ai_locked(self) -> None:
        service = self._build_service()

        first = CalendarEvent(
            id="event-1",
            summary="Review",
            description="",
            start_time=dt.datetime(2026, 3, 6, 11, 0),
            end_time=dt.datetime(2026, 3, 6, 12, 0),
            provider_color_id="11",
            ai_color_locked=True,
        )
        second = CalendarEvent(
            id="event-2",
            summary="Lunch",
            description="",
            start_time=dt.datetime(2026, 3, 6, 12, 0),
            end_time=dt.datetime(2026, 3, 6, 13, 0),
            provider_color_id="5",
            ai_color_locked=True,
        )

        def fail_classify(titles: list[str]) -> dict[str, str]:
            _ = titles
            raise AssertionError("_classify_titles should not run for AI-locked events")

        service._classify_titles = fail_classify  # type: ignore[method-assign]

        _ = service.apply([first, second])


if __name__ == "__main__":
    unittest.main()
