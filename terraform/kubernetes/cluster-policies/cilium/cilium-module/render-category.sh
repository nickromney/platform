#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: render-category.sh <category-name|sources-dir>

Render one Cilium module category from `sources/` into the equivalent
`categories/` directory using `render-cilium-policy-values.sh`.

Examples:
  render-category.sh observability
  render-category.sh ./sources/observability
EOF
}

fail() {
  echo "render-category.sh: $*" >&2
  exit 1
}

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../../.." && pwd)"
RENDER_SCRIPT="${REPO_ROOT}/terraform/kubernetes/scripts/render-cilium-policy-values.sh"
input="${1}"

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
  "${RENDER_SCRIPT}" --output "${output_file}" "${source_file}"
done < <(find "${SOURCE_DIR}" -maxdepth 1 -type f -name '*.yaml' -print0 | LC_ALL=C sort -z)
