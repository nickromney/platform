#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/go/bin:/usr/local/bin:${PATH}"
export GOCACHE="${GOCACHE:-${REPO_ROOT}/.run/go-cache}"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute] SCHEMA.json PAYLOAD.json

Validates a JSON payload against a JSON schema.

$(shell_cli_standard_options)
EOF
}

absolute_path() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s\n' "$(pwd)/$1" ;;
  esac
}

shell_cli_parse_standard_only usage "$@" || exit 1
set -- ${SHELL_CLI_ARGS[@]+"${SHELL_CLI_ARGS[@]}"}

if [[ "${SHELL_CLI_DRY_RUN}" -eq 1 ]]; then
  shell_cli_print_dry_run_summary "would validate JSON payload against schema"
  exit 0
fi

if [[ "$#" -eq 0 && "${SHELL_CLI_EXECUTE}" -ne 1 ]]; then
  usage
  shell_cli_print_dry_run_summary "would validate JSON payload against schema"
  exit 0
fi

if [[ "$#" -eq 2 ]]; then
  set -- "$(absolute_path "$1")" "$(absolute_path "$2")"
fi

exec go -C "${REPO_ROOT}/tools/platform-helpers" run ./cmd/validate-json-schema "$@"
