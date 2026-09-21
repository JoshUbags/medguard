# MedGuard Data Dictionary

Two SQLite databases, with different owners and lifetimes:

| | `medguard.db` | `medguard_user.db` |
| --- | --- | --- |
| Contents | Public DrugBank-derived reference data | The user's own health data |
| Access | Read-only, bundled in the app | Read/write, created on first launch |
| Encryption | None (public data) | SQLCipher AES-256, key in platform secure storage |
| Rebuilt by | `data_pipeline/` | The app, per device |

Row counts below are from the shipping database (75 MB, 19,227 pages, no free
pages — it is VACUUMed by `mobile/tool/optimise_db.py`).

---

## Database: medguard.db (reference, read-only)

Supports five kinds of analysis: drug–drug interactions, drug–food
interactions, duplicate therapy (via ATC codes and categories), drug–allergy
cross-checks, and the drug monograph.

### Table: drugs — 4,955 rows

| Column | Type | Description | Source |
| --- | --- | --- | --- |
| id | INTEGER PK | Auto-increment key | Generated |
| drugbank_id | TEXT UNIQUE | DrugBank ID (e.g. DB00945) | DrugBank |
| rxcui | TEXT | RxNorm Concept Unique ID | RxNorm API |
| name | TEXT | Primary drug name | DrugBank |
| generic_name | TEXT | Generic/INN name | DrugBank |
| drug_type | TEXT | small molecule / biotech | DrugBank |
| description | TEXT | Clinical description | DrugBank |
| indication | TEXT | What the drug is used for | DrugBank |
| mechanism_of_action | TEXT | How the drug works | DrugBank |
| absorption | TEXT | Absorption details | DrugBank |
| half_life | TEXT | Elimination half-life | DrugBank |
| toxicity | TEXT | Toxicity information | DrugBank |
| atc_code | TEXT | Primary ATC code | DrugBank |
| all_atc_codes | TEXT | All ATC codes (pipe-separated) | DrugBank |
| drug_class | TEXT | Primary therapeutic category | DrugBank |
| cas_number | TEXT | CAS registry number | DrugBank |
| average_mass | TEXT | Molecular weight | DrugBank |
| groups | TEXT | approved / experimental / etc. | DrugBank |

Indexes: `idx_drugs_drugbank_id`, `idx_drugs_name`, `idx_drugs_atc`,
`idx_drugs_rxcui`. Name search runs through the FTS5 table `drugs_fts`, not a
LIKE scan.

> DrugBank prose (`description`, `indication`, `mechanism_of_action`, …) carries
> the source's authoring markup — citation keys like `[label,L6616]`, linked
> terms in brackets, `**bold**`, and inline `<sub>`/`<sup>`. The app strips it at
> render time (`cleanReferenceText` in `drug_monograph_screen.dart`); it is
> stored verbatim.

### Table: drug_synonyms — 252,046 rows

| Column | Type | Description | Source |
| --- | --- | --- | --- |
| id | INTEGER PK | Auto-increment key | Generated |
| drug_id | INTEGER FK | References drugs.id | Generated |
| synonym | TEXT | Alternative name | DrugBank |
| source | TEXT | synonym / brand / product / mixture / secondary_id | DrugBank |

Index: `idx_synonyms_drug_id`. Synonym search uses the FTS5 table
`drug_synonyms_fts`.

### Table: interactions_data — 851,868 rows

`WITHOUT ROWID`, primary key `(drug_a_id, drug_b_id)`.

| Column | Type | Description | Source |
| --- | --- | --- | --- |
| drug_a_id | INTEGER | First drug (PK part) | Generated |
| drug_b_id | INTEGER | Second drug (PK part) | Generated |
| severity | TEXT | minor / moderate / major / contraindicated | Classified |
| severity_int | INTEGER | 0 / 1 / 2 / 3 | Derived |
| mech_id | INTEGER FK | → `mech_lookup.id` (interaction mechanism) | Extracted |
| effect_id | INTEGER FK | → `effect_lookup.id` (plain-English effect) | Extracted |
| template_id | INTEGER FK | → `tmpl_lookup.id` (description template) | Extracted |
| openfda_coreport_count | INTEGER | FDA adverse-event co-reports | OpenFDA |

