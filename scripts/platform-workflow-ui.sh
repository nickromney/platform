#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

HOST="127.0.0.1"
PORT="8765"

usage() {
  cat <<'EOF' | sed "1s|@SCRIPT_NAME@|${0##*/}|"
Usage: @SCRIPT_NAME@ [--host HOST] [--port PORT] [--dry-run] [--execute]

Serves the browser workflow chooser backed by scripts/platform-workflow.sh.
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

require_value() {
  local flag="$1"
  local value="${2-}"

  if [[ -z "${value}" ]]; then
    shell_cli_missing_value "$(shell_cli_script_name)" "${flag}"
    exit 2
  fi
}

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --host)
      require_value "$1" "${2-}"
      HOST="$2"
      shift 2
      ;;
    --port)
      require_value "$1" "${2-}"
      PORT="$2"
      shift 2
      ;;
    *)
      shell_cli_unknown_flag "$(shell_cli_script_name)" "$1"
      exit 2
      ;;
  esac
done

shell_cli_maybe_execute_or_preview_summary usage "would serve platform workflow UI on http://${HOST}:${PORT}"

exec python3 "${SCRIPT_DIR}/platform-workflow-ui.py" \
  --host "${HOST}" \
  --port "${PORT}" \
  --repo-root "${REPO_ROOT}"
