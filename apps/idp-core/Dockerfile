# syntax=docker/dockerfile:1.7

FROM dhi.io/python:3.13-debian13-dev AS builder

COPY --from=ghcr.io/astral-sh/uv:0.10.4 /uv /usr/local/bin/uv

WORKDIR /app

COPY apps/idp-core/pyproject.toml apps/idp-core/uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --link-mode=copy --no-dev --no-install-project

FROM dhi.io/python:3.13-debian13

WORKDIR /app

ENV PATH="/app/.venv/bin:/opt/python/bin:$PATH" \
    HOME=/tmp \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    IDP_CATALOG_PATH=/app/catalog/platform-apps.json

COPY --chown=65532:65532 --from=builder /app/.venv /app/.venv
COPY --chown=65532:65532 apps/idp-core/app ./app
COPY --chown=65532:65532 catalog/platform-apps.json ./catalog/platform-apps.json

EXPOSE 8080

USER 65532:65532

CMD ["/app/.venv/bin/uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
