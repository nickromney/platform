#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/hooks/lib.sh
source "${SCRIPT_DIR}/lib.sh"

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

