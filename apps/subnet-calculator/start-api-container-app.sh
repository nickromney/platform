#!/bin/bash
#
# Start Container App API for SWA CLI Stack 4
#

cd "$(dirname "$0")/api-fastapi-container-app" || exit 1

echo "Starting Container App API on port 8000..."
uv run uvicorn app.main:app --reload --port 8000
