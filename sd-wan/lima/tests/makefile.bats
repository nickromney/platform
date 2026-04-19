#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN}"
  export PATH="${TEST_BIN}:/usr/bin:/bin:/usr/sbin:/sbin"
}

@test "sd-wan lima help documents the host port preflight" {
  run make -C "${REPO_ROOT}/sd-wan/lima" help

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"check-host-ports"* ]]
  [[ "${output}" == *"test-e2e"* ]]
}

@test "sd-wan lima cloud templates use a pipefail-safe repo lookup" {
  for cloud_yaml in \
    "${REPO_ROOT}/sd-wan/lima/cloud1.yaml" \
    "${REPO_ROOT}/sd-wan/lima/cloud2.yaml" \
    "${REPO_ROOT}/sd-wan/lima/cloud3.yaml"; do
    run grep -n -- "| head -1" "${cloud_yaml}"
    [ "${status}" -ne 0 ]

    run grep -n -- "-print -quit" "${cloud_yaml}"
    [ "${status}" -eq 0 ]
  done
}

@test "sd-wan lima prereqs fails cleanly when limactl is missing" {
  cat >"${TEST_BIN}/lsof" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 1
EOF
  chmod +x "${TEST_BIN}/lsof"

  run make -C "${REPO_ROOT}/sd-wan/lima" prereqs

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Missing Lima CLI: limactl"* ]]
  [[ "${output}" == *"Missing Bun runtime: bun"* ]]
  [[ "${output}" == *"Install hints:"* ]]
  [[ "${output}" == *"bun:"* ]]
  [[ "${output}" == *"limactl:"* ]]
}

@test "sd-wan lima build-frontend uses the bun-managed frontend workflow" {
  frontend_shared="${BATS_TEST_TMPDIR}/frontend-shared"
  frontend_dir="${BATS_TEST_TMPDIR}/frontend"
  mkdir -p "${frontend_shared}" "${frontend_dir}/dist"
  printf '%s\n' '<html>sd-wan</html>' >"${frontend_dir}/dist/index.html"

  cat >"${TEST_BIN}/npm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "npm should not be called by build-frontend" >&2
exit 1
EOF
  chmod +x "${TEST_BIN}/npm"

  export BUN_LOG="${BATS_TEST_TMPDIR}/bun.log"
  : >"${BUN_LOG}"
  cat >"${TEST_BIN}/bun" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s::%s\n' "$PWD" "$*" >>"${BUN_LOG:?}"
exit 0
EOF
  chmod +x "${TEST_BIN}/bun"

  env_file="${BATS_TEST_TMPDIR}/platform.env"
  cat >"${env_file}" <<'EOF'
PLATFORM_ADMIN_PASSWORD=admin-password
PLATFORM_DEMO_PASSWORD=demo-password
EOF

  run make -C "${REPO_ROOT}/sd-wan/lima" \
    FRONTEND_SHARED_DIR="${frontend_shared}" \
    FRONTEND_DIR="${frontend_dir}" \
    PLATFORM_ENV_FILE="${env_file}" \
    build-frontend

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"=== Building frontend ==="* ]]
  [[ "${output}" == *"Frontend built and staged to /tmp/lima/frontend/"* ]]

  run cat "${BUN_LOG}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"${frontend_shared}::run build"* ]]
  [[ "${output}" == *"${frontend_dir}::install --frozen-lockfile"* ]]
  [[ "${output}" == *"${frontend_dir}::run build"* ]]
}

@test "sd-wan lima fix-guest-hostnames executes the helper for running clouds" {
  export LIMA_LOG="${BATS_TEST_TMPDIR}/limactl.log"
  : >"${LIMA_LOG}"

  cat >"${TEST_BIN}/limactl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
log="${LIMA_LOG:?}"
if [[ "${1:-}" == "list" && "${2:-}" == "--format" && "${3:-}" == "{{.Name}} {{.Status}}" ]]; then
  printf '%s\n' "cloud1 Running" "cloud2 Stopped" "cloud3 Running"
  exit 0
fi
if [[ "${1:-}" == "shell" ]]; then
  printf '%s\n' "$*" >>"${log}"
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/limactl"

  run make -C "${REPO_ROOT}/sd-wan/lima" fix-guest-hostnames

  [ "${status}" -eq 0 ]

  run cat "${LIMA_LOG}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'shell cloud1 -- env TARGET_CLOUD_NAME=cloud1 bash '* ]]
  [[ "${output}" == *'fix-hostname.sh --execute'* ]]
  [[ "${output}" == *'shell cloud3 -- env TARGET_CLOUD_NAME=cloud3 bash '* ]]
  [[ "${output}" != *'shell cloud2'* ]]
}

