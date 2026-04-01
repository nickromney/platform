#!/bin/bash
#
# Start Container App API for SWA CLI Stack 4
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
  cat <<EOF
Usage: start-api-container-app.sh [--dry-run] [--execute]

Start the local Container App API for subnet-calculator development.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage "would start the subnet-calculator Container App API on port 8000" "$@"

cd "${SCRIPT_DIR}/api-fastapi-container-app" || exit 1

echo "Starting Container App API on port 8000..."
uv run uvicorn app.main:app --reload --port 8000
