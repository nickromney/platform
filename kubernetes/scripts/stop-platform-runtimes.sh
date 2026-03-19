#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
k8s_dir="$(cd "${script_dir}/.." && pwd)"

exclude_kind=0
exclude_lima=0
exclude_slicer=0

usage() {
  echo "Usage: $0 [--exclude kind|lima|slicer]..." >&2
}

while [[ $# -gt 0 ]]; do
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
    *)
      usage
      exit 1
      ;;
  esac
  shift
done

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
