import math
import datetime
from PySide6.QtCore import Qt, QTimer, QTime, QPoint, QRect
from PySide6.QtGui import QPainter, QColor, QPolygon, QBrush, QPen
from PySide6.QtWidgets import QWidget
from src.core.theme import THEMES


class EventTooltip(QWidget):
    """일정 제목을 표시하는 독립적인 오버레이 툴팁 윈도우입니다."""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowFlags(
            Qt.ToolTip | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
        )
        self.setAttribute(Qt.WA_TranslucentBackground)
        # 마우스 이벤트를 통과시켜 시계 조작에 방해되지 않도록 설정
        self.setAttribute(Qt.WA_TransparentForMouseEvents)

        self.event_item = None
        self.text_width = 0
        self.box_width = 0
        self.box_height = 0
        self.padding = 10
        self.color_point_size = 10
        self.gap = 8

    def _format_time_range(self, event) -> str:
        start = event.start_time.astimezone()
        end = event.end_time.astimezone()
        return f"{start.strftime('%H:%M')} - {end.strftime('%H:%M')}"

    def show_event(self, event, global_pos):
        self.event_item = event
        self.time_range_text = self._format_time_range(event)

        title_font = self.font()
        title_font.setPointSize(10)
        title_font.setBold(True)

        sub_font = self.font()
        sub_font.setPointSize(8)
        sub_font.setBold(False)

        from PySide6.QtGui import QFontMetrics

        title_metrics = QFontMetrics(title_font)
        sub_metrics = QFontMetrics(sub_font)

        self.title_font = title_font
        self.sub_font = sub_font

        title_width = title_metrics.horizontalAdvance(event.summary)
        sub_width = sub_metrics.horizontalAdvance(self.time_range_text)
        self.text_width = max(title_width, sub_width)

        self.title_height = title_metrics.height()
        self.sub_height = sub_metrics.height()
        line_spacing = 2

        content_x = self.padding + self.color_point_size + self.gap
        self.box_width = content_x + self.text_width + self.padding
        self.box_height = (
            self.padding
            + self.title_height
            + line_spacing
            + self.sub_height
            + self.padding
        )

        self.resize(self.box_width + 10, self.box_height + 10)

        x = global_pos.x() + 15
        y = global_pos.y() + 15

        self.move(x, y)
        self.show()
        self.update()

    def paintEvent(self, paint_event):
        if not self.event_item:
            return

        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)

        tooltip_rect = QRect(0, 0, self.box_width, self.box_height)

        # 그림자 효과
        painter.setPen(Qt.NoPen)
        painter.setBrush(QColor(0, 0, 0, 100))
        painter.drawRoundedRect(tooltip_rect.translated(2, 2), 5, 5)

        # 배경
        painter.setBrush(QColor(40, 40, 40, 240))
        painter.setPen(QPen(QColor(255, 255, 255, 120), 1))
        painter.drawRoundedRect(tooltip_rect, 5, 5)

        # 일정 색상 포인트
        point_rect = QRect(
            self.padding,
            (self.box_height - self.color_point_size) / 2,
            self.color_point_size,
            self.color_point_size,
        )
        painter.setBrush(QBrush(self.event_item.color))
        painter.setPen(Qt.NoPen)
        painter.drawRect(point_rect)

        content_x = self.padding + self.color_point_size + self.gap

        painter.setPen(QColor(255, 255, 255))
        painter.setFont(self.title_font)
        painter.drawText(
            content_x,
            self.padding,
            self.text_width,
            self.title_height,
            Qt.AlignLeft | Qt.AlignVCenter,
            self.event_item.summary,
        )

        painter.setPen(QColor(180, 180, 180))
        painter.setFont(self.sub_font)
        painter.drawText(
            content_x,
            self.padding + self.title_height + 2,
            self.text_width,
            self.sub_height,
            Qt.AlignLeft | Qt.AlignVCenter,
            self.time_range_text,
        )


