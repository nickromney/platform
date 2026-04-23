# syntax=docker/dockerfile:1.7

# Stage 1: Builder - Install dependencies
FROM dhi.io/python:3.13-debian13-dev AS builder

WORKDIR /app

# Install uv
COPY --from=ghcr.io/astral-sh/uv:0.10.4 /uv /usr/local/bin/uv

# Copy dependency files
COPY pyproject.toml uv.lock ./

# Create virtual environment and install dependencies (production only)
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --link-mode=copy --no-dev --no-install-project

# Stage 2: Runtime - Copy only what's needed
FROM dhi.io/python:3.13-debian13

WORKDIR /app

ENV PATH="/app/.venv/bin:/opt/python/bin:$PATH"
ENV HOME=/tmp
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Copy virtual environment from builder
COPY --chown=65532:65532 --from=builder /app/.venv /app/.venv

# Copy application files
COPY --chown=65532:65532 app.py ./
COPY --chown=65532:65532 auth.py ./
COPY --chown=65532:65532 templates/ ./templates/
COPY --chown=65532:65532 static/ ./static/

# Expose port
EXPOSE 8000

USER 65532:65532

# Run with Gunicorn (production WSGI server)
CMD ["/app/.venv/bin/gunicorn", "--bind", "0.0.0.0:8000", "--workers", "4", "app:app"]
