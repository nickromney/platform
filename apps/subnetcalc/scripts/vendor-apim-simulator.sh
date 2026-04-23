#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

SOURCE_REPO="${APIM_SIMULATOR_SOURCE_REPO:-}"
SOURCE_REF="${APIM_SIMULATOR_SOURCE_REF:-}"
TARGET_DIR="${REPO_ROOT}/apps/subnetcalc/apim-simulator"
METADATA_FILE="${APIM_SIMULATOR_VENDOR_METADATA_FILE:-${REPO_ROOT}/apps/subnetcalc/apim-simulator.vendor.json}"
VENDOR_PROFILE="${APIM_SIMULATOR_VENDOR_PROFILE:-runtime}"
RUNTIME_INCLUDE_PATHS=(
  ".dockerignore"
  "Dockerfile"
  "LICENSE.md"
  "app"
  "contracts"
  "pyproject.toml"
  "uv.lock"
)
RUNTIME_EXCLUDE_PATHS=(
  ".github/"
  ".githooks/"
  "docs/"
  "examples/"
  "observability/"
  "scripts/"
  "tests/"
  "ui/"
)

usage() {
  cat <<EOF
Usage: vendor-apim-simulator.sh [--source PATH] [--ref TAG_OR_SHA] [--target PATH] [--metadata PATH] [--dry-run] [--execute]

Sync the vendored APIM simulator tree from a local git checkout pinned to a tag
or commit SHA.

Options:
  --source PATH    Local apim-simulator git checkout (or APIM_SIMULATOR_SOURCE_REPO)
  --ref TAG_OR_SHA Tag name or commit SHA to vendor (or APIM_SIMULATOR_SOURCE_REF)
  --target PATH    Target directory in this repo (default: ${TARGET_DIR})
  --metadata PATH  Metadata file to update with the resolved source commit
                   (default: ${METADATA_FILE})
$(shell_cli_standard_options)
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "$(shell_cli_script_name): $1 not found in PATH" >&2
    exit 1
  }
}

run_inline_python() {
  uv run --isolated python - "$@"
}

