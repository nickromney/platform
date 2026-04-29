#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
  cat <<'EOF' | sed "1s|@SCRIPT_NAME@|${0##*/}|"
Usage: @SCRIPT_NAME@ [options]

Purpose:
  Collect existing tfvars files in the provided order and print them either as
  newline-delimited paths or as flattened var-file arguments.

Options:
  --optional-file PATH          Candidate tfvars file to include if it exists
  --format FORMAT              One of: lines, repeated, assignment (default: lines)
  --flag NAME                  Flag name for repeated/assignment output

Examples:
  build-tfvar-args.sh --execute --optional-file stage.tfvars --optional-file kind.tfvars
  build-tfvar-args.sh --execute --format repeated --flag --var-file --optional-file stage.tfvars
  build-tfvar-args.sh --execute --format assignment --flag -var-file --optional-file stage.tfvars
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

format="lines"
flag=""
optional_files=()

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --optional-file)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--optional-file"
        exit 1
      }
      optional_files+=("${2:-}")
      shift 2
      ;;
    --format)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--format"
        exit 1
      }
      format="${2:-}"
      shift 2
      ;;
    --flag)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--flag"
        exit 1
      }
      flag="${2:-}"
      shift 2
      ;;
    *)
      shell_cli_unknown_flag "$(shell_cli_script_name)" "$1"
      exit 1
      ;;
  esac
done

shell_cli_maybe_execute_or_preview_summary usage \
  "would build ordered tfvar arguments from ${#optional_files[@]} candidate file(s)"

case "${format}" in
  lines)
    ;;
  repeated)
    if [[ -z "${flag}" ]]; then
      flag="--var-file"
    fi
    ;;
  assignment)
    if [[ -z "${flag}" ]]; then
      flag="-var-file"
    fi
    ;;
  *)
    printf '%s: unknown format: %s\n' "$(shell_cli_script_name)" "${format}" >&2
    exit 1
    ;;
esac

existing_files=()
for optional_file in "${optional_files[@]}"; do
  if [[ -n "${optional_file}" && -f "${optional_file}" ]]; then
    existing_files+=("${optional_file}")
  fi
done

case "${format}" in
  lines)
    for existing_file in "${existing_files[@]}"; do
      printf '%s\n' "${existing_file}"
    done
    ;;
  repeated)
    first=1
    for existing_file in "${existing_files[@]}"; do
      if [[ "${first}" -eq 0 ]]; then
        printf ' '
      fi
      printf '%s %s' "${flag}" "${existing_file}"
      first=0
    done
    printf '\n'
    ;;
  assignment)
    first=1
    for existing_file in "${existing_files[@]}"; do
      if [[ "${first}" -eq 0 ]]; then
        printf ' '
      fi
      printf '%s=%s' "${flag}" "${existing_file}"
      first=0
    done
    printf '\n'
    ;;
esac
