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
    if [[ -n "${MOCK_AUTH_DHI_OUTPUT:-}" ]]; then
      printf '%s\n' "${MOCK_AUTH_DHI_OUTPUT}"
    fi
    exit "${MOCK_AUTH_DHI_EXIT:-0}"
    ;;
  index.docker.io|docker.io)
    if [[ -n "${MOCK_AUTH_DOCKER_OUTPUT:-}" ]]; then
      printf '%s\n' "${MOCK_AUTH_DOCKER_OUTPUT}"
    fi
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
if [[ "$*" =~ -i(TCP|UDP):([0-9]+) ]]; then
  port="${BASH_REMATCH[2]}"
  env_var="MOCK_LSOF_${port}"
  if [[ -n "${!env_var:-}" ]]; then
    printf '%s\n' "${!env_var}"
    exit 0
  fi
fi
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

install_colima_stub() {
  cat >"${TEST_BIN}/colima" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  status)
    if [[ -n "${MOCK_COLIMA_STATUS_OUTPUT:-}" ]]; then
      printf '%s\n' "${MOCK_COLIMA_STATUS_OUTPUT}"
    fi
    exit "${MOCK_COLIMA_STATUS_EXIT:-1}"
    ;;
esac
exit 1
EOF
  chmod +x "${TEST_BIN}/colima"
}

install_podman_stub() {
  cat >"${TEST_BIN}/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  info)
    if [[ -n "${MOCK_PODMAN_INFO_OUTPUT:-}" ]]; then
      printf '%s\n' "${MOCK_PODMAN_INFO_OUTPUT}"
    fi
    exit "${MOCK_PODMAN_INFO_EXIT:-1}"
    ;;
esac
exit 1
EOF
  chmod +x "${TEST_BIN}/podman"
}

@test "no variant owns the machine when no local stack is active" {
  run "${SCRIPT}" --execute --output json

  [ "${status}" -eq 0 ]

  run jq -r '.overall_state + "|" + (.active_variant // "null") + "|" + .variants.kind.state + "|" + .variants.lima.state + "|" + .variants.slicer.state + "|" + .variants.sdwan_lima.state' <<<"${output}"

  [ "${status}" -eq 0 ]
  [ "${output}" = 'idle|null|absent|absent|absent|absent' ]
}

@test "the reference variant owns the machine when kind is serving traffic" {
  export MOCK_DOCKER_PS=$'kind-local-control-plane|127.0.0.1:443->30070/tcp\nkind-local-worker|'
  export MOCK_DOCKER_PS_A=$'kind-local-control-plane|Up 1 minute|127.0.0.1:443->30070/tcp\nkind-local-worker|Up 1 minute|'
  export MOCK_KIND_CLUSTERS='kind-local'
  touch "${HOME}/.kube/kind-kind-local.yaml"

  run "${SCRIPT}" --execute --output json

  [ "${status}" -eq 0 ]

  run jq -r '.overall_state + "|" + .active_cluster_variant + "|" + .cluster_variants.kind.state + "|" + (.cluster_variants.kind.serving|tostring) + "|" + (.cluster_variants.kind.runtime_present|tostring)' <<<"${output}"

  [ "${status}" -eq 0 ]
  [ "${output}" = 'running|kind|running|true|true' ]

  run "${SCRIPT}" --execute --output text

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"CLAIMED BY"* ]]
  [[ "${output}" == *"shared host ports"* ]]
  [[ "${output}" == *"kubernetes/kind"* ]]
  [[ "${output}" != *"is already using shared localhost ports"* ]]

  run awk '/^kubernetes\/lima[[:space:]]/ { print; exit }' <<<"${output}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"kubernetes/kind"* ]]
  [[ "${output}" == *"shared host ports"* ]]
}

