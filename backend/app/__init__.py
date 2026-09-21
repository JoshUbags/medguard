"""Flask application factory for the MedGuard ML/data API."""

from __future__ import annotations

import logging
import os
import time

from flask import Flask, g, jsonify, request
from flask_cors import CORS

from .auth import init_auth
from .extensions import limiter
from .routes import db as db_routes
from .routes import predict as predict_routes
from .services.audit_log import AuditLog
from .services.metrics import RequestMetrics

VERSION = "1.0.0"


_REPO_ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))


def _path(env_var: str, *parts: str) -> str:
    """Repo-relative default for a path, overridable by an env var."""
    return os.environ.get(env_var, os.path.join(_REPO_ROOT, *parts))


def _model_file(env_var: str, name: str) -> str:
    """A file belonging to the served model.

    Every model file defaults to one directory, ``MEDGUARD_MODEL_DIR`` (the
    model trained on the bundled database), so a model can never be paired
    with another training run's feature list or risk lookup.
    """
    model_dir = os.environ.get(
        "MEDGUARD_MODEL_DIR",
        os.path.join(_REPO_ROOT, "ml_pipeline", "models", "bundled_db"),
    )
    return os.environ.get(env_var, os.path.join(model_dir, name))


def create_app(config: dict | None = None) -> Flask:
    """Application factory. Tests + Gunicorn call this once at startup."""
    app = Flask(__name__)
    app.config.update(
        BUNDLED_DB_PATH=_path(
            "MEDGUARD_DB_PATH", "mobile", "assets", "db", "medguard.db"
        ),
        MODEL_PATH=_model_file("MEDGUARD_MODEL_PATH", "rf_severity_model.joblib"),
        FEATURE_COLUMNS_PATH=_model_file(
            "MEDGUARD_FEATURES_PATH", "feature_columns.json"
        ),
        DRUG_RISK_PATH=_model_file("MEDGUARD_DRUG_RISK_PATH", "drug_risk_lookup.json"),
        AUDIT_DB_PATH=_path("MEDGUARD_AUDIT_DB_PATH", "backend", "audit.db"),
        # Comma-separated browser origins. Defaults to none (deny) — a public
        # API must never ship a wildcard. Mobile HTTP clients don't enforce
        # CORS, so the app keeps working; set this only for web origins.
        ALLOWED_ORIGINS=[
            o.strip()
            for o in os.environ.get("MEDGUARD_ALLOWED_ORIGINS", "").split(",")
            if o.strip()
        ],
    )
    app.config.setdefault(
        "RATELIMIT_DEFAULT",
        os.environ.get("MEDGUARD_DEFAULT_LIMITS", "120 per minute;5 per second"),
    )
    app.config.setdefault(
        "RATELIMIT_STORAGE_URI",
        os.environ.get("MEDGUARD_RATE_STORE", "memory://"),
    )
    app.config.setdefault("RATELIMIT_STRATEGY", "fixed-window")
    if config:
        app.config.update(config)

    _configure_logging()
    _configure_cors(app)
    limiter.init_app(app)
    init_auth(app)
    _configure_metrics(app)
    _configure_audit(app)
    _register_blueprints(app)
    _register_error_handlers(app)
    _register_root_routes(app)
    return app


# ── Configuration helpers ───────────────────────────────────────────────────


def _configure_logging() -> None:
    handler = logging.StreamHandler()
    handler.setFormatter(
        logging.Formatter(
            "%(asctime)s %(levelname)s [%(name)s] %(message)s",
            datefmt="%Y-%m-%dT%H:%M:%S%z",
        )
    )
    root = logging.getLogger()
    if not root.handlers:
        root.addHandler(handler)
    root.setLevel(logging.INFO)


def _configure_cors(app: Flask) -> None:
    CORS(
        app,
        resources={r"/api/*": {"origins": app.config["ALLOWED_ORIGINS"]}},
        supports_credentials=False,
    )


def _configure_audit(app: Flask) -> None:
    # Append-only, hash-chained audit store kept in its own SQLite file,
    # separate from the read-only reference DB and from app data.
    app.extensions["audit"] = AuditLog(app.config["AUDIT_DB_PATH"])


def _configure_metrics(app: Flask) -> None:
    metrics = RequestMetrics()
    app.extensions["metrics"] = metrics

    @app.before_request
    def _start_timer() -> None:
        g._request_started_at = time.perf_counter()

    @app.after_request
    def _record_metrics(response):
        started = getattr(g, "_request_started_at", None)
        if started is None:
            return response
        latency_ms = (time.perf_counter() - started) * 1000.0
        metrics.record(
            path=request.path,
            status=response.status_code,
            latency_ms=latency_ms,
        )
        response.headers["X-MedGuard-Latency-Ms"] = f"{latency_ms:.1f}"
        return response


def _register_blueprints(app: Flask) -> None:
    app.register_blueprint(predict_routes.bp, url_prefix="/api/v1")
    app.register_blueprint(db_routes.bp, url_prefix="/api/v1/db")


def _register_error_handlers(app: Flask) -> None:
    @app.errorhandler(400)
    def _bad_request(err):  # noqa: ANN001
        return jsonify(error="bad_request", message=str(err)), 400

    @app.errorhandler(404)
    def _not_found(err):  # noqa: ANN001
        return jsonify(error="not_found", message=str(err)), 404

    @app.errorhandler(429)
    def _rate_limited(err):  # noqa: ANN001
        return (
            jsonify(error="rate_limited", message=str(err.description)),
            429,
        )

    @app.errorhandler(500)
    def _server_error(err):  # noqa: ANN001
        app.logger.exception("Server error")
        return jsonify(error="server_error", message=str(err)), 500


def _register_root_routes(app: Flask) -> None:
    @app.get("/api/health")
    def health():  # noqa: ANN201
        metrics: RequestMetrics = app.extensions["metrics"]
        # Deliberately still "ok" without the artefacts: the service is up and
        # healthy, some endpoints are simply not configured on this host. A
        # failing health check would make the platform restart a sound process.
        return jsonify(
            status="ok",
            service="medguard-api",
            version=VERSION,
            requests=metrics.snapshot(),
            artifacts={
                "database": os.path.exists(app.config["BUNDLED_DB_PATH"]),
                "model": os.path.exists(app.config["MODEL_PATH"]),
            },
        )

    @app.get("/")
    def index():  # noqa: ANN201
        return jsonify(
            service="medguard-api",
            version=VERSION,
            docs={
                "health": "/api/health",
                "predict": "/api/v1/predict",
                "db_version": "/api/v1/db/version",
                "db_delta": "/api/v1/db/delta?from_version=X",
            },
        )
