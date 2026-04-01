#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TRIVY_CACHE_DIR="${TRIVY_CACHE_DIR:-${REPO_ROOT}/.run/trivy-cache}"
dry_run=0
execute_flag=0
trivy_args=()

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/shell-cli.sh"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/trivy-common.sh"

usage() {
  cat <<'EOF'
Usage: trivy-run.sh [--dry-run] [--execute] [-- <trivy args...>]

Run the local Trivy binary with the repo cache directory configured.

Any arguments after `--` are forwarded to `trivy`. Positional passthrough
arguments remain supported as a compatibility shim.

Options:
  --dry-run    show the delegated Trivy command and exit before execution
  --execute    execute the delegated Trivy command
  -h, --help   show this help
EOF
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --dry-run)
      dry_run=1
      ;;
    --execute)
      execute_flag=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
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

if [[ "${dry_run}" -eq 1 ]]; then
  shell_cli_print_dry_run_command trivy --cache-dir "${TRIVY_CACHE_DIR}" "${trivy_args[@]}"
  exit 0
fi

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
