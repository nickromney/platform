#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/hooks/lib.sh
source "${SCRIPT_DIR}/lib.sh"

if hook_skip_requested; then
  hook_print_skip_and_exit
fi

yaml_files=()
for file in "$@"; do
  case "${file}" in
    *.yaml|*.yml)
      yaml_files+=("${file}")
      ;;
  esac
done

if [[ "${#yaml_files[@]}" -eq 0 ]]; then
  hook_ok "yamllint: no staged YAML files"
  exit 0
fi

if ! command -v yamllint >/dev/null 2>&1; then
  hook_warn "yamllint not found in PATH; skipping staged YAML lint"
  exit 0
fi

failed=0
cd "${HOOKS_REPO_ROOT}"
for file in "${yaml_files[@]}"; do
  if ! yamllint -c "${HOOKS_REPO_ROOT}/.yamllint" "${file}"; then
    hook_fail "${file}: fix yamllint findings before committing"
    failed=1
  fi
done

if [[ "${failed}" -eq 0 ]]; then
  hook_ok "yamllint: ${#yaml_files[@]} staged YAML file(s)"
fi

exit "${failed}"

