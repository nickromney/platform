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

  run env TEST_STATE_DIR="${TEST_STATE_DIR}" KUBECONFIG_PATH="${BATS_TEST_TMPDIR}/config" KIND_KUBECONFIG_LOCK_WAIT_SECONDS=2 "${SCRIPT}" --execute

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

  run "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
}

@test "returns success when kind get clusters times out" {
  cat >"${TEST_BIN}/kind" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "get" ]]; then
  sleep 10
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

  run env KIND_GET_CLUSTERS_TIMEOUT_SECONDS=1 "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
}

@test "keeps the split kubeconfig canonical and removes stale global repo context by default" {
  helper_log="${BATS_TEST_TMPDIR}/helper.log"
  global_kubeconfig="${BATS_TEST_TMPDIR}/config"

  cat >"${TEST_BIN}/kind" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  get)
    printf 'kind-local\n'
    ;;
  export)
    kubeconfig=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --kubeconfig)
          kubeconfig="$2"
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    mkdir -p "$(dirname "${kubeconfig}")"
    cat >"${kubeconfig}" <<'YAML'
apiVersion: v1
kind: Config
preferences: {}
clusters: []
contexts: []
users: []
current-context: ""
YAML
    ;;
esac
EOF
  chmod +x "${TEST_BIN}/kind"

  cat >"${TEST_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/kubectl"

  cat >"${TEST_BIN}/helper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${HELPER_LOG}"
EOF
  chmod +x "${TEST_BIN}/helper"

  cat >"${global_kubeconfig}" <<'EOF'
apiVersion: v1
kind: Config
preferences: {}
clusters: []
contexts: []
users: []
current-context: ""
EOF

  run env \
    HELPER_LOG="${helper_log}" \
    KUBECONFIG_PATH="${BATS_TEST_TMPDIR}/kind-kind-local.yaml" \
    GLOBAL_KUBECONFIG_PATH="${global_kubeconfig}" \
    KUBECONFIG_HELPER="${TEST_BIN}/helper" \
    MERGE_KUBECONFIG_TO_DEFAULT=0 \
    "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  run grep -F -- "--execute --action delete-context --kubeconfig ${global_kubeconfig} --context kind-kind-local --cluster kind-kind-local --user kind-kind-local" "${helper_log}"
  [ "${status}" -eq 0 ]
}

@test "merge mode updates the global kubeconfig and switches context there" {
  helper_log="${BATS_TEST_TMPDIR}/helper.log"
  kubectl_log="${BATS_TEST_TMPDIR}/kubectl.log"

  cat >"${TEST_BIN}/kind" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  get)
    printf 'kind-local\n'
    ;;
  export)
    kubeconfig=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --kubeconfig)
          kubeconfig="$2"
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    mkdir -p "$(dirname "${kubeconfig}")"
    cat >"${kubeconfig}" <<'YAML'
apiVersion: v1
kind: Config
preferences: {}
clusters: []
contexts: []
users: []
current-context: ""
YAML
    ;;
esac
EOF
  chmod +x "${TEST_BIN}/kind"

  cat >"${TEST_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${KUBECTL_LOG}"
if [[ "${1:-}" == "--kubeconfig" && "${3:-}" == "config" && "${4:-}" == "get-contexts" ]]; then
  exit 0
fi
if [[ "${1:-}" == "--kubeconfig" && "${3:-}" == "config" && "${4:-}" == "use-context" ]]; then
  exit 0
fi
exit 0
EOF
  chmod +x "${TEST_BIN}/kubectl"

  cat >"${TEST_BIN}/helper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${HELPER_LOG}"
EOF
  chmod +x "${TEST_BIN}/helper"

  run env \
    HELPER_LOG="${helper_log}" \
    KUBECTL_LOG="${kubectl_log}" \
    KUBECONFIG_PATH="${BATS_TEST_TMPDIR}/kind-kind-local.yaml" \
    GLOBAL_KUBECONFIG_PATH="${BATS_TEST_TMPDIR}/config" \
    KUBECONFIG_HELPER="${TEST_BIN}/helper" \
    MERGE_KUBECONFIG_TO_DEFAULT=1 \
    "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  run grep -F -- '--execute --action merge --source-kubeconfig '"${BATS_TEST_TMPDIR}"'/kind-kind-local.yaml --target-kubeconfig '"${BATS_TEST_TMPDIR}"'/config --context kind-kind-local' "${helper_log}"
  [ "${status}" -eq 0 ]
  run grep -F -- '--kubeconfig '"${BATS_TEST_TMPDIR}"'/config config use-context kind-kind-local' "${kubectl_log}"
  [ "${status}" -eq 0 ]
}
