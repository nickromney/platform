#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
  export SCRIPT="${REPO_ROOT}/kubernetes/kind/scripts/ensure-node-host-alias.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN}"
  export PATH="${TEST_BIN}:${PATH}"
  export TEST_STATE_DIR="${BATS_TEST_TMPDIR}/state"
  mkdir -p "${TEST_STATE_DIR}"

  cat >"${TEST_BIN}/kind" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'node-a\nnode-b\n'
EOF
  chmod +x "${TEST_BIN}/kind"
}

# Nodes named in RESOLVING_NODES report the alias as present; every other node
# reports it missing. Writes to /etc/hosts are recorded rather than performed.
write_docker_stub() {
  cat >"${TEST_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
state_dir="${TEST_STATE_DIR:?}"
case "${1:-}" in
  network)
    printf '172.18.0.1\n'
    ;;
  exec)
    node="${2:-}"
    if [[ "${3:-}" == "getent" ]]; then
      case " ${RESOLVING_NODES:-} " in
        *" ${node} "*) exit 0 ;;
        *) exit 1 ;;
      esac
    fi
    printf '%s\n' "${node}" >>"${state_dir}/patched"
    ;;
esac
EOF
  chmod +x "${TEST_BIN}/docker"
}

@test "--check reports missing nodes without modifying them" {
  write_docker_stub
  export RESOLVING_NODES="node-a"

  run "${SCRIPT}" --check

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"already resolves in 1 kind node(s)"* ]]
  [[ "${output}" == *"does not resolve in 1 kind node(s)"* ]]
  [[ "${output}" == *"ensure-node-host-alias"* ]]
  [ ! -f "${TEST_STATE_DIR}/patched" ]
}

@test "--check stays silent about repair when every node resolves" {
  write_docker_stub
  export RESOLVING_NODES="node-a node-b"

  run "${SCRIPT}" --check

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"already resolves in 2 kind node(s)"* ]]
  [[ "${output}" != *"does not resolve"* ]]
  [ ! -f "${TEST_STATE_DIR}/patched" ]
}

@test "--check does not require the --execute confirmation gate" {
  write_docker_stub
  export RESOLVING_NODES=""

  run "${SCRIPT}" --check

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"does not resolve in 2 kind node(s)"* ]]
}

@test "--execute patches only the nodes that do not resolve" {
  write_docker_stub
  export RESOLVING_NODES="node-a"

  run "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"added to 1 kind node(s)"* ]]
  run cat "${TEST_STATE_DIR}/patched"
  [ "${output}" = "node-b" ]
}
