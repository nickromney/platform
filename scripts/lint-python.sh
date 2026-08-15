#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/shell-cli.sh"

RUFF_BIN="${RUFF_BIN:-ruff}"
RUFF_CONFIG_FILE="${RUFF_CONFIG_FILE:-${REPO_ROOT}/ruff.toml}"
INSTALL_HINTS_SCRIPT="${INSTALL_HINTS_SCRIPT:-${REPO_ROOT}/scripts/install-tool-hints.sh}"

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute]

Lint tracked Python files using the repo ruff configuration.

$(shell_cli_standard_options)
EOF
}

fail() {
  echo "FAIL $*" >&2
  exit 1
}

list_python_files() {
  if command -v git >/dev/null 2>&1 && git -C "${REPO_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "${REPO_ROOT}" ls-files -z -- \
      '*.py' \
      ':(exclude)apps/backstage/**'
    return 0
  fi

  find "${REPO_ROOT}" \
    \( -path '*/.git' -o -path '*/.run' -o -path '*/node_modules' -o -path '*/.venv' -o -path '*/.terraform' -o -path "${REPO_ROOT}/apps/backstage" \) -prune \
    -o \( -type f -name '*.py' -print0 \) | sort -z
}

shell_cli_handle_standard_no_args usage "would lint tracked Python files under ${REPO_ROOT}" "$@"

if ! command -v "${RUFF_BIN}" >/dev/null 2>&1; then
  echo "FAIL ruff not found in PATH" >&2
  if [[ -x "${INSTALL_HINTS_SCRIPT}" ]]; then
    echo "" >&2
    echo "Install hints:" >&2
    "${INSTALL_HINTS_SCRIPT}" --execute --plain ruff | sed 's/^/  /' >&2
  fi
  exit 1
fi

[[ -f "${RUFF_CONFIG_FILE}" ]] || fail "missing ruff config: ${RUFF_CONFIG_FILE}"

python_files=()
while IFS= read -r -d '' file; do
  [[ -e "${REPO_ROOT}/${file}" ]] || continue
  python_files+=("${file}")
done < <(list_python_files)

if [[ "${#python_files[@]}" -eq 0 ]]; then
  echo "WARN no Python files found under ${REPO_ROOT}"
  exit 0
fi

echo "OK   $(${RUFF_BIN} --version)"
echo "INFO linting ${#python_files[@]} tracked Python file(s) with ${RUFF_CONFIG_FILE}"
# --no-cache so a stale .ruff_cache cannot make a dirty tree look clean, and
# because the run is fast enough that caching buys nothing.
(cd "${REPO_ROOT}" && "${RUFF_BIN}" check --no-cache --config "${RUFF_CONFIG_FILE}" "${python_files[@]}")
echo "OK   ruff"
