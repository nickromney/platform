#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

fail() { echo "FAIL $*" >&2; exit 1; }
ok() { echo "OK   $*"; }

usage() {
  cat <<'EOF'
Usage: check-rbac.sh

Checks the stage-900 demo RBAC model with kubectl auth can-i.
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi
  fail "Unknown argument: $1"
done

shell_cli_maybe_execute_or_preview_summary usage "would check platform RBAC with kubectl auth can-i"

command -v kubectl >/dev/null 2>&1 || fail "kubectl not found in PATH"
kubectl get namespaces >/dev/null

ADMIN_USER="${PLATFORM_RBAC_ADMIN_USER:-demo@admin.test}"
VIEWER_USER="${PLATFORM_RBAC_VIEWER_USER:-demo@dev.test}"
ADMIN_GROUP="${PLATFORM_RBAC_ADMIN_GROUP:-platform-admins}"
VIEWER_GROUP="${PLATFORM_RBAC_VIEWER_GROUP:-platform-viewers}"

can_i() {
  local expected="$1"
  shift
  local output
  output="$(kubectl auth can-i "$@" 2>/dev/null || true)"
  if [[ "${output}" == "${expected}" ]]; then
    ok "kubectl auth can-i $* -> ${expected}"
    return 0
  fi
  fail "kubectl auth can-i $* -> ${output:-<empty>}; expected ${expected}"
}

can_i yes '*' '*' --as="${ADMIN_USER}" --as-group="${ADMIN_GROUP}"
can_i yes get pods -n dev --as="${VIEWER_USER}" --as-group="${VIEWER_GROUP}"
can_i yes list deployments.apps -n uat --as="${VIEWER_USER}" --as-group="${VIEWER_GROUP}"
can_i no delete pods -n dev --as="${VIEWER_USER}" --as-group="${VIEWER_GROUP}"
can_i no create deployments.apps -n uat --as="${VIEWER_USER}" --as-group="${VIEWER_GROUP}"
