#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${REPO_ROOT:-}" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
fi

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

HUBBLE_UI_NAMESPACE="${HUBBLE_UI_NAMESPACE:-kube-system}"
HUBBLE_UI_DEPLOYMENT="${HUBBLE_UI_DEPLOYMENT:-hubble-ui}"

# shellcheck disable=SC2329 # invoked by name through the shell_cli_* helpers
usage() {
  cat <<'EOF' | sed "s|@SCRIPT_NAME@|${0##*/}|g"
Usage: @SCRIPT_NAME@ [--dry-run] [--execute]

Patch the Hubble UI backend FLOWS_API_ADDR to the relay Service we expose.
Requires FLOWS_API_ADDR and ROLLOUT_TIMEOUT_SECONDS.
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

shell_cli_handle_standard_no_args usage "would patch ${HUBBLE_UI_NAMESPACE}/${HUBBLE_UI_DEPLOYMENT} FLOWS_API_ADDR" "$@"

: "${KUBECONFIG:?KUBECONFIG is required}"
: "${FLOWS_API_ADDR:?FLOWS_API_ADDR is required}"
: "${ROLLOUT_TIMEOUT_SECONDS:?ROLLOUT_TIMEOUT_SECONDS is required}"
command -v kubectl >/dev/null 2>&1 || { echo "kubectl not found in PATH" >&2; exit 1; }

if ! kubectl get deployment "${HUBBLE_UI_DEPLOYMENT}" -n "${HUBBLE_UI_NAMESPACE}" >/dev/null 2>&1; then
  exit 0
fi

# The Cilium chart exposes the relay Service port, but it hardcodes the
# UI backend's FLOWS_API_ADDR to hubble-relay:80. Patch the deployment so
# the shipped UI follows the relay Service we expose locally.
kubectl patch deployment "${HUBBLE_UI_DEPLOYMENT}" -n "${HUBBLE_UI_NAMESPACE}" --type=strategic \
  -p "{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"backend\",\"env\":[{\"name\":\"FLOWS_API_ADDR\",\"value\":\"${FLOWS_API_ADDR}\"}]}]}}}}"
kubectl -n "${HUBBLE_UI_NAMESPACE}" rollout status "deployment/${HUBBLE_UI_DEPLOYMENT}" --timeout="${ROLLOUT_TIMEOUT_SECONDS}s"
