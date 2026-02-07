from PySide6.QtGui import QColor

# 테마 정의
THEMES = {
    "dark": {
        "face": QColor(30, 30, 30, 160),
        "border": QColor(255, 255, 255, 40),
        "hands": QColor(255, 255, 255, 230),
        "nums": QColor(255, 255, 255, 120),
        "ticks": QColor(255, 255, 255, 150)
    },
    "light": {
        "face": QColor(240, 240, 240, 180),
        "border": QColor(0, 0, 0, 40),
        "hands": QColor(40, 40, 40, 230),
        "nums": QColor(0, 0, 0, 150),
        "ticks": QColor(0, 0, 0, 120)
    }
}
