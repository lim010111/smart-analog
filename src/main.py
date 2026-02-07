import sys
import os

# 프로젝트 루트 디렉토리를 경로에 추가하여 'src' 패키지 임포트 가능하게 설정
current_dir = os.path.dirname(os.path.abspath(__file__))
project_root = os.path.dirname(current_dir)
if project_root not in sys.path:
    sys.path.insert(0, project_root)
from PySide6.QtWidgets import QApplication, QMessageBox
from PySide6.QtCore import Qt, QTimer
from src.ui.clock import AnalogClock
from src.ui.menu import ClockContextMenu
from src.services.calendar import CalendarService

class MainClockWindow(AnalogClock):
    def __init__(self):
        super().__init__()
        
        self.calendar_service = CalendarService()
        
        # 메인 윈도우 플래그 설정
        self.setWindowFlags(Qt.Window | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint)
        self.setWindowTitle("Analog Clock Widget")
        
        # 컨텍스트 메뉴 설정
        self.setContextMenuPolicy(Qt.CustomContextMenu)
        self.customContextMenuRequested.connect(self.show_context_menu)
        
        # 일정 갱신 타이머 (5분마다)
        self.refresh_timer = QTimer(self)
        self.refresh_timer.timeout.connect(self.refresh_calendar_events)
        self.refresh_timer.start(300000) # 300,000ms = 5분
        
        # 앱 시작 시 인증 시도 및 일정 로드 (로그인 되어 있을 때만 자동 로드)
        try:
            if os.path.exists('token.json'):
                # 인증은 비동기적으로 수행하는 것이 좋으나 앱 구조상 초기화 시도
                # 실제 API 호출 전 authenticate()는 내부적으로 토큰 유효성을 검사함
                self.refresh_calendar_events()
        except Exception as e:
            print(f"Initial sync failed: {e}")

    def sync_calendar(self):
        """Google 캘린더 전용 인증 및 전체 동기화를 수행합니다."""
        try:
            self.calendar_service.authenticate()
            self.refresh_calendar_events()
            QMessageBox.information(self, "Success", "Google Calendar synced successfully!")
        except Exception as e:
            QMessageBox.critical(self, "Error", f"Calendar sync failed: {e}")

    def refresh_calendar_events(self):
        """최신 일정을 가져와 시계에 업데이트합니다."""
        try:
            # 캘린더 서비스에서 일정을 가져와 AnalogClock의 events 리스트에 저장
            new_events = self.calendar_service.get_upcoming_events()
            self.events = new_events
            self.update() # 시계 다시 그리기
        except Exception as e:
            print(f"Failed to refresh events: {e}")

    def show_context_menu(self, pos):
        menu = ClockContextMenu(self)
        menu.exec(self.mapToGlobal(pos))

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

    def mousePressEvent(self, event):
        if event.button() == Qt.LeftButton:
            if self.windowHandle():
                self.windowHandle().startSystemMove()
            event.accept()

    def mouseDoubleClickEvent(self, event):
        if event.button() == Qt.LeftButton:
            QApplication.quit()

if __name__ == "__main__":
    app = QApplication(sys.argv)
    app.setStyle("Fusion")
    
    # 폰트 경로나 리소스 초기화가 필요하면 여기서 처리
    
    clock = MainClockWindow()
    clock.show()
    sys.exit(app.exec())
