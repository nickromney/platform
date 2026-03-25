#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../../" && pwd)"
RENDER_SCRIPT="${REPO_ROOT}/terraform/kubernetes/scripts/render-cilium-policy-values.sh"
OUTPUT_DIR="${REPO_ROOT}/terraform/cilium-module/categories/aks_sensible"

mkdir -p "${OUTPUT_DIR}"
find "${OUTPUT_DIR}" -maxdepth 1 -type f -name '*.yaml' -delete

while IFS= read -r -d '' source_file; do
  output_file="${OUTPUT_DIR}/$(basename "${source_file}")"
  "${RENDER_SCRIPT}" --output "${output_file}" "${source_file}"
done < <(find "${SCRIPT_DIR}" -maxdepth 1 -type f -name '*.yaml' -print0 | LC_ALL=C sort -z)
