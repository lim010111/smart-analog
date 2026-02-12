import sys
from PySide6.QtWidgets import QMenu, QWidgetAction, QSlider, QVBoxLayout, QWidget, QLabel, QApplication
from PySide6.QtGui import QAction
from PySide6.QtCore import Qt

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

        # 테마 전환 액션
        next_theme = "light" if self.clock.current_theme_name == "dark" else "dark"
        theme_action = QAction(f"Switch to {next_theme.capitalize()} Mode", self)
        theme_action.triggered.connect(lambda: self.clock.set_theme(next_theme))
        self.addAction(theme_action)
        
        # 항상 위에 고정 토글 액션
        ontop_action = QAction("Always on Top", self)
        ontop_action.setCheckable(True)
        ontop_action.setChecked(self.clock._always_on_top)
        ontop_action.triggered.connect(self.clock.toggle_always_on_top)
        self.addAction(ontop_action)

        # 시작 프로그램 등록 (Windows 전용)
        if sys.platform == "win32":
            startup_action = QAction("Run at Startup", self)
            startup_action.setCheckable(True)
            # MainClockWindow에서 시작 프로그램 상태 정보를 가져와야 함
            startup_action.setChecked(self.clock.is_startup_enabled())
            startup_action.triggered.connect(self.clock.toggle_startup)
            self.addAction(startup_action)

        self.addSeparator()

        # --- 투명도 조절 슬라이더 추가 ---
        transparency_label = QLabel("Event Opacity")
        transparency_label.setStyleSheet("color: #aaa; font-size: 10px; margin-left: 5px;")
        
        slider = QSlider(Qt.Horizontal)
        slider.setMinimum(0)
        slider.setMaximum(255)
        slider.setValue(self.clock.event_alpha)
        slider.setFixedWidth(150)
        slider.setStyleSheet("""
            QSlider {
                height: 30px;
            }
            QSlider::handle:horizontal {
                background: #55ff55;
                width: 12px;
                border-radius: 6px;
                margin: -4px 0;
            }
            QSlider::groove:horizontal {
                background: #444;
                height: 4px;
                border-radius: 2px;
            }
        """)
        slider.valueChanged.connect(self.update_opacity)

        # 위젯들을 담을 컨테이너
        container = QWidget()
        layout = QVBoxLayout(container)
        layout.setContentsMargins(10, 5, 10, 10)
        layout.setSpacing(5)
        layout.addWidget(transparency_label)
        layout.addWidget(slider)

        slider_action = QWidgetAction(self)
        slider_action.setDefaultWidget(container)
        self.addAction(slider_action)
        # --------------------------------

        self.addSeparator()

        # 구글 캘린더 연동 액션
        sync_action = QAction("Sync Google Calendar", self)
        sync_action.triggered.connect(self.clock.sync_calendar)
        self.addAction(sync_action)

        # 일정 새로고침 액션
        refresh_action = QAction("Refresh Events", self)
        refresh_action.triggered.connect(self.clock.refresh_calendar_events)
        self.addAction(refresh_action)

        self.addSeparator()
        
        # 종료 액션
        exit_action = QAction("Exit", self)
        exit_action.triggered.connect(QApplication.quit)
        self.addAction(exit_action)

    def update_opacity(self, value):
        self.clock.event_alpha = value
        self.clock.update()
