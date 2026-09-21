# data_pipeline

Builds the bundled clinical database `mobile/assets/db/medguard.db` from the
raw sources. Everything here is offline batch work — it runs on a workstation,
never on a device.

## Running it

```bash
python -m data_pipeline.refresh_db
python mobile/tool/optimise_db.py mobile/assets/db/medguard.db
```

`refresh_db.py` drives the whole sequence; the stages can also be run alone:

| Stage | Script | What it does |
| --- | --- | --- |
| Parse | `parse/parse_drugbank.py` | Reads the DrugBank XML export into interim rows. |
| Normalise | `normalize/normalize_rxnorm.py` | Resolves RxNorm RxCUIs (cached in `ml_pipeline/data/processed/rxnorm_cache.json`). |
| Normalise | `normalize/classify_interactions.py` | Derives `severity` / `severity_int` and the mechanism, effect and template lookups. |
| Enrich | `scripts/merge_ddinter.py` | Merges DDInter 2.0 expert severity grades. |
| Enrich | `scripts/enrich_openfda.py` | Adds OpenFDA adverse-event co-report counts. |
| Export | `export/build_database.py` | Writes the SQLite schema, rows and FTS5 indexes. |
| Export | `export/slim_database.py` | Drops columns the app never reads. |
| Verify | `scripts/verify_db.py` | Integrity check plus row-count assertions. |

## Always run the optimise step

`mobile/tool/optimise_db.py` is part of the build, not an optional extra. The
export stage emits an unoptimised layout every time, and the optimiser recovers
about **22 MB** of app size with zero rows removed: it rebuilds
`interactions_data` as `WITHOUT ROWID` keyed on `(drug_a_id, drug_b_id)`, drops
two indexes made redundant by that key and by FTS5, then VACUUMs.

It refuses to run if the drug pair is non-unique, if `integrity_check` fails, or
if any row count changes, and it leaves a `.pre-optimise` backup beside the file.
Skipping it silently ships a database 22 MB larger.

## Inputs, and where they come from

Inputs:

- `ml_pipeline/data/raw/drugbank_all_full_database.xml` — the DrugBank full
  export. Not in the repository: it is about 1.5 GB and needs a DrugBank
  account (see [ml_pipeline/README.md](../ml_pipeline/README.md)).
- `ml_pipeline/data/external/ddinter/ddinter_downloads_code_*.csv` — DDInter 2.0,
  eight ATC-grouped files, included.
- OpenFDA and RxNorm are fetched over their public APIs during the enrich and
  normalise stages.

You only need this pipeline to refresh the data. The built database is already
in the repository at `mobile/assets/db/medguard.db`.
