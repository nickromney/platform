#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/kubernetes/slicer/scripts/delete-vm-best-effort.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export SLICER_HOME="${HOME}/slicer-mac"
  export STATE_FILE="${BATS_TEST_TMPDIR}/vm-state.json"
  export SLICER_LOG="${BATS_TEST_TMPDIR}/slicer.log"
  export SLICER_MAC_LOG="${BATS_TEST_TMPDIR}/slicer-mac.log"
  mkdir -p "${TEST_BIN}" "${SLICER_HOME}"
  export PATH="${TEST_BIN}:${PATH}"

  cat >"${TEST_BIN}/slicer" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

state_file="${STATE_FILE:?}"
printf '%s\n' "$*" >> "${SLICER_LOG:?}"

case "${1:-} ${2:-} ${3:-}" in
  "vm list --json")
    cat "${state_file}"
    ;;
  "vm shutdown"*)
    exit 0
    ;;
  "vm delete"*)
    echo 'status 404 Not Found: {"error":"host group not found"}' >&2
    exit 1
    ;;
  "vm pause"*)
    python3 - <<'PY'
import json, os
path = os.environ["STATE_FILE"]
with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)
for item in data:
    if item.get("hostname") == "slicer-1":
        item["status"] = "Paused"
with open(path, "w", encoding="utf-8") as fh:
    json.dump(data, fh)
PY
    exit 0
    ;;
  *)
    echo "unexpected slicer invocation: $*" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "${TEST_BIN}/slicer"

  cat >"${SLICER_HOME}/slicer-mac" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${SLICER_MAC_LOG:?}"

case "${1:-} ${2:-} ${3:-}" in
  "service stop daemon")
    exit 0
    ;;
  *)
    echo "unexpected slicer-mac invocation: $*" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "${SLICER_HOME}/slicer-mac"
}

@test "system-socket cleanup stops slicer-mac and deletes only the managed VM disk images by default" {
  touch \
    "${SLICER_HOME}/slicer-base.img" \
    "${SLICER_HOME}/slicer-1.img" \
    "${SLICER_HOME}/slicer-1-extra.img" \
    "${SLICER_HOME}/slicer-1.log" \
    "${SLICER_HOME}/slicer-1-vsock.sock"

  run env \
    SLICER_URL="${SLICER_HOME}/slicer.sock" \
    SLICER_VM_NAME="slicer-1" \
    "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"stopped on-device slicer-mac daemon"* ]]
  [[ "${output}" == *"removed 2 on-device disk image(s) matching"* ]]

  [ -e "${SLICER_HOME}/slicer-base.img" ]
  [ ! -e "${SLICER_HOME}/slicer-1.img" ]
  [ ! -e "${SLICER_HOME}/slicer-1-extra.img" ]
  [ -e "${SLICER_HOME}/slicer-1.log" ]
  [ -e "${SLICER_HOME}/slicer-1-vsock.sock" ]
  grep -q "service stop daemon" "${SLICER_MAC_LOG}"
  [ ! -s "${SLICER_LOG}" ]
}

@test "system-socket cleanup prunes all on-device disk images when explicitly requested" {
  touch \
    "${SLICER_HOME}/slicer-base.img" \
    "${SLICER_HOME}/slicer-1.img" \
    "${SLICER_HOME}/slicer-1-extra.img"

  run env \
    SLICER_URL="${SLICER_HOME}/slicer.sock" \
    SLICER_VM_NAME="slicer-1" \
    SLICER_RESET_PRUNE_ALL_IMAGES=1 \
    "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"removed 3 on-device disk image(s) matching"* ]]
  [ ! -e "${SLICER_HOME}/slicer-base.img" ]
  [ ! -e "${SLICER_HOME}/slicer-1.img" ]
  [ ! -e "${SLICER_HOME}/slicer-1-extra.img" ]
}

@test "non-system delete failure still exits nonzero" {
  printf '[{"hostname":"slicer-1","status":"Paused"}]\n' > "${STATE_FILE}"

  run env \
    SLICER_URL="${BATS_TEST_TMPDIR}/remote.sock" \
    SLICER_VM_NAME="slicer-1" \
    "${SCRIPT}" --execute

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"slicer vm delete slicer-1 failed"* ]]
  [[ "${output}" != *"recycled on-device slicer-mac state"* ]]
}
