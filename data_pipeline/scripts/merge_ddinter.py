"""Override heuristic severity with DDInter 2.0 expert ratings (gold layer).

DDInter (http://ddinter2.scbdd.com) publishes expert-curated interaction
severities (Major / Moderate / Minor) as CSV files grouped by ATC class. This
script joins them onto our classified interactions BY DRUG NAME and, wherever a
pair matches, replaces the heuristic ``severity`` with DDInter's rating. Pairs
not covered by DDInter keep the clinical-effect heuristic from
``classify_interactions.py`` (the silver layer), so coverage stays complete.

Setup:
  1. Download every category CSV from DDInter's Download page.
  2. Put them all in:  ml_pipeline/data/external/ddinter/
     (any number of *.csv files; columns include Drug_A, Drug_B, Level)

Run:
  python -m data_pipeline.scripts.merge_ddinter
"""

from __future__ import annotations

import glob
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[2]
PROCESSED = ROOT / "ml_pipeline" / "data" / "processed"
DDINTER_DIR = ROOT / "ml_pipeline" / "data" / "external" / "ddinter"

LEVEL_TO_SEVERITY = {
    "major": "major",
    "moderate": "moderate",
    "minor": "minor",
    # DDInter has no 'contraindicated' tier; those stay from the heuristic.
}
SEVERITY_MAP = {"minor": 0, "moderate": 1, "major": 2, "contraindicated": 3}


def _norm(name: object) -> str:
    return str(name).strip().lower()


def _load_ddinter() -> dict[frozenset, str]:
    files = glob.glob(str(DDINTER_DIR / "*.csv"))
    if not files:
        raise SystemExit(
            f"No DDInter CSVs found in {DDINTER_DIR}. Download them first "
            "(see the module docstring)."
        )
    lookup: dict[frozenset, str] = {}
    rows = 0
    for fp in files:
        df = pd.read_csv(fp)
        cols = {c.lower(): c for c in df.columns}
        a_col = cols.get("drug_a") or cols.get("drug_a_name") or cols.get("a")
        b_col = cols.get("drug_b") or cols.get("drug_b_name") or cols.get("b")
        lvl_col = cols.get("level") or cols.get("severity")
        if not (a_col and b_col and lvl_col):
            print(f"  ! skipping {Path(fp).name}: columns {list(df.columns)}")
            continue
        for a, b, lvl in zip(df[a_col], df[b_col], df[lvl_col]):
            sev = LEVEL_TO_SEVERITY.get(_norm(lvl))
            if not sev:
                continue
            key = frozenset((_norm(a), _norm(b)))
            # Keep the most severe rating if a pair appears more than once.
            if key not in lookup or SEVERITY_MAP[sev] > SEVERITY_MAP[lookup[key]]:
                lookup[key] = sev
            rows += 1
    print(f"Loaded {len(lookup):,} unique DDInter pairs from {len(files)} files ({rows:,} rows).")
    return lookup


def merge() -> None:
    src = PROCESSED / "interactions_classified.csv"
    df = pd.read_csv(src)
    if "drug_a_name" not in df.columns or "drug_b_name" not in df.columns:
        raise SystemExit("interactions_classified.csv needs drug_a_name / drug_b_name.")

    lookup = _load_ddinter()
    keys = [frozenset((_norm(a), _norm(b))) for a, b in zip(df["drug_a_name"], df["drug_b_name"])]
    gold = [lookup.get(k) for k in keys]

    # Precautionary tie-break: where DDInter and the clinical-effect heuristic
    # disagree, keep whichever is MORE severe. A disagreement between the two
    # sources can therefore raise an alert but never suppress one. Taking
    # DDInter unconditionally would also demote pairs the heuristic had flagged
    # as major on the strength of a named serious effect (bleeding, QTc
    # prolongation, serotonin syndrome), which is the wrong error for a
    # medication-safety tool to make.
    resolved, raised, kept = [], 0, 0
    for g, s in zip(gold, df["severity"]):
        if not g:
            resolved.append(s)
            continue
        if SEVERITY_MAP[g] > SEVERITY_MAP[s]:
            resolved.append(g)
            raised += 1
        else:
            resolved.append(s)
            if g != s:
                kept += 1

    matched = sum(1 for g in gold if g)
    df["severity_source"] = [
        "ddinter" if g and SEVERITY_MAP[g] > SEVERITY_MAP[s] else "heuristic"
        for g, s in zip(gold, df["severity"])
    ]
    df["severity"] = resolved
    df["severity_int"] = df["severity"].map(SEVERITY_MAP)

    print(f"DDInter matched {matched:,} / {len(df):,} pairs "
          f"({matched/len(df):.1%}).")
    print(f"  raised by DDInter: {raised:,}")
    print(f"  DDInter was lower, heuristic kept: {kept:,}")
    print("\nFinal severity distribution:")
    print(df["severity"].value_counts().to_string())

    df.to_csv(src, index=False)
    print(f"\nUpdated {src}")


if __name__ == "__main__":
    merge()
