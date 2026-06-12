#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

BUILD_TFVAR_ARGS="${SCRIPT_DIR}/build-tfvar-args.sh"
RESOLVE_TFVAR_VALUE="${SCRIPT_DIR}/resolve-tfvar-value.sh"

usage() {
  cat <<'EOF' | sed "1s|@SCRIPT_NAME@|${0##*/}|"
Usage: @SCRIPT_NAME@ --stage-tfvars PATH [--optional-file PATH]...

Purpose:
  Build shell assignments for the Kubernetes browser SSO E2E runner from an
  ordered tfvars chain.

Options:
  --stage-tfvars PATH          Stage tfvars path exported as STAGE_TFVARS
  --optional-file PATH         Candidate tfvars file after the stage file

Examples:
  build-sso-e2e-env.sh --execute --stage-tfvars stage-900.tfvars --optional-file kind.tfvars
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

shell_quote() {
  printf '%q' "$1"
}

emit_assignment() {
  local name="$1"
  local value="$2"
  printf '%s=' "${name}"
  shell_quote "${value}"
  printf '\n'
}

join_by_colon() {
  local first=1
  local value
  for value in "$@"; do
    if [[ "${first}" -eq 0 ]]; then
      printf ':'
    fi
    printf '%s' "${value}"
    first=0
  done
}

stage_tfvars=""
stage_tfvars_provided=0
optional_files=()

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --stage-tfvars)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--stage-tfvars"
        exit 1
      }
      stage_tfvars="${2:-}"
      stage_tfvars_provided=1
      shift 2
      ;;
    --optional-file)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--optional-file"
        exit 1
      }
      optional_files+=("${2:-}")
      shift 2
      ;;
    *)
      shell_cli_unknown_flag "$(shell_cli_script_name)" "$1"
      exit 1
      ;;
  esac
done

shell_cli_maybe_execute_or_preview_summary usage \
  "would build SSO E2E environment assignments"

if [[ "${stage_tfvars_provided}" -eq 0 || -z "${stage_tfvars}" ]]; then
  usage
  exit 1
fi

tfvar_files=()
build_tfvar_args=("--execute" "--optional-file" "${stage_tfvars}")
for optional_file in "${optional_files[@]}"; do
  build_tfvar_args+=("--optional-file" "${optional_file}")
done
while IFS= read -r tfvar_file; do
  [[ -n "${tfvar_file}" ]] || continue
  tfvar_files+=("${tfvar_file}")
done < <(
  "${BUILD_TFVAR_ARGS}" "${build_tfvar_args[@]}"
)

enable_backstage="$("${RESOLVE_TFVAR_VALUE}" --execute enable_backstage true "${tfvar_files[@]}")"
tfvar_files_joined="$(join_by_colon "${tfvar_files[@]}")"

emit_assignment "SSO_E2E_ENABLE_BACKSTAGE" "${enable_backstage}"
emit_assignment "STAGE_TFVARS" "${stage_tfvars}"
emit_assignment "STAGE_TFVARS_FILES" "${tfvar_files_joined}"
