import sys
from PySide6.QtWidgets import (
    QMenu,
    QWidgetAction,
    QSlider,
    QVBoxLayout,
    QWidget,
    QLabel,
    QApplication,
)
from PySide6.QtGui import QAction, QActionGroup
from PySide6.QtCore import Qt

from src.services.calendar import PROVIDER_REGISTRY


class ClockContextMenu(QMenu):
    def __init__(self, parent):
        super().__init__(parent)
        self.clock = parent
        self.setup_menu()

    def setup_menu(self):
        self.setStyleSheet("""
            QMenu {
                background-color: #2b2b2b;
                color: white;
                border: 1px solid #444;
                padding: 10px;
            }
            QMenu::item:selected {
                background-color: #444;
            }
            QMenu::item:checked {
                color: #55ff55;
            }
        """)

        next_theme = "light" if self.clock.current_theme_name == "dark" else "dark"
        theme_action = QAction(f"Switch to {next_theme.capitalize()} Mode", self)
        theme_action.triggered.connect(lambda: self.clock.set_theme(next_theme))
        self.addAction(theme_action)

        ontop_action = QAction("Always on Top", self)
        ontop_action.setCheckable(True)
        ontop_action.setChecked(self.clock._always_on_top)
        ontop_action.triggered.connect(self.clock.toggle_always_on_top)
        self.addAction(ontop_action)

        if sys.platform == "win32":
            startup_action = QAction("Run at Startup", self)
            startup_action.setCheckable(True)
            startup_action.setChecked(self.clock.is_startup_enabled())
            startup_action.triggered.connect(self.clock.toggle_startup)
            self.addAction(startup_action)

        self.addSeparator()

        transparency_label = QLabel("Event Opacity")
        transparency_label.setStyleSheet(
            "color: #aaa; font-size: 10px; margin-left: 5px;"
        )

        slider = QSlider(Qt.Horizontal)
        slider.setMinimum(0)
        slider.setMaximum(255)
        slider.setValue(self.clock.event_alpha)
        slider.setFixedWidth(150)
        slider.setStyleSheet("""
            QSlider { height: 30px; }
            QSlider::handle:horizontal {
                background: #55ff55; width: 12px; border-radius: 6px; margin: -4px 0;
            }
            QSlider::groove:horizontal {
                background: #444; height: 4px; border-radius: 2px;
            }
        """)
        slider.valueChanged.connect(self._update_opacity)

        container = QWidget()
        layout = QVBoxLayout(container)
        layout.setContentsMargins(10, 5, 10, 10)
        layout.setSpacing(5)
        layout.addWidget(transparency_label)
        layout.addWidget(slider)

        slider_action = QWidgetAction(self)
        slider_action.setDefaultWidget(container)
        self.addAction(slider_action)

        self.addSeparator()

        provider_menu = QMenu("Calendar Provider", self)
        provider_menu.setStyleSheet(self.styleSheet())
        provider_group = QActionGroup(self)
        provider_group.setExclusive(True)

        active_key = self.clock.calendar_service.active_provider_key
        for key in PROVIDER_REGISTRY:
            display_name = key.capitalize()
            action = QAction(display_name, self)
            action.setCheckable(True)
            action.setChecked(key == active_key)
            action.triggered.connect(
                lambda checked, k=key: self.clock.switch_provider(k)
            )
            provider_group.addAction(action)
            provider_menu.addAction(action)

        self.addMenu(provider_menu)

        color_schema_action = QAction("Color Schema", self)
        color_schema_action.triggered.connect(self.clock.open_color_schema)
        self.addAction(color_schema_action)

        briefing_toggle_action = QAction("Today Briefing", self)
        briefing_toggle_action.setCheckable(True)
        briefing_toggle_action.setChecked(self.clock.is_today_briefing_enabled())
        briefing_toggle_action.triggered.connect(self.clock.toggle_today_briefing)
        self.addAction(briefing_toggle_action)

        briefing_tts_action = QAction("Briefing TTS", self)
        briefing_tts_action.setCheckable(True)
        briefing_tts_action.setChecked(self.clock.is_today_briefing_tts_enabled())
        briefing_tts_action.setEnabled(self.clock.is_briefing_tts_available())
        briefing_tts_action.triggered.connect(self.clock.toggle_today_briefing_tts)
        self.addAction(briefing_tts_action)

        speak_briefing_action = QAction("Speak Today Briefing", self)
        speak_briefing_action.setEnabled(self.clock.is_briefing_tts_available())
        speak_briefing_action.triggered.connect(self.clock.speak_today_briefing)
        self.addAction(speak_briefing_action)

        sync_all_color_action = QAction("Apply AI Colors to All Events", self)
        sync_all_color_action.triggered.connect(
            self.clock.apply_ai_colors_to_all_events
        )
        self.addAction(sync_all_color_action)

        sync_action = QAction("Sync Calendar", self)
        sync_action.triggered.connect(self.clock.sync_calendar)
        self.addAction(sync_action)

        refresh_action = QAction("Refresh Events", self)
        refresh_action.triggered.connect(self.clock.refresh_calendar_events)
        self.addAction(refresh_action)

        logout_action = QAction("Logout", self)
        logout_action.setEnabled(
            self.clock.calendar_service.active_provider is not None
        )
        logout_action.triggered.connect(self.clock.logout)
        self.addAction(logout_action)

        self.addSeparator()

        exit_action = QAction("Exit", self)
        exit_action.triggered.connect(QApplication.quit)
        self.addAction(exit_action)

    def _update_opacity(self, value):
        self.clock.event_alpha = value
        self.clock.update()
