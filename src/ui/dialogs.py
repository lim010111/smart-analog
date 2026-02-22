import json

from PySide6.QtWidgets import (
    QDialog,
    QVBoxLayout,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QPushButton,
    QMessageBox,
    QScrollArea,
    QWidget,
    QTextEdit,
    QFrame,
)
from src.services.providers.apple_provider import AppleCalendarProvider


class AppleLoginDialog(QDialog):
    def __init__(self, provider: AppleCalendarProvider, parent=None):
        super().__init__(parent)
        self.provider = provider
        self.setWindowTitle("Apple Calendar Login")
        self.setFixedSize(400, 220)
        self.setStyleSheet("""
            QDialog { background-color: #2b2b2b; }
            QLabel { color: #ccc; font-size: 12px; }
            QLineEdit {
                background-color: #3a3a3a; color: white; border: 1px solid #555;
                border-radius: 4px; padding: 8px; font-size: 12px;
            }
            QLineEdit:focus { border-color: #0a84ff; }
            QPushButton {
                background-color: #0a84ff; color: white; border: none;
                border-radius: 4px; padding: 8px 20px; font-size: 12px; font-weight: bold;
            }
            QPushButton:hover { background-color: #0070e0; }
            QPushButton:pressed { background-color: #005bb5; }
            QPushButton#cancelBtn {
                background-color: #555; color: #ccc;
            }
            QPushButton#cancelBtn:hover { background-color: #666; }
        """)

        layout = QVBoxLayout(self)
        layout.setSpacing(12)
        layout.setContentsMargins(24, 20, 24, 20)

        title = QLabel("Sign in with Apple ID")
        title.setStyleSheet("font-size: 16px; font-weight: bold; color: white;")
        layout.addWidget(title)

        hint = QLabel("Use an app-specific password from appleid.apple.com")
        hint.setStyleSheet("font-size: 10px; color: #888;")
        hint.setWordWrap(True)
        layout.addWidget(hint)

        self.apple_id_input = QLineEdit()
        self.apple_id_input.setPlaceholderText("Apple ID (email)")
        layout.addWidget(self.apple_id_input)

        self.password_input = QLineEdit()
        self.password_input.setPlaceholderText("App-Specific Password")
        self.password_input.setEchoMode(QLineEdit.EchoMode.Password)
        layout.addWidget(self.password_input)

        btn_layout = QHBoxLayout()
        btn_layout.setSpacing(10)

        cancel_btn = QPushButton("Cancel")
        cancel_btn.setObjectName("cancelBtn")
        cancel_btn.clicked.connect(self.reject)
        btn_layout.addWidget(cancel_btn)

        login_btn = QPushButton("Sign In")
        login_btn.clicked.connect(self._attempt_login)
        btn_layout.addWidget(login_btn)

        layout.addLayout(btn_layout)

    def _attempt_login(self):
        apple_id = self.apple_id_input.text().strip()
        app_password = self.password_input.text().strip()

        if not apple_id or not app_password:
            QMessageBox.warning(
                self,
                "Input Required",
                "Please enter both Apple ID and App-Specific Password.",
            )
            return

        try:
            self.provider.set_credentials(apple_id, app_password)
            self.provider.authenticate()
            self.accept()
        except Exception as e:
            QMessageBox.critical(
                self, "Login Failed", f"Could not connect to iCloud:\n{e}"
            )


_DARK_DIALOG_STYLE = """
    QDialog { background-color: #2b2b2b; }
    QLabel { color: #c7c7c7; font-size: 11px; }
    QLineEdit {
        background-color: #353535; color: white; border: 1px solid #4a4a4a;
        border-radius: 4px; padding: 5px 8px; font-size: 11px;
    }
    QLineEdit:focus { border-color: #0a84ff; }
    QPushButton {
        background-color: #0a84ff; color: white; border: none;
        border-radius: 4px; padding: 6px 14px; font-size: 11px; font-weight: 600;
    }
    QPushButton:hover { background-color: #0070e0; }
    QPushButton:pressed { background-color: #005bb5; }
    QPushButton#cancelBtn { background-color: #555; color: #ccc; }
    QPushButton#cancelBtn:hover { background-color: #666; }
    QPushButton#colorBtn {
        border: 1px solid #5b5b5b; border-radius: 2px;
        min-width: 14px; max-width: 14px; min-height: 14px; max-height: 14px;
        padding: 0;
    }
    QPushButton#colorBtn:hover { border-color: #555; }
    QScrollArea { border: none; background-color: transparent; }
"""

