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

Checks staged kind tfvars files for duplicate attributes.

$(shell_cli_standard_options)
EOF
}

shell_cli_parse_standard_only usage "$@" || exit 1
shell_cli_maybe_execute_or_preview_summary usage \
  "would check staged kind tfvars files for duplicate attributes"
set -- "${SHELL_CLI_ARGS[@]}"

if hook_skip_requested; then
  hook_print_skip_and_exit
fi

tfvars_files=()
for file in "$@"; do
  case "${file}" in
    kubernetes/kind/*.tfvars)
      tfvars_files+=("${file}")
      ;;
  esac
done

if [[ "${#tfvars_files[@]}" -eq 0 ]]; then
  hook_ok "kind tfvars duplicate attributes: no staged files"
  exit 0
fi

failed=0
cd "${HOOKS_REPO_ROOT}"
for file in "${tfvars_files[@]}"; do
  if ! awk '
    /^[[:space:]]*($|#|\/\/)/ { next }
    match($0, /^[[:space:]]*[A-Za-z_][A-Za-z0-9_-]*[[:space:]]*=/) {
      key = substr($0, RSTART, RLENGTH)
      sub(/^[[:space:]]*/, "", key)
      sub(/[[:space:]]*=.*/, "", key)
      if (seen[key]) {
        printf "%s:%d: duplicate attribute %s; first defined on line %d\n", FILENAME, FNR, key, seen[key]
        found = 1
      } else {
        seen[key] = FNR
      }
    }
    END { exit found ? 1 : 0 }
  ' "${file}"; then
    hook_fail "${file}: remove duplicate tfvars attributes so each key is assigned once"
    failed=1
  fi
done

if [[ "${failed}" -eq 0 ]]; then
  hook_ok "kind tfvars duplicate attributes: ${#tfvars_files[@]} staged file(s)"
fi

exit "${failed}"
