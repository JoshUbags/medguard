"""Database metadata + delta endpoints.

`GET /api/v1/db/version` returns the bundled DrugBank-derived database's
version, build timestamp, and per-table row counts (from the ``db_metadata``
table). `GET /api/v1/db/delta?from_version=X` returns a JSON envelope
describing the delta the client should apply.

The app ships a single bundled DB with each release, so the delta endpoint
returns ``no_delta`` whenever the requested version matches the deployed one.
"""

from __future__ import annotations

from flask import Blueprint, current_app, jsonify, request

from ..services.sqlite_repo import SqliteRepo

bp = Blueprint("db", __name__)


def _repo() -> SqliteRepo:
    return SqliteRepo(current_app.config["BUNDLED_DB_PATH"])


def _unavailable():  # noqa: ANN202
    """The 503 both endpoints answer when the database is not deployed.

    The standard image carries the database, but a deployment can point
    ``MEDGUARD_DB_PATH`` elsewhere. If nothing is there, "not configured here"
    is the honest answer — a 500 would suggest the service is broken.
    """
    return (
        jsonify(
            error="database_unavailable",
            message=(
                "The bundled clinical database isn't deployed on this host. "
                "See backend/README.md → Deploying."
            ),
        ),
        503,
    )


@bp.get("/version")
def version():  # noqa: ANN201
    repo = _repo()
    try:
        metadata = repo.db_metadata()
        severity = repo.severity_breakdown()
    except FileNotFoundError:
        return _unavailable()
    schema_version = metadata.get("schema_version", "1")
    drugbank_version = metadata.get("drugbank_version", "6.0")
    built_at = metadata.get("built_at")
    counts = {
        key.removeprefix("count_"): int(value)
        for key, value in metadata.items()
        if key.startswith("count_")
    }
    payload = {
        "schema_version": schema_version,
        "drugbank_version": drugbank_version,
        "built_at": built_at,
        "table_counts": counts,
        "severity_breakdown": severity,
    }
    return jsonify(payload), 200


@bp.get("/delta")
def delta():  # noqa: ANN201
    from_version = request.args.get("from_version") or request.args.get(
        "from"
    )
    if not from_version:
        return (
            jsonify(
                error="invalid_request",
                message="Provide ?from_version=<schema_version>.",
            ),
            400,
        )
    try:
        metadata = _repo().db_metadata()
    except FileNotFoundError:
        return _unavailable()
    current = metadata.get("schema_version", "1")
    if from_version == current:
        return jsonify(
            status="no_delta",
            current_version=current,
            from_version=from_version,
        )
    # Incremental delta patches are not implemented; the client
    # re-downloads the full bundled database with the next mobile release.
    return jsonify(
        status="full_rebuild",
        current_version=current,
        from_version=from_version,
        note=(
            "No incremental delta is published yet — re-download the bundled "
            "database with the next mobile release."
        ),
    )
