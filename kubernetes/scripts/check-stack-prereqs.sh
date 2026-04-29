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
  Verify required and optional host tools for a stack prereqs flow, including
  stage-aware browser/E2E recommendations.

Options:
  --stage N                    Stage number (default: 100)
  --required TOOL             Required tool; repeat as needed
  --optional TOOL             Optional tool; repeat as needed
  --recommended TOOL          Recommended browser/E2E tool; repeat as needed
  --install-hints PATH        Override install-tool-hints.sh path
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

stage="100"
required_tools=()
optional_tools=()
recommended_tools=()
install_hints_script="${REPO_ROOT}/scripts/install-tool-hints.sh"

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --stage)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--stage"
        exit 1
      }
      stage="${2:-}"
      shift 2
      ;;
    --required)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--required"
        exit 1
      }
      required_tools+=("${2:-}")
      shift 2
      ;;
    --optional)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--optional"
        exit 1
      }
      optional_tools+=("${2:-}")
      shift 2
      ;;
    --recommended)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--recommended"
        exit 1
      }
      recommended_tools+=("${2:-}")
      shift 2
      ;;
    --install-hints)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--install-hints"
        exit 1
      }
      install_hints_script="${2:-}"
      shift 2
      ;;
    *)
      shell_cli_unknown_flag "$(shell_cli_script_name)" "$1"
      exit 1
      ;;
  esac
done

shell_cli_maybe_execute_or_preview_summary usage \
  "would verify ${#required_tools[@]} required and ${#optional_tools[@]} optional host tools for stage ${stage}"

case "${stage}" in
  100|200|300|400|500|600|700|800|900) ;;
  *)
    echo "Unknown stage: ${stage}" >&2
    exit 1
    ;;
esac

if [[ "${stage}" -ge 900 ]]; then
  required_tools+=("${recommended_tools[@]}")
fi

missing_required=()
missing_recommended=()

is_required() {
  local target="$1"
  local req=""
  for req in "${required_tools[@]}"; do
    if [[ "${req}" == "${target}" ]]; then
      return 0
    fi
  done
  return 1
}

is_recommended() {
  local target="$1"
  local recommended=""
  for recommended in "${recommended_tools[@]}"; do
    if [[ "${recommended}" == "${target}" ]]; then
      return 0
    fi
  done
  return 1
}

check_bin() {
  local bin="$1"
  local required_flag="$2"

  if command -v "${bin}" >/dev/null 2>&1; then
    echo "OK   ${bin}"
    return 0
  fi

  if [[ "${required_flag}" == "1" ]]; then
    echo "FAIL ${bin} (missing)"
    missing_required+=("${bin}")
  else
    echo "WARN ${bin} (missing, optional)"
    if is_recommended "${bin}"; then
      missing_recommended+=("${bin}")
    fi
  fi
}

echo "Tool installation verification:"
sorted_tools=()
while IFS= read -r tool; do
  [[ -n "${tool}" ]] || continue
  sorted_tools+=("${tool}")
done < <(printf '%s\n' "${required_tools[@]}" "${optional_tools[@]}" | LC_ALL=C sort -u)
for tool in "${sorted_tools[@]}"; do
  [[ -n "${tool}" ]] || continue
  if is_required "${tool}"; then
    check_bin "${tool}" 1
  else
    check_bin "${tool}" 0
  fi
done

if [[ "${#missing_required[@]}" -gt 0 ]]; then
  echo
  echo "Missing required tools: ${missing_required[*]}"
  echo
  echo "Install hints:"
  "${install_hints_script}" --execute --plain "${missing_required[@]}" | sed 's/^/  /'
  exit 1
fi

if [[ "${#missing_recommended[@]}" -gt 0 ]]; then
  echo
  echo "Recommended browser/E2E test tools missing for stages below 900: ${missing_recommended[*]}"
  echo
  echo "Install hints:"
  "${install_hints_script}" --execute --plain "${missing_recommended[@]}" | sed 's/^/  /'
fi
