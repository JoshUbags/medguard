"""Append-only, hash-chained audit log.

Each event stores the SHA-256 hash of its own canonical contents plus the
hash of the previous event, forming a tamper-evident chain: editing or
deleting any event breaks every hash after it, which ``verify_chain`` detects.
The events live in their own SQLite file (separate from application data) and
the service exposes no UPDATE or DELETE — only INSERT and read — so the app
cannot doctor its own record.

This is the prototype-scale implementation of the production audit design
documented in docs/production-architecture.md (SOC 2 CC6.1 / CC7.2 / CC8.1).
"""

from __future__ import annotations

import hashlib
import json
import sqlite3
import threading
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

_GENESIS = "0" * 64


class AuditLog:
    """Thread-safe writer + verifier for the append-only audit store."""

    def __init__(self, db_path: str | Path) -> None:
        self._db_path = Path(db_path)
        self._lock = threading.Lock()
        self._local = threading.local()
        self._ensure_schema()

    def _conn(self) -> sqlite3.Connection:
        conn = getattr(self._local, "conn", None)
        if conn is None:
            self._db_path.parent.mkdir(parents=True, exist_ok=True)
            conn = sqlite3.connect(self._db_path, check_same_thread=False)
            conn.row_factory = sqlite3.Row
            self._local.conn = conn
        return conn

    def _ensure_schema(self) -> None:
        self._conn().execute(
            """
            CREATE TABLE IF NOT EXISTS audit_events (
                seq         INTEGER PRIMARY KEY AUTOINCREMENT,
                event_id    TEXT    NOT NULL,
                occurred_at TEXT    NOT NULL,
                actor_id    TEXT    NOT NULL,
                action      TEXT    NOT NULL,
                resource_type TEXT  NOT NULL,
                resource_id TEXT    NOT NULL,
                outcome     TEXT    NOT NULL,
                source_ip   TEXT,
                prev_hash   TEXT    NOT NULL,
                event_hash  TEXT    NOT NULL
            )
            """
        )
        self._conn().commit()

    @staticmethod
    def _hash(prev_hash: str, payload: dict[str, Any]) -> str:
        canonical = json.dumps(payload, sort_keys=True, separators=(",", ":"))
        return hashlib.sha256((prev_hash + canonical).encode("utf-8")).hexdigest()

    def record(
        self,
        *,
        actor_id: str,
        action: str,
        resource_type: str,
        resource_id: str,
        outcome: str,
        source_ip: str | None = None,
    ) -> str:
        """Append one event and return its hash. Logs successes and failures
        alike — auditors flag missing denial events."""
        with self._lock:
            conn = self._conn()
            row = conn.execute(
                "SELECT event_hash FROM audit_events ORDER BY seq DESC LIMIT 1"
            ).fetchone()
            prev_hash = row["event_hash"] if row else _GENESIS
            payload = {
                "event_id": str(uuid.uuid4()),
                "occurred_at": datetime.now(timezone.utc).isoformat(),
                "actor_id": actor_id,
                "action": action,
                "resource_type": resource_type,
                "resource_id": resource_id,
                "outcome": outcome,
                "source_ip": source_ip,
            }
            event_hash = self._hash(prev_hash, payload)
            conn.execute(
                """
                INSERT INTO audit_events (
                    event_id, occurred_at, actor_id, action, resource_type,
                    resource_id, outcome, source_ip, prev_hash, event_hash
                ) VALUES (?,?,?,?,?,?,?,?,?,?)
                """,
                (
                    payload["event_id"],
                    payload["occurred_at"],
                    actor_id,
                    action,
                    resource_type,
                    resource_id,
                    outcome,
                    source_ip,
                    prev_hash,
                    event_hash,
                ),
            )
            conn.commit()
            return event_hash

    def verify_chain(self) -> bool:
        """Recompute every hash in order; return False if the chain is broken
        (i.e. an event was altered or removed)."""
        prev_hash = _GENESIS
        for row in self._conn().execute(
            "SELECT * FROM audit_events ORDER BY seq ASC"
        ):
            payload = {
                "event_id": row["event_id"],
                "occurred_at": row["occurred_at"],
                "actor_id": row["actor_id"],
                "action": row["action"],
                "resource_type": row["resource_type"],
                "resource_id": row["resource_id"],
                "outcome": row["outcome"],
                "source_ip": row["source_ip"],
            }
            if row["prev_hash"] != prev_hash:
                return False
            if row["event_hash"] != self._hash(prev_hash, payload):
                return False
            prev_hash = row["event_hash"]
        return True

    def count(self) -> int:
        return int(
            self._conn().execute("SELECT COUNT(*) FROM audit_events").fetchone()[0]
        )
