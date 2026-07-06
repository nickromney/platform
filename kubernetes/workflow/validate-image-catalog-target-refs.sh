#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/go/bin:/usr/local/bin:${PATH}"
export GOCACHE="${GOCACHE:-${REPO_ROOT}/.run/go-cache}"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute] --catalog PATH --target NAME --tfvars PATH [--allow-source-tags]

Validates external image refs in rendered operator tfvars against the image
catalog target policy.

$(shell_cli_standard_options)
EOF
}

absolute_path() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s\n' "$(pwd)/$1" ;;
  esac
}

args=()
shell_cli_init_standard_flags
while [[ "$#" -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --catalog|--tfvars)
      args+=("$1" "$(absolute_path "$2")")
      shift 2
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done

if [[ "${SHELL_CLI_DRY_RUN}" -eq 1 ]]; then
  shell_cli_print_dry_run_summary "would validate image catalog target refs"
  exit 0
fi

if [[ "${#args[@]}" -eq 0 && "${SHELL_CLI_EXECUTE}" -ne 1 ]]; then
  usage
  shell_cli_print_dry_run_summary "would validate image catalog target refs"
  exit 0
fi

exec go -C "${REPO_ROOT}/tools/platform-helpers" run ./cmd/validate-image-catalog-target-refs "${args[@]}"
