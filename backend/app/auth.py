"""Request authentication via Firebase ID tokens.

The mobile app already signs users in with Firebase Auth. Every call to the
``/api/v1/*`` surface must carry that user's ID token as a
``Authorization: Bearer <token>`` header; this module verifies it server-side
with the Firebase Admin SDK and rejects anything unverified with 401.

Configuration (environment variables):
  MEDGUARD_AUTH_DISABLED=1     bypass auth — local development / unit tests only.
  MEDGUARD_FIREBASE_CREDENTIALS=/path/to/serviceAccountKey.json
                               service-account JSON used to verify tokens.
                               Falls back to GOOGLE_APPLICATION_CREDENTIALS /
                               application-default credentials when unset.
"""

from __future__ import annotations

import logging
import os

from flask import Flask, g, jsonify, request

logger = logging.getLogger("medguard.auth")

_OPEN_PATHS = ("/api/health", "/")
_firebase_ready = False


def _init_firebase() -> bool:
    """Initialise the Firebase Admin app once. Returns True when verification
    is available."""
    global _firebase_ready
    if _firebase_ready:
        return True
    try:
        import firebase_admin
        from firebase_admin import credentials

        if not firebase_admin._apps:  # noqa: SLF001 — documented public guard
            cred_path = os.environ.get("MEDGUARD_FIREBASE_CREDENTIALS")
            cred = (
                credentials.Certificate(cred_path)
                if cred_path
                else credentials.ApplicationDefault()
            )
            firebase_admin.initialize_app(cred)
        _firebase_ready = True
    except Exception:  # noqa: BLE001 — any failure means we can't verify
        logger.exception("Firebase Admin init failed; auth cannot verify tokens")
        _firebase_ready = False
    return _firebase_ready


def init_auth(app: Flask) -> None:
    """Register the before_request hook that guards the API surface."""
    disabled = app.config.get("TESTING") or os.environ.get(
        "MEDGUARD_AUTH_DISABLED"
    ) in ("1", "true", "True")
    app.config["AUTH_DISABLED"] = bool(disabled)
    if disabled:
        logger.warning(
            "Backend authentication is DISABLED — do not run like this in "
            "production. Set MEDGUARD_FIREBASE_CREDENTIALS and unset "
            "MEDGUARD_AUTH_DISABLED to enforce identity."
        )

    @app.before_request
    def _verify_identity():  # noqa: ANN202
        if app.config.get("AUTH_DISABLED"):
            g.actor_id = "dev-bypass"
            return None
        # Only the API surface is protected; health + index stay public.
        if request.path in _OPEN_PATHS or not request.path.startswith("/api/"):
            return None
        if request.method == "OPTIONS":  # CORS preflight
            return None

        header = request.headers.get("Authorization", "")
        if not header.startswith("Bearer "):
            return _unauthorized("Missing bearer token.")
        token = header[len("Bearer ") :].strip()

        if not _init_firebase():
            return (
                jsonify(
                    error="auth_unavailable",
                    message="Identity verification is not configured.",
                ),
                503,
            )
        try:
            from firebase_admin import auth as fb_auth

            decoded = fb_auth.verify_id_token(token)
        except Exception:  # noqa: BLE001 — invalid / expired / malformed token
            return _unauthorized("Invalid or expired token.")
        g.actor_id = decoded.get("uid", "unknown")
        return None


def _unauthorized(message: str):  # noqa: ANN202
    return jsonify(error="unauthorized", message=message), 401
