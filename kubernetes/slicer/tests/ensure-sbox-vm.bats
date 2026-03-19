#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/kubernetes/slicer/scripts/ensure-sbox-vm.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  export PATH="${TEST_BIN}:${PATH}"
  export SLICER_LOG="${BATS_TEST_TMPDIR}/slicer.log"
  export VM_LIST_JSON="${BATS_TEST_TMPDIR}/vm-list.json"
  mkdir -p "${TEST_BIN}"

  cat >"${TEST_BIN}/slicer" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"${SLICER_LOG}"

if [[ "${1:-}" == "vm" && "${2:-}" == "group" ]]; then
  printf 'slicer 192.168.64.0/24 4 8GiB\n'
  exit 0
fi

if [[ "${1:-}" == "vm" && "${2:-}" == "list" && "${3:-}" == "--json" ]]; then
  cat "${VM_LIST_JSON}"
  exit 0
fi

if [[ "${1:-}" == "vm" && "${2:-}" == "ready" ]]; then
  exit 0
fi

if [[ "${1:-}" == "vm" && "${2:-}" == "exec" ]]; then
  printf '%s\n' "${SLICER_VM_ROOT_BYTES}"
  exit 0
fi

if [[ "${1:-}" == "vm" && ( "${2:-}" == "resume" || "${2:-}" == "restore" || "${2:-}" == "add" ) ]]; then
  exit 0
fi

echo "unexpected slicer invocation: $*" >&2
exit 1
EOF
  chmod +x "${TEST_BIN}/slicer"

  cat >"${VM_LIST_JSON}" <<'EOF'
[
  {
    "hostname": "slicer-1",
    "ip": "192.168.64.2",
    "ram_bytes": 8589934592,
    "cpus": 4,
    "status": "Running"
  }
]
EOF
}

@test "fails fast when an existing slicer VM root disk is smaller than the minimum" {
  run env \
    SLICER_URL="${BATS_TEST_TMPDIR}/slicer.sock" \
    SLICER_USE_LOCAL_MAC=1 \
    SLICER_CONFIG="${BATS_TEST_TMPDIR}/slicer-mac.yaml" \
    SLICER_VM_ROOT_BYTES="$((15 * 1073741824))" \
    "${SCRIPT}"

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"slicer-1 has a 15GiB root disk"* ]]
  [[ "${output}" == *"at least 25GiB is required"* ]]
  [[ "${output}" == *"cannot be resized in place"* ]]
  [[ "${output}" == *"${BATS_TEST_TMPDIR}/slicer-mac.yaml"* ]]
}

@test "fails fast when the local slicer-mac daemon is missing slicer-1" {
  cat >"${VM_LIST_JSON}" <<'EOF'
[]
EOF

  run env \
    SLICER_URL="${BATS_TEST_TMPDIR}/slicer.sock" \
    SLICER_USE_LOCAL_MAC=1 \
    SLICER_CONFIG="${BATS_TEST_TMPDIR}/slicer-mac.yaml" \
    SLICER_VM_ROOT_BYTES="$((25 * 1073741824))" \
    "${SCRIPT}"

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"slicer-1 is missing from the active local slicer-mac daemon"* ]]
  [[ "${output}" == *"${BATS_TEST_TMPDIR}/slicer-mac.yaml"* ]]
}

@test "accepts an existing slicer VM when the root disk meets the minimum" {
  run env \
    SLICER_URL="${BATS_TEST_TMPDIR}/slicer.sock" \
    SLICER_VM_ROOT_BYTES="$((25 * 1073741824))" \
    "${SCRIPT}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"OK   slicer-1 root disk 25GiB (minimum 25GiB)"* ]]
  [[ "${output}" == *"OK   slicer-1 ready (192.168.64.2)"* ]]
}