@test "sd-wan lima host port preflight passes when no listeners are present" {
  cat >"${TEST_BIN}/lsof" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 1
EOF
  chmod +x "${TEST_BIN}/lsof"

  run make -C "${REPO_ROOT}/sd-wan/lima" check-host-ports

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"OK   lima host ports available:"* ]]
  [[ "${output}" == *"cloud1:tcp:127.0.0.1:58081->8080"* ]]
}

@test "sd-wan lima host port preflight reports listener conflicts" {
  cat >"${TEST_BIN}/lsof" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *"-iTCP:58081"* ]]; then
  cat <<'OUT'
COMMAND     PID USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
python3   27719 nick   12u  IPv4 0xdeadbeef      0t0  TCP 127.0.0.1:58081 (LISTEN)
OUT
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/lsof"

  cat >"${TEST_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "ps" ]]; then
  printf '%s\n' $'sdwan-proxy\t127.0.0.1:58081->8080/tcp'
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/docker"

  run make -C "${REPO_ROOT}/sd-wan/lima" check-host-ports

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"FAIL cloud1 host port tcp 127.0.0.1:58081 is already in use"* ]]
  [[ "${output}" == *"Planned mapping: cloud1.yaml guestPort=8080 -> tcp 127.0.0.1:58081"* ]]
  [[ "${output}" == *"Conflicting Docker publishers:"* ]]
  [[ "${output}" == *"sdwan-proxy: 127.0.0.1:58081->8080/tcp"* ]]
}

@test "sd-wan lima host port preflight reports overlapping planned forwards" {
  cloud_a="${BATS_TEST_TMPDIR}/cloud-a.yaml"
  cloud_b="${BATS_TEST_TMPDIR}/cloud-b.yaml"

  cat >"${cloud_a}" <<'EOF'
portForwards:
  - guestPort: 8080
    hostIP: 127.0.0.1
    hostPort: 58081
    proto: tcp
EOF

  cat >"${cloud_b}" <<'EOF'
portForwards:
  - guestPort: 9090
    hostIP: 0.0.0.0
    hostPort: 58081
    proto: tcp
EOF

  cat >"${TEST_BIN}/lsof" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 1
EOF
  chmod +x "${TEST_BIN}/lsof"

  run env LIMA_CLOUD_FILES="${cloud_a} ${cloud_b}" make -C "${REPO_ROOT}/sd-wan/lima" check-host-ports

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"FAIL planned Lima host port overlap: cloud-a (tcp 127.0.0.1:58081, guest 8080) conflicts with cloud-b (tcp 0.0.0.0:58081, guest 9090)"* ]]
}

@test "sd-wan lima host port preflight allows ports already owned by running lab instances" {
  cat >"${TEST_BIN}/lsof" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *"-iTCP:58081"*)
    cat <<'OUT'
COMMAND     PID USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
limactl   27719 nick   12u  IPv4 0xdeadbeef      0t0  TCP 127.0.0.1:58081 (LISTEN)
OUT
    exit 0
    ;;
esac
exit 1
EOF
  chmod +x "${TEST_BIN}/lsof"

  cat >"${TEST_BIN}/limactl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "list" ]]; then
  if [[ "${2:-}" == "--format" ]]; then
    printf '%s\n' "cloud1 Running" "cloud2 Running" "cloud3 Running"
    exit 0
  fi
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/limactl"

  run make -C "${REPO_ROOT}/sd-wan/lima" check-host-ports

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"OK   cloud1 host port tcp 127.0.0.1:58081 already owned by running cloud1 instance"* ]]
  [[ "${output}" == *"OK   lima host ports available:"* ]]
}

@test "sd-wan lima destroy reports when no lab instances exist" {
  rm -rf /tmp/lima/pki /tmp/lima/wireguard

  cat >"${TEST_BIN}/limactl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "list" && "${2:-}" == "--format" ]]; then
  exit 0
fi
if [[ "${1:-}" == "delete" ]]; then
  echo "unexpected delete" >&2
  exit 1
fi
exit 0
EOF
  chmod +x "${TEST_BIN}/limactl"

  cat >"${TEST_BIN}/pkill" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 1
EOF
  chmod +x "${TEST_BIN}/pkill"

  run make -C "${REPO_ROOT}/sd-wan/lima" destroy

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Skipping cloud1 (not present)"* ]]
  [[ "${output}" == *"Skipping cloud2 (not present)"* ]]
  [[ "${output}" == *"Skipping cloud3 (not present)"* ]]
  [[ "${output}" == *"No Lima instances found for this lab."* ]]
  [[ "${output}" == *"No generated PKI state found."* ]]
}

