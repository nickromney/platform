#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-kind-local}"
TARGET_CONTEXT="kind-${CLUSTER_NAME}"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-${KUBECONFIG:-$HOME/.kube/${TARGET_CONTEXT}.yaml}}"
GLOBAL_KUBECONFIG_PATH="${GLOBAL_KUBECONFIG_PATH:-$HOME/.kube/config}"
KUBECONFIG_HELPER="${KUBECONFIG_HELPER:-${REPO_ROOT}/terraform/kubernetes/scripts/manage-kubeconfig.sh}"
MERGE_KUBECONFIG_TO_DEFAULT="${MERGE_KUBECONFIG_TO_DEFAULT:-0}"
WAIT_SECONDS="${KIND_KUBECONFIG_LOCK_WAIT_SECONDS:-15}"
DEVCONTAINER_HOST_ALIAS="${KIND_DEVCONTAINER_HOST_ALIAS:-host.docker.internal}"
DEVCONTAINER_TLS_SERVER_NAME="${KIND_DEVCONTAINER_TLS_SERVER_NAME:-localhost}"

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

rewrite_for_devcontainer_host_socket() {
  local kubeconfig_path="$1"

  [[ "${PLATFORM_DEVCONTAINER:-0}" == "1" ]] || return 0
  [[ -f "${kubeconfig_path}" ]] || return 0

  python3 - "${kubeconfig_path}" "${DEVCONTAINER_HOST_ALIAS}" "${DEVCONTAINER_TLS_SERVER_NAME}" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
host_alias = sys.argv[2]
tls_server_name = sys.argv[3]
text = path.read_text()

# kind exports a host-loopback endpoint such as 127.0.0.1:6443. Inside a
# host-socket devcontainer, that loopback resolves to the container, not the
# host, so the API server must be addressed via host.docker.internal while the
# TLS hostname remains "localhost".
text = re.sub(r'^\s*tls-server-name:\s+.*\n?', '', text, flags=re.MULTILINE)
text, count = re.subn(
    r'^(?P<indent>\s*)server:\s+https://(?:127\.0\.0\.1|localhost):(?P<port>\d+)\s*$',
    lambda match: (
        f"{match.group('indent')}server: https://{host_alias}:{match.group('port')}\n"
        f"{match.group('indent')}tls-server-name: {tls_server_name}"
    ),
    text,
    flags=re.MULTILINE,
)

if count:
    path.write_text(text)
PY
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

rewrite_for_devcontainer_host_socket "${KUBECONFIG_PATH}"

if [[ -x "${KUBECONFIG_HELPER}" ]]; then
  "${KUBECONFIG_HELPER}" ensure-valid "${KUBECONFIG_PATH}"
  if [[ "${MERGE_KUBECONFIG_TO_DEFAULT}" == "1" ]]; then
    "${KUBECONFIG_HELPER}" ensure-valid "${GLOBAL_KUBECONFIG_PATH}"
    "${KUBECONFIG_HELPER}" merge "${KUBECONFIG_PATH}" "${GLOBAL_KUBECONFIG_PATH}" "${TARGET_CONTEXT}"
  elif [[ -e "${GLOBAL_KUBECONFIG_PATH}" ]]; then
    "${KUBECONFIG_HELPER}" ensure-valid "${GLOBAL_KUBECONFIG_PATH}"
    "${KUBECONFIG_HELPER}" delete-context "${GLOBAL_KUBECONFIG_PATH}" "${TARGET_CONTEXT}" "${TARGET_CONTEXT}" "${TARGET_CONTEXT}" 0
  fi
fi

if [[ "${MERGE_KUBECONFIG_TO_DEFAULT}" == "1" ]] && kubectl --kubeconfig "${GLOBAL_KUBECONFIG_PATH}" config get-contexts "${TARGET_CONTEXT}" >/dev/null 2>&1; then
  run_with_lock_retry \
    "switching kubectl context to ${TARGET_CONTEXT}" \
    kubectl --kubeconfig "${GLOBAL_KUBECONFIG_PATH}" config use-context "${TARGET_CONTEXT}" >/dev/null
fi
