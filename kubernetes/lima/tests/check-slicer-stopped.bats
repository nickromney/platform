#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/kubernetes/scripts/check-slicer-stopped.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN}"
  export PATH="${TEST_BIN}:${PATH}"
}

@test "fails when the slicer gateway proxy container is still running" {
  cat >"${TEST_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "ps" ]]; then
  printf 'slicer-platform-gateway-443\n'
fi
EOF
  chmod +x "${TEST_BIN}/docker"

  cat >"${TEST_BIN}/ps" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/ps"

  run env SLICER_URL="${BATS_TEST_TMPDIR}/missing.sock" SLICER_SOCKET="${BATS_TEST_TMPDIR}/missing.sock" "${SCRIPT}"

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"make -C kubernetes/slicer stop-slicer"* ]]
  [[ "${output}" == *"slicer-platform-gateway-443"* ]]
}

@test "fails when the slicer llm proxy container is still running" {
  cat >"${TEST_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "ps" ]]; then
  printf 'slicer-platform-llm-12434\n'
fi
EOF
  chmod +x "${TEST_BIN}/docker"

  cat >"${TEST_BIN}/ps" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/ps"

  run env SLICER_URL="${BATS_TEST_TMPDIR}/missing.sock" SLICER_SOCKET="${BATS_TEST_TMPDIR}/missing.sock" "${SCRIPT}"

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"make -C kubernetes/slicer stop-slicer"* ]]
  [[ "${output}" == *"slicer-platform-llm-12434"* ]]
}

@test "returns success when slicer has no running vm, forwards, or proxy" {
  cat >"${TEST_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/docker"

  cat >"${TEST_BIN}/ps" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/ps"

  run env SLICER_URL="${BATS_TEST_TMPDIR}/missing.sock" SLICER_SOCKET="${BATS_TEST_TMPDIR}/missing.sock" "${SCRIPT}"

  [ "${status}" -eq 0 ]
}
