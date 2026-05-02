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

  cat >"${TEST_BIN}/lsof" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case " $* " in
  *" -iTCP:443 "*|*" -iTCP:30080 "*|*" -iTCP:3302 "*)
    printf 'COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME\n'
    exit 0
    ;;
esac
exit 1
EOF
  chmod +x "${TEST_BIN}/lsof"

  run "${SCRIPT}" --execute

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"make -C kubernetes/lima stop-lima"* ]]
  [[ "${output}" == *"Shared host ports currently in use while Lima is active:"* ]]
  [[ "${output}" != *"currently in use by Lima"* ]]
  [[ "${output}" == *"127.0.0.1:443"* ]]
  [[ "${output}" == *"127.0.0.1:30080"* ]]
  [[ "${output}" == *"127.0.0.1:3302"* ]]
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

  run "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
}
