"""Train, calibrate and evaluate the interaction-risk model on the full data.

Reads the feature matrices produced by ``build_features`` for a given evaluation
regime, trains RandomForest / HistGradientBoosting / calibrated LogisticRegression
on the full training split, selects the best on validation macro-F1 (RandomForest
preferred on a near-tie for interpretability), tunes the safety decision rule and
isotonically calibrates the HIGH-tier probability, and evaluates on the held-out
test split.

For the ``random`` (transductive) regime it also writes the *deployed* artefacts
the backend and app load: ``rf_severity_model.joblib``, ``model_meta.json`` and
``test_metrics.json``. For ``coldstart`` it writes ``cold_start_metrics.json``.

    python -m ml_pipeline.src.features.build_features random
    python -m ml_pipeline.src.features.build_features coldstart
    python -m ml_pipeline.src.training.train_model random
    python -m ml_pipeline.src.training.train_model coldstart
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.ensemble import HistGradientBoostingClassifier, RandomForestClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler
from sklearn.pipeline import make_pipeline
from sklearn.isotonic import IsotonicRegression
from sklearn.utils.class_weight import compute_sample_weight
from sklearn.metrics import (
    accuracy_score, f1_score, precision_recall_fscore_support,
    recall_score, roc_auc_score,
)

ROOT = Path(__file__).resolve().parents[3]
INTERIM = ROOT / "ml_pipeline" / "data" / "interim" / "retrain"
# Where the deployed artefacts are written. Overridable so a retrain on a
# different corpus (e.g. the bundled database) cannot overwrite the metrics the
# dissertation cites.
MODELS = Path(
    os.environ.get("MEDGUARD_MODELS_OUT", str(ROOT / "ml_pipeline" / "models"))
)
MODELS.mkdir(parents=True, exist_ok=True)
TIER = {0: 0, 1: 1, 2: 2, 3: 2}
RS = 42


def _load(regime):
    d = INTERIM / regime
    cols = json.loads((d / "feature_columns.json").read_text())
    out = {}
    for name in ("train", "val", "test"):
        df = pd.read_parquet(d / f"{name}.parquet")
        y = np.vectorize(TIER.get)(df["severity_int"].to_numpy()).astype(np.int8)
        out[name] = (df[cols].to_numpy(np.float32), y)
    return cols, out


def _ece(p, y, bins=10):
    e, edges = 0.0, np.linspace(0, 1, bins + 1)
    for i in range(bins):
        m = (p >= edges[i]) & (p < edges[i + 1]) if i < bins - 1 else (p >= edges[i]) & (p <= edges[i + 1])
        if m.sum():
            e += abs(y[m].mean() - p[m].mean()) * m.sum() / len(p)
    return float(e)


def _tune_rule(pva, yv):
    base = pva.argmax(1)
    bhr = recall_score(yv, base, labels=[2], average=None, zero_division=0)[0]
    bacc = accuracy_score(yv, base)
    best = None
    for th in (.30, .35, .40, .45, .50):
        for tl in (.55, .60, .65, .70, .75):
            pr = np.ones(len(pva), int); pr[pva[:, 0] >= tl] = 0; pr[pva[:, 2] >= th] = 2
            hr = recall_score(yv, pr, labels=[2], average=None, zero_division=0)[0]
            if hr >= bhr and accuracy_score(yv, pr) >= bacc - 0.002:
                mf = f1_score(yv, pr, average="macro")
                if best is None or mf > best[0]:
                    best = (mf, th, tl)
    return (best[1], best[2]) if best else (0.45, 0.65)


def _rule(p, th, tl):
    o = np.ones(len(p), int); o[p[:, 0] >= tl] = 0; o[p[:, 2] >= th] = 2; return o


def main(regime="random"):
    cols, D = _load(regime)
    (Xtr, ytr), (Xva, yva), (Xte, yte) = D["train"], D["val"], D["test"]
    print(f"[{regime}] train={Xtr.shape} val={Xva.shape} test={Xte.shape}", flush=True)

    sw = compute_sample_weight("balanced", ytr)
    models = {
        "RandomForest": RandomForestClassifier(n_estimators=300, max_depth=20, min_samples_leaf=20,
                                                class_weight="balanced", random_state=RS, n_jobs=-1).fit(Xtr, ytr),
        "HistGradientBoosting": HistGradientBoostingClassifier(learning_rate=0.1, max_iter=300, max_leaf_nodes=63,
                                                               min_samples_leaf=50, l2_regularization=1.0,
                                                               early_stopping=True, validation_fraction=0.1,
                                                               random_state=RS).fit(Xtr, ytr, sample_weight=sw),
        "LogisticRegression": make_pipeline(StandardScaler(), LogisticRegression(max_iter=300, class_weight="balanced")).fit(Xtr, ytr),
    }
    comp = {n: round(float(f1_score(yva, m.predict(Xva), average="macro")), 4) for n, m in models.items()}
    winner = "RandomForest" if comp["RandomForest"] >= comp["HistGradientBoosting"] - 0.005 else max(comp, key=comp.get)
    model = models[winner]
    print(f"[{regime}] comparison {comp} -> {winner}", flush=True)

    pva, pte = model.predict_proba(Xva), model.predict_proba(Xte)
    th, tl = _tune_rule(pva, yva)
    yp = _rule(pte, th, tl)
    pr, rc, f1, sup = precision_recall_fscore_support(yte, yp, labels=[0, 1, 2], zero_division=0)
    yb = np.eye(3)[yte]
    iso = IsotonicRegression(out_of_bounds="clip").fit(pva[:, 2], (yva == 2).astype(int))
    ph, yhi = pte[:, 2], (yte == 2).astype(int); phc = iso.transform(ph)
    yb1 = np.full_like(yte, 1)
    b = int(((yp == yte) & (yb1 != yte)).sum()); c = int(((yp != yte) & (yb1 == yte)).sum()); n = b + c
    res = {
        "regime": regime, "n_features": len(cols), "winner": winner,
        "train_rows": int(len(ytr)), "test_rows": int(len(yte)),
        "model_comparison_val_macro_f1": comp, "decision_thresholds": {"high": th, "low": tl},
        "accuracy": round(float(accuracy_score(yte, yp)), 4),
        "f1_macro": round(float(f1_score(yte, yp, average="macro")), 4),
        "auc_roc_macro_ovr": round(float(roc_auc_score(yb, pte, multi_class="ovr", average="macro")), 4),
        "per_tier": {["low", "moderate", "high"][k]: {
            "precision": round(float(pr[k]), 4), "recall": round(float(rc[k]), 4),
            "f1": round(float(f1[k]), 4), "support": int(sup[k])} for k in (0, 1, 2)},
        "high_recall": round(float(rc[2]), 4),
        "baseline_majority_accuracy": round(float((yb1 == yte).mean()), 4),
        "mcnemar_chi2": round(((abs(b - c) - 1) ** 2) / n, 1) if n else 0.0,
        "calibration_high_tier": {
            "brier_raw": round(float(np.mean((ph - yhi) ** 2)), 4),
            "brier_isotonic": round(float(np.mean((phc - yhi) ** 2)), 4),
            "ece_raw": round(_ece(ph, yhi), 4), "ece_isotonic": round(_ece(phc, yhi), 4)},
    }

    if regime == "random":
        # deployed artefacts the backend + app load
        joblib.dump(model, MODELS / "rf_severity_model.joblib", compress=3)
        (MODELS / "test_metrics.json").write_text(json.dumps(res, indent=2))
        if hasattr(model, "feature_importances_"):
            pd.DataFrame(sorted(zip(cols, model.feature_importances_), key=lambda z: -z[1]),
                         columns=["feature", "importance"]).to_csv(MODELS / "feature_importance.csv", index=False)
        (MODELS / "model_meta.json").write_text(json.dumps({
            "task": "triclass", "classes": [0, 1, 2],
            "labels": {"0": "low", "1": "moderate", "2": "high"},
            "tier_map": {"0": 0, "1": 1, "2": 2, "3": 2},
            "class_weight": "balanced", "winning_algorithm": winner,
            "n_features": len(cols), "decision_thresholds": {"high": th, "low": tl},
        }, indent=2))
    else:
        (MODELS / "cold_start_metrics.json").write_text(json.dumps(res, indent=2))
    print(json.dumps(res, indent=2))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "random")
