#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
  export SCRIPT="${REPO_ROOT}/kubernetes/kind/scripts/install-host-alias-timer.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN}"
  export PATH="${TEST_BIN}:${PATH}"
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}"
  export UNIT_DIR="${HOME}/.config/systemd/user"

  cat >"${TEST_BIN}/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${SYSTEMCTL_LOG:?}"
EOF
  chmod +x "${TEST_BIN}/systemctl"
  export SYSTEMCTL_LOG="${BATS_TEST_TMPDIR}/systemctl.log"
  : >"${SYSTEMCTL_LOG}"
}

@test "install writes both units into the user systemd directory" {
  run "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [ -f "${UNIT_DIR}/kind-node-host-alias.service" ]
  [ -f "${UNIT_DIR}/kind-node-host-alias.timer" ]
}

@test "installed service invokes the repair script by absolute path" {
  run "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  run cat "${UNIT_DIR}/kind-node-host-alias.service"
  [[ "${output}" == *"${REPO_ROOT}/kubernetes/kind/scripts/ensure-node-host-alias.sh"* ]]
  # A timer-driven repair must not wait on the --execute confirmation gate.
  [[ "${output}" == *"--execute"* ]]
  [[ "${output}" == *"Type=oneshot"* ]]
}

@test "installed timer fires at boot and on an interval" {
  run "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  run cat "${UNIT_DIR}/kind-node-host-alias.timer"
  # Boot covers the reboot case that started this; the interval covers a plain
  # container restart, which does not reboot the host.
  [[ "${output}" == *"OnBootSec="* ]]
  [[ "${output}" == *"OnUnitActiveSec="* ]]
  [[ "${output}" == *"WantedBy=timers.target"* ]]
}

@test "install reloads systemd and enables the timer" {
  run "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  run cat "${SYSTEMCTL_LOG}"
  [[ "${output}" == *"daemon-reload"* ]]
  [[ "${output}" == *"enable"* ]]
  [[ "${output}" == *"kind-node-host-alias.timer"* ]]
}

@test "install is idempotent" {
  run "${SCRIPT}" --execute
  [ "${status}" -eq 0 ]
  run "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [ -f "${UNIT_DIR}/kind-node-host-alias.timer" ]
}

@test "custom interval is honoured" {
  run "${SCRIPT}" --execute --interval 15min

  [ "${status}" -eq 0 ]
  run cat "${UNIT_DIR}/kind-node-host-alias.timer"
  [[ "${output}" == *"OnUnitActiveSec=15min"* ]]
}

@test "uninstall removes both units and disables the timer" {
  run "${SCRIPT}" --execute
  [ "${status}" -eq 0 ]

  run "${SCRIPT}" --execute --uninstall

  [ "${status}" -eq 0 ]
  [ ! -f "${UNIT_DIR}/kind-node-host-alias.service" ]
  [ ! -f "${UNIT_DIR}/kind-node-host-alias.timer" ]
  run cat "${SYSTEMCTL_LOG}"
  [[ "${output}" == *"disable"* ]]
}

@test "install refuses on a host without systemd rather than pretending" {
  # macOS has no systemd; Docker Desktop injects the alias anyway, so there is
  # nothing to install and saying so beats writing dead unit files. Point at a
  # missing binary rather than editing PATH, since the real systemctl lives in
  # /usr/bin on this host and would otherwise still be found.
  export KIND_SYSTEMCTL_BIN="${BATS_TEST_TMPDIR}/no-such-systemctl"
  run "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"systemctl"* ]]
  [ ! -f "${UNIT_DIR}/kind-node-host-alias.timer" ]
}
