"""Container entry point: fill in any missing artefacts, then start gunicorn.

Deliberately Python rather than a shell script — a `.sh` checked out on Windows
can carry CRLF line endings and fail in the image with a confusing
"exec format error".

A failed fetch never blocks start-up: the service comes up, `/api/health`
answers 200 so the platform's health check passes, and the endpoints that need
the missing artefact answer 503 with a clear message.
"""

from __future__ import annotations

import os
import sys


def main() -> None:
    try:
        from backend.fetch_artifacts import fetch_all

        fetch_all()
    except Exception as exc:  # noqa: BLE001 — never block boot on a fetch
        print(f"[entrypoint] artefact fetch failed: {exc}", file=sys.stderr)

    port = os.environ.get("PORT", "8000")
    workers = os.environ.get("GUNICORN_WORKERS", "2")
    timeout = os.environ.get("GUNICORN_TIMEOUT", "60")
    argv = [
        "gunicorn",
        "--bind",
        f"0.0.0.0:{port}",
        "--workers",
        workers,
        "--timeout",
        timeout,
        "backend.app.main:app",
    ]
    print(f"[entrypoint] exec {' '.join(argv)}", file=sys.stderr, flush=True)
    os.execvp("gunicorn", argv)


if __name__ == "__main__":
    main()
