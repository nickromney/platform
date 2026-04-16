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
    last_arg=""
    for arg in "$@"; do
      last_arg="${arg}"
    done
  case "${last_arg}" in
    '{{.Names}}')
      printf 'kind-local-control-plane\nkind-local-worker\n'
      ;;
    '{{.Names}}|{{.Ports}}')
      printf 'kind-local-control-plane|127.0.0.1:6443->6443/tcp, 127.0.0.1:443->30070/tcp, 127.0.0.1:30080->30080/tcp\n'
      printf 'kind-local-worker|\n'
      ;;
  esac
fi
EOF
  chmod +x "${TEST_BIN}/docker"

  run "${SCRIPT}" --execute

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"make -C kubernetes/kind stop-kind"* ]]
  [[ "${output}" == *"Conflicting shared host ports for Lima/Slicer:"* ]]
  [[ "${output}" == *"127.0.0.1:443"* ]]
  [[ "${output}" == *"127.0.0.1:30080"* ]]
  [[ "${output}" == *"Other published kind host ports:"* ]]
  [[ "${output}" == *"127.0.0.1:6443"* ]]
  [[ "${output}" == *"Running kind containers:"* ]]
  [[ "${output}" == *"kind-local-control-plane"* ]]
  [[ "${output}" == *"kind-local-worker"* ]]
}

@test "returns success when kind-local is not running" {
  cat >"${TEST_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/docker"

  run "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
}
