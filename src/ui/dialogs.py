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
    QColorDialog,
)
from PySide6.QtCore import Qt
from PySide6.QtGui import QColor

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
        self.password_input.setEchoMode(QLineEdit.Password)
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
    QPushButton#cancelBtn { background-color: #555; color: #ccc; }
    QPushButton#cancelBtn:hover { background-color: #666; }
    QPushButton#addBtn {
        background-color: #3a3a3a; color: #0a84ff; border: 1px dashed #555;
        padding: 6px; font-size: 18px;
    }
    QPushButton#addBtn:hover { background-color: #444; border-color: #0a84ff; }
    QPushButton#removeBtn {
        background-color: transparent; color: #f45b69; border: none;
        font-size: 16px; font-weight: bold; padding: 4px 8px;
    }
    QPushButton#removeBtn:hover { color: #ff7a7a; }
    QPushButton#colorBtn {
        border: 2px solid #555; border-radius: 4px;
        min-width: 36px; max-width: 36px; min-height: 36px; max-height: 36px;
    }
    QPushButton#colorBtn:hover { border-color: #888; }
    QPushButton#generateBtn {
        background-color: #6f59d9; color: white;
    }
    QPushButton#generateBtn:hover { background-color: #5a45c0; }
    QScrollArea { border: none; background-color: transparent; }
"""

DEFAULT_ROW_COLORS = [
    "#f45b69",
    "#4f83ff",
    "#3cb371",
    "#f2a93b",
    "#6f59d9",
    "#38b7a6",
    "#ff7a59",
    "#5c7cfa",
]


class CustomColorSchemaDialog(QDialog):
    def __init__(self, ai_service, parent=None):
        super().__init__(parent)
        self.ai_service = ai_service
        self._rows: list[dict] = []

        self.setWindowTitle("Color Schema")
        self.setMinimumSize(480, 400)
        self.setStyleSheet(_DARK_DIALOG_STYLE)

        layout = QVBoxLayout(self)
        layout.setSpacing(12)
        layout.setContentsMargins(24, 20, 24, 20)

        title = QLabel("Custom Color Schema")
        title.setStyleSheet("font-size: 16px; font-weight: bold; color: white;")
        layout.addWidget(title)

        hint = QLabel(
            "Define color-category rules. Click Generate to create keywords via AI."
        )
        hint.setStyleSheet("font-size: 10px; color: #888;")
        hint.setWordWrap(True)
        layout.addWidget(hint)

        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        self._rows_container = QWidget()
        self._rows_layout = QVBoxLayout(self._rows_container)
        self._rows_layout.setSpacing(8)
        self._rows_layout.setContentsMargins(0, 0, 0, 0)
        self._rows_layout.addStretch()
        scroll.setWidget(self._rows_container)
        layout.addWidget(scroll, 1)

        add_btn = QPushButton("+")
        add_btn.setObjectName("addBtn")
        add_btn.clicked.connect(self._add_empty_row)
        layout.addWidget(add_btn)

        btn_layout = QHBoxLayout()
        btn_layout.setSpacing(10)

        cancel_btn = QPushButton("Cancel")
        cancel_btn.setObjectName("cancelBtn")
        cancel_btn.clicked.connect(self.reject)
        btn_layout.addWidget(cancel_btn)

        generate_btn = QPushButton("Generate Keywords")
        generate_btn.setObjectName("generateBtn")
        generate_btn.clicked.connect(self._generate_keywords)
        btn_layout.addWidget(generate_btn)

        save_btn = QPushButton("Save")
        save_btn.clicked.connect(self._save_schema)
        btn_layout.addWidget(save_btn)

        layout.addLayout(btn_layout)

        self._load_existing_rules()

    def _load_existing_rules(self):
        schema = self.ai_service.custom_schema
        if schema.is_empty:
            self._add_empty_row()
            return

        for rule in schema.rules:
            self._add_row(rule.color_hex, rule.label)

    def _next_color(self) -> str:
        idx = len(self._rows) % len(DEFAULT_ROW_COLORS)
        return DEFAULT_ROW_COLORS[idx]

    def _add_empty_row(self):
        self._add_row(self._next_color(), "")

    def _add_row(self, color_hex: str, label: str):
        row_widget = QWidget()
        row_layout = QHBoxLayout(row_widget)
        row_layout.setContentsMargins(0, 0, 0, 0)
        row_layout.setSpacing(8)

        color_btn = QPushButton()
        color_btn.setObjectName("colorBtn")
        color_btn.setStyleSheet(f"background-color: {color_hex};")
        color_btn.setProperty("color_hex", color_hex)
        color_btn.clicked.connect(lambda: self._pick_color(color_btn))
        row_layout.addWidget(color_btn)

        label_input = QLineEdit()
        label_input.setPlaceholderText("Category (e.g. 중요한 회의, 개발 작업)")
        label_input.setText(label)
        row_layout.addWidget(label_input, 1)

        remove_btn = QPushButton("✕")
        remove_btn.setObjectName("removeBtn")
        remove_btn.clicked.connect(lambda: self._remove_row(row_widget))
        row_layout.addWidget(remove_btn)

        row_data = {
            "widget": row_widget,
            "color_btn": color_btn,
            "label_input": label_input,
        }
        self._rows.append(row_data)

        insert_pos = self._rows_layout.count() - 1
        self._rows_layout.insertWidget(insert_pos, row_widget)

    def _pick_color(self, btn: QPushButton):
        current = QColor(btn.property("color_hex"))
        color = QColorDialog.getColor(current, self, "Select Color")
        if color.isValid():
            hex_val = color.name()
            btn.setStyleSheet(f"background-color: {hex_val};")
            btn.setProperty("color_hex", hex_val)

    def _remove_row(self, row_widget: QWidget):
        self._rows = [r for r in self._rows if r["widget"] is not row_widget]
        self._rows_layout.removeWidget(row_widget)
        row_widget.deleteLater()

    def _collect_rules(self):
        from src.services.ai.color_schema import ColorRule

        rules = []
        for row in self._rows:
            label = row["label_input"].text().strip()
            if not label:
                continue
            color_hex = row["color_btn"].property("color_hex")
            rules.append(ColorRule(color_hex=color_hex, label=label))
        return rules

    def _generate_keywords(self):
        rules = self._collect_rules()
        if not rules:
            QMessageBox.warning(
                self, "No Rules", "Add at least one category label before generating."
            )
            return

        if not self.ai_service.api_key:
            QMessageBox.warning(
                self,
                "API Key Required",
                "Set OPENAI_API_KEY in .env to use AI keyword generation.",
            )
            return

        self.setCursor(Qt.WaitCursor)
        try:
            updated = self.ai_service.generate_keywords_for_rules(rules)
            schema = self.ai_service.custom_schema
            schema.rules = updated
            schema.save()
            self.ai_service.reload_schema()
        finally:
            self.unsetCursor()

        keyword_summary = "\n".join(
            f"• {r.label}: {', '.join(r.keywords[:5])}{'...' if len(r.keywords) > 5 else ''}"
            for r in updated
            if r.keywords
        )

        if keyword_summary:
            QMessageBox.information(
                self,
                "Keywords Generated",
                f"Generated keywords:\n\n{keyword_summary}",
            )
            self.accept()
        else:
            QMessageBox.warning(
                self,
                "Generation Failed",
                "Could not generate keywords. Check your API key and try again.",
            )

    def _save_schema(self):
        rules = self._collect_rules()
        schema = self.ai_service.custom_schema
        schema.rules = rules
        schema.save()
        self.ai_service.reload_schema()
        self.accept()
