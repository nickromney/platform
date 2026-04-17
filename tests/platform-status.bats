#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export SCRIPT="${REPO_ROOT}/scripts/platform-status.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN}"
  export PATH="${TEST_BIN}:${PATH}"
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}/.kube"

  install_auth_stub
  install_docker_stub
  install_kind_stub
  install_limactl_stub
  install_slicer_stub
  install_lsof_stub
  install_ps_stub
}

install_auth_stub() {
  auth_stub="${BATS_TEST_TMPDIR}/check-docker-registry-auth.sh"
  cat >"${auth_stub}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
registry=""
for arg in "$@"; do
  case "${arg}" in
    dhi.io|index.docker.io|docker.io)
      registry="${arg}"
      ;;
  esac
done
case "${registry}" in
  dhi.io)
    exit "${MOCK_AUTH_DHI_EXIT:-0}"
    ;;
  index.docker.io|docker.io)
    exit "${MOCK_AUTH_DOCKER_EXIT:-0}"
    ;;
esac
exit 0
EOF
  chmod +x "${auth_stub}"
  export PLATFORM_STATUS_CHECK_DOCKER_REGISTRY_AUTH_SCRIPT="${auth_stub}"
}

install_docker_stub() {
  cat >"${TEST_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

subcommand="${1:-}"
shift || true

case "${subcommand}" in
  info)
    exit "${MOCK_DOCKER_INFO_EXIT:-0}"
    ;;
  context)
    if [[ "${1:-}" == "show" ]]; then
      printf '%s\n' "${MOCK_DOCKER_CONTEXT:-desktop-linux}"
      exit 0
    fi
    ;;
  ps)
    if [[ "${1:-}" == "-a" ]]; then
      printf '%s\n' "${MOCK_DOCKER_PS_A:-}"
      exit 0
    fi
    printf '%s\n' "${MOCK_DOCKER_PS:-}"
    exit 0
    ;;
esac

exit 1
EOF
  chmod +x "${TEST_BIN}/docker"
}

install_kind_stub() {
  cat >"${TEST_BIN}/kind" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "get" && "${2:-}" == "clusters" ]]; then
  printf '%s\n' "${MOCK_KIND_CLUSTERS:-}"
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/kind"
}

install_limactl_stub() {
  cat >"${TEST_BIN}/limactl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "list" ]]; then
  printf '%s\n' "${MOCK_LIMACTL_LIST:-}"
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/limactl"
}

install_slicer_stub() {
  cat >"${TEST_BIN}/slicer" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "vm" && "${2:-}" == "list" && "${3:-}" == "--json" ]]; then
  if [[ "${MOCK_SLICER_VM_LIST_EXIT:-0}" -ne 0 ]]; then
    exit "${MOCK_SLICER_VM_LIST_EXIT:-0}"
  fi
  printf '%s\n' "${MOCK_SLICER_VM_LIST_JSON:-[]}"
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/slicer"
}

install_lsof_stub() {
  cat >"${TEST_BIN}/lsof" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *"-iTCP:443"*)
    if [[ -n "${MOCK_LSOF_443:-}" ]]; then
      printf '%s\n' "${MOCK_LSOF_443}"
      exit 0
    fi
    exit 1
    ;;
  *"-iTCP:58081"*)
    if [[ -n "${MOCK_LSOF_58081:-}" ]]; then
      printf '%s\n' "${MOCK_LSOF_58081}"
      exit 0
    fi
    exit 1
    ;;
esac
exit 1
EOF
  chmod +x "${TEST_BIN}/lsof"
}

install_ps_stub() {
  cat >"${TEST_BIN}/ps" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-ax" ]]; then
  printf '%s\n' "${MOCK_PS_AX_OUTPUT:-}"
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/ps"
}

@test "platform status reports no local projects when nothing is active" {
  run "${SCRIPT}" --execute --output json

  [ "${status}" -eq 0 ]

  run jq -r '.overall_state + "|" + (.active_provider // "null") + "|" + .projects.kind.state + "|" + .projects.lima.state + "|" + .projects.slicer.state + "|" + .projects.sdwan_lima.state' <<<"${output}"

  [ "${status}" -eq 0 ]
  [ "${output}" = 'idle|null|absent|absent|absent|absent' ]
}

@test "platform status reports kind as the active serving cluster" {
  export MOCK_DOCKER_PS=$'kind-local-control-plane|127.0.0.1:443->30070/tcp\nkind-local-worker|'
  export MOCK_DOCKER_PS_A="${MOCK_DOCKER_PS}"
  export MOCK_KIND_CLUSTERS='kind-local'
  touch "${HOME}/.kube/kind-kind-local.yaml"

  run "${SCRIPT}" --execute --output json

  [ "${status}" -eq 0 ]

  run jq -r '.overall_state + "|" + .active_provider + "|" + .providers.kind.state + "|" + (.providers.kind.serving|tostring) + "|" + (.providers.kind.runtime_present|tostring)' <<<"${output}"

  [ "${status}" -eq 0 ]
  [ "${output}" = 'running|kind|running|true|true' ]
}

