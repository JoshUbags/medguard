"""
MedGuard Database Refresh — Full ETL Pipeline

Usage:
    python data_pipeline/refresh_db.py                 (full pipeline)
    python data_pipeline/refresh_db.py --skip-rxnorm   (skip the slow RxNorm step)
    python data_pipeline/refresh_db.py --skip-openfda  (skip the slow OpenFDA step)

Order matters. merge_ddinter overwrites interactions_classified.csv in place, so
it has to run after classify_interactions and before enrich_openfda, which reads
that file and writes interactions_enriched.csv. build_database prefers the
enriched file when it exists.

Prerequisites (neither is tracked in git):
    ml_pipeline/data/raw/drugbank_all_full_database.xml
        DrugBank 6.0 full database XML, downloaded under an academic licence.
    ml_pipeline/data/external/ddinter/*.csv
        DDInter 2.0 category CSVs. Optional: the pipeline runs without them,
        but severity then rests on the clinical-effect heuristic alone.
"""
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RAW_XML = ROOT / "ml_pipeline" / "data" / "raw" / "drugbank_all_full_database.xml"
DDINTER_DIR = ROOT / "ml_pipeline" / "data" / "external" / "ddinter"
PROCESSED = ROOT / "ml_pipeline" / "data" / "processed"
DB_DIR = ROOT / "mobile" / "assets" / "db"
DB_FULL = DB_DIR / "medguard_full.db"
DB_SHIPPED = DB_DIR / "medguard.db"

# (label, script, argv, optional)
STEPS = [
    ("Parse DrugBank XML into 5 CSVs", "data_pipeline/parse/parse_drugbank.py", [], False),
    ("Classify severity, mechanism and clinical effect", "data_pipeline/normalize/classify_interactions.py", [], False),
    ("Override severity with DDInter 2.0 expert ratings", "data_pipeline/scripts/merge_ddinter.py", [], True),
    ("Normalise drug names against RxNorm", "data_pipeline/normalize/normalize_rxnorm.py", [], False),
    ("Enrich with OpenFDA co-report counts", "data_pipeline/scripts/enrich_openfda.py", [], False),
    ("Build the full SQLite database", "data_pipeline/export/build_database.py", [], False),
    ("Slim the database for shipping", "data_pipeline/export/slim_database.py", ["__SRC__", "__DST__"], False),
    ("Verify the built database", "data_pipeline/scripts/verify_db.py", [], False),
]


def preflight() -> None:
    problems = []
    if not RAW_XML.exists():
        problems.append(
            f"Missing DrugBank XML at {RAW_XML.relative_to(ROOT)}\n"
            "    Download the Full Database XML from https://go.drugbank.com/releases/latest\n"
            "    under your academic licence, unzip it, and name it drugbank_all_full_database.xml"
        )
    csvs = list(DDINTER_DIR.glob("*.csv")) if DDINTER_DIR.exists() else []
    if not csvs:
        print(
            f"WARNING: no DDInter CSVs found in {DDINTER_DIR.relative_to(ROOT)}.\n"
            "         The DDInter override step will be skipped and severity will rest\n"
            "         on the clinical-effect heuristic alone. Download the category CSVs\n"
            "         from http://ddinter2.scbdd.com/server/download/ to enable it.\n"
        )
    else:
        print(f"Found {len(csvs)} DDInter CSV file(s).")
    PROCESSED.mkdir(parents=True, exist_ok=True)
    DB_DIR.mkdir(parents=True, exist_ok=True)
    if problems:
        print("\nCannot start:\n")
        for p in problems:
            print("  - " + p)
        sys.exit(1)


def run(label: str, script: str, argv: list, optional: bool) -> None:
    print(f"\n>>> {label}")
    print("-" * 60)
    result = subprocess.run([sys.executable, script, *argv], cwd=str(ROOT))
    if result.returncode != 0:
        if optional:
            print(f"NOTE: {label} did not complete. Continuing without it.")
            return
        print(f"\nERROR: {label} failed. Fix and re-run.")
        sys.exit(1)


if __name__ == "__main__":
    print("=" * 60)
    print("MedGuard Database Refresh — Full ETL Pipeline")
    print("=" * 60)
    preflight()

    skip_rxnorm = "--skip-rxnorm" in sys.argv
    skip_openfda = "--skip-openfda" in sys.argv
    start = time.time()

    for label, script, argv, optional in STEPS:
        if skip_rxnorm and "normalize_rxnorm" in script:
            print(f"\n>>> SKIPPING: {label}")
            continue
        if skip_openfda and "enrich_openfda" in script:
            print(f"\n>>> SKIPPING: {label}")
            continue

        if "slim_database" in script:
            # build_database.py writes straight to the shipped path, so move the
            # full build aside and let slim_database write the shipped file.
            if not DB_SHIPPED.exists():
                print("ERROR: build_database.py produced no database to slim.")
                sys.exit(1)
            if DB_FULL.exists():
                DB_FULL.unlink()
            shutil.move(str(DB_SHIPPED), str(DB_FULL))
            argv = [str(DB_FULL), str(DB_SHIPPED)]

        run(label, script, argv, optional)

    elapsed = time.time() - start
    print("\n" + "=" * 60)
    print(f"Pipeline complete in {elapsed / 60:.1f} minutes")
    if DB_SHIPPED.exists():
        print(f"Shipped database: {DB_SHIPPED.relative_to(ROOT)} "
              f"({os.path.getsize(DB_SHIPPED) / 1e6:.1f} MB)")
    if DB_FULL.exists():
        print(f"Pre-slim database: {DB_FULL.relative_to(ROOT)} "
              f"({os.path.getsize(DB_FULL) / 1e6:.1f} MB)  — delete once verified")
    print("=" * 60)
