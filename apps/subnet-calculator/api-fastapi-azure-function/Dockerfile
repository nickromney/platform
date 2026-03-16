# Stage 1: Builder - Install dependencies
FROM mcr.microsoft.com/azure-functions/python:4-python3.11 AS builder

WORKDIR /app

# Install uv
COPY --from=ghcr.io/astral-sh/uv:0.10.4 /uv /usr/local/bin/uv

# Copy dependency files
COPY pyproject.toml uv.lock ./

# Create virtual environment and install dependencies with uv (production only)
RUN uv sync --frozen --no-cache --no-dev --no-install-project

# Stage 2: Runtime - Copy only what's needed
FROM mcr.microsoft.com/azure-functions/python:4-python3.11

ENV AzureWebJobsScriptRoot=/home/site/wwwroot \
    AzureFunctionsJobHost__Logging__Console__IsEnabled=true \
    WEBSITES_PORT=8080 \
    ASPNETCORE_URLS=http://+:8080 \
    PYTHONUNBUFFERED=1 \
    PATH="/app/.venv/bin:$PATH"

# Copy virtual environment from builder
COPY --chown=app:app --from=builder /app/.venv /app/.venv

# Copy application files (excludes tests, docs, etc. per .dockerignore)
COPY --chown=app:app . /home/site/wwwroot

EXPOSE 8080

USER app
