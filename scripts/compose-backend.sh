#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/compose-cli.sh"

usage() {
  cat <<'EOF'
Usage: compose-backend.sh --print

Print the first supported compose backend command.
EOF
}

case "${1:---print}" in
  --print)
    if backend="$(compose_cli_backend)"; then
      printf '%s\n' "${backend}"
    else
      exit 1
    fi
    ;;
  -h|--help)
    usage
    ;;
  *)
    printf 'compose-backend.sh: unknown flag: %s\n' "$1" >&2
    exit 2
    ;;
esac
