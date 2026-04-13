#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/kubernetes/scripts/reset-kubeconfig-context.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN}"
  export PATH="${TEST_BIN}:${PATH}"
}

@test "reset-kubeconfig-context prepares and deletes an existing context" {
  helper_log="${BATS_TEST_TMPDIR}/helper.log"

  cat >"${TEST_BIN}/helper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${HELPER_LOG}"
EOF
  chmod +x "${TEST_BIN}/helper"

  cat >"${TEST_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "config" && "${2:-}" == "get-contexts" && "${3:-}" == "kind-kind-local" ]]; then
  exit 0
fi
exit 0
EOF
  chmod +x "${TEST_BIN}/kubectl"

  run env HELPER_LOG="${helper_log}" "${SCRIPT}" --execute \
    --kubeconfig "${BATS_TEST_TMPDIR}/config" \
    --context kind-kind-local \
    --cluster kind-kind-local \
    --user kind-kind-local \
    --kubeconfig-helper "${TEST_BIN}/helper" \
    --auto-approve 1 \
    --delete-file-if-empty

  [ "${status}" -eq 0 ]
  run cat "${helper_log}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"--execute --action prepare-for-reset --kubeconfig ${BATS_TEST_TMPDIR}/config"* ]]
  [[ "${output}" == *"--execute --action delete-context --kubeconfig ${BATS_TEST_TMPDIR}/config --context kind-kind-local --cluster kind-kind-local --user kind-kind-local --delete-file-if-empty"* ]]
}

@test "reset-kubeconfig-context returns 10 when the context is already absent" {
  helper_log="${BATS_TEST_TMPDIR}/helper.log"

  cat >"${TEST_BIN}/helper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${HELPER_LOG}"
EOF
  chmod +x "${TEST_BIN}/helper"

  cat >"${TEST_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "config" && "${2:-}" == "get-contexts" ]]; then
  exit 1
fi
exit 0
EOF
  chmod +x "${TEST_BIN}/kubectl"

  run env HELPER_LOG="${helper_log}" "${SCRIPT}" --execute \
    --kubeconfig "${BATS_TEST_TMPDIR}/config" \
    --context limavm-k3s \
    --cluster limavm-k3s \
    --user limavm-k3s \
    --kubeconfig-helper "${TEST_BIN}/helper" \
    --auto-approve 0

  [ "${status}" -eq 10 ]
  run cat "${helper_log}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"--execute --action prepare-for-reset --kubeconfig ${BATS_TEST_TMPDIR}/config"* ]]
  [[ "${output}" == *"--execute --action delete-context --kubeconfig ${BATS_TEST_TMPDIR}/config --context limavm-k3s --cluster limavm-k3s --user limavm-k3s"* ]]
}
