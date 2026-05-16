#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/kubernetes/scripts/host-gateway-proxy.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN}"
  export PATH="${TEST_BIN}:${PATH}"
}

@test "shared host gateway proxy reports configured running proxy" {
  cat >"${TEST_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  info)
    exit 0
    ;;
  ps)
    printf 'shared-proxy\n'
    ;;
  *)
    exit 1
    ;;
esac
EOF
  chmod +x "${TEST_BIN}/docker"

  run env CONTAINER_NAME=shared-proxy \
    LISTEN_PORT=9443 \
    UPSTREAM_HOST=host.docker.internal \
    UPSTREAM_PORT=8443 \
    "${SCRIPT}" --action status --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == "RUNNING shared-proxy :9443 -> host.docker.internal:8443" ]]
}
