#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/kubernetes/kind/scripts/ensure-kind-kubeconfig.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN}"
  export PATH="${TEST_BIN}:${PATH}"
  export TEST_STATE_DIR="${BATS_TEST_TMPDIR}/state"
  mkdir -p "${TEST_STATE_DIR}"
}

@test "retries kubeconfig export when the kubeconfig lock is busy" {
  cat >"${TEST_BIN}/kind" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
state_dir="${TEST_STATE_DIR:?}"
attempt_file="${state_dir}/kind-export-attempts"
attempts=0
if [[ -f "${attempt_file}" ]]; then
  attempts="$(cat "${attempt_file}")"
fi
case "${1:-}" in
  get)
    printf 'kind-local\n'
    ;;
  export)
    attempts=$((attempts + 1))
    printf '%s' "${attempts}" >"${attempt_file}"
    if [[ "${attempts}" == "1" ]]; then
      echo "failed to lock config file: open ${KUBECONFIG_PATH}.lock: file exists" >&2
      exit 1
    fi
    ;;
esac
EOF
  chmod +x "${TEST_BIN}/kind"

  cat >"${TEST_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-} ${2:-} ${3:-}" in
  "config get-contexts kind-kind-local")
    exit 0
    ;;
  "config use-context kind-kind-local")
    exit 0
    ;;
esac
exit 0
EOF
  chmod +x "${TEST_BIN}/kubectl"

  run env TEST_STATE_DIR="${TEST_STATE_DIR}" KUBECONFIG_PATH="${BATS_TEST_TMPDIR}/config" KIND_KUBECONFIG_LOCK_WAIT_SECONDS=2 "${SCRIPT}"

  [ "${status}" -eq 0 ]
  [[ "$(cat "${TEST_STATE_DIR}/kind-export-attempts")" == "2" ]]
}

@test "returns success when the kind cluster does not exist" {
  cat >"${TEST_BIN}/kind" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "get" ]]; then
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/kind"

  cat >"${TEST_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/kubectl"

  run "${SCRIPT}"

  [ "${status}" -eq 0 ]
}
