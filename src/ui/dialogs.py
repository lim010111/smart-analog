from PySide6.QtWidgets import (
    QDialog,
    QVBoxLayout,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QPushButton,
    QMessageBox,
)
from PySide6.QtCore import Qt

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
