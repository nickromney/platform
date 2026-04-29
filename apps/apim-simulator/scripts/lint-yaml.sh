#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/shell-cli.sh"

YAMLLINT_BIN="${YAMLLINT_BIN:-yamllint}"
YAMLLINT_CONFIG_FILE="${YAMLLINT_CONFIG_FILE:-${REPO_ROOT}/.yamllint}"

usage() {
  cat <<EOF
Usage: lint-yaml.sh [--dry-run] [--execute]

Lint tracked YAML files using the repo yamllint configuration.

$(shell_cli_standard_options)
EOF
}

fail() {
  echo "FAIL $*" >&2
  exit 1
}

list_yaml_files() {
  if command -v git >/dev/null 2>&1 && git -C "${REPO_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "${REPO_ROOT}" ls-files -z -- \
      '*.yaml' \
      '*.yml' \
      '.yamllint'
    return 0
  fi

  find "${REPO_ROOT}" \
    \( -path '*/.git' -o -path '*/.run' -o -path '*/node_modules' -o -path '*/.venv' -o -path '*/.terraform' -o -path '*/dist' \) -prune \
    -o \( -type f \( -name '*.yaml' -o -name '*.yml' -o -name '.yamllint' \) -print0 \) | sort -z
}

shell_cli_handle_standard_no_args usage "would lint tracked YAML files under ${REPO_ROOT}" "$@"

if ! command -v "${YAMLLINT_BIN}" >/dev/null 2>&1; then
  fail "yamllint not found in PATH"
fi

[[ -f "${YAMLLINT_CONFIG_FILE}" ]] || fail "missing yamllint config: ${YAMLLINT_CONFIG_FILE}"

yaml_files=()
while IFS= read -r -d '' file; do
  yaml_files+=("${file}")
done < <(list_yaml_files)

if [[ "${#yaml_files[@]}" -eq 0 ]]; then
  echo "WARN no YAML files found under ${REPO_ROOT}"
  exit 0
fi

echo "OK   $(${YAMLLINT_BIN} --version)"
echo "INFO linting ${#yaml_files[@]} tracked YAML file(s) with ${YAMLLINT_CONFIG_FILE}"
"${YAMLLINT_BIN}" -c "${YAMLLINT_CONFIG_FILE}" "${yaml_files[@]}"
echo "OK   yamllint"