resolve_ref_kind() {
  local source_repo="$1"
  local source_ref="$2"

  if [[ "${source_ref}" =~ ^[0-9a-f]{7,40}$ ]]; then
    printf 'commit\n'
    return 0
  fi

  if [[ "${source_ref}" == refs/tags/* ]] && git -C "${source_repo}" show-ref --verify --quiet "${source_ref}"; then
    printf 'tag\n'
    return 0
  fi

  if git -C "${source_repo}" show-ref --verify --quiet "refs/tags/${source_ref}"; then
    printf 'tag\n'
    return 0
  fi

  return 1
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
    --metadata)
      [[ $# -ge 2 ]] || { shell_cli_missing_value "${script_name}" "$1"; exit 1; }
      METADATA_FILE="$2"
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

summary_source="${SOURCE_REPO:-<required --source>}"
summary_ref="${SOURCE_REF:-<required --ref tag-or-sha>}"
dry_run_summary="would vendor apim-simulator from ${summary_source} @ ${summary_ref} into ${TARGET_DIR} and record ${METADATA_FILE}"
shell_cli_maybe_execute_or_preview_summary usage "${dry_run_summary}"

if [[ -z "${SOURCE_REPO}" ]]; then
  echo "${script_name}: --source is required (or set APIM_SIMULATOR_SOURCE_REPO)" >&2
  exit 1
fi

if [[ -z "${SOURCE_REF}" ]]; then
  echo "${script_name}: --ref is required (or set APIM_SIMULATOR_SOURCE_REF)" >&2
  exit 1
fi

require_cmd git
require_cmd rsync
require_cmd tar
require_cmd uv

if [[ ! -d "${SOURCE_REPO}/.git" ]]; then
  echo "${script_name}: source is not a git checkout: ${SOURCE_REPO}" >&2
  exit 1
fi

source_ref_kind="$(resolve_ref_kind "${SOURCE_REPO}" "${SOURCE_REF}" || true)"
if [[ -z "${source_ref_kind}" ]]; then
  echo "${script_name}: --ref must be a tag or commit SHA, not a floating ref (${SOURCE_REF})" >&2
  exit 1
fi

source_commit="$(git -C "${SOURCE_REPO}" rev-parse --verify "${SOURCE_REF}^{commit}")"
source_origin="$(git -C "${SOURCE_REPO}" remote get-url origin 2>/dev/null || true)"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

mkdir -p "${tmp_dir}/export"
git -C "${SOURCE_REPO}" archive "${source_commit}" | tar -x -C "${tmp_dir}/export"
mkdir -p "${tmp_dir}/vendor"
case "${VENDOR_PROFILE}" in
  runtime)
    for include_path in "${RUNTIME_INCLUDE_PATHS[@]}"; do
      if [[ -e "${tmp_dir}/export/${include_path}" ]]; then
        (
          cd "${tmp_dir}/export"
          rsync -a --relative "./${include_path}" "${tmp_dir}/vendor/"
        )
      fi
    done
    run_inline_python "${tmp_dir}/vendor/Dockerfile" <<'PY'
import sys
from pathlib import Path

dockerfile = Path(sys.argv[1])
if not dockerfile.exists():
    raise SystemExit(0)

lines = dockerfile.read_text(encoding="utf-8").splitlines()
filtered = [
    line
    for line in lines
    if "COPY --chown=${APP_UID}:${APP_GID} examples ./examples" not in line
]
dockerfile.write_text("\n".join(filtered) + "\n", encoding="utf-8")
PY
    ;;
  full)
    rsync -a "${tmp_dir}/export"/ "${tmp_dir}/vendor/"
    ;;
  *)
    echo "${script_name}: unsupported APIM_SIMULATOR_VENDOR_PROFILE=${VENDOR_PROFILE}" >&2
    exit 1
    ;;
esac
mkdir -p "${TARGET_DIR}"
rsync -a --delete "${tmp_dir}/vendor"/ "${TARGET_DIR}/"
mkdir -p "$(dirname "${METADATA_FILE}")"
run_inline_python "${METADATA_FILE}" "${REPO_ROOT}" "${TARGET_DIR}" "${source_ref_kind}" "${SOURCE_REF}" "${source_commit}" "${source_origin}" "${VENDOR_PROFILE}" "${RUNTIME_INCLUDE_PATHS[@]}" -- "${RUNTIME_EXCLUDE_PATHS[@]}" <<'PY'
import json
import sys
from pathlib import Path

metadata_path = Path(sys.argv[1])
repo_root = Path(sys.argv[2])
target_dir = Path(sys.argv[3])
ref_kind = sys.argv[4]
requested_ref = sys.argv[5]
resolved_commit = sys.argv[6]
source_origin = sys.argv[7] or None
vendor_profile = sys.argv[8]
separator = sys.argv.index("--")
included_paths = sys.argv[9:separator]
excluded_paths = sys.argv[separator + 1 :]

try:
    vendored_path = str(target_dir.relative_to(repo_root))
except ValueError:
    vendored_path = str(target_dir)

metadata = {
    "vendored_path": vendored_path,
    "upstream": {
        "origin": source_origin,
        "ref_kind": ref_kind,
        "requested_ref": requested_ref,
        "resolved_commit": resolved_commit,
    },
    "subset": {
        "profile": vendor_profile,
        "included_paths": included_paths if vendor_profile == "runtime" else ["."],
        "excluded_paths": excluded_paths if vendor_profile == "runtime" else [],
        "postprocess": [
            "Dockerfile: removed upstream examples copy"
        ] if vendor_profile == "runtime" else [],
    },
}

metadata_path.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
PY

printf 'Vendored apim-simulator %s (%s %s, %s profile) -> %s\n' "${source_commit}" "${source_ref_kind}" "${SOURCE_REF}" "${VENDOR_PROFILE}" "${TARGET_DIR}"
printf 'Recorded vendoring metadata in %s\n' "${METADATA_FILE}"
