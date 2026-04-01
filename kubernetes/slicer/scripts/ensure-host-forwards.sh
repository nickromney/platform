#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../scripts/lib/shell-cli.sh"

fail() { echo "FAIL $*" >&2; exit 1; }
ok() { echo "OK   $*"; }
warn() { echo "WARN $*" >&2; }

COMMAND=""
SLICER_VM_NAME="${SLICER_VM_NAME:-slicer-1}"
ARGOCD_NODE_PORT="${ARGOCD_NODE_PORT:-30080}"
HUBBLE_NODE_PORT="${HUBBLE_NODE_PORT:-31235}"
GITEA_HTTP_NODE_PORT="${GITEA_HTTP_NODE_PORT:-30090}"
GITEA_SSH_NODE_PORT="${GITEA_SSH_NODE_PORT:-30022}"
SIGNOZ_LOCAL_PORT="${SIGNOZ_LOCAL_PORT:-3301}"
SIGNOZ_NODE_PORT="${SIGNOZ_NODE_PORT:-30301}"
GRAFANA_LOCAL_PORT="${GRAFANA_LOCAL_PORT:-3302}"
GRAFANA_NODE_PORT="${GRAFANA_NODE_PORT:-30302}"
GATEWAY_HTTPS_FORWARD_PORT="${GATEWAY_HTTPS_FORWARD_PORT:-${GATEWAY_HTTPS_HOST_PORT:-8443}}"
GATEWAY_HTTPS_GUEST_PORT="${GATEWAY_HTTPS_GUEST_PORT:-443}"

usage() {
  cat <<EOF
Usage: ensure-host-forwards.sh [--action ensure|stop|status] [--dry-run] [--execute]

Manages the long-lived Slicer host-forward process that maps local ports into
the VM.

Positional compatibility:
  ensure-host-forwards.sh [ensure|stop|status]

$(shell_cli_standard_options)
EOF
}

positional=()
shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --action)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--action"
        exit 1
      }
      COMMAND="$2"
      shift 2
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        positional+=("$1")
        shift
      done
      ;;
    -*)
      shell_cli_unknown_flag "$(shell_cli_script_name)" "$1"
      exit 1
      ;;
    *)
      positional+=("$1")
      shift
      ;;
  esac
done

if [[ -z "${COMMAND}" ]]; then
  COMMAND="${positional[0]:-ensure}"
fi
if [[ "${#positional[@]}" -gt 1 ]]; then
  shell_cli_unexpected_arg "$(shell_cli_script_name)" "${positional[1]}"
  exit 1
fi

if [[ "${SHELL_CLI_DRY_RUN}" -eq 1 ]]; then
  shell_cli_print_dry_run_summary "would ${COMMAND} the Slicer host-forward process"
  exit 0
fi

: "${RUN_DIR:?RUN_DIR is required}"
: "${SLICER_URL:?SLICER_URL is required}"

FORWARD_PID_FILE="${FORWARD_PID_FILE:-${RUN_DIR}/slicer-host-forwards.pid}"
FORWARD_LOG_FILE="${FORWARD_LOG_FILE:-${RUN_DIR}/slicer-host-forwards.log}"

LOCAL_PORTS=(
  "${ARGOCD_NODE_PORT}"
  "${HUBBLE_NODE_PORT}"
  "${GITEA_HTTP_NODE_PORT}"
  "${GITEA_SSH_NODE_PORT}"
  "${SIGNOZ_LOCAL_PORT}"
  "${GRAFANA_LOCAL_PORT}"
  "${GATEWAY_HTTPS_FORWARD_PORT}"
)

FORWARD_ARGS=(
  -L "127.0.0.1:${ARGOCD_NODE_PORT}:127.0.0.1:${ARGOCD_NODE_PORT}"
  -L "127.0.0.1:${HUBBLE_NODE_PORT}:127.0.0.1:${HUBBLE_NODE_PORT}"
  -L "127.0.0.1:${GITEA_HTTP_NODE_PORT}:127.0.0.1:${GITEA_HTTP_NODE_PORT}"
  -L "127.0.0.1:${GITEA_SSH_NODE_PORT}:127.0.0.1:${GITEA_SSH_NODE_PORT}"
  -L "127.0.0.1:${SIGNOZ_LOCAL_PORT}:127.0.0.1:${SIGNOZ_NODE_PORT}"
  -L "127.0.0.1:${GRAFANA_LOCAL_PORT}:127.0.0.1:${GRAFANA_NODE_PORT}"
  -L "127.0.0.1:${GATEWAY_HTTPS_FORWARD_PORT}:127.0.0.1:${GATEWAY_HTTPS_GUEST_PORT}"
)

port_listening() {
  local port="$1"
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1
    return
  fi
  nc -z 127.0.0.1 "${port}" >/dev/null 2>&1
}

forward_process_pids() {
  ps -ax -o pid=,command= | awk -v vm="${SLICER_VM_NAME}" -v url="${SLICER_URL}" '
    index($0, "slicer vm forward") && index($0, " " vm " ") && index($0, url) {
      gsub(/^[[:space:]]+/, "", $0)
      print $1
    }
  '
}

forward_process_running() {
  [[ -n "$(forward_process_pids)" ]]
}

all_ports_ready() {
  local port
  for port in "${LOCAL_PORTS[@]}"; do
    if ! port_listening "${port}"; then
      return 1
    fi
  done
}

any_ports_listening() {
  local port
  for port in "${LOCAL_PORTS[@]}"; do
    if port_listening "${port}"; then
      return 0
    fi
  done
  return 1
}

