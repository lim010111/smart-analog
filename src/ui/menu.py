from PySide6.QtWidgets import QMenu
from PySide6.QtGui import QAction

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
        from PySide6.QtWidgets import QApplication
        exit_action.triggered.connect(QApplication.quit)
        self.addAction(exit_action)
