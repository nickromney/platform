#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export HOST_PORT_LISTENERS_LIB="${REPO_ROOT}/scripts/lib/host-port-listeners.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN}"
  export PATH="${TEST_BIN}:${PATH}"
}

@test "host_port_listeners_for_port filters loopback listeners for loopback binds" {
  cat >"${TEST_BIN}/lsof" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *"-iTCP:8443"* ]]; then
  cat <<'OUT'
COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
nginx 101 nick 12u IPv4 0x1 0t0 TCP *:8443 (LISTEN)
python 102 nick 13u IPv4 0x2 0t0 TCP 127.0.0.1:8443 (LISTEN)
node 103 nick 14u IPv4 0x3 0t0 TCP localhost:8443 (LISTEN)
ssh 104 nick 15u IPv6 0x4 0t0 TCP [::1]:8443 (LISTEN)
postgres 105 nick 16u IPv4 0x5 0t0 TCP 192.168.1.20:8443 (LISTEN)
OUT
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/lsof"

  run bash -lc "export PATH='${TEST_BIN}:'\"\$PATH\"; source '${HOST_PORT_LISTENERS_LIB}'; host_port_listeners_for_port 127.0.0.1 8443"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"COMMAND PID USER"* ]]
  [[ "${output}" == *"TCP *:8443 (LISTEN)"* ]]
  [[ "${output}" == *"TCP 127.0.0.1:8443 (LISTEN)"* ]]
  [[ "${output}" == *"TCP localhost:8443 (LISTEN)"* ]]
  [[ "${output}" == *"TCP [::1]:8443 (LISTEN)"* ]]
  [[ "${output}" != *"192.168.1.20:8443"* ]]
}

@test "host_port_listeners_for_port keeps all listeners for wildcard binds" {
  cat >"${TEST_BIN}/lsof" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat <<'OUT'
COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
nginx 101 nick 12u IPv4 0x1 0t0 TCP 127.0.0.1:8088 (LISTEN)
postgres 105 nick 16u IPv4 0x5 0t0 TCP 192.168.1.20:8088 (LISTEN)
OUT
EOF
  chmod +x "${TEST_BIN}/lsof"

  run bash -lc "export PATH='${TEST_BIN}:'\"\$PATH\"; source '${HOST_PORT_LISTENERS_LIB}'; host_port_listeners_for_port 0.0.0.0 8088"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"127.0.0.1:8088"* ]]
  [[ "${output}" == *"192.168.1.20:8088"* ]]
}

@test "host_port_listeners_for_port falls back to ss when lsof is unavailable" {
  ln -s "$(command -v awk)" "${TEST_BIN}/awk"

  cat >"${TEST_BIN}/ss" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' \
  'LISTEN 0 4096 127.0.0.1:8300 0.0.0.0:*' \
  'LISTEN 0 4096 10.0.0.5:8300 0.0.0.0:*'
EOF
  chmod +x "${TEST_BIN}/ss"

  run /bin/bash -lc "export PATH='${TEST_BIN}'; source '${HOST_PORT_LISTENERS_LIB}'; host_port_listeners_for_port 127.0.0.1 8300"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"State Recv-Q Send-Q Local Address:Port Peer Address:Port"* ]]
  [[ "${output}" == *"127.0.0.1:8300"* ]]
  [[ "${output}" != *"10.0.0.5:8300"* ]]
}

@test "host_port_listener_addresses_for_ports returns normalized unique listener addresses" {
  cat >"${TEST_BIN}/lsof" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *"-iTCP:443"*)
    cat <<'OUT'
COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
nginx 101 nick 12u IPv4 0x1 0t0 TCP *:443 (LISTEN)
node 102 nick 13u IPv4 0x2 0t0 TCP localhost:443 (LISTEN)
OUT
    ;;
  *"-iTCP:8443"*)
    cat <<'OUT'
COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
nginx 101 nick 12u IPv4 0x1 0t0 TCP *:443 (LISTEN)
ssh 103 nick 14u IPv6 0x3 0t0 TCP [::1]:8443 (LISTEN)
OUT
    ;;
  *)
    exit 1
    ;;
esac
EOF
  chmod +x "${TEST_BIN}/lsof"

  run bash -lc "export PATH='${TEST_BIN}:'\"\$PATH\"; source '${HOST_PORT_LISTENERS_LIB}'; host_port_listener_addresses_for_ports '443 8443'"

  [ "${status}" -eq 0 ]
  [ "${output}" = "$(printf '0.0.0.0:443\n127.0.0.1:443\n[::1]:8443')" ]
}

@test "host_port_binds_overlap matches shared-port wildcard conflicts" {
  run bash -lc "source '${HOST_PORT_LISTENERS_LIB}'; host_port_binds_overlap 127.0.0.1 443 0.0.0.0 443"
  [ "${status}" -eq 0 ]

  run bash -lc "source '${HOST_PORT_LISTENERS_LIB}'; host_port_binds_overlap 127.0.0.1 443 127.0.0.1 8443"
  [ "${status}" -ne 0 ]

  run bash -lc "source '${HOST_PORT_LISTENERS_LIB}'; host_port_binds_overlap 127.0.0.1 443 192.168.1.20 443"
  [ "${status}" -ne 0 ]
}
