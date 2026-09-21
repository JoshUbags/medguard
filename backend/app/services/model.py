"""Wraps the persisted severity model plus the feature builder. Loaded lazily
so the test suite + DB endpoints don't pay the ~5 s joblib bootstrap cost when
they don't need it.

The deployed model is a three-class classifier that predicts a graded risk
level for a drug pair: LOW (minor), MODERATE (moderate), or HIGH (major or
contraindicated). The same feature engineering is mirrored on-device (see
``mobile/lib/services/interaction_feature_builder.dart``). Five drug-level risk
features are appended from ``drug_risk_lookup.json`` (see
``ml_pipeline.src.features.build_features``).
"""

from __future__ import annotations

import json
import math
import re
import threading
from pathlib import Path
from typing import Any

import joblib
import numpy as np

from .sqlite_repo import SqliteRepo

# The three deployed risk tiers: 0 = low (minor), 1 = moderate, 2 = high
# (major or contraindicated). This is the single classification the whole
# stack speaks in — backend, on-device model, and UI.
RISK_LABELS = {0: "low", 1: "moderate", 2: "high"}

# The five drug-level risk feature names, appended after the 12 base features.
RISK_FEATURES = (
    "drug_risk_a",
    "drug_risk_b",
    "drug_risk_prod",
    "drug_risk_max",
    "drug_risk_min",
)