@test "platform status reports kubernetes lima as active and sd-wan lima as another running project" {
  export MOCK_DOCKER_PS='limavm-platform-gateway-443|127.0.0.1:443->host.docker.internal:30070/tcp'
  export MOCK_DOCKER_PS_A="${MOCK_DOCKER_PS}"
  export MOCK_LSOF_58081=$'COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME\nlimactl 123 nick 12u IPv4 0xdeadbeef 0t0 TCP 127.0.0.1:58081 (LISTEN)'
  export MOCK_LIMACTL_LIST=$'NAME STATUS SSH CPUS MEMORY DISK DIR\nk3s-node-1 Running 127.0.0.1:60022 4 8GiB 25GiB ~/.lima/k3s-node-1\ncloud1 Running 127.0.0.1:60031 2 4GiB 20GiB ~/.lima/cloud1\ncloud2 Running 127.0.0.1:60032 2 4GiB 20GiB ~/.lima/cloud2\ncloud3 Running 127.0.0.1:60033 2 4GiB 20GiB ~/.lima/cloud3'
  touch "${HOME}/.kube/limavm-k3s.yaml"

  run "${SCRIPT}" --execute --output json

  [ "${status}" -eq 0 ]

  run jq -r '.active_provider + "|" + .projects.lima.state + "|" + .projects.sdwan_lima.state + "|" + (.projects.sdwan_lima.serving|tostring)' <<<"${output}"

  [ "${status}" -eq 0 ]
  [ "${output}" = 'lima|running|running|true' ]

  run "${SCRIPT}" --execute --output text

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Active cluster provider: kubernetes/lima"* ]]
  [[ "${output}" == *"sd-wan/lima"* ]]
}

@test "platform status reports lima as degraded when the vm is running but the localhost proxy is missing" {
  export MOCK_LIMACTL_LIST=$'NAME STATUS SSH CPUS MEMORY DISK DIR\nk3s-node-1 Running 127.0.0.1:60022 4 8GiB 25GiB ~/.lima/k3s-node-1'
  touch "${HOME}/.kube/limavm-k3s.yaml"

  run "${SCRIPT}" --execute --output json

  [ "${status}" -eq 0 ]

  run jq -r '.providers.lima.state + "|" + (.providers.lima.serving|tostring)' <<<"${output}"

  [ "${status}" -eq 0 ]
  [ "${output}" = 'degraded|false' ]
}

@test "platform status reports slicer as paused when the vm exists but is not running" {
  export MOCK_SLICER_VM_LIST_JSON='[{"hostname":"slicer-1","status":"Paused","ip":"192.168.64.2"}]'
  touch "${HOME}/.kube/slicer-k3s.yaml"

  run "${SCRIPT}" --execute --output json

  [ "${status}" -eq 0 ]

  run jq -r '.providers.slicer.state + "|" + (.providers.slicer.runtime_present|tostring)' <<<"${output}"

  [ "${status}" -eq 0 ]
  [ "${output}" = 'paused|true' ]
}

@test "platform status reports a conflict when multiple providers claim localhost https" {
  export MOCK_DOCKER_PS=$'kind-local-control-plane|127.0.0.1:443->30070/tcp\nlimavm-platform-gateway-443|127.0.0.1:443->host.docker.internal:30070/tcp'
  export MOCK_DOCKER_PS_A="${MOCK_DOCKER_PS}"
  export MOCK_KIND_CLUSTERS='kind-local'
  export MOCK_LIMACTL_LIST=$'NAME STATUS SSH CPUS MEMORY DISK DIR\nk3s-node-1 Running 127.0.0.1:60022 4 8GiB 25GiB ~/.lima/k3s-node-1'

  run "${SCRIPT}" --execute --output json

  [ "${status}" -eq 0 ]

  run jq -r '.overall_state + "|" + (.active_provider // "null")' <<<"${output}"

  [ "${status}" -eq 0 ]
  [ "${output}" = 'conflict|null' ]
}

@test "platform status reports foreign listeners on shared ports" {
  export MOCK_LSOF_443=$'COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME\nnginx 321 nick 12u IPv4 0xdeadbeef 0t0 TCP 127.0.0.1:443 (LISTEN)'

  run "${SCRIPT}" --execute --output json

  [ "${status}" -eq 0 ]

  run jq -r '.foreign_ports[0]' <<<"${output}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"127.0.0.1:443"* ]]
}

@test "platform status reports kind blockers when docker auth is missing" {
  export MOCK_AUTH_DHI_EXIT=1
  export MOCK_AUTH_DOCKER_EXIT=1

  run "${SCRIPT}" --execute --output json

  [ "${status}" -eq 0 ]

  run jq -r '(.providers.kind.readiness.dhi_auth|tostring) + "|" + (.providers.kind.readiness.docker_hub_auth|tostring) + "|" + .providers.kind.blockers[0]' <<<"${output}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == false\|false\|* ]]
}
