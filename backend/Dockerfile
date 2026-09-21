# syntax=docker/dockerfile:1.7
FROM python:3.11-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=on \
    PIP_NO_CACHE_DIR=on

# Render injects the listening port via $PORT; default for local docker run.
ENV PORT=8000 \
    GUNICORN_WORKERS=2 \
    GUNICORN_TIMEOUT=60

WORKDIR /srv/medguard

# 1. Dependencies first, so a source change does not reinstall them.
COPY backend/requirements.txt /srv/medguard/backend/requirements.txt
RUN pip install --upgrade pip \
 && pip install -r /srv/medguard/backend/requirements.txt

# 2. The API source.
COPY backend /srv/medguard/backend

# 3. The clinical database and the served model, straight from the repository.
#    Build from the repository root: docker build -f backend/Dockerfile .
COPY mobile/assets/db/medguard.db /srv/medguard/artifacts/medguard.db
COPY ml_pipeline/models/bundled_db/ /srv/medguard/artifacts/

ENV MEDGUARD_DB_PATH=/srv/medguard/artifacts/medguard.db \
    MEDGUARD_MODEL_DIR=/srv/medguard/artifacts \
    PYTHONPATH=/srv/medguard

EXPOSE 8000

# 4. Fill in any missing artefacts, then exec gunicorn on $PORT, so the same
#    image runs on Render and locally.
CMD ["python", "-m", "backend.entrypoint"]
