"""Rebuild the training inputs from the bundled clinical database.

The original corpus came from the full DrugBank XML, which is licensed, is not
in this repository, and was lost locally. This script regenerates everything
``build_features`` reads from ``mobile/assets/db/medguard.db`` instead — the
very data the app ships — so the model can be retrained with no licensed
download.

Two honest differences from the original run, both worth stating whenever the
resulting metrics are quoted:

* The shipped database is the **slimmed** set: 851,868 pairs against the ~1.45M
  the first model was trained on. Fewer, and not a random sample.
* Each pair is stored once, in an arbitrary direction (measured: no row's
  mirror is present). Pairs are canonicalised to `(min, max)` here so the
  ordering is consistent and a duplicate could never straddle the split.

    python -m ml_pipeline.src.features.export_from_bundled_db
"""

from __future__ import annotations

import os
import sqlite3
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[3]
DB = Path(
    os.environ.get(
        "MEDGUARD_DB_PATH", str(ROOT / "mobile" / "assets" / "db" / "medguard.db")
    )
)
OUT = ROOT / "ml_pipeline" / "data" / "processed"
RANDOM_STATE = 42


def main() -> None:
    if not DB.exists():
        raise SystemExit(
            f"Bundled database not found at {DB}. Build it with data_pipeline "
            "(see data_pipeline/README.md)."
        )
    OUT.mkdir(parents=True, exist_ok=True)

    con = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    try:
        drugs = pd.read_sql_query(
            """
            SELECT id, drugbank_id, name, generic_name, drug_type, atc_code,
                   all_atc_codes, half_life, groups
            FROM drugs
            """,
            con,
        )
        enzymes = pd.read_sql_query(
            """
            SELECT d.drugbank_id, e.enzyme_type, e.enzyme_name, e.gene_name,
                   e.actions
            FROM drug_enzymes e JOIN drugs d ON d.id = e.drug_id
            """,
            con,
        )
        categories = pd.read_sql_query(
            """
            SELECT d.drugbank_id, c.category, c.mesh_id
            FROM drug_categories c JOIN drugs d ON d.id = c.drug_id
            """,
            con,
        )
        pairs = pd.read_sql_query(
            """
            SELECT da.drugbank_id AS drug_a_id,
                   dbx.drugbank_id AS drug_b_id,
                   i.severity_int
            FROM interactions_data i
            JOIN drugs da  ON da.id  = i.drug_a_id
            JOIN drugs dbx ON dbx.id = i.drug_b_id
            """,
            con,
        )
    finally:
        con.close()

    drugs.to_csv(OUT / "drugs_normalized.csv", index=False)
    enzymes.to_csv(OUT / "enzymes_raw.csv", index=False)
    categories.to_csv(OUT / "categories_raw.csv", index=False)

    # Collapse the two stored directions onto one canonical ordering.
    lo = np.minimum(pairs["drug_a_id"], pairs["drug_b_id"])
    hi = np.maximum(pairs["drug_a_id"], pairs["drug_b_id"])
    pairs["drug_a_id"], pairs["drug_b_id"] = lo, hi
    pairs["severity_int"] = pairs["severity_int"].fillna(1).astype(int)
    # Keep the most severe grade if the two directions ever disagree.
    pairs = (
        pairs.sort_values("severity_int", ascending=False)
        .drop_duplicates(subset=["drug_a_id", "drug_b_id"], keep="first")
        .reset_index(drop=True)
    )

    # A stratified 70/15/15 split. ``build_features`` re-splits from the
    # concatenation of these three files, so this only fixes their shape.
    rng = np.random.RandomState(RANDOM_STATE)
    order = np.arange(len(pairs))
    sev = pairs["severity_int"].to_numpy()
    parts: dict[str, list[np.ndarray]] = {"train": [], "val": [], "test": []}
    for label in np.unique(sev):
        group = order[sev == label].copy()
        rng.shuffle(group)
        a, b = int(len(group) * 0.70), int(len(group) * 0.85)
        parts["train"].append(group[:a])
        parts["val"].append(group[a:b])
        parts["test"].append(group[b:])

    for name, chunks in parts.items():
        frame = pairs.iloc[np.concatenate(chunks)]
        frame.to_csv(OUT / f"{name}.csv", index=False)
        print(f"{name}: {len(frame):,} pairs")

    counts = pairs["severity_int"].value_counts().sort_index().to_dict()
    print(
        f"drugs={len(drugs):,} enzymes={len(enzymes):,} "
        f"categories={len(categories):,} unique_pairs={len(pairs):,}"
    )
    print(f"severity_int distribution: {counts}")
    print(f"written to {OUT}")


if __name__ == "__main__":
    main()