class ModelService:
    """Loads the joblib model + feature_columns.json + drug_risk_lookup.json and
    computes feature vectors for arbitrary DrugBank-ID pairs using the bundled
    SQLite DB."""

    def __init__(
        self,
        *,
        model_path: str | Path,
        feature_columns_path: str | Path,
        repo: SqliteRepo,
        drug_risk_path: str | Path | None = None,
    ) -> None:
        self._model_path = Path(model_path)
        self._feature_columns_path = Path(feature_columns_path)
        # Defaults next to the model file if not supplied.
        self._drug_risk_path = (
            Path(drug_risk_path)
            if drug_risk_path is not None
            else self._model_path.with_name("drug_risk_lookup.json")
        )
        self._repo = repo
        self._lock = threading.Lock()
        self._model = None
        self._feature_columns: list[str] | None = None
        self._classes: list[int] | None = None
        self._drug_risk: dict[str, float] = {}
        self._global_risk: float = 0.0
        # Safety-oriented decision thresholds (overridable from model_meta.json).
        self._high_threshold: float = 0.45
        self._low_threshold: float = 0.65

    @property
    def feature_columns(self) -> list[str]:
        self._ensure_loaded()
        assert self._feature_columns is not None
        return self._feature_columns

    @property
    def classes(self) -> list[int]:
        self._ensure_loaded()
        assert self._classes is not None
        return self._classes

    @property
    def repo(self) -> SqliteRepo:
        return self._repo

    def _ensure_loaded(self) -> None:
        if self._model is not None:
            return
        with self._lock:
            if self._model is not None:
                return
            if not self._model_path.exists():
                raise FileNotFoundError(
                    f"Model file missing: {self._model_path}. Train it with "
                    "`python -m ml_pipeline.src.training.train_model`."
                )
            if not self._feature_columns_path.exists():
                raise FileNotFoundError(
                    f"Feature columns missing: {self._feature_columns_path}"
                )
            self._model = joblib.load(self._model_path)
            with self._feature_columns_path.open() as f:
                cols = json.load(f)
            # feature_columns.json may be a bare list or {"feature_columns": [...]}.
            if isinstance(cols, dict):
                cols = cols.get("feature_columns", [])
            self._feature_columns = list(cols)
            self._classes = [int(c) for c in self._model.classes_]
            if set(self._classes) != {0, 1, 2}:
                raise ValueError(
                    "Expected a three-class model with classes {0, 1, 2} "
                    f"(low/moderate/high); got {sorted(self._classes)}. Retrain "
                    "with `python -m ml_pipeline.src.training.train_model`."
                )
            self._load_thresholds()
            self._load_drug_risk()

    def _load_thresholds(self) -> None:
        """Load the safety-oriented decision thresholds persisted alongside the
        model (``model_meta.json`` key ``decision_thresholds``). Defaults are
        used when the file or key is absent."""
        meta_path = self._model_path.with_name("model_meta.json")
        if not meta_path.exists():
            return
        try:
            meta = json.loads(meta_path.read_text())
        except (ValueError, OSError):
            return
        thresholds = meta.get("decision_thresholds") or {}
        self._high_threshold = float(thresholds.get("high", self._high_threshold))
        self._low_threshold = float(thresholds.get("low", self._low_threshold))

    def _load_drug_risk(self) -> None:
        """Load the per-drug high-tier-rate lookup used for the risk features:
        how often each drug participates in a HIGH-tier (major/contraindicated)
        interaction, estimated from the training split. Missing file is
        non-fatal: risk features fall back to the global mean (0.0), which
        simply weakens predictions rather than breaking them."""
        if not self._drug_risk_path.exists():
            self._drug_risk = {}
            self._global_risk = 0.0
            return
        with self._drug_risk_path.open() as f:
            payload = json.load(f)
        self._drug_risk = {
            str(k): float(v) for k, v in payload.get("drug_risk", {}).items()
        }
        self._global_risk = float(
            payload.get("global_high_rate", payload.get("global_dangerous_rate", 0.0))
        )

    def predict(
        self, drug_a_drugbank_id: str, drug_b_drugbank_id: str
    ) -> dict[str, Any]:
        self._ensure_loaded()
        drug_a = self._repo.get_drug_by_drugbank_id(drug_a_drugbank_id)
        drug_b = self._repo.get_drug_by_drugbank_id(drug_b_drugbank_id)
        if drug_a is None:
            raise ValueError(f"Unknown DrugBank id: {drug_a_drugbank_id}")
        if drug_b is None:
            raise ValueError(f"Unknown DrugBank id: {drug_b_drugbank_id}")

        feature_map, feature_explanations = self._build_features(drug_a, drug_b)
        # Assemble the vector strictly in feature_columns order (order-safe).
        feature_values = [
            float(feature_map.get(name, 0.0)) for name in self.feature_columns
        ]
        x = np.array([feature_values], dtype=np.float32)
        probabilities = self._model.predict_proba(x)[0]
        classes = list(self._classes)
        p_low = float(probabilities[classes.index(0)])
        p_high = float(probabilities[classes.index(2)])
        # Safety-oriented decision rule (thresholds in model_meta.json):
        #   * flag HIGH whenever P(high) clears a sensitivity threshold (< 0.5,
        #     because a missed serious interaction is the costliest error);
        #   * only call a pair LOW when the model is highly confident — otherwise
        #     default to MODERATE rather than give false reassurance.
        if p_high >= self._high_threshold:
            predicted_int = 2
        elif p_low >= self._low_threshold:
            predicted_int = 0
        else:
            predicted_int = 1
        confidence = float(probabilities[classes.index(predicted_int)])

        result: dict[str, Any] = {
            "features_used": dict(
                zip(self.feature_columns, [float(v) for v in feature_values])
            ),
            "explanation": feature_explanations,
            "drugs": {
                "a": {
                    "drugbank_id": drug_a["drugbank_id"],
                    "name": drug_a["name"],
                    "atc_code": drug_a.get("atc_code"),
                },
                "b": {
                    "drugbank_id": drug_b["drugbank_id"],
                    "name": drug_b["name"],
                    "atc_code": drug_b.get("atc_code"),
                },
            },
        }

        # Single three-class path: low / moderate / high.
        # `risk_probability` is P(HIGH tier), the headline number the UI uses to
        # decide how loudly to warn. `severity` mirrors `risk_level` on the wire
        # because the reference DB's column is named `severity`.
        high_idx = list(self._classes).index(2)
        high_prob = float(probabilities[high_idx])
        risk_level = RISK_LABELS.get(predicted_int, "unknown")
        result.update(
            {
                "severity": risk_level,
                "risk_level": risk_level,
                "severity_int": predicted_int,
                "risk_probability": round(high_prob, 4),
                "confidence": round(confidence, 4),
                "probabilities": {
                    RISK_LABELS.get(int(c), str(c)): round(float(p), 4)
                    for c, p in zip(self._classes, probabilities)
                },
            }
        )
        return result

    # ── Feature engineering (mirrors the training pipeline) ─────────────────

    def _ensure_feature_meta(self) -> None:
        """Load the enzyme index, PD-class table and narrow-TI list saved next to
        the model, so the backend computes the same 27 features as training."""
        if getattr(self, "_feat_meta_loaded", False):
            return
        base = self._model_path.parent

        def _load(name, default):
            p = base / name
            try:
                return json.loads(p.read_text()) if p.exists() else default
            except (ValueError, OSError):
                return default

        self._enzyme_bit = {str(k): int(v) for k, v in _load("enzyme_index.json", {}).items()}
        pd_meta = _load("pd_class_meta.json", {})
        self._pd_groups = list(pd_meta.get("groups", []))
        self._pd_prefixes = {k: list(v) for k, v in pd_meta.get("atc_prefixes", {}).items()}
        self._pd_keywords = {k: list(v) for k, v in pd_meta.get("name_keywords", {}).items()}
        self._nti = set(_load("nti_list.json", []))
        self._feat_meta_loaded = True

    def _pd_mask(self, drug: dict[str, Any]) -> int:
        codes: list[str] = []
        primary = (drug.get("atc_code") or "").strip()
        if primary:
            codes.append(primary)
        allc = drug.get("all_atc_codes") or ""
        if allc:
            codes.extend(c for c in re.split(r"[|,;\s]+", allc) if c)
        name = (drug.get("name") or "").lower()
        mask = 0
        for gi, g in enumerate(self._pd_groups):
            hit = any(c.startswith(p) for c in codes for p in self._pd_prefixes.get(g, []))
            if not hit and g in self._pd_keywords:
                hit = any(k in name for k in self._pd_keywords[g])
            if hit:
                mask |= (1 << gi)
        return mask

    def _build_features(
        self, drug_a: dict[str, Any], drug_b: dict[str, Any]
    ) -> tuple[dict[str, float], list[str]]:
        self._ensure_feature_meta()
        pc = getattr(int, "bit_count", None) or (lambda x: bin(x).count("1"))

        atc_a = (drug_a.get("atc_code") or "").strip()
        atc_b = (drug_b.get("atc_code") or "").strip()
        atc_overlap = {
            n: 1.0 if atc_a[:n] and atc_a[:n] == atc_b[:n] else 0.0
            for n in (1, 3, 4, 5)
        }
        atc_missing = 1.0 if (not atc_a or not atc_b) else 0.0

        def _masks(drug_id: int) -> tuple[int, int, int]:
            sub = inh = ind = 0
            for enzyme, acts in self._repo.metabolism_for_drug(drug_id).items():
                bit_i = self._enzyme_bit.get(enzyme)
                if bit_i is None:
                    continue
                bit = 1 << bit_i
                if "substrate" in acts:
                    sub |= bit
                if "inhibitor" in acts:
                    inh |= bit
                if "inducer" in acts:
                    ind |= bit
            return sub, inh, ind

        sub_a, inh_a, ind_a = _masks(drug_a["id"])
        sub_b, inh_b, ind_b = _masks(drug_b["id"])
        shared_cyp_count = float(pc(sub_a & sub_b))
        inhibitor_substrate_count = float(pc(inh_a & sub_b) + pc(inh_b & sub_a))
        inducer_substrate_count = float(pc(ind_a & sub_b) + pc(ind_b & sub_a))

        cats_a = set(self._repo.categories_for_drug(drug_a["id"]))
        cats_b = set(self._repo.categories_for_drug(drug_b["id"]))
        category_overlap = float(len(cats_a & cats_b))

        type_a = drug_a.get("drug_type") or ""
        type_b = drug_b.get("drug_type") or ""
        drug_type_match = 1.0 if type_a and type_a == type_b else 0.0

        half_life_a = _parse_half_life(drug_a.get("half_life"))
        half_life_b = _parse_half_life(drug_b.get("half_life"))
        if half_life_a and half_life_b and half_life_a > 0 and half_life_b > 0:
            half_life_ratio = float(math.log(max(half_life_a, half_life_b) / min(half_life_a, half_life_b)))
            half_life_missing = 0.0
        else:
            half_life_ratio = 0.0
            half_life_missing = 1.0

        mask_a = self._pd_mask(drug_a)
        mask_b = self._pd_mask(drug_b)

        def _both(g: str) -> float:
            i = self._pd_groups.index(g) if g in self._pd_groups else -1
            return 1.0 if i >= 0 and (mask_a >> i) & 1 and (mask_b >> i) & 1 else 0.0

        def _in(mask: int, g: str) -> int:
            i = self._pd_groups.index(g) if g in self._pd_groups else -1
            return (mask >> i) & 1 if i >= 0 else 0

        bleed_a = _in(mask_a, "anticoagulant") + _in(mask_a, "antiplatelet") + _in(mask_a, "nsaid")
        bleed_b = _in(mask_b, "anticoagulant") + _in(mask_b, "antiplatelet") + _in(mask_b, "nsaid")
        bleeding = 1.0 if bleed_a >= 1 and bleed_b >= 1 else 0.0

        name_a = (drug_a.get("name") or "").lower()
        name_b = (drug_b.get("name") or "").lower()
        nti_a = 1 if any(k in name_a for k in self._nti) else 0
        nti_b = 1 if any(k in name_b for k in self._nti) else 0

        risk_a = self._drug_risk.get(str(drug_a.get("drugbank_id")), self._global_risk)
        risk_b = self._drug_risk.get(str(drug_b.get("drugbank_id")), self._global_risk)

        features: dict[str, float] = {
            "atc_overlap_1": atc_overlap[1],
            "atc_overlap_3": atc_overlap[3],
            "atc_overlap_4": atc_overlap[4],
            "atc_overlap_5": atc_overlap[5],
            "atc_missing_either": atc_missing,
            "shared_cyp_count": shared_cyp_count,
            "inhibitor_substrate_count": inhibitor_substrate_count,
            "inducer_substrate_count": inducer_substrate_count,
            "both_substrates": 1.0 if shared_cyp_count > 0 else 0.0,
            "inhibitor_substrate": 1.0 if inhibitor_substrate_count > 0 else 0.0,
            "inducer_substrate": 1.0 if inducer_substrate_count > 0 else 0.0,
            "category_overlap": category_overlap,
            "drug_type_match": drug_type_match,
            "half_life_ratio": half_life_ratio,
            "half_life_missing": half_life_missing,
            "both_qt_prolong": _both("qt_prolong"),
            "both_serotonergic": _both("serotonergic"),
            "both_cns_depressant": _both("cns_depressant"),
            "both_nephrotoxic": _both("nephrotoxic"),
            "bleeding_risk_combo": bleeding,
            "nti_either": float(nti_a | nti_b),
            "nti_both": float(nti_a & nti_b),
            "drug_risk_a": risk_a,
            "drug_risk_b": risk_b,
            "drug_risk_prod": risk_a * risk_b,
            "drug_risk_max": max(risk_a, risk_b),
            "drug_risk_min": min(risk_a, risk_b),
        }

        explanations: list[str] = []
        if max(risk_a, risk_b) >= max(self._global_risk * 1.5, 0.35):
            explanations.append(
                f"Drug-level risk profile is elevated (risk_a={risk_a:.2f}, "
                f"risk_b={risk_b:.2f}; baseline {self._global_risk:.2f})."
            )
        if shared_cyp_count:
            explanations.append(
                f"Share {int(shared_cyp_count)} metabolic enzyme(s); "
                f"inhibitor→substrate cascades={int(inhibitor_substrate_count)}, "
                f"inducer→substrate cascades={int(inducer_substrate_count)}."
            )
        pd_labels = {
            "both_qt_prolong": "both drugs prolong the QT interval",
            "both_serotonergic": "both drugs are serotonergic",
            "both_cns_depressant": "both drugs depress the CNS",
            "both_nephrotoxic": "both drugs are nephrotoxic",
        }
        for key, label in pd_labels.items():
            if features[key]:
                explanations.append(f"Additive pharmacodynamics: {label}.")
        if bleeding:
            explanations.append(
                "Combined bleeding risk: both drugs affect coagulation "
                "(anticoagulant / antiplatelet / NSAID)."
            )
        if nti_a and nti_b:
            explanations.append("Both drugs have a narrow therapeutic index.")
        elif nti_a or nti_b:
            explanations.append("One drug has a narrow therapeutic index.")
        if category_overlap:
            explanations.append(
                f"Share {int(category_overlap)} therapeutic category(ies)."
            )
        if any(v for v in atc_overlap.values()):
            shared_depth = max(n for n, v in atc_overlap.items() if v)
            explanations.append(
                f"ATC overlap at first {shared_depth} characters."
            )
        if drug_type_match:
            explanations.append("Drugs share a molecular type.")
        if not explanations:
            explanations.append(
                "No structural overlap detected; prediction inferred from the "
                "model's learned distribution."
            )
        return features, explanations


def _parse_half_life(raw: object) -> float | None:
    """Mirrors ``_half_life_hours`` in the training pipeline and the Dart
    ``_parseHalfLife``: parse a single value or a low–high range, average it,
    and normalise minutes/days to hours."""
    if not isinstance(raw, str) or not raw:
        return None
    text = raw.lower()
    m = re.search(r"(\d+(?:\.\d+)?)(?:\s*[-–]\s*(\d+(?:\.\d+)?))?", text)
    if not m:
        return None
    low = float(m.group(1))
    high = float(m.group(2)) if m.group(2) else low
    avg = (low + high) / 2
    if "min" in text:
        return avg / 60
    if "day" in text:
        return avg * 24
    return avg