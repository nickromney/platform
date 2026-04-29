#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/shell-cli.sh"

usage() {
  cat <<'EOF'
Usage: ./scripts/check-host-ports.sh [--dry-run] [--execute] [PORT...]

Checks whether each host TCP port is free for listening.

Examples:
  ./scripts/check-host-ports.sh --execute
  ./scripts/check-host-ports.sh --execute 3000 8000 9443

Defaults:
  3000 8443 3007 8000 8088 8180 9443

Options:
  --dry-run  Show the port set and exit before inspecting listeners
  --execute  Inspect host ports
  -h, --help Show this message
EOF
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

listeners_for_port_lsof() {
  local port="$1"
  lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null || true
}

listeners_for_port_ss() {
  local port="$1"
  local body

  body="$(ss -H -ltn "sport = :${port}" 2>/dev/null || true)"
  [[ -n "$body" ]] || return 0
  printf 'State Recv-Q Send-Q Local Address:Port Peer Address:Port\n%s\n' "$body"
}

listeners_for_port() {
  local port="$1"

  if have_cmd lsof; then
    listeners_for_port_lsof "$port"
    return 0
  fi

  if have_cmd ss; then
    listeners_for_port_ss "$port"
    return 0
  fi

  echo "Neither lsof nor ss is available; cannot inspect host ports." >&2
  exit 2
}

shell_cli_init_standard_flags
ports=()
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --)
      shift
      ports+=("$@")
      break
      ;;
    -*)
      shell_cli_unknown_flag "$(shell_cli_script_name)" "$1"
      exit 1
      ;;
    *)
      ports+=("$1")
      shift
      ;;
  esac
done

if [[ "${#ports[@]}" -eq 0 ]]; then
  ports=(3000 8443 3007 8000 8088 8180 9443)
fi

shell_cli_maybe_execute_or_preview_summary usage \
  "would inspect host TCP ports: ${ports[*]}"

conflicts=0

for port in "${ports[@]}"; do
  if ! [[ "$port" =~ ^[0-9]+$ ]]; then
    echo "invalid port: $port" >&2
    exit 2
  fi

  listeners="$(listeners_for_port "$port")"
  if [[ -z "$listeners" ]]; then
    echo "OK   host port $port is free"
    continue
  fi

  conflicts=1
  echo "FAIL host port $port is already in use" >&2
  printf '%s\n' "$listeners" >&2
done

exit "$conflicts"
