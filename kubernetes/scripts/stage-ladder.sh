#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
METADATA_FILE="${SCRIPT_DIR}/../stage-ladder.mk"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
  cat <<'EOF'
Usage: stage-ladder.sh --stack-dir PATH [--dry-run] [--execute]

Purpose:
  Emit the shared platform stage ladder as stage:path pairs for a stack root.

Options:
  --stack-dir PATH              Stack directory that owns the staged tfvars files
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

stack_dir=""

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --stack-dir)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--stack-dir"
        exit 1
      }
      stack_dir="${2:-}"
      shift 2
      ;;
    *)
      shell_cli_unknown_flag "$(shell_cli_script_name)" "$1"
      exit 1
      ;;
  esac
done

shell_cli_maybe_execute_or_preview_summary usage \
  "would emit shared stage ladder paths for ${stack_dir:-<unspecified>}"

[[ -n "${stack_dir}" ]] || {
  usage
  echo "Missing --stack-dir" >&2
  exit 1
}

if [[ ! -f "${METADATA_FILE}" ]]; then
  echo "Missing stage ladder metadata: ${METADATA_FILE}" >&2
  exit 1
fi

stack_dir="$(cd "${stack_dir}" && pwd)"
valid_stages="$(awk -F':=' '
  $1 ~ /^VALID_STAGES[[:space:]]*$/ {
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
    print $2
    exit
  }
' "${METADATA_FILE}")"

for stage in ${valid_stages}; do
  rel_file="$(awk -F':=' -v stage="${stage}" '
    $1 ~ "^STAGE_FILE_REL_" stage "[[:space:]]*$" {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
      print $2
      exit
    }
  ' "${METADATA_FILE}")"
  [[ -n "${rel_file}" ]] || {
    echo "Missing STAGE_FILE_REL_${stage} in ${METADATA_FILE}" >&2
    exit 1
  }
  printf '%s:%s/%s\n' "${stage}" "${stack_dir}" "${rel_file}"
done
