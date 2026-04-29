#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TRIVY_CACHE_DIR="${TRIVY_CACHE_DIR:-${REPO_ROOT}/.run/trivy-cache}"
trivy_args=()

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/shell-cli.sh"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/trivy-common.sh"

usage() {
  cat <<'EOF' | sed "1s|@SCRIPT_NAME@|${0##*/}|"
Usage: @SCRIPT_NAME@ [--dry-run] [--execute] [-- <trivy args...>]

Run the local Trivy binary with the repo cache directory configured.

Any arguments after `--` are forwarded to `trivy`. Positional passthrough
arguments remain supported as a compatibility shim.

Options:
  --dry-run    show the delegated Trivy command and exit before execution
  --execute    execute the delegated Trivy command
  -h, --help   show this help
EOF
}

print_dry_run() {
  shell_cli_print_dry_run_command trivy --cache-dir "${TRIVY_CACHE_DIR}" ${trivy_args[@]+"${trivy_args[@]}"}
}

shell_cli_init_standard_flags
while [[ "$#" -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --)
      shift
      break
      ;;
    *)
      trivy_args+=("$1")
      ;;
  esac
  shift
done

while [[ "$#" -gt 0 ]]; do
  trivy_args+=("$1")
  shift
done

shell_cli_maybe_execute_or_preview usage print_dry_run

mkdir -p "${TRIVY_CACHE_DIR}"

local_status="$(trivy_local_status)"
case "${local_status}" in
  available:*)
    exec trivy --cache-dir "${TRIVY_CACHE_DIR}" "${trivy_args[@]}"
    ;;
  unparseable)
    printf 'trivy-run: local trivy is present but its version could not be determined\n' >&2
    ;;
  *)
    printf 'trivy-run: local trivy is not available; install it if you want to run app scans\n' >&2
    ;;
esac

exit 1
