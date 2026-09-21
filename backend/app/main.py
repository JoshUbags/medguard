"""Entry-point Gunicorn binds to in production (`gunicorn app.main:app`).
The factory itself lives in `backend.app.__init__:create_app`.
"""

from . import create_app

app = create_app()


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(__import__("os").environ.get("PORT", 8000)))
