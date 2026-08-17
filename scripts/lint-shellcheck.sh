#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/shell-cli.sh"

SHELLCHECK_BIN="${SHELLCHECK_BIN:-shellcheck}"
TOOLCHAIN_VERSIONS_FILE="${TOOLCHAIN_VERSIONS_FILE:-${REPO_ROOT}/.devcontainer/toolchain-versions.sh}"
INSTALL_HINTS_SCRIPT="${INSTALL_HINTS_SCRIPT:-${REPO_ROOT}/scripts/install-tool-hints.sh}"

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute]

Run shellcheck over every tracked shell script.

This exists because \`make lint\` never actually ran shellcheck. \`lint-shell\`
calls scripts/audit-shell-scripts.sh, which audits *conventions* -- entrypoint
flags, the Python wrapper policy -- and never invokes shellcheck at all.
shellcheck ran only in the lefthook pre-commit hook, and only over *staged*
files, so a script was checked when it was first committed and never again.

18 of 207 tracked scripts were failing when that gap was found, including
scripts/check-worktree-unchanged.sh, which had been added as a guard. Two of
them executed commands out of their own \`--help\` text.

\`-x\` follows sourced files, matching what the pre-commit hook does, so the two
surfaces cannot disagree about whether the tree is clean.

$(shell_cli_standard_options)
EOF
}

fail() {
  echo "FAIL $*" >&2
  exit 1
}

list_shell_files() {
  if command -v git >/dev/null 2>&1 && git -C "${REPO_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "${REPO_ROOT}" ls-files -z -- '*.sh'
    return 0
  fi

  find "${REPO_ROOT}" \
    \( -path '*/.git' -o -path '*/.run' -o -path '*/node_modules' -o -path '*/.venv' -o -path '*/.terraform' \) -prune \
    -o \( -type f -name '*.sh' -print0 \) | sort -z
}

shell_cli_handle_standard_no_args usage "would run shellcheck over tracked shell scripts under ${REPO_ROOT}" "$@"

if ! command -v "${SHELLCHECK_BIN}" >/dev/null 2>&1; then
  echo "FAIL shellcheck not found in PATH" >&2
  if [[ -x "${INSTALL_HINTS_SCRIPT}" ]]; then
    echo "" >&2
    echo "Install hints:" >&2
    "${INSTALL_HINTS_SCRIPT}" --execute --plain shellcheck | sed 's/^/  /' >&2
  fi
  exit 1
fi

shell_files=()
while IFS= read -r -d '' file; do
  [[ -f "${REPO_ROOT}/${file}" ]] || continue
  shell_files+=("${file}")
done < <(list_shell_files)

if [[ "${#shell_files[@]}" -eq 0 ]]; then
  echo "WARN no shell scripts found under ${REPO_ROOT}"
  exit 0
fi

# A clean run means nothing without the version that produced it. shellcheck
# 0.9.0 emits SC2317 where 0.11.0 does not: PR #201 was clean on every developer
# machine and failed CI with 449 findings, because CI took shellcheck from the
# runner image while every other tool in that job was pinned. Report the version,
# and say so plainly when it is not the pinned one.
running_version="$("${SHELLCHECK_BIN}" --version | awk '/^version:/ { print $2 }')"
expected_version=""
if [[ -r "${TOOLCHAIN_VERSIONS_FILE}" ]]; then
  # shellcheck source=/dev/null
  source "${TOOLCHAIN_VERSIONS_FILE}" 2>/dev/null || true
  expected_version="${SHELLCHECK_VERSION#v}"
fi

echo "OK   shellcheck ${running_version}"
if [[ -n "${expected_version}" && "${running_version}" != "${expected_version}" ]]; then
  echo "WARN this is not the pinned shellcheck (${expected_version}); a clean run here" >&2
  echo "     does not mean CI will be clean, and a finding here may not be real." >&2
  echo "     Pin: SHELLCHECK_VERSION in ${TOOLCHAIN_VERSIONS_FILE#"${REPO_ROOT}/"}" >&2
fi
echo "INFO checking ${#shell_files[@]} tracked shell script(s)"

failed=0
cd "${REPO_ROOT}"
for file in "${shell_files[@]}"; do
  if ! "${SHELLCHECK_BIN}" -x "${file}"; then
    failed=1
  fi
done

[[ "${failed}" -eq 0 ]] || fail "shellcheck reported findings; fix them or add a scoped disable with a reason"

echo "OK   shellcheck"
