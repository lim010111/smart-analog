import sys
import os
import datetime

current_dir = os.path.dirname(os.path.abspath(__file__))
project_root = os.path.dirname(current_dir)
if project_root not in sys.path:
    sys.path.insert(0, project_root)
from PySide6.QtWidgets import QApplication, QMessageBox
from PySide6.QtCore import Qt, QTimer, QThread, Signal
from src.ui.clock import AnalogClock
from src.ui.menu import ClockContextMenu
from src.ui.dialogs import AppleLoginDialog, CustomColorSchemaDialog
from src.services.calendar import CalendarService
from src.services.ai import BriefingTTSAdapter
from src.services.providers.apple_provider import AppleCalendarProvider
from caldav.lib.error import AuthorizationError
import src.core.startup as startup


class BulkColorSyncThread(QThread):
    completed = Signal(int, int)
    failed = Signal(str)

    def __init__(self, calendar_service):
        super().__init__()
        self.calendar_service = calendar_service

    def run(self):
        try:
            total, updated = self.calendar_service.sync_ai_colors_for_all_events(
                max_results=None,
                page_size=250,
                throttle_seconds=0.05,
            )
            self.completed.emit(total, updated)
        except Exception as e:
            self.failed.emit(str(e))


class TodayBriefingThread(QThread):
    completed = Signal(str)
    failed = Signal(str)

    def __init__(self, briefing_service, events: list):
        super().__init__()
        self.briefing_service = briefing_service
        self.events = list(events)

    def run(self):
        try:
            text = self.briefing_service.generate_today_briefing(self.events)
            self.completed.emit(text)
        except Exception as e:
            self.failed.emit(str(e))


