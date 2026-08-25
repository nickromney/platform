#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
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
  'LISTEN 0 4096 [::1]:8300 [::]:*' \
  'LISTEN 0 4096 10.0.0.5:8300 0.0.0.0:*'
EOF
  chmod +x "${TEST_BIN}/ss"

  run /bin/bash -lc "export PATH='${TEST_BIN}'; source '${HOST_PORT_LISTENERS_LIB}'; host_port_listeners_for_port 127.0.0.1 8300"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"State Recv-Q Send-Q Local Address:Port Peer Address:Port"* ]]
  [[ "${output}" == *"127.0.0.1:8300"* ]]
  # The [::1] row also kills LOGICAL_AND_OR at host-port-listeners.sh:45:
  # ANDing the last two loopback alternatives makes both unsatisfiable, so
  # an IPv6 loopback listener stops counting as a conflict.
  [[ "${output}" == *"[::1]:8300"* ]]
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
  # The identical-IP case kills LOGICAL_AND_OR at host-port-listeners.sh:154:
  # ANDing the first two alternatives makes a same-address collision report
  # no overlap unless one side is also the wildcard.
  run bash -lc "source '${HOST_PORT_LISTENERS_LIB}'; host_port_binds_overlap 127.0.0.1 443 127.0.0.1 443"
  [ "${status}" -eq 0 ]

  run bash -lc "source '${HOST_PORT_LISTENERS_LIB}'; host_port_binds_overlap 127.0.0.1 443 0.0.0.0 443"
  [ "${status}" -eq 0 ]

  run bash -lc "source '${HOST_PORT_LISTENERS_LIB}'; host_port_binds_overlap 127.0.0.1 443 127.0.0.1 8443"
  [ "${status}" -ne 0 ]

  run bash -lc "source '${HOST_PORT_LISTENERS_LIB}'; host_port_binds_overlap 127.0.0.1 443 192.168.1.20 443"
  [ "${status}" -ne 0 ]
}

@test "host_port_listeners_for_port keeps lsof output when lsof exits nonzero" {
  # Kills LOGICAL_AND_OR and BOOLEAN_LITERAL at host-port-listeners.sh:15.
  # lsof exits nonzero when it cannot examine every socket -- a routine
  # occurrence on a shared host -- while still printing the listeners it did
  # resolve. Without `|| true` the assignment inherits that status and an
  # errexit caller aborts before any listener is reported, which reads as a
  # free port.
  cat >"${TEST_BIN}/lsof" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
nginx 101 nick 12u IPv4 0x1 0t0 TCP 127.0.0.1:8443 (LISTEN)
OUT
exit 1
EOF
  chmod +x "${TEST_BIN}/lsof"

  run bash -lc "export PATH='${TEST_BIN}:'\"\$PATH\"; set -euo pipefail; source '${HOST_PORT_LISTENERS_LIB}'; host_port_listeners_for_port 127.0.0.1 8443"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"TCP 127.0.0.1:8443 (LISTEN)"* ]]
}

@test "host_port_listeners_for_port reports failure when nothing is listening" {
  # Kills RETURN_CODE at host-port-listeners.sh:16. An empty lsof result is the
  # free-port case, which callers read off the nonzero status. Flipped to
  # `return 0` every free port reports a conflict with no rows to show for it.
  cat >"${TEST_BIN}/lsof" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "${TEST_BIN}/lsof"

  run bash -lc "export PATH='${TEST_BIN}:'\"\$PATH\"; source '${HOST_PORT_LISTENERS_LIB}'; host_port_listeners_for_port 127.0.0.1 8443"

  [ "${status}" -eq 1 ]
  [ -z "${output}" ]
}

@test "host_port_listeners_for_port reports failure when no lsof listener matches a loopback bind" {
  # Kills RETURN_CODE at host-port-listeners.sh:28. The port is busy, but only
  # on an address a 127.0.0.1 bind cannot collide with, so the bind is free.
  # Flipped to `return 0` the caller is told about a conflict and handed the
  # header row alone.
  cat >"${TEST_BIN}/lsof" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
postgres 105 nick 16u IPv4 0x5 0t0 TCP 192.168.1.20:8443 (LISTEN)
OUT
EOF
  chmod +x "${TEST_BIN}/lsof"

  run bash -lc "export PATH='${TEST_BIN}:'\"\$PATH\"; source '${HOST_PORT_LISTENERS_LIB}'; host_port_listeners_for_port 127.0.0.1 8443"

  [ "${status}" -eq 1 ]
  [ -z "${output}" ]
}

@test "host_port_listeners_for_port keeps ss output when ss exits nonzero" {
  # Kills LOGICAL_AND_OR and BOOLEAN_LITERAL at host-port-listeners.sh:37, the
  # ss half of the guard covered at :15.
  ln -s "$(command -v awk)" "${TEST_BIN}/awk"

  cat >"${TEST_BIN}/ss" <<'EOF'
#!/bin/sh
printf '%s\n' 'LISTEN 0 4096 127.0.0.1:8300 0.0.0.0:*'
exit 1
EOF
  chmod +x "${TEST_BIN}/ss"

  run /bin/bash -lc "export PATH='${TEST_BIN}'; set -euo pipefail; source '${HOST_PORT_LISTENERS_LIB}'; host_port_listeners_for_port 127.0.0.1 8300"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"127.0.0.1:8300"* ]]
}

@test "host_port_listeners_for_port reports failure when ss finds nothing" {
  # Kills RETURN_CODE at host-port-listeners.sh:38, the ss half of :16.
  ln -s "$(command -v awk)" "${TEST_BIN}/awk"

  cat >"${TEST_BIN}/ss" <<'EOF'
#!/bin/sh
exit 0
EOF
  chmod +x "${TEST_BIN}/ss"

  run /bin/bash -lc "export PATH='${TEST_BIN}'; source '${HOST_PORT_LISTENERS_LIB}'; host_port_listeners_for_port 127.0.0.1 8300"

  [ "${status}" -eq 1 ]
  [ -z "${output}" ]
}

