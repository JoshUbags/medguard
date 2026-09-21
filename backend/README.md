# backend

Stateless Flask service exposing the trained drug-interaction model and the
reference-database metadata endpoints.

## Endpoints

- `GET  /api/health` — liveness + request metrics (public)
- `GET  /` — service info (public)
- `POST /api/v1/predict` — severity for a DrugBank pair (authenticated)
- `GET  /api/v1/db/version` — bundled reference-DB version (authenticated)
- `GET  /api/v1/db/delta?from_version=X` — delta envelope (authenticated)

## Authentication

`/api/v1/*` requires the caller's Firebase ID token as
`Authorization: Bearer <token>`; it is verified server-side with the Firebase
Admin SDK and rejected with 401 if invalid (`app/auth.py`).

- `MEDGUARD_FIREBASE_CREDENTIALS` — path to the service-account JSON used to
  verify tokens. Without it, authenticated routes return 503.
- `MEDGUARD_AUTH_DISABLED=1` — bypass auth for **local dev only**. Tests set
  `TESTING=True`, which disables it automatically.

## Other configuration

- `MEDGUARD_ALLOWED_ORIGINS` — comma-separated browser origins for CORS.
  Empty by default (deny); never a wildcard.
- `MEDGUARD_RATE_STORE` — limiter storage URI (`memory://` default;
  `redis://…` for multi-instance). Per-route cap on `/predict` is 30/min.
- `MEDGUARD_AUDIT_DB_PATH` — location of the append-only, hash-chained audit
  log (`app/services/audit_log.py`).

## Running locally

From the repository root:

```bash
python -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scriptsctivate
pip install -r backend/requirements.txt
MEDGUARD_AUTH_DISABLED=1 python -m flask --app backend.app.main run
```

In PowerShell, set the variable first: `$env:MEDGUARD_AUTH_DISABLED = "1"`.

The clinical database and the served model are read straight from the
repository, so nothing else needs setting up:

| Variable | Default |
| --- | --- |
| `MEDGUARD_DB_PATH` | `mobile/assets/db/medguard.db` |
| `MEDGUARD_MODEL_DIR` | `ml_pipeline/models/bundled_db` |

`MEDGUARD_MODEL_DIR` holds the model and every metadata file it needs.
`MEDGUARD_MODEL_PATH`, `MEDGUARD_FEATURES_PATH` and `MEDGUARD_DRUG_RISK_PATH`
override single files; if you use them, take all three from the same training
run, or predictions are silently scored against the wrong features.

## Tests

```bash
python -m pytest backend/tests -q -rs
```

All tests run against the database and model in the repository.

## Deploying

Build from the repository root, so the image can include the database and the
model:

```bash
docker build -f backend/Dockerfile -t medguard-api .
docker run -p 8000:8000 -e MEDGUARD_AUTH_DISABLED=1 medguard-api
```

On Render, create a Blueprint from [`render.yaml`](render.yaml). The one value
to supply is `MEDGUARD_FIREBASE_CREDENTIALS`: upload the Firebase
service-account JSON as a Secret File and point the variable at it.

`GET /api/health` reports what the running service has loaded:

```json
{ "status": "ok", "artifacts": { "database": true, "model": true } }
```

If you build a slimmer image without them, the service still starts and the
endpoints that need a missing file answer 503 naming it. `MEDGUARD_DB_URL` and
`MEDGUARD_MODEL_BUNDLE_URL` fill in missing files at boot — the second is a
`.tar.gz` of the model directory:

```bash
tar -czf model_bundle.tar.gz -C ml_pipeline/models/bundled_db .
```

The app never depends on this service. It only calls it when built with the
service's address:

```bash
flutter build apk --dart-define=MEDGUARD_API_BASE_URL=https://your-host
```

Without that, and whenever `/api/v1/predict` is unreachable, predictions come
from the on-device model.
