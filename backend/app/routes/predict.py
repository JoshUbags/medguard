"""POST /api/v1/predict — score a DrugBank pair.

Accepts a JSON body with two DrugBank IDs and returns the model's predicted
interaction risk level (low / moderate / high), the feature vector used, and a
short human-readable explanation. Each authenticated request is written to the
tamper-evident audit log.
"""

from __future__ import annotations

import logging
import threading
from typing import Any

from flask import Blueprint, current_app, g, jsonify, request

from ..extensions import limiter
from ..services.model import ModelService
from ..services.sqlite_repo import SqliteRepo

bp = Blueprint("predict", __name__)
logger = logging.getLogger("medguard.predict")

_service_lock = threading.Lock()
_service: ModelService | None = None


def _get_service() -> ModelService:
    global _service
    if _service is not None:
        return _service
    with _service_lock:
        if _service is None:
            repo = SqliteRepo(current_app.config["BUNDLED_DB_PATH"])
            _service = ModelService(
                model_path=current_app.config["MODEL_PATH"],
                feature_columns_path=current_app.config[
                    "FEATURE_COLUMNS_PATH"
                ],
                drug_risk_path=current_app.config.get("DRUG_RISK_PATH"),
                repo=repo,
            )
    return _service


def _validate_payload(payload: Any) -> tuple[str, str] | tuple[None, str]:
    if not isinstance(payload, dict):
        return None, "Request body must be a JSON object."
    drug_a = payload.get("drug_a_id") or payload.get("drug_a_drugbank_id")
    drug_b = payload.get("drug_b_id") or payload.get("drug_b_drugbank_id")
    if not isinstance(drug_a, str) or not drug_a.startswith("DB"):
        return None, "drug_a_id must be a DrugBank id like 'DB00945'."
    if not isinstance(drug_b, str) or not drug_b.startswith("DB"):
        return None, "drug_b_id must be a DrugBank id like 'DB00945'."
    if drug_a == drug_b:
        return None, "drug_a_id and drug_b_id must be different."
    return drug_a, drug_b


def _audit(action: str, resource_id: str, *, outcome: str) -> None:
    """Append one event to the tamper-evident audit log, if configured."""
    audit = current_app.extensions.get("audit")
    if audit is None:
        return
    audit.record(
        actor_id=getattr(g, "actor_id", "anonymous"),
        action=action,
        resource_type="interaction_check",
        resource_id=resource_id,
        outcome=outcome,
        source_ip=request.headers.get("X-Forwarded-For", request.remote_addr),
    )


@bp.post("/predict")
@limiter.limit("30 per minute")
def predict():  # noqa: ANN201
    payload = request.get_json(silent=True)
    drug_a, drug_b = _validate_payload(payload)
    if drug_a is None:
        _audit("predict", f"{payload}", outcome="denied")
        return jsonify(error="invalid_request", message=drug_b), 400

    try:
        result = _get_service().predict(drug_a, drug_b)
    except FileNotFoundError as exc:
        logger.error("Model bundle missing: %s", exc)
        return (
            jsonify(
                error="model_unavailable",
                message="The prediction model isn't deployed on this host.",
            ),
            503,
        )
    except ValueError as exc:
        _audit("predict", f"{drug_a}+{drug_b}", outcome="denied")
        return jsonify(error="unknown_drug", message=str(exc)), 404
    except Exception:  # noqa: BLE001 — surface as 500 + logged trace
        logger.exception("predict failed for %s + %s", drug_a, drug_b)
        return (
            jsonify(error="server_error", message="Unable to score this pair."),
            500,
        )

    _audit("predict", f"{drug_a}+{drug_b}", outcome="allowed")
    metrics = current_app.extensions.get("metrics")
    if metrics is not None:
        metrics.record_prediction(result["severity"])
    logger.info(
        "predict drug_a=%s drug_b=%s severity=%s confidence=%.3f",
        drug_a,
        drug_b,
        result["severity"],
        result["confidence"],
    )
    return jsonify(result), 200
