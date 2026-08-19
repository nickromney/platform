#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${REPO_ROOT:-}" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
fi

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

WAIT_ATTEMPTS="${WAIT_ATTEMPTS:-300}"
SLEEP_SECONDS="${SLEEP_SECONDS:-2}"

# shellcheck disable=SC2329 # invoked by name through the shell_cli_* helpers
usage() {
  cat <<'EOF' | sed "s|@SCRIPT_NAME@|${0##*/}|g"
Usage: @SCRIPT_NAME@ [--dry-run] [--execute]

Wait until a namespaced Deployment exists, then wait for its rollout.
Requires NAMESPACE, DEPLOYMENT, and ROLLOUT_TIMEOUT_SECONDS.
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

shell_cli_handle_standard_no_args usage "would wait for ${NAMESPACE:-<NAMESPACE>}/${DEPLOYMENT:-<DEPLOYMENT>}" "$@"

: "${KUBECONFIG:?KUBECONFIG is required}"
: "${NAMESPACE:?NAMESPACE is required}"
: "${DEPLOYMENT:?DEPLOYMENT is required}"
: "${ROLLOUT_TIMEOUT_SECONDS:?ROLLOUT_TIMEOUT_SECONDS is required}"
command -v kubectl >/dev/null 2>&1 || { echo "kubectl not found in PATH" >&2; exit 1; }

attempt=1
while (( attempt <= WAIT_ATTEMPTS )); do
  if kubectl -n "${NAMESPACE}" get deploy "${DEPLOYMENT}" >/dev/null 2>&1; then
    kubectl -n "${NAMESPACE}" rollout status "deploy/${DEPLOYMENT}" --timeout="${ROLLOUT_TIMEOUT_SECONDS}s"
    exit 0
  fi
  sleep "${SLEEP_SECONDS}"
  attempt=$((attempt + 1))
done

echo "Timed out waiting for deployment/${DEPLOYMENT} in namespace ${NAMESPACE}" >&2
kubectl -n "${NAMESPACE}" get all || true
exit 1
