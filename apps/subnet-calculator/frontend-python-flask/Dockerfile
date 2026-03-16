# Stage 1: Builder - Install dependencies
FROM dhi.io/python:3.13-debian13-dev AS builder

WORKDIR /app

# Install uv
COPY --from=ghcr.io/astral-sh/uv:0.10.4 /uv /usr/local/bin/uv

# Copy dependency files
COPY pyproject.toml uv.lock ./

# Create virtual environment and install dependencies (production only)
RUN uv sync --frozen --no-cache --no-dev --no-install-project

# Stage 2: Runtime - Copy only what's needed
FROM dhi.io/python:3.13-debian13

WORKDIR /app

ENV PATH="/app/.venv/bin:/opt/python/bin:$PATH"
ENV PYTHONUNBUFFERED=1

# Copy virtual environment from builder
COPY --chown=nonroot:nonroot --from=builder /app/.venv /app/.venv

# Copy application files
COPY --chown=nonroot:nonroot app.py ./
COPY --chown=nonroot:nonroot auth.py ./
COPY --chown=nonroot:nonroot templates/ ./templates/
COPY --chown=nonroot:nonroot static/ ./static/

# Expose port
EXPOSE 8000

USER nonroot

# Run with Gunicorn (production WSGI server)
CMD ["/app/.venv/bin/gunicorn", "--bind", "0.0.0.0:8000", "--workers", "4", "app:app"]