@test "platform status exposes variant-oriented operator fields without provider aliases" {
  export MOCK_DOCKER_PS=$'kind-local-control-plane|127.0.0.1:443->30070/tcp\nkind-local-worker|'
  export MOCK_DOCKER_PS_A=$'kind-local-control-plane|Up 1 minute|127.0.0.1:443->30070/tcp\nkind-local-worker|Up 1 minute|'
  export MOCK_KIND_CLUSTERS='kind-local'
  touch "${HOME}/.kube/kind-kind-local.yaml"

  run "${SCRIPT}" --execute --output json

  [ "${status}" -eq 0 ]

  run jq -r '[
    has("active_provider"),
    has("active_provider_path"),
    has("active_project"),
    has("active_project_path"),
    has("providers"),
    has("projects"),
    (.actions | any(has("provider") or has("project")))
  ] | map(tostring) | join("|")' <<<"${output}"

  [ "${status}" -eq 0 ]
  [ "${output}" = 'false|false|false|false|false|false|false' ]

  run "${SCRIPT}" --execute --output text

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Active cluster variant: kubernetes/kind"* ]]
  [[ "${output}" == *"Active variant: kubernetes/kind"* ]]
  [[ "${output}" != *"Active cluster provider:"* ]]
  [[ "${output}" != *"Active provider:"* ]]
}

@test "platform status exposes IDP core component actions" {
  run "${SCRIPT}" --execute --output json

  [ "${status}" -eq 0 ]

  run jq -r '
    [
      (.actions | any(.id == "kind-idp-catalog" and .command == "make -C kubernetes/kind idp-catalog")),
      (.actions | any(.id == "kind-idp-env-create" and (.command | contains("idp-env ACTION=create APP=hello-platform ENV=preview-nr")))),
      (.actions | any(.id == "kind-idp-deployments" and .command == "make -C kubernetes/kind idp-deployments")),
      (.actions | any(.id == "kind-idp-secrets" and .command == "make -C kubernetes/kind idp-secrets")),
      (.actions | any(.id == "kind-gitea-repo-lifecycle-demo" and (.command | contains("gitea-repo-lifecycle-demo"))))
    ] | map(tostring) | join("|")
  ' <<<"${output}"

  [ "${status}" -eq 0 ]
  [ "${output}" = 'true|true|true|true|true' ]
}

@test "platform status falls back to docker ps when docker info is unavailable" {
  export MOCK_DOCKER_INFO_EXIT=1
  export MOCK_DOCKER_PS=$'kind-local-control-plane|127.0.0.1:443->30070/tcp\nkind-local-worker|'
  export MOCK_DOCKER_PS_A=$'kind-local-control-plane|Up 1 minute|127.0.0.1:443->30070/tcp\nkind-local-worker|Up 1 minute|'
  export MOCK_KIND_CLUSTERS='kind-local'
  touch "${HOME}/.kube/kind-kind-local.yaml"

  run "${SCRIPT}" --execute --output json

  [ "${status}" -eq 0 ]

  run jq -r '.platforms.docker.detail + "|" + .cluster_variants.kind.state + "|" + (.cluster_variants.kind.runtime_present|tostring)' <<<"${output}"

  [ "${status}" -eq 0 ]
  [ "${output}" = 'context=desktop-linux|running|true' ]
}

