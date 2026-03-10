#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-kind-local}"
TARGET_CONTEXT="kind-${CLUSTER_NAME}"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-${KUBECONFIG:-$HOME/.kube/${TARGET_CONTEXT}.yaml}}"
GLOBAL_KUBECONFIG_PATH="${GLOBAL_KUBECONFIG_PATH:-$HOME/.kube/config}"
KUBECONFIG_HELPER="${KUBECONFIG_HELPER:-${REPO_ROOT}/terraform/kubernetes/scripts/manage-kubeconfig.sh}"
WAIT_SECONDS="${KIND_KUBECONFIG_LOCK_WAIT_SECONDS:-15}"

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

run_with_lock_retry() {
  local description="$1"
  shift

  local attempt rc
  local stderr_file
  stderr_file="$(mktemp)"
  trap 'rm -f "${stderr_file}"' RETURN

  for ((attempt = 1; attempt <= WAIT_SECONDS; attempt++)); do
    if "$@" 2>"${stderr_file}"; then
      rm -f "${stderr_file}"
      trap - RETURN
      return 0
    fi

    rc=$?
    if grep -qi "failed to lock config file" "${stderr_file}" || [[ -e "${KUBECONFIG_PATH}.lock" ]]; then
      if (( attempt == WAIT_SECONDS )); then
        echo "Timed out waiting for kubeconfig lock to clear while ${description}: ${KUBECONFIG_PATH}.lock" >&2
        cat "${stderr_file}" >&2 || true
        rm -f "${stderr_file}"
        trap - RETURN
        return "${rc}"
      fi
      sleep 1
      continue
    fi

    cat "${stderr_file}" >&2 || true
    rm -f "${stderr_file}"
    trap - RETURN
    return "${rc}"
  done
}

if ! have_cmd kind || ! have_cmd kubectl; then
  exit 0
fi

if ! kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  exit 0
fi

mkdir -p "$(dirname "${KUBECONFIG_PATH}")"

run_with_lock_retry \
  "exporting ${TARGET_CONTEXT} kubeconfig" \
  kind export kubeconfig --name "${CLUSTER_NAME}" --kubeconfig "${KUBECONFIG_PATH}" >/dev/null

if [[ -x "${KUBECONFIG_HELPER}" ]]; then
  "${KUBECONFIG_HELPER}" ensure-valid "${KUBECONFIG_PATH}"
  "${KUBECONFIG_HELPER}" ensure-valid "${GLOBAL_KUBECONFIG_PATH}"
  "${KUBECONFIG_HELPER}" merge "${KUBECONFIG_PATH}" "${GLOBAL_KUBECONFIG_PATH}" "${TARGET_CONTEXT}"
fi

if kubectl --kubeconfig "${GLOBAL_KUBECONFIG_PATH}" config get-contexts "${TARGET_CONTEXT}" >/dev/null 2>&1; then
  run_with_lock_retry \
    "switching kubectl context to ${TARGET_CONTEXT}" \
    kubectl --kubeconfig "${GLOBAL_KUBECONFIG_PATH}" config use-context "${TARGET_CONTEXT}" >/dev/null
fi
