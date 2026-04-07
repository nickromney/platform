FROM python:3.13-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY --from=ghcr.io/astral-sh/uv:0.10.4 /uv /usr/local/bin/uv

COPY pyproject.toml uv.lock ./

RUN uv sync --frozen --no-cache --no-dev --no-install-project

FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/app/.venv/bin:$PATH" \
    PORT=8000

RUN addgroup --system app && adduser --system --ingroup app --home /app app

WORKDIR /app

COPY --chown=app:app --from=builder /app/.venv /app/.venv
COPY --chown=app:app app ./app
COPY --chown=app:app examples ./examples

EXPOSE 8000

USER app

CMD ["sh", "-c", "/app/.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000} --no-access-log"]
