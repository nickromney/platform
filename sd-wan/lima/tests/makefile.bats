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
  [[ "${output}" == *"Install hints:"* ]]
  [[ "${output}" == *"limactl:"* ]]
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
