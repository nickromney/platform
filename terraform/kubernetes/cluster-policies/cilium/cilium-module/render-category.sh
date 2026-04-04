#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
  cat <<EOF
Usage: render-category.sh --input CATEGORY_OR_SOURCE_DIR [--dry-run] [--execute]

Render one Cilium module category from `sources/` into the equivalent
`categories/` directory using `render-cilium-policy-values.sh`.

Examples:
  render-category.sh --input observability
  render-category.sh --input ./sources/observability

Positional compatibility:
  render-category.sh observability
  render-category.sh ./sources/observability

$(shell_cli_standard_options)
EOF
}

fail() {
  echo "render-category.sh: $*" >&2
  exit 1
}

input=""
positional=()
shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --input)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--input"
        exit 1
      }
      input="$2"
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

if [[ -z "${input}" && "${#positional[@]}" -eq 0 ]]; then
  shell_cli_maybe_execute_or_preview_summary usage \
    "would render a Cilium module category after --input is provided"
fi

if [[ -z "${input}" ]]; then
  if [[ "${#positional[@]}" -ne 1 ]]; then
    usage >&2
    exit 2
  fi
  input="${positional[0]}"
elif [[ "${#positional[@]}" -ne 0 ]]; then
  usage >&2
  exit 2
fi

shell_cli_maybe_execute_or_preview_summary usage "would render Cilium category ${input}"

RENDER_SCRIPT="${REPO_ROOT}/terraform/kubernetes/scripts/render-cilium-policy-values.sh"

if [[ -d "${input}" ]]; then
  SOURCE_DIR="$(cd "${input}" && pwd)"
  CATEGORY_NAME="$(basename "${SOURCE_DIR}")"
else
  CATEGORY_NAME="${input}"
  SOURCE_DIR="${SCRIPT_DIR}/sources/${CATEGORY_NAME}"
fi

[[ -d "${SOURCE_DIR}" ]] || fail "source directory not found: ${input}"

OUTPUT_DIR="${SCRIPT_DIR}/categories/${CATEGORY_NAME}"

mkdir -p "${OUTPUT_DIR}"
find "${OUTPUT_DIR}" -maxdepth 1 -type f -name '*.yaml' -delete

while IFS= read -r -d '' source_file; do
  output_file="${OUTPUT_DIR}/$(basename "${source_file}")"
  "${RENDER_SCRIPT}" --execute --output "${output_file}" "${source_file}"
done < <(find "${SOURCE_DIR}" -maxdepth 1 -type f -name '*.yaml' -print0 | LC_ALL=C sort -z)
