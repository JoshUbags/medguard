"""Thin read-only repository over the bundled DrugBank SQLite database.

The endpoints read from the **same** `medguard.db` the mobile app ships with
(passed in via ``MEDGUARD_DB_PATH``), so feature engineering on the server is
bit-identical to feature engineering in the Flutter app.
"""

from __future__ import annotations

import sqlite3
import threading
from pathlib import Path
from typing import Any


class SqliteRepo:
    """Thread-safe SQLite reader with a per-thread connection pool."""

    def __init__(self, db_path: str | Path) -> None:
        self._db_path = Path(db_path)
        self._local = threading.local()

    @property
    def db_path(self) -> Path:
        return self._db_path

    def _conn(self) -> sqlite3.Connection:
        conn = getattr(self._local, "conn", None)
        if conn is None:
            if not self._db_path.exists():
                raise FileNotFoundError(
                    f"Bundled DB not found at {self._db_path}"
                )
            conn = sqlite3.connect(
                self._db_path,
                check_same_thread=False,
                uri=False,
            )
            conn.row_factory = sqlite3.Row
            self._local.conn = conn
        return conn

    # ── Drug lookups ────────────────────────────────────────────────────────

    def get_drug_by_drugbank_id(self, drugbank_id: str) -> dict[str, Any] | None:
        row = self._conn().execute(
            "SELECT id, drugbank_id, name, atc_code, all_atc_codes, drug_type, half_life "
            "FROM drugs WHERE drugbank_id = ?",
            (drugbank_id,),
        ).fetchone()
        return dict(row) if row else None

    def categories_for_drug(self, drug_id: int) -> list[str]:
        rows = self._conn().execute(
            "SELECT category FROM drug_categories WHERE drug_id = ?",
            (drug_id,),
        ).fetchall()
        return [r["category"] for r in rows if r["category"]]

    def metabolism_for_drug(self, drug_id: int) -> dict[str, set[str]]:
        rows = self._conn().execute(
            "SELECT enzyme_name, actions FROM drug_enzymes "
            "WHERE drug_id = ? AND enzyme_type = 'enzymes'",
            (drug_id,),
        ).fetchall()
        out: dict[str, set[str]] = {}
        for row in rows:
            enzyme = row["enzyme_name"]
            actions_raw = row["actions"] or ""
            actions = {
                t.strip().lower()
                for t in actions_raw.split("|")
                if t.strip()
            }
            out.setdefault(enzyme, set()).update(actions)
        return out

    def coreport_count(self, drug_a_id: int, drug_b_id: int) -> int:
        row = self._conn().execute(
            """
            SELECT openfda_coreport_count FROM interactions
            WHERE (drug_a_id = ? AND drug_b_id = ?)
               OR (drug_a_id = ? AND drug_b_id = ?)
            ORDER BY openfda_coreport_count DESC
            LIMIT 1
            """,
            (drug_a_id, drug_b_id, drug_b_id, drug_a_id),
        ).fetchone()
        return int(row[0]) if row and row[0] is not None else 0

    # ── Metadata + delta endpoints ─────────────────────────────────────────

    def db_metadata(self) -> dict[str, str]:
        try:
            rows = self._conn().execute(
                "SELECT key, value FROM db_metadata"
            ).fetchall()
            return {row["key"]: row["value"] for row in rows}
        except sqlite3.OperationalError:
            # Older bundled DBs predate the db_metadata table.
            return {}

    def severity_breakdown(self) -> dict[str, int]:
        rows = self._conn().execute(
            "SELECT severity, COUNT(*) AS c FROM interactions GROUP BY severity"
        ).fetchall()
        return {row["severity"]: int(row["c"]) for row in rows}
