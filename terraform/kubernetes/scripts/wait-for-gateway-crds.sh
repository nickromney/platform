#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${REPO_ROOT:-}" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
fi

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

CRD_WAIT_SECONDS="${CRD_WAIT_SECONDS:-180}"

# shellcheck disable=SC2329 # invoked by name through the shell_cli_* helpers
usage() {
  cat <<'EOF' | sed "s|@SCRIPT_NAME@|${0##*/}|g"
Usage: @SCRIPT_NAME@ [--dry-run] [--execute]

Wait until each Gateway API CRD in CRD_NAMES is Established.
CRD_NAMES is a space- or comma-separated list.
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

shell_cli_handle_standard_no_args usage "would wait for Gateway API CRDs to become Established" "$@"

: "${KUBECONFIG:?KUBECONFIG is required}"
: "${CRD_NAMES:?CRD_NAMES is required}"
command -v kubectl >/dev/null 2>&1 || { echo "kubectl not found in PATH" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq not found in PATH" >&2; exit 1; }

KUBE_CONTEXT="${KUBE_CONTEXT:-}"
kubectl_args=()
if [[ -n "${KUBE_CONTEXT}" ]]; then
  kubectl_args=(--context "${KUBE_CONTEXT}")
fi

# shellcheck disable=SC2086
set -- ${CRD_NAMES//,/ }
for crd in "$@"; do
  [[ -n "${crd}" ]] || continue
  deadline=$((SECONDS + CRD_WAIT_SECONDS))
  established=""
  while (( SECONDS < deadline )); do
    established="$(kubectl "${kubectl_args[@]}" get "crd/${crd}" -o json 2>/dev/null | jq -r '.status.conditions[]? | select(.type=="Established") | .status' | head -n1 || true)"
    if [[ "${established}" == "True" ]]; then
      break
    fi
    sleep 2
  done

  if [[ "${established}" != "True" ]]; then
    echo "Timed out waiting for CRD/${crd} to become Established" >&2
    kubectl "${kubectl_args[@]}" get "crd/${crd}" -o yaml || true
    exit 1
  fi

  kubectl "${kubectl_args[@]}" wait --for=condition=Established --timeout=10s "crd/${crd}" >/dev/null
done