Index: `idx_interactions_b` (the `_a` direction is served by the primary key).

> **Each pair is stored once, in an arbitrary direction.** Measured on the
> shipping database: 851,868 rows, 851,868 distinct unordered pairs, and zero
> rows whose mirror is also present (424,928 happen to have `drug_a_id <
> drug_b_id`, 426,940 the other way). So a lookup must test **both** orders —
> which is exactly why the table carries the primary key on
> `(drug_a_id, drug_b_id)` *and* `idx_interactions_b`. The `GROUP BY MIN/MAX`
> in `checkAllInteractions` is defensive de-duplication, not a necessity.

**Prose is normalised out.** Mechanism, effect and description text repeat
across hundreds of thousands of pairs, so they live in three small lookup
tables and the pair row keeps an integer. That is most of why the database
fits in 75 MB.

### Lookup tables

| Table | Rows | Columns |
| --- | --- | --- |
| mech_lookup | 15 | `id INTEGER PK`, `text TEXT` |
| effect_lookup | 13 | `id INTEGER PK`, `text TEXT` |
| tmpl_lookup | 718 | `id INTEGER PK`, `template TEXT` |

### View: interactions

**The interface every caller uses** — the app's `DatabaseService` and the
backend's `sqlite_repo` both query `interactions`, never `interactions_data`
directly. It reassembles one readable row per pair:

| Column | Derived from |
| --- | --- |
| drug_a_id, drug_b_id | `interactions_data` |
| severity, severity_int | `interactions_data` |
| mechanism | `mech_lookup.text` |
| clinical_effect | `effect_lookup.text` |
| description | `tmpl_lookup.template` with `{A}` / `{B}` replaced by the two drug names |
| openfda_coreport_count | `interactions_data` |

So the storage layout can change (as the optimiser does) without touching a
single query, as long as the view keeps these columns.

### Table: food_interactions — 2,503 rows

| Column | Type | Description | Source |
| --- | --- | --- | --- |
| id | INTEGER PK | Auto-increment key | Generated |
| drug_id | INTEGER FK | References drugs.id | Generated |
| description | TEXT | Food interaction description | DrugBank |

Index: `idx_food_drug`.

### Table: drug_categories — 65,784 rows

| Column | Type | Description | Source |
| --- | --- | --- | --- |
| id | INTEGER PK | Auto-increment key | Generated |
| drug_id | INTEGER FK | References drugs.id | Generated |
| category | TEXT | Therapeutic category name | DrugBank |
| mesh_id | TEXT | MeSH identifier | DrugBank |

Indexes: `idx_cat_drug`, `idx_cat_name`. Duplicate-therapy detection reads this
table plus ATC codes.

### Table: drug_enzymes — 20,822 rows

| Column | Type | Description | Source |
| --- | --- | --- | --- |
| id | INTEGER PK | Auto-increment key | Generated |
| drug_id | INTEGER FK | References drugs.id | Generated |
| enzyme_type | TEXT | enzymes / carriers / transporters / targets | DrugBank |
| enzyme_name | TEXT | Enzyme name (e.g. Cytochrome P450 3A4) | DrugBank |
| gene_name | TEXT | Gene name (e.g. CYP3A4) | DrugBank |
| actions | TEXT | substrate / inhibitor / inducer (pipe-separated) | DrugBank |
| known_action | TEXT | yes / no / unknown | DrugBank |

Index: `idx_enz_drug`.

### Risk tiers

The app collapses the four stored `severity` values into three tiers the user
sees — **Low** (minor), **Moderate** (moderate), **High** (major +
contraindicated) — via `Severity.riskLevel`. The deployed ML model predicts the
three tiers directly (classes `0`/`1`/`2`).

