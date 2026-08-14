#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

UNIT_NAME="kind-node-host-alias"
INTERVAL="${KIND_HOST_ALIAS_INTERVAL:-5min}"
# Overridable so the no-systemd path stays testable on a host that has systemd.
SYSTEMCTL_BIN="${KIND_SYSTEMCTL_BIN:-systemctl}"
UNINSTALL=0
REPAIR_SCRIPT="${REPO_ROOT}/kubernetes/kind/scripts/ensure-node-host-alias.sh"

usage() {
  cat <<EOF
Usage: ${0##*/} [--interval <systemd-time>] [--uninstall] [--dry-run] [--execute]

Install a user systemd timer that keeps host.docker.internal resolvable inside
the kind nodes.

A kind node's /etc/hosts does not survive a container restart, and Docker
Engine on Linux does not inject the name the way Docker Desktop does. Nothing
in the platform re-applies it outside plan/apply/prereqs, so a plain host
reboot leaves the cluster up but unable to pull any image that references the
host registry. It surfaces much later as unexplained ImagePullBackOff pods,
which is why this repairs on a schedule instead of waiting to be noticed.

Runs as a user unit: no sudo, provided the invoking user is in the docker
group. The repair script is idempotent and a no-op when the alias resolves, so
firing every ${INTERVAL} costs two docker exec calls per node.

Options:
  --interval TIME  How often to re-check (systemd time span, default ${INTERVAL})
  --uninstall      Remove the units and disable the timer
$(shell_cli_standard_options)
EOF
}

warn() { echo "WARN install-host-alias-timer: $*" >&2; }
ok() { echo "OK   $*"; }

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --interval)
      [[ $# -ge 2 ]] || { shell_cli_missing_value "$(shell_cli_script_name)" "--interval"; exit 1; }
      INTERVAL="$2"
      shift 2
      ;;
    --uninstall)
      UNINSTALL=1
      shift
      ;;
    *)
      shell_cli_unknown_flag "$(shell_cli_script_name)" "$1"
      exit 1
      ;;
  esac
done

shell_cli_maybe_execute_or_preview_summary usage \
  "would install the ${UNIT_NAME} timer (every ${INTERVAL}) into ${HOME}/.config/systemd/user"

if ! command -v "${SYSTEMCTL_BIN}" >/dev/null 2>&1; then
  warn "systemctl not found; nothing to install"
  warn "on macOS, Docker Desktop injects host.docker.internal and no timer is needed"
  exit 0
fi

UNIT_DIR="${HOME}/.config/systemd/user"
SERVICE_FILE="${UNIT_DIR}/${UNIT_NAME}.service"
TIMER_FILE="${UNIT_DIR}/${UNIT_NAME}.timer"

if [[ "${UNINSTALL}" -eq 1 ]]; then
  "${SYSTEMCTL_BIN}" --user disable --now "${UNIT_NAME}.timer" >/dev/null 2>&1 || true
  rm -f "${SERVICE_FILE}" "${TIMER_FILE}"
  "${SYSTEMCTL_BIN}" --user daemon-reload >/dev/null 2>&1 || true
  ok "removed ${UNIT_NAME} timer and service"
  exit 0
fi

mkdir -p "${UNIT_DIR}"

cat >"${SERVICE_FILE}" <<EOF
[Unit]
Description=Restore host.docker.internal in kind nodes
Documentation=file://${REPAIR_SCRIPT}

[Service]
Type=oneshot
ExecStart=${REPAIR_SCRIPT} --execute
# The repair is best-effort: no cluster, no docker, or a stopped cluster are all
# ordinary states. Failing here would only produce noise in the journal.
SuccessExitStatus=0
EOF

cat >"${TIMER_FILE}" <<EOF
[Unit]
Description=Periodically restore host.docker.internal in kind nodes

[Timer]
# Boot covers the reboot that motivated this; the interval covers a container
# restart, which does not reboot the host.
OnBootSec=30s
OnUnitActiveSec=${INTERVAL}
AccuracySec=30s
Unit=${UNIT_NAME}.service

[Install]
WantedBy=timers.target
EOF

"${SYSTEMCTL_BIN}" --user daemon-reload
"${SYSTEMCTL_BIN}" --user enable --now "${UNIT_NAME}.timer"

ok "installed ${UNIT_NAME}.timer (every ${INTERVAL}, plus 30s after boot)"
ok "status: systemctl --user status ${UNIT_NAME}.timer"