class MainClockWindow(AnalogClock):
    def __init__(self):
        super().__init__()

        self.calendar_service = CalendarService()
        self.calendar_service.set_active_provider("google")
        self._briefing_tts = BriefingTTSAdapter()
        self._briefing_thread: TodayBriefingThread | None = None
        self._today_briefing_text = ""
        self.today_briefing_enabled = (
            self.calendar_service.ai_today_briefing_service.is_enabled()
        )

        self.setWindowFlags(
            Qt.Window | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
        )
        self.setWindowTitle("Analog Clock Widget")

        self.setContextMenuPolicy(Qt.CustomContextMenu)
        self.customContextMenuRequested.connect(self.show_context_menu)

        self.refresh_timer = QTimer(self)
        self.refresh_timer.timeout.connect(self.refresh_calendar_events)
        self.refresh_timer.start(300000)
        self._bulk_sync_thread: BulkColorSyncThread | None = None

        try:
            if os.path.exists("token.json"):
                self.refresh_calendar_events()
            self._trigger_today_briefing_generation(on_startup=True)
        except Exception as e:
            print(f"Initial sync failed: {e}")

    def sync_calendar(self):
        try:
            provider = self.calendar_service.active_provider
            if not provider:
                QMessageBox.warning(
                    self, "No Provider", "Please select a calendar provider first."
                )
                return

            if (
                isinstance(provider, AppleCalendarProvider)
                and not provider.is_authenticated()
            ):
                if not provider.has_saved_credentials():
                    dialog = AppleLoginDialog(provider, self)
                    if dialog.exec() != AppleLoginDialog.Accepted:
                        return

            self.calendar_service.authenticate()
            self.refresh_calendar_events()
            name = provider.provider_name
            QMessageBox.information(
                self, "Success", f"{name} Calendar synced successfully!"
            )
        except AuthorizationError:
            self._handle_apple_reauth()
        except Exception as e:
            QMessageBox.critical(self, "Error", f"Calendar sync failed: {e}")

    def _handle_apple_reauth(self):
        provider = self.calendar_service.active_provider
        if not isinstance(provider, AppleCalendarProvider):
            return

        self.events = []
        self.update()

        QMessageBox.warning(
            self,
            "Session Expired",
            "Apple Calendar session has expired.\nPlease sign in again.",
        )

        dialog = AppleLoginDialog(provider, self)
        if dialog.exec() == AppleLoginDialog.Accepted:
            self.refresh_calendar_events()

    def refresh_calendar_events(self):
        try:
            new_events = self.calendar_service.get_todays_events()
            self.events = new_events
            self.update()
            self._trigger_today_briefing_generation(on_startup=False)
        except AuthorizationError:
            self._handle_apple_reauth()
        except Exception as e:
            print(f"Failed to refresh events: {e}")

    def switch_provider(self, provider_key: str):
        provider = self.calendar_service.set_active_provider(provider_key)

        if isinstance(provider, AppleCalendarProvider):
            if not provider.has_saved_credentials():
                dialog = AppleLoginDialog(provider, self)
                if dialog.exec() != AppleLoginDialog.Accepted:
                    self.calendar_service.set_active_provider("google")
                    return

        try:
            self.refresh_calendar_events()
        except Exception as e:
            print(f"Provider switch refresh failed: {e}")

    def show_context_menu(self, pos):
        menu = ClockContextMenu(self)
        menu.exec(self.mapToGlobal(pos))

    def is_today_briefing_enabled(self) -> bool:
        return self.calendar_service.ai_today_briefing_service.is_enabled()

    def toggle_today_briefing(self) -> None:
        service = self.calendar_service.ai_today_briefing_service
        next_state = not service.is_enabled()
        service.set_enabled(next_state)
        self.today_briefing_enabled = next_state

        if next_state:
            self._trigger_today_briefing_generation(on_startup=False, force=True)
        else:
            self._today_briefing_text = ""
            self.clear_today_briefing()

    def is_briefing_tts_available(self) -> bool:
        return self._briefing_tts.is_available()

    def is_today_briefing_tts_enabled(self) -> bool:
        return self.calendar_service.ai_today_briefing_service.is_tts_enabled()

    def toggle_today_briefing_tts(self) -> None:
        service = self.calendar_service.ai_today_briefing_service
        next_state = not service.is_tts_enabled()
        service.set_tts_enabled(next_state)

    def speak_today_briefing(self) -> None:
        if not self._briefing_tts.is_available():
            reason = self._briefing_tts.unavailable_reason()
            message = "No TTS backend is available on this system."
            if reason:
                message = f"{message}\n\nReason: {reason}"
            QMessageBox.information(
                self,
                "TTS Unavailable",
                message,
            )
            return
        if not self._today_briefing_text:
            self._trigger_today_briefing_generation(on_startup=False, force=True)
            return
        self._briefing_tts.speak(self._today_briefing_text)

    def _trigger_today_briefing_generation(
        self,
        on_startup: bool,
        force: bool = False,
    ) -> None:
        service = self.calendar_service.ai_today_briefing_service
        if not service.is_enabled():
            return

        if self._briefing_thread and self._briefing_thread.isRunning():
            return

        self._briefing_thread = TodayBriefingThread(service, self.events)
        self._briefing_thread.completed.connect(
            lambda text: self._on_today_briefing_completed(text, on_startup)
        )
        self._briefing_thread.failed.connect(self._on_today_briefing_failed)
        self._briefing_thread.finished.connect(self._on_today_briefing_finished)
        self._briefing_thread.start()

    def _on_today_briefing_completed(self, text: str, on_startup: bool) -> None:
        normalized = str(text).strip()
        self._today_briefing_text = normalized
        self.set_today_briefing(normalized)

        service = self.calendar_service.ai_today_briefing_service
        self.today_briefing_enabled = service.is_enabled()

        if on_startup and normalized:
            QMessageBox.information(self, "오늘의 브리핑", normalized)

        if on_startup and normalized and service.is_tts_enabled():
            self._briefing_tts.speak(normalized)

    def _on_today_briefing_failed(self, message: str) -> None:
        print(f"Today briefing failed: {message}")

    def _on_today_briefing_finished(self) -> None:
        self._briefing_thread = None

    def toggle_always_on_top(self):
        self._always_on_top = not self._always_on_top
        self.setWindowFlag(Qt.WindowStaysOnTopHint, self._always_on_top)
        self.show()
        if self._always_on_top:
            self.raise_()
            self.activateWindow()

    def set_theme(self, theme_name):
        self.current_theme_name = theme_name
        self.update()

    def is_startup_enabled(self):
        return startup.is_startup_enabled()

    def toggle_startup(self):
        current = startup.is_startup_enabled()
        startup.set_startup(not current)
        self.update()

    def logout(self):
        provider = self.calendar_service.active_provider
        if not provider:
            QMessageBox.warning(self, "No Provider", "No calendar provider is active.")
            return

        name = provider.provider_name
        self.calendar_service.logout()
        self.events = []
        self.update()
        QMessageBox.information(
            self, "Logged Out", f"{name} account has been logged out."
        )

    def open_color_schema(self):
        if not self.calendar_service.can_write_event_colors():
            QMessageBox.warning(
                self,
                "Unsupported Provider",
                "Current calendar provider does not support event color write.",
            )
            return

        allowed_colors = self.calendar_service.get_supported_ai_colors()
        if not allowed_colors:
            QMessageBox.warning(
                self,
                "No Color Palette",
                "No writable color palette available for current provider.",
            )
            return

        ai_service = self.calendar_service.ai_event_color_service
        dialog = CustomColorSchemaDialog(ai_service, allowed_colors, self)
        if dialog.exec() == CustomColorSchemaDialog.Accepted:
            self.refresh_calendar_events()

    def apply_ai_colors_to_all_events(self):
        if not self.calendar_service.can_write_event_colors():
            QMessageBox.warning(
                self,
                "Unsupported Provider",
                "Current calendar provider does not support event color write.",
            )
            return

        confirmed = QMessageBox.question(
            self,
            "Apply AI Colors",
            "Apply AI color rules to all events in this calendar?\n"
            "This may take some time and perform many API updates.",
            QMessageBox.Yes | QMessageBox.No,
            QMessageBox.No,
        )
        if confirmed != QMessageBox.Yes:
            return

        if self._bulk_sync_thread and self._bulk_sync_thread.isRunning():
            QMessageBox.information(
                self,
                "Sync In Progress",
                "AI color sync is already running in background.",
            )
            return

        self.refresh_timer.stop()
        self.setCursor(Qt.WaitCursor)

        self._bulk_sync_thread = BulkColorSyncThread(self.calendar_service)
        self._bulk_sync_thread.completed.connect(self._on_bulk_sync_completed)
        self._bulk_sync_thread.failed.connect(self._on_bulk_sync_failed)
        self._bulk_sync_thread.finished.connect(self._on_bulk_sync_finished)
        self._bulk_sync_thread.start()

        QMessageBox.information(
            self,
            "AI Color Sync Started",
            "Full event AI color sync is running in background.",
        )

    def _on_bulk_sync_completed(self, total: int, updated: int):
        self.refresh_calendar_events()
        QMessageBox.information(
            self,
            "AI Color Sync Complete",
            f"Processed {total} events and updated {updated} event colors.",
        )

    def _on_bulk_sync_failed(self, message: str):
        QMessageBox.critical(self, "AI Color Sync Failed", message)

    def _on_bulk_sync_finished(self):
        self.unsetCursor()
        self.refresh_timer.start(300000)
        self._bulk_sync_thread = None

    def mousePressEvent(self, event):
        if event.button() == Qt.LeftButton:
            if self.check_close_button(event.position().toPoint()):
                QApplication.quit()
                return

            if self.windowHandle():
                self.windowHandle().startSystemMove()
            event.accept()


if __name__ == "__main__":
    app = QApplication(sys.argv)
    app.setStyle("Fusion")

    clock = MainClockWindow()
    clock.show()
    sys.exit(app.exec())
