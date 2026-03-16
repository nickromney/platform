# Stage 1: Build dependencies
FROM dhi.io/python:3.13-debian13-dev AS builder

# Install uv for fast dependency management
COPY --from=ghcr.io/astral-sh/uv:0.10.4 /uv /usr/local/bin/uv

# Set working directory
WORKDIR /app

# Copy dependency files
COPY pyproject.toml uv.lock ./

# Install dependencies to /app/.venv
RUN uv sync --frozen --no-cache --no-dev --no-install-project

# Stage 2: Runtime
FROM dhi.io/python:3.13-debian13

# Set working directory
WORKDIR /app

ENV PATH="/app/.venv/bin:/opt/python/bin:$PATH"
ENV PYTHONUNBUFFERED=1

# Copy virtual environment from builder
COPY --chown=nonroot:nonroot --from=builder /app/.venv /app/.venv

# Copy application code
COPY --chown=nonroot:nonroot app ./app

# Expose port
EXPOSE 8000

USER nonroot

# Run Uvicorn ASGI server
CMD ["/app/.venv/bin/uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
