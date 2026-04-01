#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
k8s_dir="$(cd "${script_dir}/.." && pwd)"
# shellcheck source=/dev/null
source "${script_dir}/../../scripts/lib/shell-cli.sh"

exclude_kind=0
exclude_lima=0
exclude_slicer=0

usage() {
  cat <<EOF >&2
Usage: stop-platform-runtimes.sh [--exclude kind|lima|slicer]... [--dry-run] [--execute]

Stops local kind, Lima, and Slicer runtimes best-effort, optionally excluding
selected runtimes.

$(shell_cli_standard_options)
EOF
}

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --exclude)
      shift
      if [[ $# -eq 0 ]]; then
        usage
        exit 1
      fi
      case "$1" in
        kind)
          exclude_kind=1
          ;;
        lima)
          exclude_lima=1
          ;;
        slicer)
          exclude_slicer=1
          ;;
        *)
          echo "Unknown platform for --exclude: $1" >&2
          usage
          exit 1
          ;;
      esac
      ;;
    --)
      shift
      break
      ;;
    -*)
      shell_cli_unknown_flag "$(shell_cli_script_name)" "$1"
      exit 1
      ;;
    *)
      shell_cli_unexpected_arg "$(shell_cli_script_name)" "$1"
      exit 1
      ;;
  esac
  shift
done

shell_cli_maybe_execute_or_preview_summary usage "would stop local platform runtimes best-effort"

run_stop() {
  local platform="$1"
  local target="$2"
  local excluded="$3"

  if [[ "${excluded}" == "1" ]]; then
    return 0
  fi

  echo "Stopping ${platform} runtime (best-effort)..."
  if make -C "${k8s_dir}/${platform}" "${target}" AUTO_APPROVE=1; then
    echo "OK   ${platform} runtime quiesced"
    return 0
  else
    local rc=$?
    echo "WARN ${platform} stop returned ${rc}; continuing" >&2
  fi
}

run_stop kind stop-kind "${exclude_kind}"
run_stop lima stop-lima "${exclude_lima}"
run_stop slicer stop-slicer "${exclude_slicer}"
