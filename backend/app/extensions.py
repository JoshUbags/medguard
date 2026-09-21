"""Shared Flask extension instances.

The limiter is created here (without an app) so route modules can decorate
their views with ``@limiter.limit(...)`` at import time; ``init_app`` binds it
to the real application inside the factory.
"""

from __future__ import annotations

from flask_limiter import Limiter
from flask_limiter.util import get_remote_address

limiter = Limiter(key_func=get_remote_address, headers_enabled=True)
