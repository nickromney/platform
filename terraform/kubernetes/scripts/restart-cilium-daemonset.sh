#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${REPO_ROOT:-}" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
fi

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

CILIUM_NAMESPACE="${CILIUM_NAMESPACE:-kube-system}"
CILIUM_DAEMONSET="${CILIUM_DAEMONSET:-cilium}"

# shellcheck disable=SC2329 # invoked by name through the shell_cli_* helpers
usage() {
  cat <<'EOF' | sed "s|@SCRIPT_NAME@|${0##*/}|g"
Usage: @SCRIPT_NAME@ [--dry-run] [--execute]

Rollout-restart the Cilium agent DaemonSet so ConfigMap-sourced features
(including WireGuard) take effect. Requires ROLLOUT_TIMEOUT_SECONDS.
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

shell_cli_handle_standard_no_args usage "would rollout restart ${CILIUM_NAMESPACE}/${CILIUM_DAEMONSET}" "$@"

: "${KUBECONFIG:?KUBECONFIG is required}"
: "${ROLLOUT_TIMEOUT_SECONDS:?ROLLOUT_TIMEOUT_SECONDS is required}"
command -v kubectl >/dev/null 2>&1 || { echo "kubectl not found in PATH" >&2; exit 1; }

# Several Cilium features, including WireGuard encryption, are sourced from
# the rendered ConfigMap but do not take effect until the agent DaemonSet restarts.
kubectl -n "${CILIUM_NAMESPACE}" get daemonset "${CILIUM_DAEMONSET}" >/dev/null 2>&1 || exit 0
kubectl -n "${CILIUM_NAMESPACE}" rollout restart "daemonset/${CILIUM_DAEMONSET}"
kubectl -n "${CILIUM_NAMESPACE}" rollout status "daemonset/${CILIUM_DAEMONSET}" --timeout="${ROLLOUT_TIMEOUT_SECONDS}s"
