#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
  cat <<EOF >&2
Usage: resolve-tfvar-value.sh --key NAME --default VALUE [--tfvars-file PATH]... [--dry-run] [--execute]

Resolves a tfvars value by scanning the provided files in order and falling
back to the supplied default.

Positional compatibility:
  resolve-tfvar-value.sh KEY DEFAULT [TFVARS_FILE...]

$(shell_cli_standard_options)
EOF
}

key=""
default_value=""
files=()
positional=()
shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --key)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--key"
        exit 1
      }
      key="$2"
      shift 2
      ;;
    --default)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--default"
        exit 1
      }
      default_value="$2"
      shift 2
      ;;
    --tfvars-file)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--tfvars-file"
        exit 1
      }
      files+=("$2")
      shift 2
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        positional+=("$1")
        shift
      done
      ;;
    -*)
      shell_cli_unknown_flag "$(shell_cli_script_name)" "$1"
      exit 1
      ;;
    *)
      positional+=("$1")
      shift
      ;;
  esac
done

if [[ -z "${key}" ]]; then
  key="${positional[0]:-}"
fi
if [[ -z "${default_value}" ]]; then
  default_value="${positional[1]:-}"
fi
if [[ "${#files[@]}" -eq 0 && "${#positional[@]}" -gt 2 ]]; then
  files=("${positional[@]:2}")
elif [[ "${#positional[@]}" -gt 2 ]]; then
  shell_cli_unexpected_arg "$(shell_cli_script_name)" "${positional[2]}"
  exit 1
fi

if [[ -z "${key}" || -z "${default_value}" ]]; then
  usage
  exit 1
fi

if [[ "${SHELL_CLI_DRY_RUN}" -eq 1 ]]; then
  shell_cli_print_dry_run_summary "would resolve tfvar ${key} from ${#files[@]} file(s) with fallback ${default_value}"
  exit 0
fi

value=""
for file in "${files[@]}"; do
  [[ -n "${file}" && -f "${file}" ]] || continue
  current="$(
    grep -E "^[[:space:]]*${key}[[:space:]]*=" "${file}" 2>/dev/null | tail -n 1 | \
      sed -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"?([^\"#]+)\"?.*$/\1/" | xargs || true
  )"
  if [[ -n "${current}" ]]; then
    value="${current}"
  fi
done

if [[ -n "${value}" ]]; then
  printf '%s\n' "${value}"
else
  printf '%s\n' "${default_value}"
fi
