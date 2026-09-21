import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
# Add the repo root so ``import backend.app`` works without installing.
sys.path.insert(0, str(ROOT))

# The served model's files all live together; see backend/app/__init__.py.
MODEL_DIR = ROOT / "ml_pipeline" / "models" / "bundled_db"

os.environ.setdefault(
    "MEDGUARD_DB_PATH", str(ROOT / "mobile" / "assets" / "db" / "medguard.db")
)
os.environ.setdefault("MEDGUARD_MODEL_PATH", str(MODEL_DIR / "rf_severity_model.joblib"))
os.environ.setdefault("MEDGUARD_FEATURES_PATH", str(MODEL_DIR / "feature_columns.json"))
os.environ.setdefault("MEDGUARD_DRUG_RISK_PATH", str(MODEL_DIR / "drug_risk_lookup.json"))
