#!/bin/bash
#
# Start Azure Function API for SWA CLI Stack 5
#

cd "$(dirname "$0")/api-fastapi-azure-function" || exit 1

echo "Starting Azure Function API on port 7071..."
uv run func start