---

## Database: medguard_user.db (per-device, encrypted)

Created by `UserDataService` at schema version 10. Never leaves the device and
has no server-side copy. Tables behind removed features
(`user_pharmacogenomics`, `side_effect_reports`, `side_effect_alerts`) are
dropped on upgrade.

### Table: user_medications

`id INTEGER PK`, `user_id TEXT NOT NULL`, `drug_id INTEGER NOT NULL`,
`drug_name TEXT NOT NULL`, `atc_code TEXT`, `nickname TEXT`,
`custom_color INTEGER`, `added_at TEXT NOT NULL`, `UNIQUE(user_id, drug_id)`.

### Table: user_allergies

`id INTEGER PK`, `user_id TEXT NOT NULL`, `drug_id INTEGER`, `class_name TEXT`,
`label TEXT NOT NULL`, `note TEXT`, `added_at TEXT NOT NULL`. A row is either a
specific drug (`drug_id`) or a whole class (`class_name`).

### Table: user_foods

`id INTEGER PK`, `user_id TEXT NOT NULL`, `label TEXT NOT NULL`, `note TEXT`,
`added_at TEXT NOT NULL`, `UNIQUE(user_id, label)`.

### Table: dose_schedules

`id INTEGER PK`, `user_id`, `drug_id`, `drug_name`, `amount`, `unit`,
`frequency`, `time_slots TEXT NOT NULL` (encoded list), `start_date TEXT NOT
NULL`, `end_date`, `refill_date`, `quantity`, `created_at TEXT NOT NULL`.
Index: `idx_dose_schedules_user`.

### Table: dose_logs

`id INTEGER PK`, `schedule_id` (FK), `user_id`, `scheduled_time TEXT NOT NULL`,
`status`, `logged_at`, `UNIQUE(schedule_id, scheduled_time)`. Index:
`idx_dose_logs_schedule`. One row per dose occurrence, which is what adherence
is computed from.

### Table: check_logs

`id INTEGER PK`, `user_id TEXT NOT NULL`, `drug_ids TEXT NOT NULL`
(comma-separated), `drug_names TEXT NOT NULL` (pipe-separated),
`overall_risk TEXT NOT NULL`, `interaction_count`, `food_count`,
`duplicate_count`, `allergy_count` (INTEGER, default 0), `source TEXT NOT NULL`
(`rule_based` / `ml`), `created_at TEXT NOT NULL`. Index:
`idx_check_logs_user(user_id, created_at DESC)`.

### Table: managed_profiles

`id INTEGER PK`, `owner_id TEXT NOT NULL`, `profile_id TEXT NOT NULL`,
`name TEXT NOT NULL`, `relation`, `date_of_birth`, `notes`,
`created_at TEXT NOT NULL`, `UNIQUE(owner_id, profile_id)`. Index:
`idx_managed_profiles_owner`. Removing a profile cascade-deletes its rows.

### Table: ml_predictions

`id INTEGER PK`, `drug_a_drugbank_id`, `drug_b_drugbank_id`, `severity`,
`severity_int`, `confidence REAL`, `source`, `features_json`,
`explanation_json`, `cached_at`,
`UNIQUE(drug_a_drugbank_id, drug_b_drugbank_id, source)`. The prediction cache
that keeps a repeat review instant.

### Table: pending_api_requests

`id INTEGER PK`, `endpoint`, `payload_json`, `attempts INTEGER DEFAULT 0`,
`last_error`, `queued_at`. Requests made while offline, replayed on reconnect.

---

## Data Sources

| Source | URL | Licence | Download Date |
| --- | --- | --- | --- |
| DrugBank | go.drugbank.com | Academic | April 2025 |
| RxNorm | rxnav.nlm.nih.gov | Public domain | April 2025 |
| OpenFDA | open.fda.gov | Public domain | April 2025 |
| DDInter 2.0 | ddinter2.scbdd.com | Academic, non-commercial | August 2026 |
