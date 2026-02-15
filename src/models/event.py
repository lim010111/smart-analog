from dataclasses import dataclass, field
from datetime import datetime
from PySide6.QtGui import QColor


@dataclass
class CalendarEvent:
    id: str
    summary: str
    start_time: datetime
    end_time: datetime
    color: QColor = field(default_factory=lambda: QColor(100, 150, 255, 180))
    all_day: bool = False

    @property
    def duration_minutes(self) -> int:
        delta = self.end_time - self.start_time
        return int(delta.total_seconds() / 60)
