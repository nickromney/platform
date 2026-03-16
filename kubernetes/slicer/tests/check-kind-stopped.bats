#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/kubernetes/slicer/scripts/check-kind-stopped.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN}"
  export PATH="${TEST_BIN}:${PATH}"
}

@test "fails when kind-local containers are still running" {
  cat >"${TEST_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "ps" ]]; then
  printf 'kind-local-control-plane\nkind-local-worker\n'
fi
EOF
  chmod +x "${TEST_BIN}/docker"

  run "${SCRIPT}"

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"make -C kubernetes/kind stop-kind"* ]]
}

@test "returns success when kind-local is not running" {
  cat >"${TEST_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/docker"

  run "${SCRIPT}"

  [ "${status}" -eq 0 ]
}