FALLBACK_ROW_COLORS = [
    "#f45b69",
    "#4f83ff",
    "#3cb371",
    "#f2a93b",
    "#6f59d9",
    "#38b7a6",
    "#ff7a59",
    "#5c7cfa",
]

ROW_LABEL_EXAMPLES = [
    "중요한 일",
    "데이트",
    "친구",
    "게임",
    "공부",
    "독서",
    "운동",
    "업무",
    "이동",
    "가족",
    "취미",
]


class CustomColorSchemaDialog(QDialog):
    def __init__(self, ai_service, allowed_colors: list[str], parent=None):
        super().__init__(parent)
        self.ai_service = ai_service
        self._rows: list[dict] = []
        self._allowed_colors = [
            color.lower() for color in allowed_colors if str(color).strip()
        ]
        if not self._allowed_colors:
            self._allowed_colors = list(FALLBACK_ROW_COLORS)

        self.setWindowTitle("Color Schema")
        self.setMinimumSize(420, 380)
        self.setStyleSheet(_DARK_DIALOG_STYLE)

        layout = QVBoxLayout(self)
        layout.setSpacing(8)
        layout.setContentsMargins(16, 14, 16, 14)

        title = QLabel("Custom Color Schema")
        title.setStyleSheet("font-size: 14px; font-weight: 600; color: white;")
        layout.addWidget(title)

        hint = QLabel("Set labels for each calendar-supported color.")
        hint.setStyleSheet("font-size: 10px; color: #8f8f8f;")
        hint.setWordWrap(True)
        layout.addWidget(hint)

        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        self._rows_container = QWidget()
        self._rows_layout = QVBoxLayout(self._rows_container)
        self._rows_layout.setSpacing(5)
        self._rows_layout.setContentsMargins(0, 0, 0, 0)
        self._rows_layout.addStretch()
        scroll.setWidget(self._rows_container)
        layout.addWidget(scroll, 1)

        btn_layout = QHBoxLayout()
        btn_layout.setSpacing(8)

        cancel_btn = QPushButton("Cancel")
        cancel_btn.setObjectName("cancelBtn")
        cancel_btn.clicked.connect(self.reject)
        btn_layout.addWidget(cancel_btn)

        save_btn = QPushButton("Save")
        save_btn.clicked.connect(self._save_schema)
        btn_layout.addWidget(save_btn)

        layout.addLayout(btn_layout)

        self._load_existing_rules()

    def _load_existing_rules(self):
        labels_by_color: dict[str, str] = {}
        schema = self.ai_service.custom_schema
        for rule in schema.rules:
            labels_by_color[str(rule.color_hex).strip().lower()] = rule.label

        for idx, color_hex in enumerate(self._allowed_colors):
            placeholder = (
                ROW_LABEL_EXAMPLES[idx] if idx < len(ROW_LABEL_EXAMPLES) else "..."
            )
            self._add_row(color_hex, labels_by_color.get(color_hex, ""), placeholder)

    def _add_row(self, color_hex: str, label: str, placeholder: str):
        row_widget = QWidget()
        row_widget.setFixedHeight(24)
        row_layout = QHBoxLayout(row_widget)
        row_layout.setContentsMargins(0, 0, 0, 0)
        row_layout.setSpacing(7)

        color_btn = QPushButton()
        color_btn.setObjectName("colorBtn")
        color_btn.setStyleSheet(f"background-color: {color_hex};")
        color_btn.setProperty("color_hex", color_hex)
        color_btn.setEnabled(False)
        row_layout.addWidget(color_btn)

        label_input = QLineEdit()
        label_input.setPlaceholderText(placeholder)
        label_input.setText(label)
        label_input.setFixedHeight(24)
        row_layout.addWidget(label_input, 1)

        row_data = {
            "widget": row_widget,
            "color_btn": color_btn,
            "label_input": label_input,
        }
        self._rows.append(row_data)

        insert_pos = self._rows_layout.count() - 1
        self._rows_layout.insertWidget(insert_pos, row_widget)

    def _collect_rules(self):
        from src.services.ai.color_schema import ColorRule

        rules = []
        for row in self._rows:
            label = row["label_input"].text().strip()
            if not label:
                continue
            color_hex = row["color_btn"].property("color_hex")
            if str(color_hex).lower() not in self._allowed_colors:
                continue
            rules.append(ColorRule(color_hex=color_hex, label=label))
        return rules

    def _save_schema(self):
        rules = self._collect_rules()
        schema = self.ai_service.custom_schema
        schema.rules = rules
        schema.save()
        self.ai_service.reload_schema()
        self.accept()