class AnalogClock(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.current_theme_name = "dark"
        self._always_on_top = True
        self.events = []  # 캘린더 이벤트 리스트
        self.event_alpha = 150  # 일정 영역 기본 투명도 (0-255)

        # 닫기 버튼 설정
        self.close_btn_rect = QRect(260, 10, 30, 30)
        self.is_hovering_close = False
        self.hovered_event = None
        self.mouse_pos = QPoint(0, 0)

        # 오버레이 툴팁 윈도우 생성
        self.tooltip_window = EventTooltip(self)

        # 기본 윈도우 플래그는 관리를 위해 Main에서 처리하도록 위젯 속성만 설정
        self.setAttribute(Qt.WA_TranslucentBackground)
        self.setMouseTracking(True)

        # 타이머 설정 (부드러운 업데이트를 위해 50ms 간격)
        self.timer = QTimer(self)
        self.timer.timeout.connect(self.update)
        self.timer.start(50)

        self.resize(300, 300)

    def closeEvent(self, event):
        """윈도우 종료 시 툴팁 윈도우도 함께 닫습니다."""
        self.tooltip_window.close()
        super().closeEvent(event)

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)

        # 전체 영역 클릭 감지용 배경
        painter.fillRect(self.rect(), QColor(0, 0, 0, 1))

        side = min(self.width(), self.height())
        time_now = QTime.currentTime()
        theme = THEMES[self.current_theme_name]

        # --- [시작] 시계 판 그리기 영역 ---
        painter.save()  # 전체 시계 판 변환을 위해 상태 저장

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
            if j % 4 != 0:  # 12시간 눈금과 겹치지 않는 경우만 그리기
                painter.drawLine(88, 0, 90, 0)
            painter.rotate(7.5)  # 360 / 48 = 7.5도 (15분 단위)

        # 시침
        painter.setPen(Qt.NoPen)
        painter.setBrush(theme["hands"])
        painter.save()
        painter.rotate(30.0 * (time_now.hour() + time_now.minute() / 60.0))
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
            painter.drawText(
                int(x - rect_size / 2),
                int(y - rect_size / 2),
                rect_size,
                rect_size,
                Qt.AlignCenter,
                str(i),
            )

        painter.restore()  # 시계 판 변환 복구 (기본 좌표계로)
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
        painter.drawLine(
            r.left() + margin, r.top() + margin, r.right() - margin, r.bottom() - margin
        )
        painter.drawLine(
            r.right() - margin, r.top() + margin, r.left() + margin, r.bottom() - margin
        )

        painter.restore()

    def mouseMoveEvent(self, event):
        """마우스 이동 시 호버 여부를 체크합니다."""
        self.mouse_pos = event.position().toPoint()

        # 1. 닫기 버튼 호버 체크
        was_hovering_close = self.is_hovering_close
        self.is_hovering_close = self.close_btn_rect.contains(self.mouse_pos)

        # 2. 일정 영역 호버 체크
        old_hovered_event = self.hovered_event
        self.hovered_event = self.check_event_hover(self.mouse_pos)

        # 오버레이 툴팁 갱신
        if self.hovered_event:
            global_pos = self.mapToGlobal(self.mouse_pos)
            self.tooltip_window.show_event(self.hovered_event, global_pos)
        else:
            self.tooltip_window.hide()

        # 상태가 변했을 때만 다시 그리기 호출
        if (
            was_hovering_close != self.is_hovering_close
            or old_hovered_event != self.hovered_event
        ):
            self.update()

        super().mouseMoveEvent(event)

    def check_event_hover(self, pos):
        """마우스 위치가 일정 영역 위인지 확인하고 해당 이벤트를 반환합니다."""
        if not self.events:
            return None

        # 시계 중심으로부터의 상대 좌표 계산
        center = QPoint(self.width() / 2, self.height() / 2)
        rel_x = pos.x() - center.x()
        rel_y = pos.y() - center.y()

        # 반지름 계산 (피타고라스)
        dist = math.sqrt(rel_x**2 + rel_y**2)

        # 스케일 보정 (paintEvent와 동일하게)
        side = min(self.width(), self.height())
        scale = side / 200.0
        scaled_dist = dist / scale

        in_pie_region = 15 <= scaled_dist <= 88
        in_arc_region = 90 <= scaled_dist <= 97

        if not in_pie_region and not in_arc_region:
            return None

        # 각도 계산 (라디안 -> 도)
        # math.atan2는 3시 방향이 0도, 아래쪽이 +, 위쪽이 - (반시계 역방향 느낌)
        # QPainter.drawPie는 3시가 0도, 반시계 방향이 +
        # 우리가 쓰는 start_angle 계산: (90 - (hour * 30)) * 16

        angle_rad = math.atan2(-rel_y, rel_x)  # y 부호 반전하여 상단을 +로
        angle_deg = math.degrees(angle_rad)
        if angle_deg < 0:
            angle_deg += 360  # 0 ~ 360 범위로 보정 (3시=0, 12시=90, 9시=180, 6시=270)

        now_dt = datetime.datetime.now().astimezone()
        current_is_am = now_dt.hour < 12

        for event in self.events:
            ev_start_local = event.start_time.astimezone()
            ev_end_local = event.end_time.astimezone()

            if now_dt > ev_end_local:
                continue

            is_in_progress = ev_start_local <= now_dt <= ev_end_local
            is_current_cycle = is_in_progress or current_is_am == (
                ev_start_local.hour < 12
            )

            if is_current_cycle and not in_pie_region:
                continue
            if not is_current_cycle and not in_arc_region:
                continue

            # 일전 각도 범위 계산 (16배 하지 않은 도 단위)
            start_hour = ev_start_local.hour % 12 + ev_start_local.minute / 60.0

            # 진행 중인 일정은 현재 시각부터 시작함
            if is_in_progress:
                now_hour_val = (
                    now_dt.hour % 12 + now_dt.minute / 60.0 + now_dt.second / 3600.0
                )
                start_angle = 90 - (now_hour_val * 30)
            else:
                start_angle = 90 - (start_hour * 30)

            span_min = min(event.duration_minutes, 12 * 60)

            if is_in_progress:
                remaining_seconds = (ev_end_local - now_dt).total_seconds()
                remaining_hours = min(12.0, remaining_seconds / 3600.0)
                span_angle = -(remaining_hours * 30)
            else:
                span_angle = -(span_min / (12 * 60) * 360)

            # 0~360 범위로 정규화
            s_angle = start_angle % 360
            e_angle = (start_angle + span_angle) % 360

            # 각도 포함 여부 체크 (시계 방향으로 그려지므로 span은 음수)
            # 예: start=90(12시), span=-30 -> range [60, 90]
            # e_angle이 s_angle보다 작은 경우 (일반적)
            if e_angle < s_angle:
                if e_angle <= angle_deg <= s_angle:
                    return event
            else:
                # 0도를 통과하는 경우 (예: 2시~4시는 30도 ~ 330도)
                # s_angle이 e_angle보다 작아진 경우 (30 < 330)
                if angle_deg >= e_angle or angle_deg <= s_angle:
                    return event

        return None

    def check_close_button(self, pos):
        """클릭 좌표가 닫기 버튼 영역인지 확인합니다."""
        return self.close_btn_rect.contains(pos)

    def draw_calendar_events(self, painter):
        """캘린더 일정을 시계 판 위에 시각화합니다."""
        if not self.events:
            return

        # 현재 로컬 시간 기준 (시계 바늘과 일치시키기 위함)
        now_dt = datetime.datetime.now().astimezone()
        current_is_am = now_dt.hour < 12

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

            # AM/PM 사이클 분류 (check_event_hover와 동일한 로직)
            is_in_progress = ev_start_local <= now_dt <= ev_end_local
            is_current_cycle = is_in_progress or current_is_am == (
                ev_start_local.hour < 12
            )

            # 진행 중인 일정에 대한 특수 효과
            if is_in_progress:
                # 시침 위치에 맞춰 실시간으로 영역 지우기 효과 적용 (모든 일정 공통)
                now_hour_val = (
                    now_dt.hour % 12 + now_dt.minute / 60.0 + now_dt.second / 3600.0
                )
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
                color.setAlpha(int(self.event_alpha * 0.4))  # 기본 투명도의 40%

            if is_current_cycle:
                # 현재 사이클 일정: 부채꼴(pie) + 외곽선(arc) 렌더링
                painter.setPen(Qt.NoPen)
                painter.setBrush(QBrush(color))

                rect = QRect(-88, -88, 176, 176)
                painter.drawPie(rect, int(start_angle), int(span_angle))

                # 외곽선 그리기
                outline_color = QColor(color)
                if is_in_progress:
                    outline_color.setAlpha(min(255, self.event_alpha + 60))
                else:
                    outline_color.setAlpha(min(255, color.alpha() + 40))

                pen = QPen(outline_color, 1.5, Qt.SolidLine)
                painter.setPen(pen)
                painter.setBrush(Qt.NoBrush)
                painter.drawArc(rect, int(start_angle), int(span_angle))
            else:
                # 다음 사이클 일정: 바깥쪽 호(arc)만 렌더링
                outer_rect = QRect(-94, -94, 188, 188)
                arc_color = QColor(color)
                arc_color.setAlpha(min(255, color.alpha() + 40))

                pen = QPen(arc_color, 4, Qt.SolidLine, Qt.RoundCap)
                painter.setPen(pen)
                painter.setBrush(Qt.NoBrush)
                painter.drawArc(outer_rect, int(start_angle), int(span_angle))
