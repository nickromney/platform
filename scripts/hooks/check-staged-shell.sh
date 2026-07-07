#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/hooks/lib.sh
source "${SCRIPT_DIR}/lib.sh"
# shellcheck disable=SC1091
source "${HOOKS_REPO_ROOT}/scripts/lib/shell-cli.sh"

# shellcheck disable=SC2329
usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute] [--] [FILE...]

Runs shellcheck for staged shell files.

$(shell_cli_standard_options)
EOF
}

shell_cli_parse_standard_only usage "$@" || exit 1
shell_cli_maybe_execute_or_preview_summary usage \
  "would run shellcheck for staged shell files"
set -- "${SHELL_CLI_ARGS[@]}"

if hook_skip_requested; then
  hook_print_skip_and_exit
fi

shell_files=()
for file in "$@"; do
  case "${file}" in
    *.sh)
      shell_files+=("${file}")
      ;;
  esac
done

if [[ "${#shell_files[@]}" -eq 0 ]]; then
  hook_ok "shellcheck: no staged shell files"
  exit 0
fi

if ! command -v shellcheck >/dev/null 2>&1; then
  hook_fail "shellcheck not found in PATH; install shellcheck or unstage shell files"
  exit 1
fi

failed=0
cd "${HOOKS_REPO_ROOT}"
for file in "${shell_files[@]}"; do
  if ! shellcheck -x "${file}"; then
    hook_fail "${file}: fix shellcheck findings before committing"
    failed=1
  fi
done

if [[ "${failed}" -eq 0 ]]; then
  hook_ok "shellcheck: ${#shell_files[@]} staged shell file(s)"
fi

exit "${failed}"