@test "platform status reports kubernetes lima as active and sd-wan lima as another running project" {
  export MOCK_LSOF_58081=$'COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME\nlimactl 123 nick 12u IPv4 0xdeadbeef 0t0 TCP 127.0.0.1:58081 (LISTEN)'
  export MOCK_LSOF_443=$'COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME\nlimactl 123 nick 12u IPv4 0xdeadbeef 0t0 TCP 127.0.0.1:443 (LISTEN)'
  export MOCK_LSOF_30022=$'COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME\nlimactl 123 nick 13u IPv4 0xdeadbeef 0t0 TCP 127.0.0.1:30022 (LISTEN)'
  export MOCK_LSOF_30080=$'COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME\nlimactl 123 nick 14u IPv4 0xdeadbeef 0t0 TCP 127.0.0.1:30080 (LISTEN)'
  export MOCK_LSOF_30090=$'COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME\nlimactl 123 nick 15u IPv4 0xdeadbeef 0t0 TCP 127.0.0.1:30090 (LISTEN)'
  export MOCK_LSOF_31235=$'COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME\nlimactl 123 nick 16u IPv4 0xdeadbeef 0t0 TCP 127.0.0.1:31235 (LISTEN)'
  export MOCK_LSOF_3301=$'COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME\nlimactl 123 nick 17u IPv4 0xdeadbeef 0t0 TCP 127.0.0.1:3301 (LISTEN)'
  export MOCK_LIMACTL_LIST=$'NAME STATUS SSH CPUS MEMORY DISK DIR\nk3s-node-1 Running 127.0.0.1:60022 4 8GiB 25GiB ~/.lima/k3s-node-1\ncloud1 Running 127.0.0.1:60031 2 4GiB 20GiB ~/.lima/cloud1\ncloud2 Running 127.0.0.1:60032 2 4GiB 20GiB ~/.lima/cloud2\ncloud3 Running 127.0.0.1:60033 2 4GiB 20GiB ~/.lima/cloud3'
  touch "${HOME}/.kube/limavm-k3s.yaml"

  run "${SCRIPT}" --execute --output json

  [ "${status}" -eq 0 ]

  run jq -r '.active_cluster_variant + "|" + .variants.lima.state + "|" + .variants.sdwan_lima.state + "|" + (.variants.sdwan_lima.serving|tostring)' <<<"${output}"

  [ "${status}" -eq 0 ]
  [ "${output}" = 'lima|running|running|true' ]

  run "${SCRIPT}" --execute --output text

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Active cluster variant: kubernetes/lima"* ]]
  [[ "${output}" == *"sd-wan/lima"* ]]
  [[ "${output}" == *"30022,30080,30090"* ]]
  [[ "${output}" == *"31235,3301,443"* ]]
  [[ "${output}" != *"127.0.0.1:30022"* ]]
  [[ "${output}" != *"127.0.0.1:30090"* ]]
  [[ "${output}" != *"127.0.0.1:31235"* ]]

  run awk '/^kubernetes\/lima[[:space:]]/ { print; getline; print; exit }' <<<"${output}"

  [ "${status}" -eq 0 ]
  first_line="$(printf '%s\n' "${output}" | sed -n '1p')"
  second_line="$(printf '%s\n' "${output}" | sed -n '2p')"
  [[ "${first_line}" == *"30022,30080,30090"* ]]
  [[ "${second_line}" == *"31235,3301,443"* ]]
  [[ "${second_line}" != *"kubernetes/lima"* ]]
}

@test "platform status reports lima as degraded when the vm is running but the localhost proxy is missing" {
  export MOCK_LIMACTL_LIST=$'NAME STATUS SSH CPUS MEMORY DISK DIR\nk3s-node-1 Running 127.0.0.1:60022 4 8GiB 25GiB ~/.lima/k3s-node-1'
  touch "${HOME}/.kube/limavm-k3s.yaml"

  run "${SCRIPT}" --execute --output json

  [ "${status}" -eq 0 ]

  run jq -r '.cluster_variants.lima.state + "|" + (.cluster_variants.lima.serving|tostring)' <<<"${output}"

  [ "${status}" -eq 0 ]
  [ "${output}" = 'degraded|false' ]
}

@test "platform status reports slicer as paused when the vm exists but is not running" {
  export MOCK_SLICER_VM_LIST_JSON='[{"hostname":"slicer-1","status":"Paused","ip":"192.168.64.2"}]'
  touch "${HOME}/.kube/slicer-k3s.yaml"

  run "${SCRIPT}" --execute --output json

  [ "${status}" -eq 0 ]

  run jq -r '.cluster_variants.slicer.state + "|" + (.cluster_variants.slicer.runtime_present|tostring)' <<<"${output}"

  [ "${status}" -eq 0 ]
  [ "${output}" = 'paused|true' ]
}