@test "sd-wan lima destroy reports deleted instances" {
  cat >"${TEST_BIN}/limactl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "list" && "${2:-}" == "--format" ]]; then
  printf '%s\n' "cloud1 Running" "cloud2 Stopped"
  exit 0
fi
if [[ "${1:-}" == "delete" && "${2:-}" == "--force" ]]; then
  printf 'deleted %s\n' "${3:-}"
  exit 0
fi
exit 0
EOF
  chmod +x "${TEST_BIN}/limactl"

  cat >"${TEST_BIN}/pkill" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 1
EOF
  chmod +x "${TEST_BIN}/pkill"

  mkdir -p /tmp/lima/pki /tmp/lima/wireguard

  run make -C "${REPO_ROOT}/sd-wan/lima" destroy

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Deleting cloud1 (Running)..."* ]]
  [[ "${output}" == *"deleted cloud1"* ]]
  [[ "${output}" == *"Deleting cloud2 (Stopped)..."* ]]
  [[ "${output}" == *"deleted cloud2"* ]]
  [[ "${output}" == *"Skipping cloud3 (not present)"* ]]
  [[ "${output}" == *"Removed /tmp/lima/pki"* ]]
  [[ "${output}" == *"Removed /tmp/lima/wireguard"* ]]
}

@test "sd-wan lima up reuses already-running instances and still resyncs lab state" {
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}/.lima/_config"
  cat >"${HOME}/.lima/_config/networks.yaml" <<'EOF'
paths:
  socketVMNet: "/bin/bash"
networks:
  user-v2:
EOF

  frontend_shared="${BATS_TEST_TMPDIR}/frontend-shared"
  frontend_dir="${BATS_TEST_TMPDIR}/frontend"
  mkdir -p "${frontend_shared}" "${frontend_dir}/dist"
  printf '%s\n' '<html>sd-wan</html>' >"${frontend_dir}/dist/index.html"

  check_host_ports="${BATS_TEST_TMPDIR}/check-host-ports.sh"
  cat >"${check_host_ports}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "host ports look good"
EOF
  chmod +x "${check_host_ports}"

  cat >"${TEST_BIN}/node" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' 'v20.0.0'
EOF
  chmod +x "${TEST_BIN}/node"

  cat >"${TEST_BIN}/npm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "npm should not be called by up" >&2
exit 1
EOF
  chmod +x "${TEST_BIN}/npm"

  cat >"${TEST_BIN}/bun" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/bun"

  export LIMA_LOG="${BATS_TEST_TMPDIR}/limactl.log"
  : >"${LIMA_LOG}"
  cat >"${TEST_BIN}/limactl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
log="${LIMA_LOG:?}"
case "${1:-}" in
  --version)
    printf '%s\n' 'limactl version 1.0.0'
    ;;
  list)
    if [[ "${2:-}" == "--format" ]]; then
      case "${3:-}" in
        "{{.Name}}")
          printf '%s\n' cloud1 cloud2 cloud3
          ;;
        "{{.Name}} {{.Status}}")
          printf '%s\n' "cloud1 Running" "cloud2 Running" "cloud3 Running"
          ;;
      esac
      exit 0
    fi
    cat <<'OUT'
NAME    STATUS
cloud1  Running
cloud2  Running
cloud3  Running
OUT
    ;;
  start)
    printf 'start %s\n' "$*" >>"${log}"
    ;;
  shell)
    printf 'shell %s\n' "${2:-unknown}" >>"${log}"
    ;;
esac
EOF
  chmod +x "${TEST_BIN}/limactl"

  env_file="${BATS_TEST_TMPDIR}/platform.env"
  cat >"${env_file}" <<'EOF'
PLATFORM_ADMIN_PASSWORD=admin-password
PLATFORM_DEMO_PASSWORD=demo-password
EOF

  run make -C "${REPO_ROOT}/sd-wan/lima" \
    CHECK_HOST_PORTS="${check_host_ports}" \
    FRONTEND_SHARED_DIR="${frontend_shared}" \
    FRONTEND_DIR="${frontend_dir}" \
    PLATFORM_ENV_FILE="${env_file}" \
    up

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"=== Starting SD-WAN simulation ==="* ]]
  [[ "${output}" == *"cloud1 already running"* ]]
  [[ "${output}" == *"cloud2 already running"* ]]
  [[ "${output}" == *"cloud3 already running"* ]]
  [[ "${output}" == *"=== Syncing frontend on cloud1 ==="* ]]
  [[ "${output}" == *"=== Syncing subnet calculator API on cloud2 ==="* ]]
  [[ "${output}" == *"=== Syncing WireGuard mesh ==="* ]]
  [[ "${output}" != *"Starting existing cloud1"* ]]
  [[ "${output}" != *"Creating and starting cloud1"* ]]

  run cat "${LIMA_LOG}"

  [ "${status}" -eq 0 ]
  [[ "${output}" != *"start cloud1"* ]]
  [[ "${output}" != *"start cloud2"* ]]
  [[ "${output}" != *"start cloud3"* ]]
  [[ "${output}" == *"shell cloud1"* ]]
  [[ "${output}" == *"shell cloud2"* ]]
  [[ "${output}" == *"shell cloud3"* ]]
}
