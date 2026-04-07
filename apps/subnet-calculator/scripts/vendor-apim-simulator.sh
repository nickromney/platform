#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

SOURCE_REPO="${APIM_SIMULATOR_SOURCE_REPO:-}"
SOURCE_REF="${APIM_SIMULATOR_SOURCE_REF:-HEAD}"
TARGET_DIR="${REPO_ROOT}/apps/subnet-calculator/apim-simulator"

usage() {
  cat <<EOF
Usage: vendor-apim-simulator.sh [--source PATH] [--ref GIT_REF] [--target PATH] [--dry-run] [--execute]

Sync the vendored APIM simulator tree from a local git checkout at an exact ref.

Options:
  --source PATH  Local apim-simulator git checkout (or APIM_SIMULATOR_SOURCE_REPO)
  --ref GIT_REF  Git ref to vendor (default: HEAD or APIM_SIMULATOR_SOURCE_REF)
  --target PATH  Target directory in this repo (default: ${TARGET_DIR})
$(shell_cli_standard_options)
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "$(shell_cli_script_name): $1 not found in PATH" >&2
    exit 1
  }
}

shell_cli_init_standard_flags
script_name="$(shell_cli_script_name)"
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --source)
      [[ $# -ge 2 ]] || { shell_cli_missing_value "${script_name}" "$1"; exit 1; }
      SOURCE_REPO="$2"
      shift 2
      ;;
    --ref)
      [[ $# -ge 2 ]] || { shell_cli_missing_value "${script_name}" "$1"; exit 1; }
      SOURCE_REF="$2"
      shift 2
      ;;
    --target)
      [[ $# -ge 2 ]] || { shell_cli_missing_value "${script_name}" "$1"; exit 1; }
      TARGET_DIR="$2"
      shift 2
      ;;
    -*)
      shell_cli_unknown_flag "${script_name}" "$1"
      exit 1
      ;;
    *)
      shell_cli_unexpected_arg "${script_name}" "$1"
      exit 1
      ;;
  esac
done

if [[ -z "${SOURCE_REPO}" ]]; then
  echo "${script_name}: --source is required (or set APIM_SIMULATOR_SOURCE_REPO)" >&2
  exit 1
fi

require_cmd git
require_cmd rsync
require_cmd tar

if [[ ! -d "${SOURCE_REPO}/.git" ]]; then
  echo "${script_name}: source is not a git checkout: ${SOURCE_REPO}" >&2
  exit 1
fi

source_commit="$(git -C "${SOURCE_REPO}" rev-parse --verify "${SOURCE_REF}^{commit}")"
dry_run_summary="would vendor apim-simulator from ${SOURCE_REPO} @ ${SOURCE_REF} (${source_commit}) into ${TARGET_DIR}"
shell_cli_maybe_execute_or_preview_summary usage "${dry_run_summary}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

mkdir -p "${tmp_dir}/export"
git -C "${SOURCE_REPO}" archive "${source_commit}" | tar -x -C "${tmp_dir}/export"
mkdir -p "${TARGET_DIR}"
rsync -a --delete "${tmp_dir}/export"/ "${TARGET_DIR}/"

printf 'Vendored apim-simulator %s -> %s\n' "${source_commit}" "${TARGET_DIR}"