class TodayBriefingDialog(QDialog):
    def __init__(self, briefing_text: str, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Today Briefing")
        self.setMinimumSize(440, 280)
        self.setStyleSheet(
            _DARK_DIALOG_STYLE
            + """
            QFrame#briefingCard {
                background-color: #1f2128;
                border: 1px solid #3f4556;
                border-radius: 10px;
            }
            QLabel#briefingTitle {
                color: #f0f2f7;
                font-size: 16px;
                font-weight: 700;
            }
            QLabel#briefingHint {
                color: #9ca3b8;
                font-size: 11px;
            }
            QTextEdit#briefingBody {
                background-color: #262a35;
                color: #e9edf8;
                border: 1px solid #3f4556;
                border-radius: 8px;
                padding: 10px;
                font-size: 13px;
                line-height: 1.45;
            }
            QPushButton#closeBtn {
                background-color: #4f83ff;
                color: white;
                font-weight: 700;
            }
            QPushButton#closeBtn:hover {
                background-color: #3f74f5;
            }
            """
        )

        root = QVBoxLayout(self)
        root.setContentsMargins(16, 14, 16, 14)
        root.setSpacing(10)

        card = QFrame()
        card.setObjectName("briefingCard")
        card_layout = QVBoxLayout(card)
        card_layout.setContentsMargins(14, 12, 14, 12)
        card_layout.setSpacing(8)

        title = QLabel("오늘의 브리핑")
        title.setObjectName("briefingTitle")
        card_layout.addWidget(title)

        hint = QLabel("현재 시각 이후 일정을 바탕으로 생성된 요약")
        hint.setObjectName("briefingHint")
        card_layout.addWidget(hint)

        body = QTextEdit()
        body.setObjectName("briefingBody")
        body.setReadOnly(True)
        body.setText(str(briefing_text).strip() or "표시할 브리핑이 없습니다.")
        card_layout.addWidget(body, 1)

        root.addWidget(card, 1)

        button_row = QHBoxLayout()
        button_row.addStretch(1)

        close_btn = QPushButton("닫기")
        close_btn.setObjectName("closeBtn")
        close_btn.clicked.connect(self.accept)
        button_row.addWidget(close_btn)

        root.addLayout(button_row)


class NaturalInputPromptDialog(QDialog):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("AI Natural Input")
        self.setFixedSize(460, 180)
        self.setStyleSheet(_DARK_DIALOG_STYLE)

        layout = QVBoxLayout(self)
        layout.setSpacing(10)
        layout.setContentsMargins(16, 14, 16, 14)

        title = QLabel("Parse Natural Language")
        title.setStyleSheet("font-size: 14px; font-weight: 600; color: white;")
        layout.addWidget(title)

        hint = QLabel(
            "Enter one sentence describing a schedule. "
            "Result is preview-only in phase 1."
        )
        hint.setStyleSheet("font-size: 10px; color: #8f8f8f;")
        hint.setWordWrap(True)
        layout.addWidget(hint)

        self._text_input = QLineEdit()
        self._text_input.setPlaceholderText(
            "예: 내일 오후 3시에 디자인 리뷰 미팅 잡아줘"
        )
        self._text_input.returnPressed.connect(self.accept)
        layout.addWidget(self._text_input)

        btn_layout = QHBoxLayout()
        btn_layout.setSpacing(8)

        cancel_btn = QPushButton("Cancel")
        cancel_btn.setObjectName("cancelBtn")
        cancel_btn.clicked.connect(self.reject)
        btn_layout.addWidget(cancel_btn)

        parse_btn = QPushButton("Parse")
        parse_btn.clicked.connect(self.accept)
        btn_layout.addWidget(parse_btn)

        layout.addLayout(btn_layout)

    def input_text(self) -> str:
        return self._text_input.text().strip()


class NaturalInputPreviewDialog(QDialog):
    def __init__(
        self,
        source_text: str,
        result,
        can_create: bool,
        create_block_reason: str = "",
        parent=None,
    ):
        super().__init__(parent)
        self._create_requested = False
        self.setWindowTitle("AI Natural Input Preview")
        self.setMinimumSize(500, 420)
        self.setStyleSheet(_DARK_DIALOG_STYLE)

        layout = QVBoxLayout(self)
        layout.setSpacing(8)
        layout.setContentsMargins(16, 14, 16, 14)

        title = QLabel("Parsed Schedule Draft")
        title.setStyleSheet("font-size: 14px; font-weight: 600; color: white;")
        layout.addWidget(title)

        source_label = QLabel(f"Input: {source_text}")
        source_label.setStyleSheet("font-size: 11px; color: #b0b0b0;")
        source_label.setWordWrap(True)
        layout.addWidget(source_label)

        details = [
            ("Intent", str(result.intent)),
            ("Title", str(result.title) or "-"),
            ("Start", self._format_dt(result.start_time)),
            ("End", self._format_dt(result.end_time)),
            ("All Day", "Yes" if result.all_day else "No"),
            ("Confidence", f"{result.confidence:.2f}"),
        ]
        for key, value in details:
            row = QLabel(f"{key}: {value}")
            row.setStyleSheet("font-size: 11px; color: #d5d5d5;")
            row.setWordWrap(True)
            layout.addWidget(row)

        note_text = str(result.note or "")
        if note_text:
            note = QLabel(f"Note: {note_text}")
            note.setStyleSheet("font-size: 10px; color: #f0bd60;")
            note.setWordWrap(True)
            layout.addWidget(note)

        raw_label = QLabel("Raw JSON")
        raw_label.setStyleSheet("font-size: 10px; color: #8f8f8f;")
        layout.addWidget(raw_label)

        raw_view = QTextEdit()
        raw_view.setReadOnly(True)
        raw_view.setMinimumHeight(160)
        raw_view.setPlainText(json.dumps(result.raw, ensure_ascii=False, indent=2))
        layout.addWidget(raw_view, 1)

        if create_block_reason:
            reason = QLabel(f"Create blocked: {create_block_reason}")
            reason.setStyleSheet("font-size: 10px; color: #f0bd60;")
            reason.setWordWrap(True)
            layout.addWidget(reason)

        btn_layout = QHBoxLayout()
        btn_layout.setSpacing(8)

        close_btn = QPushButton("Close")
        close_btn.setObjectName("cancelBtn")
        close_btn.clicked.connect(self.reject)
        btn_layout.addWidget(close_btn)

        create_btn = QPushButton("Create Event")
        create_btn.setEnabled(can_create)
        create_btn.clicked.connect(self._accept_create)
        btn_layout.addWidget(create_btn)

        layout.addLayout(btn_layout)

    @property
    def create_requested(self) -> bool:
        return self._create_requested

    def _accept_create(self) -> None:
        self._create_requested = True
        self.accept()

    @staticmethod
    def _format_dt(value) -> str:
        if value is None:
            return "-"
        try:
            return value.strftime("%Y-%m-%d %H:%M (%Z)")
        except Exception:
            return str(value)
