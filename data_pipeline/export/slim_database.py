"""Shrink the bundled MedGuard reference database without losing information.

The `interactions` table dominates the file: 851k rows whose `description`,
`mechanism`, and `clinical_effect` columns are highly repetitive. The
descriptions reduce to a few hundred templates once the two drug names are
masked (e.g. "The risk or severity of adverse effects can be increased when
{A} is combined with {B}."), and mechanism / clinical_effect each have only a
dozen-odd distinct values.

This script replaces those repeated strings with small integer codes plus
lookup tables, stores the interaction rows in `interactions_data`, and exposes
a VIEW named `interactions` that reconstructs the original columns on the fly
(re-inserting the drug names into the template with REPLACE). The app and
backend query `interactions` exactly as before, so no client code changes.

Usage:
    python data_pipeline/export/slim_database.py <source.db> <dest.db>
"""

from __future__ import annotations

import sqlite3
import sys
import time


def slim(src_path: str, dst_path: str) -> None:
    import os
    import shutil

    if os.path.exists(dst_path):
        os.remove(dst_path)
    shutil.copyfile(src_path, dst_path)

    c = sqlite3.connect(dst_path)
    t0 = time.time()

    # Drop runtime/user tables that don't belong in a read-only reference DB.
    for tbl in ("allergies", "check_logs", "user_medications"):
        c.execute(f"DROP TABLE IF EXISTS {tbl}")

    # 1. Lookup tables for the repeated mechanism / clinical_effect strings.
    c.execute("CREATE TABLE mech_lookup (id INTEGER PRIMARY KEY, text TEXT)")
    c.execute("CREATE TABLE effect_lookup (id INTEGER PRIMARY KEY, text TEXT)")
    c.execute("CREATE TABLE tmpl_lookup (id INTEGER PRIMARY KEY, template TEXT)")

    mech_ids = _intern(c, "mechanism", "mech_lookup")
    effect_ids = _intern(c, "clinical_effect", "effect_lookup")

    # 2. Build the description templates by masking each interaction's two
    #    drug names. Round-trips exactly: mask(name->{A}) then REPLACE({A}->name).
    names = {
        row[0]: row[1]
        for row in c.execute("SELECT id, name FROM drugs")
    }
    tmpl_ids: dict[str, int] = {}
    rows_out: list[tuple] = []
    next_tmpl = 1
    cur = c.execute(
        "SELECT drug_a_id, drug_b_id, severity, severity_int, mechanism, "
        "clinical_effect, description, openfda_coreport_count FROM interactions"
    )
    for a_id, b_id, sev, sev_int, mech, effect, desc, coreport in cur:
        template = desc or ""
        na, nb = names.get(a_id), names.get(b_id)
        # Mask the longer name first to avoid partial-substring clashes.
        for placeholder, name in sorted(
            (("{A}", na), ("{B}", nb)),
            key=lambda p: len(p[1] or ""),
            reverse=True,
        ):
            if name:
                template = template.replace(name, placeholder)
        tid = tmpl_ids.get(template)
        if tid is None:
            tid = next_tmpl
            tmpl_ids[template] = tid
            next_tmpl += 1
        rows_out.append(
            (a_id, b_id, sev, sev_int, mech_ids.get(mech),
             effect_ids.get(effect), tid, coreport)
        )

    c.executemany(
        "INSERT INTO tmpl_lookup (id, template) VALUES (?, ?)",
        [(v, k) for k, v in tmpl_ids.items()],
    )

    # 3. Compact interactions table keyed by codes.
    c.execute("DROP TABLE interactions")
    c.execute(
        """
        CREATE TABLE interactions_data (
            drug_a_id INTEGER, drug_b_id INTEGER,
            severity TEXT, severity_int INTEGER,
            mech_id INTEGER, effect_id INTEGER, template_id INTEGER,
            openfda_coreport_count INTEGER
        )
        """
    )
    c.executemany(
        "INSERT INTO interactions_data VALUES (?,?,?,?,?,?,?,?)", rows_out
    )
    c.execute("CREATE INDEX idx_interactions_a ON interactions_data(drug_a_id)")
    c.execute("CREATE INDEX idx_interactions_b ON interactions_data(drug_b_id)")

    # 4. VIEW that reconstructs the original columns — clients are unchanged.
    c.execute(
        """
        CREATE VIEW interactions AS
        SELECT
            d.drug_a_id, d.drug_b_id, d.severity, d.severity_int,
            m.text AS mechanism, e.text AS clinical_effect,
            REPLACE(REPLACE(t.template, '{A}', da.name), '{B}', dbx.name)
                AS description,
            d.openfda_coreport_count
        FROM interactions_data d
        JOIN drugs da  ON da.id  = d.drug_a_id
        JOIN drugs dbx ON dbx.id = d.drug_b_id
        LEFT JOIN mech_lookup   m ON m.id = d.mech_id
        LEFT JOIN effect_lookup e ON e.id = d.effect_id
        LEFT JOIN tmpl_lookup   t ON t.id = d.template_id
        """
    )

    # 5. Ensure the FTS5 name/synonym search indexes exist and are current.
    #    Older source DBs predate FTS, so create-if-missing then rebuild from the
    #    (unchanged) drugs / drug_synonyms tables. The app uses these for fast
    #    autocomplete and falls back to LIKE when fts5 is unavailable.
    c.executescript(
        """
        CREATE VIRTUAL TABLE IF NOT EXISTS drugs_fts USING fts5(
            name, content='drugs', content_rowid='id',
            tokenize='unicode61 remove_diacritics 2');
        CREATE VIRTUAL TABLE IF NOT EXISTS drug_synonyms_fts USING fts5(
            synonym, content='drug_synonyms', content_rowid='id',
            tokenize='unicode61 remove_diacritics 2');
        """
    )
    c.execute("INSERT INTO drugs_fts(drugs_fts) VALUES('rebuild')")
    c.execute("INSERT INTO drug_synonyms_fts(drug_synonyms_fts) VALUES('rebuild')")

    c.commit()
    c.execute("VACUUM")
    c.commit()
    c.close()

    src_mb = os.path.getsize(src_path) / 1e6
    dst_mb = os.path.getsize(dst_path) / 1e6
    print(f"templates: {len(tmpl_ids)}  rows: {len(rows_out)}")
    print(f"{src_mb:.1f} MB -> {dst_mb:.1f} MB  ({time.time()-t0:.0f}s)")


def _intern(c: sqlite3.Connection, column: str, lookup: str) -> dict:
    ids: dict = {}
    for i, (value,) in enumerate(
        c.execute(f"SELECT DISTINCT {column} FROM interactions"), start=1
    ):
        ids[value] = i
        c.execute(f"INSERT INTO {lookup} (id, text) VALUES (?, ?)", (i, value))
    return ids


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    slim(sys.argv[1], sys.argv[2])
