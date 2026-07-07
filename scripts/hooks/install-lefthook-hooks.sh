#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=scripts/lib/shell-cli.sh
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute]

Installs lefthook-managed repo hooks with platform worktree guards.

$(shell_cli_standard_options)
EOF
}

abs_path() {
  local path="$1"
  local parent
  local base

  case "${path}" in
    /*)
      printf '%s\n' "${path}"
      ;;
    *)
      parent="$(dirname "${path}")"
      base="$(basename "${path}")"
      printf '%s/%s\n' "$(cd "${parent}" && pwd)" "${base}"
      ;;
  esac
}

install_hook_shim() {
  local hooks_dir="$1"
  local hook_name="$2"
  local target="${hooks_dir}/${hook_name}"

  cp "${SCRIPT_DIR}/lefthook-git-hook.sh" "${target}"
  chmod +x "${target}"
}

shell_cli_handle_standard_no_args usage \
  "would install lefthook hooks with linked-worktree and core.bare guards" \
  "$@"

cd "${REPO_ROOT}"

if ! command -v lefthook >/dev/null 2>&1; then
  echo "lefthook not found in PATH." >&2
  echo "Install the pinned toolchain with: .devcontainer/install-toolchain.sh --execute" >&2
  exit 1
fi

core_bare="$(git config --bool --get core.bare 2>/dev/null || true)"
if [[ "${core_bare}" == "true" ]]; then
  echo "Refusing to install hooks because core.bare=true in this non-bare checkout." >&2
  echo "Repair the shared repo config first, for example from the main checkout:" >&2
  echo "  git config --local core.bare false" >&2
  exit 1
fi

inside_work_tree="$(git rev-parse --is-inside-work-tree 2>/dev/null || true)"
if [[ "${inside_work_tree}" != "true" ]]; then
  echo "Refusing to install hooks outside a Git work tree." >&2
  echo "If this checkout unexpectedly became bare, inspect core.bare before retrying." >&2
  exit 1
fi

git_dir="$(git rev-parse --git-dir)"
git_common_dir="$(git rev-parse --git-common-dir)"
git_dir_abs="$(abs_path "${git_dir}")"
git_common_dir_abs="$(abs_path "${git_common_dir}")"

if [[ "${git_dir_abs}" != "${git_common_dir_abs}" ]]; then
  main_checkout="$(dirname "${git_common_dir_abs}")"
  echo "Refusing to run lefthook install from a linked Git worktree." >&2
  echo "Run make hooks from the main checkout instead:" >&2
  echo "  cd ${main_checkout}" >&2
  echo "  make hooks" >&2
  exit 1
fi

lefthook install

hooks_dir="$(git rev-parse --git-path hooks)"
mkdir -p "${hooks_dir}"
install_hook_shim "${hooks_dir}" "pre-commit"
install_hook_shim "${hooks_dir}" "pre-push"
