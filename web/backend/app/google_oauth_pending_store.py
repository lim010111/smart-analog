from __future__ import annotations

import sqlite3
import threading
import time
from pathlib import Path
from typing import TypedDict, cast


class GoogleOAuthPendingRecord(TypedDict):
    redirect_uri: str
    mobile_callback: str | None
    code_verifier: str | None
    created_at: float


class GoogleOAuthPendingStore:
    _db_path: Path
    _ttl_seconds: int
    _lock: threading.RLock

    def __init__(self, db_path: Path, ttl_seconds: int) -> None:
        self._db_path = Path(db_path)
        self._ttl_seconds = max(1, int(ttl_seconds))
        self._lock = threading.RLock()

    @property
    def db_path(self) -> Path:
        return self._db_path

    @property
    def ttl_seconds(self) -> int:
        return self._ttl_seconds

    def initialize(self) -> None:
        self._db_path.parent.mkdir(parents=True, exist_ok=True)
        with self._lock, self._connect() as connection:
            _ = connection.execute("PRAGMA journal_mode=WAL")
            _ = connection.execute(
                """
                CREATE TABLE IF NOT EXISTS google_oauth_pending (
                    state TEXT PRIMARY KEY,
                    redirect_uri TEXT NOT NULL,
                    mobile_callback TEXT,
                    code_verifier TEXT,
                    created_at REAL NOT NULL
                )
                """
            )
            existing_columns = {
                str(row[1])
                for row in connection.execute(
                    "PRAGMA table_info(google_oauth_pending)"
                ).fetchall()
                if len(row) > 1
            }
            if "code_verifier" not in existing_columns:
                _ = connection.execute(
                    "ALTER TABLE google_oauth_pending ADD COLUMN code_verifier TEXT"
                )
            _ = connection.execute(
                """
                CREATE INDEX IF NOT EXISTS idx_google_oauth_pending_created_at
                ON google_oauth_pending(created_at)
                """
            )
            connection.commit()

    def put(
        self,
        *,
        state: str,
        redirect_uri: str,
        mobile_callback: str | None,
        code_verifier: str | None = None,
        created_at: float | None = None,
    ) -> None:
        normalized_state = str(state).strip()
        normalized_redirect_uri = str(redirect_uri).strip()
        if not normalized_state:
            raise ValueError("state is required")
        if not normalized_redirect_uri:
            raise ValueError("redirect_uri is required")

        callback = (
            str(mobile_callback).strip()
            if isinstance(mobile_callback, str) and mobile_callback.strip()
            else None
        )
        verifier = (
            str(code_verifier).strip()
            if isinstance(code_verifier, str) and code_verifier.strip()
            else None
        )
        created = float(created_at if created_at is not None else time.time())

        with self._lock, self._connect() as connection:
            _ = connection.execute(
                """
                INSERT OR REPLACE INTO google_oauth_pending(
                    state,
                    redirect_uri,
                    mobile_callback,
                    code_verifier,
                    created_at
                ) VALUES (?, ?, ?, ?, ?)
                """,
                (
                    normalized_state,
                    normalized_redirect_uri,
                    callback,
                    verifier,
                    created,
                ),
            )
            _ = self._delete_expired(connection, now_ts=created)
            connection.commit()

    def pop(self, state: str) -> GoogleOAuthPendingRecord | None:
        normalized_state = str(state).strip()
        if not normalized_state:
            return None

        now_ts = time.time()
        with self._lock, self._connect() as connection:
            _ = connection.execute("BEGIN IMMEDIATE")
            try:
                cursor = connection.execute(
                    """
                    SELECT redirect_uri, mobile_callback, code_verifier, created_at
                    FROM google_oauth_pending
                    WHERE state = ?
                    """,
                    (normalized_state,),
                )
                row = cast(
                    tuple[str, str | None, str | None, float] | None,
                    cursor.fetchone(),
                )
                if row is None:
                    _ = self._delete_expired(connection, now_ts=now_ts)
                    connection.commit()
                    return None

                _ = connection.execute(
                    "DELETE FROM google_oauth_pending WHERE state = ?",
                    (normalized_state,),
                )
                _ = self._delete_expired(connection, now_ts=now_ts)
                connection.commit()
            except Exception:
                connection.rollback()
                raise

        record = row
        created_at = float(record[3])
        if now_ts - created_at > self._ttl_seconds:
            return None

        mobile_callback = record[1]
        code_verifier = record[2]
        return {
            "redirect_uri": str(record[0]),
            "mobile_callback": str(mobile_callback).strip()
            if isinstance(mobile_callback, str) and mobile_callback.strip()
            else None,
            "code_verifier": str(code_verifier).strip()
            if isinstance(code_verifier, str) and code_verifier.strip()
            else None,
            "created_at": created_at,
        }

    def cleanup_expired(self) -> int:
        now_ts = time.time()
        with self._lock, self._connect() as connection:
            cursor = self._delete_expired(connection, now_ts=now_ts)
            connection.commit()
            return int(cursor.rowcount or 0)

    def _delete_expired(self, connection: sqlite3.Connection, now_ts: float):
        cutoff = float(now_ts) - float(self._ttl_seconds)
        return connection.execute(
            "DELETE FROM google_oauth_pending WHERE created_at < ?",
            (cutoff,),
        )

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(str(self._db_path), timeout=5.0)
        _ = connection.execute("PRAGMA busy_timeout=5000")
        return connection