@test "host_port_listeners_for_port reports failure when no ss listener matches a loopback bind" {
  # Kills RETURN_CODE at host-port-listeners.sh:51, the ss half of :28. The
  # awk filter empties the body, and an empty body after filtering still means
  # the loopback bind is free.
  ln -s "$(command -v awk)" "${TEST_BIN}/awk"

  cat >"${TEST_BIN}/ss" <<'EOF'
#!/bin/sh
printf '%s\n' 'LISTEN 0 4096 10.0.0.5:8300 0.0.0.0:*'
EOF
  chmod +x "${TEST_BIN}/ss"

  run /bin/bash -lc "export PATH='${TEST_BIN}'; source '${HOST_PORT_LISTENERS_LIB}'; host_port_listeners_for_port 127.0.0.1 8300"

  [ "${status}" -eq 1 ]
  [ -z "${output}" ]
}

@test "host_port_listener_addresses_from_lsof accepts empty input" {
  # Kills RETURN_CODE at host-port-listeners.sh:78. No lsof output is the
  # free-port case: success with no rows, not an error. The callers below feed
  # this helper unconditionally, so a nonzero return here aborts the sweep.
  run bash -lc "source '${HOST_PORT_LISTENERS_LIB}'; host_port_listener_addresses_from_lsof ''"

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "host_port_listener_addresses_from_lsof reads rows that carry no (LISTEN) suffix" {
  # Kills LOGICAL_AND_OR at host-port-listeners.sh:82. Both halves have to hold
  # before the address is taken from the penultimate field. ORed, `NF > 1` is
  # true for every real row, so the address is always read one field early --
  # here `TCP`, which the trailing-port check then discards, losing the
  # listener entirely.
  input="$(printf 'COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME\nnginx 101 nick 12u IPv4 0x1 0t0 TCP 127.0.0.1:8443\n')"

  run bash -lc "source '${HOST_PORT_LISTENERS_LIB}'; host_port_listener_addresses_from_lsof \"\$1\"" _ "${input}"

  [ "${status}" -eq 0 ]
  [ "${output}" = "127.0.0.1:8443" ]
}

@test "host_port_listener_addresses_from_ss accepts empty input" {
  # Kills RETURN_CODE at host-port-listeners.sh:98, the ss half of :78.
  run bash -lc "source '${HOST_PORT_LISTENERS_LIB}'; host_port_listener_addresses_from_ss ''"

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "host_port_listener_addresses_from_ss normalizes the local address field" {
  # Kills LOGICAL_AND_OR at host-port-listeners.sh:98 -- ANDed, non-empty input
  # returns before the awk runs and every listener disappears -- and
  # STRING_COMPARE at :101, where inverting the guard reads the peer address in
  # $5 instead of the local address in $4, and `0.0.0.0:*` fails the
  # trailing-port check.
  input="$(printf 'LISTEN 0 4096 *:8300 0.0.0.0:*\nLISTEN 0 4096 [::1]:8300 [::]:*\n')"

  run bash -lc "source '${HOST_PORT_LISTENERS_LIB}'; host_port_listener_addresses_from_ss \"\$1\"" _ "${input}"

  [ "${status}" -eq 0 ]
  [ "${output}" = "$(printf '0.0.0.0:8300\n[::1]:8300')" ]
}

@test "host_port_listener_addresses_for_port keeps addresses when lsof exits nonzero" {
  # Kills LOGICAL_AND_OR and BOOLEAN_LITERAL at host-port-listeners.sh:119, the
  # address-sweep copy of the guard covered at :15.
  cat >"${TEST_BIN}/lsof" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
nginx 101 nick 12u IPv4 0x1 0t0 TCP 127.0.0.1:8443 (LISTEN)
OUT
exit 1
EOF
  chmod +x "${TEST_BIN}/lsof"

  run bash -lc "export PATH='${TEST_BIN}:'\"\$PATH\"; set -euo pipefail; source '${HOST_PORT_LISTENERS_LIB}'; host_port_listener_addresses_for_port 8443"

  [ "${status}" -eq 0 ]
  [ "${output}" = "127.0.0.1:8443" ]
}

@test "host_port_listener_addresses_for_port keeps addresses when ss exits nonzero" {
  # Kills LOGICAL_AND_OR and BOOLEAN_LITERAL at host-port-listeners.sh:125, and
  # is the only coverage of the ss branch of the address sweep.
  ln -s "$(command -v awk)" "${TEST_BIN}/awk"

  cat >"${TEST_BIN}/ss" <<'EOF'
#!/bin/sh
printf '%s\n' 'LISTEN 0 4096 127.0.0.1:8300 0.0.0.0:*'
exit 1
EOF
  chmod +x "${TEST_BIN}/ss"

  run /bin/bash -lc "export PATH='${TEST_BIN}'; set -euo pipefail; source '${HOST_PORT_LISTENERS_LIB}'; host_port_listener_addresses_for_port 8300"

  [ "${status}" -eq 0 ]
  [ "${output}" = "127.0.0.1:8300" ]
}

@test "host_port_listener_addresses_for_ports accepts an empty port list" {
  # Kills RETURN_CODE at host-port-listeners.sh:139. Callers pass a port list
  # assembled from config; when it is empty there are no listeners to report,
  # which is success, not an error.
  run bash -lc "source '${HOST_PORT_LISTENERS_LIB}'; host_port_listener_addresses_for_ports ''"

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}
