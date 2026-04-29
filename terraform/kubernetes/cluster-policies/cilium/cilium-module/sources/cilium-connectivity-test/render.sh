#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../../../../../../.." && pwd)}"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute]

Render the cilium-connectivity-test Cilium module source directory into its checked-in category output.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage \
  "would render the cilium-connectivity-test Cilium module category" \
  "$@"

exec "${SCRIPT_DIR}/../../render-category.sh" --execute --input "${SCRIPT_DIR}"
