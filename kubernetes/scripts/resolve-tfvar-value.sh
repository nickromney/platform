#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
  cat <<EOF >&2
Usage: ${0##*/} --key NAME --default VALUE [--tfvars-file PATH]... [--dry-run] [--execute]

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
key_provided=0
default_provided=0
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
      key_provided=1
      shift 2
      ;;
    --default)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--default"
        exit 1
      }
      default_value="$2"
      default_provided=1
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

if [[ "${key_provided}" -eq 0 && "${#positional[@]}" -ge 1 ]]; then
  key="${positional[0]:-}"
  key_provided=1
fi
if [[ "${default_provided}" -eq 0 && "${#positional[@]}" -ge 2 ]]; then
  default_value="${positional[1]:-}"
  default_provided=1
fi
if [[ "${#files[@]}" -eq 0 && "${#positional[@]}" -gt 2 ]]; then
  files=("${positional[@]:2}")
elif [[ "${#positional[@]}" -gt 2 ]]; then
  shell_cli_unexpected_arg "$(shell_cli_script_name)" "${positional[2]}"
  exit 1
fi

if [[ "${key_provided}" -eq 0 && "${default_provided}" -eq 0 && "${#files[@]}" -eq 0 && "${#positional[@]}" -eq 0 ]]; then
  shell_cli_maybe_execute_or_preview_summary usage \
    "would resolve a tfvar value after --key and --default are provided"
fi

if [[ "${key_provided}" -eq 0 || "${default_provided}" -eq 0 || -z "${key}" ]]; then
  usage
  exit 1
fi

shell_cli_maybe_execute_or_preview_summary usage \
  "would resolve tfvar ${key} from ${#files[@]} file(s) with fallback ${default_value}"

value=""
if [[ "${#files[@]}" -gt 0 ]]; then
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
fi

if [[ -n "${value}" ]]; then
  printf '%s\n' "${value}"
else
  printf '%s\n' "${default_value}"
fi
