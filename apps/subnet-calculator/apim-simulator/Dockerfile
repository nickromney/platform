FROM dhi.io/python:3.13-debian13-dev AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY --from=ghcr.io/astral-sh/uv:0.10.4 /uv /usr/local/bin/uv

COPY pyproject.toml uv.lock ./

RUN uv sync --frozen --no-cache --no-dev --no-install-project

FROM dhi.io/python:3.13-debian13

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/app/.venv/bin:/opt/python/bin:$PATH" \
    PORT=8000

WORKDIR /app

COPY --chown=nonroot:nonroot --from=builder /app/.venv /app/.venv
COPY --chown=nonroot:nonroot app ./app
COPY --chown=nonroot:nonroot config ./config

EXPOSE 8000

USER nonroot

CMD ["/app/.venv/bin/uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
