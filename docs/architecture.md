# MedGuard architecture

MedGuard checks a person's medication regimen for drug–drug interactions,
food interactions, duplicate therapy, and allergy conflicts, working fully
offline with an optional cloud ML assist.

## Components

- **Mobile app (Flutter, `mobile/`)** — the product. Bundles a read-only
  DrugBank-derived SQLite reference DB and an on-device TFLite severity model,
  and keeps the user's own data in a separate, encrypted SQLite database.
- **Backend API (Flask, `backend/`)** — a stateless ML/data service exposing
  `/api/v1/predict` (three-tier clinical-significance risk — `low` / `moderate`
  / `high` — for a DrugBank pair, with per-tier probabilities; a `dangerous`
  flag for the `high` tier is retained for back-compat) and `/api/v1/db/*`
  (reference-DB version + delta). Authenticated with Firebase ID tokens.
- **ML pipeline (`ml_pipeline/`)** — trains the three-tier (low/moderate/high)
  Random Forest risk model (selected over gradient boosting) and exports the
  bundled TFLite model, feature columns, and the drug-risk lookup.
- **Data pipeline (`data_pipeline/`)** — parses and normalises DrugBank into
  the bundled `medguard.db`.

## Accounts are optional

The safety engine is entirely local, so the app works with no account at all:
`GuestModeService` records that choice and the launch gate routes a local-only
user straight into the app. Signing in adds what an account is actually for —
check history that outlives the handset, and caregiver profiles, whose ids embed
the owning account. `GuestDataMigration` adopts a local record into an account
on first sign-in.

## How a safety check runs

1. The user's medication list is resolved for the active profile
   (`SessionService`, which follows the caregiver profile switch).
2. `InteractionChecker` queries the bundled reference DB for known
   interactions, food interactions, duplicates, and allergy hits.
3. For pairs the rule DB doesn't recognise, it falls through a chain:
   cached result → remote `/api/v1/predict` → on-device TFLite predictor. The
   remote step only exists in builds made with
   `--dart-define=MEDGUARD_API_BASE_URL=…`; by default the app never leaves the
   device. When connectivity is already known to be down the remote call is
   queued rather than attempted, so an offline review never waits on a
   timeout.
   A `moderate`-or-`high` ML prediction (or any rule-DB hit at the Moderate or
   High tier) is surfaced in the `SafetyReport`; the regimen verdict is the
   highest tier present (a High pair, allergy conflict, or duplicate therapy is
   High; a Moderate pair is Moderate; otherwise Low).
4. The result is cached and written to local check history.

## What else the app does

Dose scheduling with local notifications and adherence tracking
(`DoseService`), a generated notification feed built only from the user's own
data (`NotificationCenter`), an emergency card with a scannable QR handoff, a
pharmacist report as text or PDF, and plain-English insight articles. The
assistant tab's interface is complete, but it does not answer questions yet: it
says so and points to the interaction review instead.

## Design system

Every screen is built from one shared widget layer in
`mobile/lib/widgets/common/` — `DetailPage` (the chrome for every routed
screen), `SurfaceCard`/`SectionBlock` (the card and section grammar),
`SettingsGroup`/`SettingsRow`, `ItemRowCard`, `AppButton`, `AppTextField`,
`showModalSheet` — over the tokens in `mobile/lib/theme/`. Screens are expected
to compose those rather than re-declare padding, radii, or type scales, which is
what keeps a routed page indistinguishable in style from a primary tab.

## Data stores

- `medguard.db` — bundled, read-only, public reference data. Copied to the
  app sandbox on first launch. See
  [data_dictionary.md](data_dictionary.md).
- `medguard_user.db` — the user's health data, **encrypted** (SQLCipher; key
  in platform secure storage). See [data-protection.md](data-protection.md).
- Firebase Auth — identity only; no health data.
