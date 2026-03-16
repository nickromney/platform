#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/kubernetes/scripts/check-lima-stopped.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN}"
  export PATH="${TEST_BIN}:${PATH}"
}

@test "fails when a Lima VM is still running" {
  cat >"${TEST_BIN}/limactl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "list" ]]; then
  printf 'k3s-node-1 Running 127.0.0.1:60022\n'
fi
EOF
  chmod +x "${TEST_BIN}/limactl"

  cat >"${TEST_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/docker"

  run "${SCRIPT}"

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"make -C kubernetes/lima stop-lima"* ]]
  [[ "${output}" == *"k3s-node-1"* ]]
}

@test "returns success when Lima has no running vm or proxies" {
  cat >"${TEST_BIN}/limactl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "list" ]]; then
  printf 'k3s-node-1 Stopped 127.0.0.1:60022\n'
fi
EOF
  chmod +x "${TEST_BIN}/limactl"

  cat >"${TEST_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/docker"

  run "${SCRIPT}"

  [ "${status}" -eq 0 ]
}
