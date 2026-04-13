#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/kubernetes/kind/scripts/refresh-kind-kubeconfig.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN}"
  export PATH="${TEST_BIN}:${PATH}"
}

@test "refresh-kind-kubeconfig forwards env and execute mode to ensure-kind-kubeconfig" {
  log_file="${BATS_TEST_TMPDIR}/ensure.log"

  cat >"${TEST_BIN}/ensure-kind-kubeconfig" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "KUBECONFIG_PATH=${KUBECONFIG_PATH}" >"${LOG_FILE}"
printf '%s\n' "GLOBAL_KUBECONFIG_PATH=${GLOBAL_KUBECONFIG_PATH}" >>"${LOG_FILE}"
printf '%s\n' "KUBECONFIG_HELPER=${KUBECONFIG_HELPER}" >>"${LOG_FILE}"
printf '%s\n' "MERGE_KUBECONFIG_TO_DEFAULT=${MERGE_KUBECONFIG_TO_DEFAULT}" >>"${LOG_FILE}"
printf '%s\n' "ARGS=$*" >>"${LOG_FILE}"
EOF
  chmod +x "${TEST_BIN}/ensure-kind-kubeconfig"

  run env \
    LOG_FILE="${log_file}" \
    ENSURE_KIND_KUBECONFIG_SCRIPT="${TEST_BIN}/ensure-kind-kubeconfig" \
    KUBECONFIG_PATH="${BATS_TEST_TMPDIR}/kind.yaml" \
    GLOBAL_KUBECONFIG_PATH="${BATS_TEST_TMPDIR}/config" \
    KUBECONFIG_HELPER="/bin/true" \
    MERGE_KUBECONFIG_TO_DEFAULT=1 \
    "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  run cat "${log_file}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"KUBECONFIG_PATH=${BATS_TEST_TMPDIR}/kind.yaml"* ]]
  [[ "${output}" == *"GLOBAL_KUBECONFIG_PATH=${BATS_TEST_TMPDIR}/config"* ]]
  [[ "${output}" == *"KUBECONFIG_HELPER=/bin/true"* ]]
  [[ "${output}" == *"MERGE_KUBECONFIG_TO_DEFAULT=1"* ]]
  [[ "${output}" == *"ARGS=--execute"* ]]
}
