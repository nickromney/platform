#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/compose-cli.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/shell-cli.sh"

usage() {
  cat <<USAGE
Usage: compose-backend.sh [--print] [--dry-run] [--execute]

Print the first supported compose backend command. Without --execute, the
script previews the action only.

Options:
  --print  Print the compose backend command (default)
  --dry-run  Show a summary and exit before side effects
  --execute  Execute the script body; without it the script prints help and/or preview output
  -h, --help Show this message
USAGE
}

shell_cli_init_standard_flags
action="print"
while [ "$#" -gt 0 ]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --print)
      action="print"
      shift
      ;;
    --)
      shift
      if [ "$#" -gt 0 ]; then
        shell_cli_unexpected_arg "$1"
        exit 1
      fi
      ;;
    -*)
      shell_cli_unknown_flag "$(shell_cli_script_name)" "$1"
      exit 1
      ;;
    *)
      shell_cli_unexpected_arg "$1"
      exit 1
      ;;
  esac
done

if [ "${action}" != "print" ]; then
  shell_cli_unexpected_arg "${action}"
  exit 1
fi

shell_cli_maybe_execute_or_preview_summary \
  usage \
  "would print the first supported compose backend command"

backend=""
if ! backend="$(compose_cli_backend)"; then
  exit 1
fi

printf '%s\n' "${backend}"