@test "platform status reports a conflict when multiple cluster variants claim localhost https" {
  export MOCK_DOCKER_PS=$'kind-local-control-plane|127.0.0.1:443->30070/tcp\nlimavm-platform-gateway-443|127.0.0.1:443->host.docker.internal:30070/tcp'
  export MOCK_DOCKER_PS_A=$'kind-local-control-plane|Up 1 minute|127.0.0.1:443->30070/tcp\nlimavm-platform-gateway-443|Up 1 minute|127.0.0.1:443->host.docker.internal:30070/tcp'
  export MOCK_KIND_CLUSTERS='kind-local'
  export MOCK_LSOF_443=$'COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME\nlimactl 123 nick 12u IPv4 0xdeadbeef 0t0 TCP 127.0.0.1:443 (LISTEN)'
  export MOCK_LIMACTL_LIST=$'NAME STATUS SSH CPUS MEMORY DISK DIR\nk3s-node-1 Running 127.0.0.1:60022 4 8GiB 25GiB ~/.lima/k3s-node-1'

  run "${SCRIPT}" --execute --output json

  [ "${status}" -eq 0 ]

  run jq -r '.overall_state + "|" + (.active_cluster_variant // "null")' <<<"${output}"

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

@test "platform status keeps the legacy provider ports env alias working" {
  export PLATFORM_STATUS_SHARED_PORTS=""
  export PLATFORM_STATUS_SDWAN_PORTS=""
  export PLATFORM_STATUS_PROVIDER_PORTS="5555"
  export MOCK_LSOF_5555=$'COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME\nnginx 321 nick 12u IPv4 0xdeadbeef 0t0 TCP 127.0.0.1:5555 (LISTEN)'

  run "${SCRIPT}" --execute --output json

  [ "${status}" -eq 0 ]

  run jq -r '.foreign_ports[0]' <<<"${output}"

  [ "${status}" -eq 0 ]
  [ "${output}" = '127.0.0.1:5555' ]
}

@test "platform status reports kind blockers when docker auth is missing" {
  export MOCK_AUTH_DHI_EXIT=1
  export MOCK_AUTH_DOCKER_EXIT=1

  run "${SCRIPT}" --execute --output json

  [ "${status}" -eq 0 ]

  run jq -r '(.cluster_variants.kind.readiness.dhi_auth|tostring) + "|" + (.cluster_variants.kind.readiness.docker_hub_auth|tostring) + "|" + .cluster_variants.kind.blockers[0]' <<<"${output}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == false\|false\|* ]]
}

@test "platform status reports platforms and registry auth sources" {
  install_colima_stub
  install_podman_stub
  export MOCK_COLIMA_STATUS_EXIT=0
  export MOCK_COLIMA_STATUS_OUTPUT='INFO colima is running using qemu'
  export MOCK_PODMAN_INFO_EXIT=0
  export MOCK_PODMAN_INFO_OUTPUT='host: podman machine is running'
  export MOCK_AUTH_DHI_OUTPUT='OK   Docker Hardened Images (dhi.io) credentials found via docker-credential-desktop'
  export MOCK_AUTH_DOCKER_OUTPUT='OK   Docker Hub credentials found in config.json'

  run "${SCRIPT}" --execute --output json

  [ "${status}" -eq 0 ]

  run jq -r '(.platforms.docker.running|tostring)
    + "|" + (.host_runtimes.colima.available|tostring)
    + "|" + (.host_runtimes.colima.running|tostring)
    + "|" + (.host_runtimes.podman.running|tostring)
    + "|" + (.platforms.lima.available|tostring)
    + "|" + (.platforms.slicer.available|tostring)
    + "|" + (.registry_auth.dhi_io.authenticated|tostring)
    + "|" + (.registry_auth.dhi_io.source // "-")
    + "|" + (.registry_auth.docker_io.source // "-")' <<<"${output}"

  [ "${status}" -eq 0 ]
  [ "${output}" = 'true|true|true|true|true|true|true|docker-credential-desktop|config.json' ]

  run "${SCRIPT}" --execute --output text

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Platforms:"* ]]
  [[ "${output}" == *"lima"* ]]
  [[ "${output}" == *"slicer"* ]]
  [[ "${output}" == *"Registry auth (Docker config + credential helper probe):"* ]]
  [[ "${output}" == *"docker-credential-desktop"* ]]
  [[ "${output}" == *"config.json"* ]]
}

@test "platform status text shows only available platforms in alphabetical order" {
  run "${SCRIPT}" --execute --output text

  [ "${status}" -eq 0 ]
  [[ "${output}" == *$'Platforms:\nPLATFORM  AVAIL  RUNNING  DETAIL'* ]]
  [[ "${output}" == *$'\ndocker    Y      Y'* ]]
  [[ "${output}" == *$'\nlima      Y      N'* ]]
  [[ "${output}" == *$'\nslicer    Y      N'* ]]
  [[ "${output}" != *$'\ncolima    '* ]]
  [[ "${output}" != *$'\npodman    '* ]]

  docker_line="$(printf '%s\n' "${output}" | awk '/^docker[[:space:]]/ { print NR; exit }')"
  lima_line="$(printf '%s\n' "${output}" | awk '/^lima[[:space:]]/ { print NR; exit }')"
  slicer_line="$(printf '%s\n' "${output}" | awk '/^slicer[[:space:]]/ { print NR; exit }')"
  [ -n "${docker_line}" ]
  [ -n "${lima_line}" ]
  [ -n "${slicer_line}" ]
  [ "${docker_line}" -lt "${lima_line}" ]
  [ "${lima_line}" -lt "${slicer_line}" ]
}
