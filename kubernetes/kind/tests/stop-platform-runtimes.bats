#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/kubernetes/scripts/stop-platform-runtimes.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  export MAKE_LOG="${BATS_TEST_TMPDIR}/make.log"
  mkdir -p "${TEST_BIN}"
  export PATH="${TEST_BIN}:${PATH}"
}

@test "stop-platform-runtimes dry-run previews without invoking make" {
  cat >"${TEST_BIN}/make" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${MAKE_LOG}"
EOF
  chmod +x "${TEST_BIN}/make"

  run "${SCRIPT}" --dry-run

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"would stop local platform runtimes best-effort"* ]]
  [ ! -e "${MAKE_LOG}" ]
}

@test "stop-platform-runtimes honors excludes and continues best-effort failures" {
  cat >"${TEST_BIN}/make" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${MAKE_LOG}"
case "$*" in
  *"kubernetes/lima stop-lima"*)
    exit 17
    ;;
esac
EOF
  chmod +x "${TEST_BIN}/make"

  run "${SCRIPT}" --execute --exclude kind

  [ "${status}" -eq 0 ]
  [[ "${output}" != *"Stopping kind runtime"* ]]
  [[ "${output}" == *"Stopping lima runtime"* ]]
  [[ "${output}" == *"WARN lima stop returned 17; continuing"* ]]
  [[ "${output}" == *"Stopping slicer runtime"* ]]

  run cat "${MAKE_LOG}"
  [ "${status}" -eq 0 ]
  [[ "${output}" != *"kubernetes/kind stop-kind"* ]]
  [[ "${output}" == *"kubernetes/lima stop-lima AUTO_APPROVE=1"* ]]
  [[ "${output}" == *"kubernetes/slicer stop-slicer AUTO_APPROVE=1"* ]]
}