pid_running() {
  local pid="$1"
  [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null
}

read_pid() {
  if [[ -f "${FORWARD_PID_FILE}" ]]; then
    tr -d '[:space:]' < "${FORWARD_PID_FILE}"
  fi
}

cleanup_stale_pid() {
  local pid
  pid="$(read_pid)"
  if [[ -n "${pid}" ]] && ! pid_running "${pid}"; then
    rm -f "${FORWARD_PID_FILE}"
  fi
  if [[ ! -f "${FORWARD_PID_FILE}" ]] && forward_process_running; then
    forward_process_pids | head -n 1 > "${FORWARD_PID_FILE}"
  fi
}

port_conflict() {
  local port
  for port in "${LOCAL_PORTS[@]}"; do
    if port_listening "${port}"; then
      if forward_process_running; then
        continue
      fi
      printf '%s\n' "${port}"
      return 0
    fi
  done
  return 1
}

start_forwarder() {
  local wrapper_pid
  local conflict_port=""
  local discovered_pid=""

  mkdir -p "${RUN_DIR}"
  cleanup_stale_pid

  if conflict_port="$(port_conflict)"; then
    fail "local port ${conflict_port} is already in use; stop the conflicting process first"
  fi

  if ! command -v script >/dev/null 2>&1; then
    fail "script is required to keep slicer vm forward attached to a PTY on macOS"
  fi

  script -q /dev/null \
    slicer vm forward "${SLICER_VM_NAME}" -u "${SLICER_URL}" "${FORWARD_ARGS[@]}" \
    >"${FORWARD_LOG_FILE}" 2>&1 &
  wrapper_pid="$!"

  for _ in $(seq 1 30); do
    discovered_pid="$(forward_process_pids | head -n 1 || true)"
    if [[ -z "${discovered_pid}" ]] && ! pid_running "${wrapper_pid}"; then
      warn "slicer vm forward exited early; recent log:"
      tail -n 40 "${FORWARD_LOG_FILE}" >&2 || true
      rm -f "${FORWARD_PID_FILE}"
      return 1
    fi
    if [[ -n "${discovered_pid}" ]] && all_ports_ready; then
      printf '%s\n' "${discovered_pid}" > "${FORWARD_PID_FILE}"
      ok "host forwards running (${SLICER_VM_NAME}; pid=${discovered_pid})"
      return 0
    fi
    sleep 1
  done

  warn "timed out waiting for slicer host forwards; recent log:"
  tail -n 40 "${FORWARD_LOG_FILE}" >&2 || true
  if grep -Fq "bind: permission denied" "${FORWARD_LOG_FILE}" && [[ "${GATEWAY_HTTPS_FORWARD_PORT}" =~ ^[0-9]+$ ]] && [ "${GATEWAY_HTTPS_FORWARD_PORT}" -lt 1024 ]; then
    warn "macOS denied the privileged bind for localhost:${GATEWAY_HTTPS_FORWARD_PORT}; use an unprivileged forward port such as 8443 or add a separate privileged proxy on the host"
  fi
  return 1
}

ensure_forwarder() {
  local pid
  cleanup_stale_pid
  pid="$(read_pid)"

  if forward_process_running && all_ports_ready; then
    if [[ -z "${pid}" ]] || ! pid_running "${pid}"; then
      pid="$(forward_process_pids | head -n 1 || true)"
      [[ -n "${pid}" ]] && printf '%s\n' "${pid}" > "${FORWARD_PID_FILE}"
    fi
    ok "host forwards already running (${SLICER_VM_NAME}; pid=${pid})"
    return 0
  fi

  if forward_process_running; then
    while IFS= read -r existing_pid; do
      [[ -n "${existing_pid}" ]] || continue
      kill "${existing_pid}" >/dev/null 2>&1 || true
    done < <(forward_process_pids)
    sleep 1
  fi
  rm -f "${FORWARD_PID_FILE}"

  start_forwarder
}

stop_forwarder() {
  local pid
  local stopped=0
  cleanup_stale_pid
  pid="$(read_pid)"

  if [[ -z "${pid}" ]] && ! forward_process_running; then
    ok "host forwards not running"
    return 0
  fi

  while IFS= read -r existing_pid; do
    [[ -n "${existing_pid}" ]] || continue
    kill "${existing_pid}" >/dev/null 2>&1 || true
    stopped=1
  done < <(forward_process_pids)

  for _ in $(seq 1 20); do
    if ! forward_process_running && ! any_ports_listening; then
      rm -f "${FORWARD_PID_FILE}"
      if [[ "${stopped}" = "1" ]]; then
        ok "stopped host forwards (${SLICER_VM_NAME})"
      else
        ok "host forwards not running"
      fi
      return 0
    fi
    sleep 1
  done

  while IFS= read -r existing_pid; do
    [[ -n "${existing_pid}" ]] || continue
    warn "force killing host forwards (${existing_pid})"
    kill -9 "${existing_pid}" >/dev/null 2>&1 || true
  done < <(forward_process_pids)
  rm -f "${FORWARD_PID_FILE}"
}

print_status() {
  local pid
  cleanup_stale_pid
  pid="$(forward_process_pids | head -n 1 || true)"
  if [[ -n "${pid}" ]] && all_ports_ready; then
    echo "RUNNING host forwards ${SLICER_VM_NAME} pid=${pid} ports=${LOCAL_PORTS[*]}"
  else
    echo "STOPPED host forwards ${SLICER_VM_NAME}"
  fi
}

case "${COMMAND}" in
  ensure)
    ensure_forwarder
    ;;
  stop)
    stop_forwarder
    ;;
  status)
    print_status
    ;;
  *)
    usage
    exit 1
    ;;
esac
