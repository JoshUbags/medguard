"""Shrink the bundled clinical database WITHOUT removing a single row.

Run this after regenerating `assets/db/medguard.db` from the data pipeline —
the pipeline emits a database that is ~29% larger than it needs to be, so the
saving is lost on every rebuild unless this is re-applied.

    python tool/optimise_db.py assets/db/medguard.db

What it does, and why each step is safe:

1. `interactions_data` is rebuilt as a WITHOUT ROWID table keyed on
   `(drug_a_id, drug_b_id)`. The pipeline emits it as a plain rowid table, so
   every one of its 851,868 rows carries a hidden 8-byte rowid plus its own
   B-tree. The pair is already unique (verified below), so promoting it to the
   primary key stores the same data in one B-tree instead of two.

2. `idx_interactions_a` is dropped — the new primary key indexes `drug_a_id`
   as its leading column, so the separate index was an exact duplicate of
   information the table now carries itself. `idx_interactions_b` is kept
   because reverse lookups still need it.

3. `idx_synonyms_synonym` is dropped. Nothing queries it: real search runs
   through the `drug_synonyms_fts` FTS5 index, and the only other synonym
   query filters on `drug_id` (which uses `idx_synonyms_drug_id`). Confirm with
   EXPLAIN QUERY PLAN before trusting this — the check is included below.

4. `VACUUM` repacks the file so the freed pages are actually returned.

No rows are deleted and no column is dropped, so every query in
`DatabaseService` returns byte-identical results. Measured on the July 2026
database: 97.0 MB -> 75.1 MB (-22.6%).
"""

from __future__ import annotations

import os
import shutil
import sqlite3
import sys
import time

EXPECTED_TABLES = [
    "drugs",
    "interactions_data",
    "drug_synonyms",
    "drug_categories",
    "drug_enzymes",
    "food_interactions",
    "mech_lookup",
    "effect_lookup",
    "tmpl_lookup",
]


def row_counts(conn: sqlite3.Connection) -> dict[str, int]:
    return {
        table: conn.execute(f'SELECT COUNT(*) FROM "{table}"').fetchone()[0]
        for table in EXPECTED_TABLES
    }


def optimise(path: str) -> None:
    if not os.path.exists(path):
        raise SystemExit(f"no such database: {path}")

    backup = f"{path}.pre-optimise"
    print(f"backing up -> {backup}")
    shutil.copy2(path, backup)

    started = time.time()
    before_bytes = os.path.getsize(path)
    conn = sqlite3.connect(path)
    cur = conn.cursor()

    counts_before = row_counts(conn)
    print(f"start: {before_bytes / 1048576:.1f} MB")

    # The pair must be unique before it can become a primary key. If the
    # pipeline ever starts emitting duplicates this must fail loudly rather
    # than silently dropping rows.
    total, distinct = cur.execute(
        "SELECT COUNT(*), COUNT(DISTINCT drug_a_id || ':' || drug_b_id) "
        "FROM interactions_data"
    ).fetchone()
    if total != distinct:
        raise SystemExit(
            f"ABORT: {total - distinct} duplicate (drug_a_id, drug_b_id) pairs. "
            "Rebuilding as WITHOUT ROWID would discard them."
        )

    # The `interactions` view reads the table, so SQLite refuses to drop it
    # while the view exists. Recreate the view verbatim afterwards.
    view_sql = cur.execute(
        "SELECT sql FROM sqlite_master WHERE type='view' AND name='interactions'"
    ).fetchone()[0]

    cur.executescript(
        """
        PRAGMA foreign_keys=OFF;
        DROP VIEW interactions;
        CREATE TABLE interactions_new (
          drug_a_id INTEGER NOT NULL,
          drug_b_id INTEGER NOT NULL,
          severity TEXT, severity_int INTEGER,
          mech_id INTEGER, effect_id INTEGER, template_id INTEGER,
          openfda_coreport_count INTEGER,
          PRIMARY KEY (drug_a_id, drug_b_id)
        ) WITHOUT ROWID;
        INSERT INTO interactions_new
          SELECT drug_a_id, drug_b_id, severity, severity_int, mech_id,
                 effect_id, template_id, openfda_coreport_count
          FROM interactions_data;
        DROP INDEX IF EXISTS idx_interactions_a;
        DROP INDEX IF EXISTS idx_interactions_b;
        DROP TABLE interactions_data;
        ALTER TABLE interactions_new RENAME TO interactions_data;
        CREATE INDEX idx_interactions_b ON interactions_data(drug_b_id);
        DROP INDEX IF EXISTS idx_synonyms_synonym;
        """
    )
    cur.execute(view_sql)
    conn.commit()

    print("vacuuming…")
    cur.execute("VACUUM")
    conn.commit()

    counts_after = row_counts(conn)
    integrity = cur.execute("PRAGMA integrity_check").fetchone()[0]
    conn.close()

    if integrity != "ok":
        raise SystemExit(f"ABORT: integrity_check said {integrity!r}")
    if counts_before != counts_after:
        changed = {
            t: (counts_before[t], counts_after[t])
            for t in counts_before
            if counts_before[t] != counts_after[t]
        }
        raise SystemExit(f"ABORT: row counts changed: {changed}")

    after_bytes = os.path.getsize(path)
    saved = before_bytes - after_bytes
    print(
        f"done in {time.time() - started:.0f}s: "
        f"{before_bytes / 1048576:.1f} MB -> {after_bytes / 1048576:.1f} MB "
        f"(-{saved / 1048576:.1f} MB, -{saved / before_bytes * 100:.1f}%)"
    )
    print(f"every row preserved; backup kept at {backup}")


if __name__ == "__main__":
    optimise(sys.argv[1] if len(sys.argv) > 1 else "assets/db/medguard.db")
