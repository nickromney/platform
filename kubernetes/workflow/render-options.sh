#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OPTIONS_BASE_FILE="${OPTIONS_BASE_FILE:-${SCRIPT_DIR}/options.json}"
VARIANTS_DIR="${VARIANTS_DIR:-${REPO_ROOT}/kubernetes/variants}"

usage() {
  cat <<'EOF'
Usage: render-options.sh

Renders the Kubernetes workflow options contract with variant facts sourced
from kubernetes/variants/*/variant.json.
EOF
}

if [[ "${1-}" = "-h" || "${1-}" = "--help" ]]; then
  usage
  exit 0
fi

contracts=()
while IFS= read -r contract; do
  contracts+=("${contract}")
done < <(find "${VARIANTS_DIR}" -mindepth 2 -maxdepth 2 -name variant.json -type f | LC_ALL=C sort)

if [[ "${#contracts[@]}" -eq 0 ]]; then
  echo "No variant contracts found under ${VARIANTS_DIR}" >&2
  exit 1
fi

jq -s '
  def contract_for($contracts; $id):
    ($contracts[] | select(.id == $id));
  def merge_variant($contracts; $variant):
      (contract_for($contracts; $variant.id)) as $contract
      | $variant + {
          path: $contract.path,
          label: $contract.label,
          guided_label: $contract.guided_label,
          family: $contract.family,
          class: $contract.class,
          lifecycle_mode: $contract.lifecycle_mode,
          state_scope: $contract.state_scope,
          contexts: $contract.contexts,
          readiness: $contract.readiness,
          variant_contract: $contract
        };
  .[0] as $base
  | .[1:] as $contracts
  | $base
  | .variants = [
      $base.variants[] | merge_variant($contracts; .)
    ]
' "${OPTIONS_BASE_FILE}" "${contracts[@]}"
