"""Optionally fetch the API's runtime artefacts from URLs at boot.

The Docker image already contains the clinical database and the served model,
copied in from the repository, so normally there is nothing to do: anything
already present on disk is left alone and this is a no-op.

The variables exist for deployments that supply the artefacts some other way,
for example a slimmer image with a mounted disk. Each fills in a file only if
it is missing:

* ``MEDGUARD_DB_URL``            → downloaded to ``MEDGUARD_DB_PATH``
* ``MEDGUARD_MODEL_BUNDLE_URL``  → a .tar.gz unpacked beside ``MEDGUARD_MODEL_PATH``
  (rf_severity_model.joblib, feature_columns.json, drug_risk_lookup.json,
  model_meta.json, enzyme_index.json, pd_class_meta.json, nti_list.json)

Standard library only: this runs before the app imports.
"""

from __future__ import annotations

import os
import sys
import tarfile
import tempfile
import urllib.request
from pathlib import Path

_CHUNK = 1 << 20


def _log(message: str) -> None:
    print(f"[fetch-artifacts] {message}", file=sys.stderr, flush=True)


def _download(url: str, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    tmp = destination.with_suffix(destination.suffix + ".part")
    with urllib.request.urlopen(url) as response:  # noqa: S310 — operator-supplied
        with tmp.open("wb") as handle:
            while chunk := response.read(_CHUNK):
                handle.write(chunk)
    tmp.replace(destination)
    _log(f"wrote {destination} ({destination.stat().st_size / 1e6:.1f} MB)")


def _extract(archive: Path, target: Path) -> None:
    target.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive) as tar:
        try:
            tar.extractall(target, filter="data")
        except TypeError:  # Python < 3.11.4 has no extraction filter
            tar.extractall(target)  # noqa: S202 — operator-supplied archive
    _log(f"unpacked model bundle into {target}")


def fetch_all() -> None:
    db_url = os.environ.get("MEDGUARD_DB_URL")
    db_path = Path(
        os.environ.get("MEDGUARD_DB_PATH", "/srv/medguard/artifacts/medguard.db")
    )
    if db_url and not (db_path.exists() and db_path.stat().st_size > 0):
        _log("downloading clinical database")
        _download(db_url, db_path)
    elif db_path.exists():
        _log(f"clinical database already present at {db_path}")

    bundle_url = os.environ.get("MEDGUARD_MODEL_BUNDLE_URL")
    model_path = Path(
        os.environ.get(
            "MEDGUARD_MODEL_PATH", "/srv/medguard/artifacts/rf_severity_model.joblib"
        )
    )
    if bundle_url and not model_path.exists():
        _log("downloading model bundle")
        with tempfile.TemporaryDirectory() as tmpdir:
            archive = Path(tmpdir) / "model_bundle.tar.gz"
            _download(bundle_url, archive)
            _extract(archive, model_path.parent)
    elif model_path.exists():
        _log(f"model already present at {model_path}")

    if not db_path.exists():
        _log("no clinical database — /api/v1/db/* will answer 503")
    if not model_path.exists():
        _log("no model — /api/v1/predict will answer 503")


if __name__ == "__main__":
    fetch_all()
