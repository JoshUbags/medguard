"""End-to-end tests for the backend API.

These exercise the real Flask app factory with the real bundled SQLite + a
trained joblib model, so failures here also tell us about the data
pipeline / model artefacts being in the wrong place.
"""

from __future__ import annotations

import os
from pathlib import Path

import pytest

from backend.app import create_app


@pytest.fixture()
def client():
    app = create_app({"TESTING": True})
    return app.test_client()


def _require_bundled_db() -> None:
    # The database ships in the repository; this only skips if it has been
    # removed or replaced by a stub. A real database is tens of megabytes.
    db = Path(os.environ["MEDGUARD_DB_PATH"])
    if not db.exists() or db.stat().st_size < 1024 * 1024:
        pytest.skip("Bundled clinical DB missing or a stub; restore mobile/assets/db.")


def _require_model() -> None:
    if not Path(os.environ["MEDGUARD_MODEL_PATH"]).exists():
        pytest.skip("Served model missing; restore ml_pipeline/models/bundled_db.")


def test_health_endpoint(client) -> None:
    r = client.get("/api/health")
    assert r.status_code == 200
    body = r.get_json()
    assert body["status"] == "ok"
    assert body["service"] == "medguard-api"
    assert "version" in body


def test_index_lists_documented_routes(client) -> None:
    r = client.get("/")
    body = r.get_json()
    assert "/api/v1/predict" in body["docs"].values()
    assert "/api/v1/db/version" in body["docs"].values()


def test_db_version_returns_known_metadata(client) -> None:
    _require_bundled_db()
    r = client.get("/api/v1/db/version")
    assert r.status_code == 200
    body = r.get_json()
    assert "schema_version" in body
    assert "severity_breakdown" in body
    # The bundled DrugBank dataset always has at least the moderate bucket.
    assert body["severity_breakdown"].get("moderate", 0) > 0


def test_db_delta_requires_version(client) -> None:
    r = client.get("/api/v1/db/delta")
    assert r.status_code == 400


def test_db_endpoints_report_503_without_the_database(tmp_path) -> None:
    """A host without the licensed database serves 503, not a 500.

    This is the state of a container built straight from a git checkout, so it
    is the path most deployments hit first.
    """
    app = create_app(
        {"TESTING": True, "BUNDLED_DB_PATH": str(tmp_path / "absent.db")}
    )
    client = app.test_client()
    version = client.get("/api/v1/db/version")
    assert version.status_code == 503
    assert version.get_json()["error"] == "database_unavailable"
    delta = client.get("/api/v1/db/delta?from_version=1")
    assert delta.status_code == 503
    # The service itself is still healthy, and says what it is missing.
    health = client.get("/api/health").get_json()
    assert health["status"] == "ok"
    assert health["artifacts"]["database"] is False


def test_db_delta_reports_no_delta_when_versions_match(client) -> None:
    _require_bundled_db()
    version = client.get("/api/v1/db/version").get_json()["schema_version"]
    r = client.get(f"/api/v1/db/delta?from_version={version}")
    assert r.status_code == 200
    body = r.get_json()
    assert body["status"] == "no_delta"


def test_predict_rejects_missing_payload(client) -> None:
    r = client.post("/api/v1/predict", json={})
    assert r.status_code == 400


def test_predict_rejects_non_drugbank_id(client) -> None:
    r = client.post(
        "/api/v1/predict",
        json={"drug_a_id": "foo", "drug_b_id": "DB00945"},
    )
    assert r.status_code == 400


def test_predict_returns_severity_for_known_pair(client) -> None:
    _require_model()
    _require_bundled_db()
    # Warfarin + Ibuprofen — well-known major-severity DrugBank pair.
    r = client.post(
        "/api/v1/predict",
        json={"drug_a_id": "DB00682", "drug_b_id": "DB01050"},
    )
    assert r.status_code == 200
    body = r.get_json()
    # The deployed model is three-tier: low / moderate / high risk.
    assert body["severity"] in {"low", "moderate", "high"}
    assert body["risk_level"] == body["severity"]
    assert body["severity_int"] in {0, 1, 2}
    # `risk_probability` is P(high tier) — the headline number the UI warns on.
    assert 0.0 <= body["risk_probability"] <= 1.0
    assert 0.0 <= body["confidence"] <= 1.0
    assert set(body["probabilities"]) == {"low", "moderate", "high"}
    # 22 structural/mechanistic features + 5 drug-level risk features
    # (must match feature_columns.json and the on-device builder).
    assert len(body["features_used"]) == 27
    assert isinstance(body["explanation"], list)
    assert body["drugs"]["a"]["drugbank_id"] == "DB00682"


def test_predict_returns_404_for_unknown_drugs(client) -> None:
    _require_model()
    _require_bundled_db()
    r = client.post(
        "/api/v1/predict",
        json={"drug_a_id": "DB99999", "drug_b_id": "DB00945"},
    )
    assert r.status_code == 404


def test_per_route_rate_limit_returns_429() -> None:
    # Relax the global default so we exercise the per-route 30/minute limit.
    from backend.app.extensions import limiter

    app = create_app(
        {"TESTING": True, "RATELIMIT_DEFAULT": "1000 per minute"}
    )
    limiter.reset()
    c = app.test_client()
    statuses = [
        c.post("/api/v1/predict", json={}).status_code for _ in range(32)
    ]
    # The 31st+ call inside the window must be rejected by the limiter.
    assert 429 in statuses
    assert statuses.index(429) >= 30
    limiter.reset()


def test_api_requires_auth_when_enabled() -> None:
    # AUTH_DISABLED is forced off here even though TESTING is on, so the
    # before_request guard runs and rejects the unauthenticated call.
    app = create_app({"TESTING": True})
    app.config["AUTH_DISABLED"] = False
    r = app.test_client().post("/api/v1/predict", json={})
    assert r.status_code in (401, 503)


def test_audit_chain_is_tamper_evident() -> None:
    from backend.app.services.audit_log import AuditLog

    log = AuditLog(":memory:")
    for i in range(5):
        log.record(
            actor_id="user_1",
            action="predict",
            resource_type="interaction_check",
            resource_id=f"DB0000{i}+DB0001{i}",
            outcome="allowed",
        )
    assert log.count() == 5
    assert log.verify_chain() is True

    # Tamper with one row — the chain must no longer verify.
    log._conn().execute(  # noqa: SLF001 — test reaches in deliberately
        "UPDATE audit_events SET outcome='denied' WHERE seq=3"
    )
    log._conn().commit()
    assert log.verify_chain() is False
