"""Export the on-device TFLite model by knowledge distillation.

A scikit-learn Random Forest cannot convert to TFLite, so a compact Keras MLP is
trained to reproduce the deployed forest's **soft predictions** (predict_proba) —
genuine knowledge distillation — then exported as a quantised TFLite buffer and
bundled with the Flutter app. Requires TensorFlow (`pip install tensorflow`).

Run after `train_model random`:

    python -m ml_pipeline.src.inference.convert_tflite
"""

from __future__ import annotations

import json
import shutil
from pathlib import Path

import joblib
import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[3]
INTERIM = ROOT / "ml_pipeline" / "data" / "interim" / "retrain" / "random"
MODELS = ROOT / "ml_pipeline" / "models"
ASSET = ROOT / "mobile" / "assets" / "ml"
HIGH_THR, LOW_THR = 0.40, 0.75  # keep in sync with model_meta.json


def _rule(p, th=HIGH_THR, tl=LOW_THR):
    o = np.ones(len(p), int); o[p[:, 0] >= tl] = 0; o[p[:, 2] >= th] = 2; return o


def main() -> None:
    import tensorflow as tf

    cols = json.loads((MODELS / "feature_columns.json").read_text())
    rf = joblib.load(MODELS / "rf_severity_model.joblib")
    tr = pd.read_parquet(INTERIM / "train.parquet")
    va = pd.read_parquet(INTERIM / "val.parquet")
    Xtr = tr[cols].to_numpy("float32"); Xva = va[cols].to_numpy("float32")
    tier = {0: 0, 1: 1, 2: 2, 3: 2}
    yva = np.vectorize(tier.get)(va["severity_int"].to_numpy()).astype(int)

    soft = rf.predict_proba(Xtr).astype("float32")  # teacher targets (distillation)

    student = tf.keras.Sequential([
        tf.keras.layers.Input(shape=(len(cols),)),
        tf.keras.layers.Dense(64, activation="relu"),
        tf.keras.layers.Dropout(0.2),
        tf.keras.layers.Dense(32, activation="relu"),
        tf.keras.layers.Dense(3, activation="softmax"),
    ])
    student.compile(optimizer="adam", loss="categorical_crossentropy")
    student.fit(Xtr, soft, validation_split=0.1, epochs=30, batch_size=256, verbose=2)
    student.save(MODELS / "severity_mlp.keras")

    conv = tf.lite.TFLiteConverter.from_keras_model(student)
    conv.optimizations = [tf.lite.Optimize.DEFAULT]
    tfl = conv.convert()
    (MODELS / "severity_mlp.tflite").write_bytes(tfl)

    ASSET.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(MODELS / "severity_mlp.tflite", ASSET / "severity_mlp.tflite")
    (ASSET / "feature_columns.json").write_text(json.dumps({"feature_columns": cols, "classes": [0, 1, 2]}))
    for meta in ("drug_risk_lookup.json", "enzyme_index.json", "pd_class_meta.json", "nti_list.json"):
        if (MODELS / meta).exists():
            shutil.copyfile(MODELS / meta, ASSET / meta)

    from sklearn.metrics import recall_score
    rf_pred = _rule(rf.predict_proba(Xva))
    mlp_pred = _rule(student.predict(Xva, verbose=0))
    report = {
        "n_features": len(cols),
        "tflite_bytes": (MODELS / "severity_mlp.tflite").stat().st_size,
        "distillation": "soft-label (student trained on RF predict_proba)",
        "agreement_rf_mlp_with_rule": round(float((rf_pred == mlp_pred).mean()), 4),
        "mlp_high_recall_with_rule": round(float(recall_score(yva, mlp_pred, labels=[2], average=None, zero_division=0)[0]), 4),
    }
    (MODELS / "parity_report.json").write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
