import math
import datetime
from PySide6.QtCore import Qt, QTimer, QTime, QPoint, QRect
from PySide6.QtGui import QPainter, QColor, QPolygon, QBrush, QPen
from PySide6.QtWidgets import QWidget
from src.core.theme import THEMES

class AnalogClock(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.current_theme_name = "dark"
        self._always_on_top = True
        self.events = [] # 캘린더 이벤트 리스트
        self.event_alpha = 150  # 일정 영역 기본 투명도 (0-255)
        
        # 닫기 버튼 설정
        self.close_btn_rect = QRect(260, 10, 30, 30)
        self.is_hovering_close = False
        
        # 기본 윈도우 플래그는 관리를 위해 Main에서 처리하도록 위젯 속성만 설정
        self.setAttribute(Qt.WA_TranslucentBackground)
        self.setMouseTracking(True)
        
        # 타이머 설정 (부드러운 업데이트를 위해 50ms 간격)
        self.timer = QTimer(self)
        self.timer.timeout.connect(self.update)
        self.timer.start(50)
        
        self.resize(300, 300)

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        
        # 전체 영역 클릭 감지용 배경
        painter.fillRect(self.rect(), QColor(0, 0, 0, 1))

        side = min(self.width(), self.height())
        time_now = QTime.currentTime()
        theme = THEMES[self.current_theme_name]

        # --- [시작] 시계 판 그리기 영역 ---
        painter.save() # 전체 시계 판 변환을 위해 상태 저장
        
        # 중앙으로 이동 및 스케일 조정
        painter.translate(self.width() / 2, self.height() / 2)
        painter.scale(side / 200.0, side / 200.0)

        # 시계 배경 원
        painter.setPen(QPen(theme["border"], 2))
        painter.setBrush(QBrush(theme["face"]))
        painter.drawEllipse(-95, -95, 190, 190)

        # 일정(Calendar Events) 그리기 - 배경 위에, 눈금 아래에 위치
        self.draw_calendar_events(painter)

        # 눈금 그리기 (시간)
        painter.setPen(QPen(theme["ticks"], 2))
        for i in range(12):
            painter.drawLine(85, 0, 90, 0)
            painter.rotate(30.0)

        # 눈금 그리기 (분/초 보조 눈금 - 15분 단위 분할)
        painter.setPen(QPen(theme["ticks"], 1))
        for j in range(48):
            if j % 4 != 0: # 12시간 눈금과 겹치지 않는 경우만 그리기
                painter.drawLine(88, 0, 90, 0)
            painter.rotate(7.5) # 360 / 48 = 7.5도 (15분 단위)

        # 시침
        painter.setPen(Qt.NoPen)
        painter.setBrush(theme["hands"])
        painter.save()
        painter.rotate(30.0 * ((time_now.hour() + time_now.minute() / 60.0)))
        painter.drawPolygon(QPolygon([QPoint(-4, 8), QPoint(4, 8), QPoint(0, -50)]))
        painter.restore()

        # 분침
        painter.setBrush(theme["hands"])
        painter.save()
        painter.rotate(6.0 * (time_now.minute() + time_now.second() / 60.0))
        painter.drawPolygon(QPolygon([QPoint(-3, 8), QPoint(3, 8), QPoint(0, -75)]))
        painter.restore()

        # 초침
        painter.setBrush(QColor(255, 80, 80)) 
        painter.save()
        smooth_seconds = time_now.second() + time_now.msec() / 1000.0
        painter.rotate(6.0 * smooth_seconds)
        painter.drawPolygon(QPolygon([QPoint(-1, 15), QPoint(1, 15), QPoint(0, -85)]))
        painter.restore()
        
        # 중앙 핀
        painter.setBrush(theme["hands"])
        painter.drawEllipse(-3, -3, 6, 6)

        # 시간 숫자 표시 (1-12)
        painter.setPen(QPen(theme["nums"]))
        font = painter.font()
        font.setBold(False)
        font.setPointSize(9)
        painter.setFont(font)
        
        for i in range(1, 13):
            angle = (i * 30 - -270) * math.pi / 180.0
            x = 72 * math.cos(angle)
            y = 72 * math.sin(angle)
            
            rect_size = 20
            painter.drawText(int(x - rect_size/2), int(y - rect_size/2), rect_size, rect_size, 
                             Qt.AlignCenter, str(i))
            
        painter.restore() # 시계 판 변환 복구 (기본 좌표계로)
        # --- [끝] 시계 판 그리기 영역 ---

        # 닫기 버튼 그리기 (기본 좌표계에서 수행)
        self.draw_close_button(painter, theme)

    def draw_close_button(self, painter, theme):
        """우측 상단에 닫기(x) 버튼을 그립니다."""
        painter.save()
        
        # 호버 상태에 따른 색상 정의
        bg_alpha = 150 if self.is_hovering_close else 30
        x_alpha = 255 if self.is_hovering_close else 150
        
        # 배경 원 (옵션)
        painter.setPen(Qt.NoPen)
        painter.setBrush(QColor(255, 80, 80, bg_alpha))
        painter.drawEllipse(self.close_btn_rect)
        
        # 'x' 그리기
        pen = QPen(QColor(255, 255, 255, x_alpha), 2, Qt.SolidLine, Qt.RoundCap)
        painter.setPen(pen)
        
        margin = 10
        r = self.close_btn_rect
        painter.drawLine(r.left() + margin, r.top() + margin, r.right() - margin, r.bottom() - margin)
        painter.drawLine(r.right() - margin, r.top() + margin, r.left() + margin, r.bottom() - margin)
        
        painter.restore()

    def mouseMoveEvent(self, event):
        """마우스 이동 시 닫기 버튼 호버 여부를 체크합니다."""
        was_hovering = self.is_hovering_close
        self.is_hovering_close = self.close_btn_rect.contains(event.position().toPoint())
        
        # 상태가 변했을 때만 다시 그리기 호출
        if was_hovering != self.is_hovering_close:
            self.update()
        
        super().mouseMoveEvent(event)

    def check_close_button(self, pos):
        """클릭 좌표가 닫기 버튼 영역인지 확인합니다."""
        return self.close_btn_rect.contains(pos)

    def draw_calendar_events(self, painter):
        """캘린더 일정을 시계 판 위에 시각화합니다."""
        if not self.events:
            return

        # 현재 로컬 시간 기준 (시계 바늘과 일치시키기 위함)
        now_dt = datetime.datetime.now().astimezone()
        
        for event in self.events:
            # Google API로부터 온 Aware Datetime을 사용자의 로컬 타임존으로 변환
            # (start_time.hour 등이 로컬 시간 기준으로 작동하도록 함)
            ev_start_local = event.start_time.astimezone()
            ev_end_local = event.end_time.astimezone()

            # 일정이 현재 시계가 보여주는 12시간 범위 내에 있는지 확인
            # 시작/종료 시간 각도 계산 (로컬 시간 기준)
            start_hour = ev_start_local.hour % 12 + ev_start_local.minute / 60.0
            end_hour = ev_end_local.hour % 12 + ev_end_local.minute / 60.0
            
            # 아날로그 시계 각도 (12시가 90도, 시계 방향)
            # QPainter.drawArc/drawPie는 1/16도 단위를 사용하며, 3시 방향이 0도, 반시계 방향임
            
            start_angle = (90 - (start_hour * 30)) * 16
            
            # duration_minutes가 12시간을 넘을 경우 제한
            span_min = min(event.duration_minutes, 12 * 60)
            span_angle = -(span_min / (12 * 60) * 360) * 16
            
            # 종료된 일정은 표시하지 않음 (사용자 요청 반영)
            if now_dt > ev_end_local:
                continue

            # 진행 중인 일정에 대한 특수 효과
            if ev_start_local <= now_dt <= ev_end_local:
                # 시침 위치에 맞춰 실시간으로 영역 지우기 효과 적용 (모든 일정 공통)
                now_hour_val = now_dt.hour % 12 + now_dt.minute / 60.0 + now_dt.second / 3600.0
                start_angle = (90 - (now_hour_val * 30)) * 16
                
                remaining_seconds = (ev_end_local - now_dt).total_seconds()
                # 남은 시간을 최대 12시간으로 제한 (시계 한 바퀴)
                remaining_hours = min(12.0, remaining_seconds / 3600.0)
                span_angle = -(remaining_hours * 30) * 16
                
                color = QColor(event.color)
                color.setAlpha(self.event_alpha)
            else:
                # 시작 전 일정 (미래): 은은하게 표시
                color = QColor(event.color)
                color.setAlpha(int(self.event_alpha * 0.4)) # 기본 투명도의 40%

            # 렌더링 시작
            painter.setPen(Qt.NoPen)
            painter.setBrush(QBrush(color))
            
            # 1. 색상 채우기 (부채꼴)
            rect = QRect(-88, -88, 176, 176)
            painter.drawPie(rect, int(start_angle), int(span_angle))
            
            # 2. 외곽선 그리기
            outline_color = QColor(color)
            if ev_start_local <= now_dt <= ev_end_local:
                # 진행 중인 일정: 채우기보다 약간 더 선명하게 (최대 255)
                outline_color.setAlpha(min(255, self.event_alpha + 60))
            else:
                # 미래 일정: 채우기 알파값에 비례하여 설정
                outline_color.setAlpha(min(255, color.alpha() + 40))
                
            pen = QPen(outline_color, 1.5, Qt.SolidLine)
            painter.setPen(pen)
            painter.setBrush(Qt.NoBrush)
            painter.drawArc(rect, int(start_angle), int(span_angle))
