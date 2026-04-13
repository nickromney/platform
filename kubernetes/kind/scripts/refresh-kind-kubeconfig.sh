#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
  cat <<'EOF'
Usage: refresh-kind-kubeconfig.sh [--dry-run] [--execute]

Purpose:
  Refresh the split kind kubeconfig using the existing ensure-kind-kubeconfig
  helper while preserving the current merge policy and kubeconfig env.
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

ensure_kind_kubeconfig_script="${ENSURE_KIND_KUBECONFIG_SCRIPT:-${SCRIPT_DIR}/ensure-kind-kubeconfig.sh}"

shell_cli_handle_standard_no_args usage \
  "would refresh the split kind kubeconfig via ensure-kind-kubeconfig" \
  "$@"

"${ensure_kind_kubeconfig_script}" --execute
