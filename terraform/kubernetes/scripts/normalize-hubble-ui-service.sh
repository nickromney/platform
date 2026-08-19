#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${REPO_ROOT:-}" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
fi

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

HUBBLE_UI_NAMESPACE="${HUBBLE_UI_NAMESPACE:-kube-system}"
HUBBLE_UI_SERVICE="${HUBBLE_UI_SERVICE:-hubble-ui}"

# shellcheck disable=SC2329 # invoked by name through the shell_cli_* helpers
usage() {
  cat <<'EOF' | sed "s|@SCRIPT_NAME@|${0##*/}|g"
Usage: @SCRIPT_NAME@ [--dry-run] [--execute]

Normalize a leftover hubble-ui Service back to chart-native port 80 before
Helm upgrades. Requires HUBBLE_UI_NODE_PORT.
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

shell_cli_handle_standard_no_args usage "would normalize ${HUBBLE_UI_NAMESPACE}/${HUBBLE_UI_SERVICE} ports" "$@"

: "${KUBECONFIG:?KUBECONFIG is required}"
: "${HUBBLE_UI_NODE_PORT:?HUBBLE_UI_NODE_PORT is required}"
command -v kubectl >/dev/null 2>&1 || { echo "kubectl not found in PATH" >&2; exit 1; }

if ! kubectl get service "${HUBBLE_UI_SERVICE}" -n "${HUBBLE_UI_NAMESPACE}" >/dev/null 2>&1; then
  exit 0
fi

# Older runs rewrote hubble-ui to port 8080. Normalize back to chart-native
# port 80 before Helm upgrades to avoid duplicate nodePort patch failures.
kubectl patch service "${HUBBLE_UI_SERVICE}" -n "${HUBBLE_UI_NAMESPACE}" --type=json \
  -p "[{\"op\":\"replace\",\"path\":\"/spec/ports\",\"value\":[{\"name\":\"http\",\"port\":80,\"protocol\":\"TCP\",\"targetPort\":8081,\"nodePort\":${HUBBLE_UI_NODE_PORT}}]}]"
