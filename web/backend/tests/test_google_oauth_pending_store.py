from __future__ import annotations

import tempfile
import time
import unittest
from importlib import import_module
from pathlib import Path
from typing import Protocol, cast


class PendingStoreProtocol(Protocol):
    db_path: Path

    def initialize(self) -> None: ...

    def put(
        self,
        *,
        state: str,
        redirect_uri: str,
        mobile_callback: str | None,
        created_at: float | None = None,
    ) -> None: ...

    def pop(self, state: str): ...

    def cleanup_expired(self) -> int: ...


class GoogleOAuthPendingStoreTest(unittest.TestCase):
    _temp_dir: tempfile.TemporaryDirectory[str] | None = None
    store: PendingStoreProtocol | None = None

    def _store(self) -> PendingStoreProtocol:
        if self.store is None:
            self.fail("Store was not initialized.")
        return self.store

    def setUp(self) -> None:
        self._temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self._temp_dir.cleanup)
        db_path = Path(self._temp_dir.name) / "oauth_pending.sqlite3"
        GoogleOAuthPendingStore = getattr(
            import_module("web.backend.app.google_oauth_pending_store"),
            "GoogleOAuthPendingStore",
        )
        self.store = cast(
            PendingStoreProtocol,
            GoogleOAuthPendingStore(db_path=db_path, ttl_seconds=60),
        )
        self._store().initialize()

    def test_put_and_pop_roundtrip(self) -> None:
        self._store().put(
            state="state-1",
            redirect_uri="http://localhost:8000/callback",
            mobile_callback="smartanalog://auth/google",
        )

        record = self._store().pop("state-1")
        if record is None:
            self.fail("Expected pending record to exist.")
        checked = cast(dict[str, object], record)
        self.assertEqual(checked["redirect_uri"], "http://localhost:8000/callback")
        self.assertEqual(checked["mobile_callback"], "smartanalog://auth/google")
        self.assertIsInstance(checked["created_at"], float)

    def test_state_is_single_use(self) -> None:
        self._store().put(
            state="state-2",
            redirect_uri="http://localhost:8000/callback",
            mobile_callback=None,
        )

        self.assertIsNotNone(self._store().pop("state-2"))
        self.assertIsNone(self._store().pop("state-2"))

    def test_expired_state_returns_none(self) -> None:
        GoogleOAuthPendingStore = getattr(
            import_module("web.backend.app.google_oauth_pending_store"),
            "GoogleOAuthPendingStore",
        )
        short_ttl_store = GoogleOAuthPendingStore(
            db_path=self._store().db_path,
            ttl_seconds=1,
        )
        short_ttl_store.initialize()
        short_ttl_store.put(
            state="state-3",
            redirect_uri="http://localhost:8000/callback",
            mobile_callback=None,
            created_at=time.time() - 5,
        )

        self.assertIsNone(short_ttl_store.pop("state-3"))

    def test_cleanup_expired_removes_rows(self) -> None:
        GoogleOAuthPendingStore = getattr(
            import_module("web.backend.app.google_oauth_pending_store"),
            "GoogleOAuthPendingStore",
        )
        short_ttl_store = GoogleOAuthPendingStore(
            db_path=self._store().db_path,
            ttl_seconds=1,
        )
        short_ttl_store.initialize()
        short_ttl_store.put(
            state="state-4",
            redirect_uri="http://localhost:8000/callback",
            mobile_callback=None,
            created_at=time.time() - 5,
        )
        short_ttl_store.put(
            state="state-5",
            redirect_uri="http://localhost:8000/callback",
            mobile_callback=None,
            created_at=time.time(),
        )

        _ = short_ttl_store.cleanup_expired()
        self.assertIsNone(short_ttl_store.pop("state-4"))
        self.assertIsNotNone(short_ttl_store.pop("state-5"))
