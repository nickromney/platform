#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/kubernetes/slicer/scripts/start-daemon.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  export PATH="${TEST_BIN}:${PATH}"
  export RUN_DIR="${BATS_TEST_TMPDIR}/run"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export SYSTEM_DIR="${HOME}/slicer-mac"
  export SYSTEM_SOCKET="${SYSTEM_DIR}/slicer.sock"
  export DAEMON_STARTED_FLAG="${BATS_TEST_TMPDIR}/daemon-started"
  export SLICER_READY_FLAG="${BATS_TEST_TMPDIR}/slicer-ready"
  export SLICER_MAC_LOG="${BATS_TEST_TMPDIR}/slicer-mac.log"
  unset SLICER_URL
  unset SLICER_SOCKET
  mkdir -p "${TEST_BIN}" "${RUN_DIR}" "${SYSTEM_DIR}"

  cat >"${TEST_BIN}/slicer" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "vm" && "${2:-}" == "list" ]]; then
  if [[ -f "${SLICER_READY_FLAG}" ]]; then
    printf 'slicer-1 192.168.64.2 Running\n'
    exit 0
  fi
  exit 1
fi

echo "unexpected slicer invocation: $*" >&2
exit 1
EOF
  chmod +x "${TEST_BIN}/slicer"

  cat >"${SYSTEM_DIR}/slicer-mac" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${SLICER_MAC_LOG}"

case "${1:-} ${2:-} ${3:-}" in
  "service start daemon"|"service restart daemon")
    touch "${DAEMON_STARTED_FLAG}"
    touch "${SLICER_READY_FLAG}"
    exit 0
    ;;
  "up  ")
    touch "${DAEMON_STARTED_FLAG}"
    touch "${SLICER_READY_FLAG}"
    exit 0
    ;;
esac

echo "unexpected slicer-mac invocation: $*" >&2
exit 1
EOF
  chmod +x "${SYSTEM_DIR}/slicer-mac"
}

@test "starts the on-device daemon via launchd service when the local socket is missing" {
  run env \
    RUN_DIR="${RUN_DIR}" \
    SLICER_SYSTEM_DIR="${SYSTEM_DIR}" \
    SLICER_SYSTEM_BIN="${SYSTEM_DIR}/slicer-mac" \
    SLICER_SYSTEM_SOCKET="${SYSTEM_SOCKET}" \
    SLICER_SYSTEM_SOCKET_WAIT_SECONDS=3 \
    "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Using on-device slicer-mac at ${SYSTEM_SOCKET}"* ]]
  [[ "${output}" == *"launchd service"* ]]
  [ -f "${DAEMON_STARTED_FLAG}" ]
  grep -q "service start daemon" "${SLICER_MAC_LOG}"
}

@test "restarts the on-device daemon when the local slicer socket is stale" {
  uv run --isolated python - <<'PY'
import os
import socket

path = os.environ["SYSTEM_SOCKET"]
sock = socket.socket(socket.AF_UNIX)
sock.bind(path)
sock.close()
PY

  run env \
    RUN_DIR="${RUN_DIR}" \
    SLICER_SYSTEM_DIR="${SYSTEM_DIR}" \
    SLICER_SYSTEM_BIN="${SYSTEM_DIR}/slicer-mac" \
    SLICER_SYSTEM_SOCKET="${SYSTEM_SOCKET}" \
    SLICER_SYSTEM_SOCKET_WAIT_SECONDS=3 \
    "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Using on-device slicer-mac at ${SYSTEM_SOCKET}"* ]]
  [ -f "${DAEMON_STARTED_FLAG}" ]
  grep -q "service restart daemon" "${SLICER_MAC_LOG}"
}
