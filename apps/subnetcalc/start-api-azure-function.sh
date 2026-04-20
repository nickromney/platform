#!/bin/bash
#
# Start Azure Function API for SWA CLI Stack 5
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
  cat <<EOF
Usage: start-api-azure-function.sh [--dry-run] [--execute]

Start the local Azure Function API for subnetcalc development.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage "would start the subnetcalc Azure Function API on port 7071" "$@"

cd "${SCRIPT_DIR}/api-fastapi-azure-function" || exit 1

echo "Starting Azure Function API on port 7071..."
uv run func start
