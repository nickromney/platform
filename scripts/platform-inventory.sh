#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

OUTPUT_FORMAT="json"
VARIANT="kind"
STAGE="900"
STATUS_SCRIPT="${PLATFORM_INVENTORY_STATUS_SCRIPT:-${REPO_ROOT}/scripts/platform-status.sh}"
WORKFLOW_SCRIPT="${PLATFORM_INVENTORY_WORKFLOW_SCRIPT:-${REPO_ROOT}/scripts/platform-workflow.sh}"

usage() {
  cat <<'EOF' | sed "1s|@SCRIPT_NAME@|${0##*/}|"
Usage: @SCRIPT_NAME@ [--variant kind|lima|slicer] [--stage STAGE] [--output json|text] [--dry-run] [--execute]

Builds a read-only deployment inventory view for the guided workflow UI/TUI.
The inventory is observed live state plus workflow metadata; it is not
Terraform truth.
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

die_usage() {
  printf '%s\n' "$*" >&2
  exit 2
}

require_value() {
  local flag="$1"
  local value="${2-}"

  if [[ -z "${value}" ]]; then
    shell_cli_missing_value "$(shell_cli_script_name)" "${flag}"
    exit 2
  fi
}

validate_variant() {
  case "$1" in
    kind|lima|slicer) ;;
    *) die_usage "Invalid --variant '${1}'. Expected one of: kind, lima, slicer" ;;
  esac
}

validate_output() {
  case "$1" in
    json|text) ;;
    *) die_usage "Invalid --output '${1}'. Expected json or text" ;;
  esac
}

build_inventory_json() {
  local status_json=""
  local workflow_json=""

  status_json="$("${STATUS_SCRIPT}" --execute --output json)"
  workflow_json="$("${WORKFLOW_SCRIPT}" preview --execute --variant "${VARIANT}" --stage "${STAGE}" --action status --output json)"

  jq -n \
    --arg variant "${VARIANT}" \
    --arg stage "${STAGE}" \
    --argjson status "${status_json}" \
    --argjson workflow "${workflow_json}" \
    '{
      schema_version: "0.1",
      variant: $variant,
      stage: $stage,
      generated_at: $status.generated_at,
      observed_live_state: true,
      terraform_truth: false,
      workflow: {
        variant: $workflow.variant,
        stage: $workflow.stage,
        action: $workflow.action,
        contexts: $workflow.contexts,
        contract_requirements: $workflow.contract_requirements,
        effective_config: $workflow.effective_config
      },
      health_summary: {
        overall_state: $status.overall_state,
        active_variant: $status.active_variant,
        active_variant_path: $status.active_variant_path
      },
      variants: $status.variants,
      variants_order: $status.variants_order,
      host_runtimes: $status.host_runtimes,
      host_runtimes_order: $status.host_runtimes_order,
      registry_auth: $status.registry_auth,
      registry_auth_order: $status.registry_auth_order,
      raw_status: $status
    }'
}

print_inventory() {
  local inventory_json=""

  inventory_json="$(build_inventory_json)"
  case "${OUTPUT_FORMAT}" in
    json)
      printf '%s\n' "${inventory_json}"
      ;;
    text)
      jq -r '"Variant: \(.variant)\nStage: \(.stage)\nOverall: \(.health_summary.overall_state // "unknown")\nActive variant: \(.health_summary.active_variant // "none")"' <<<"${inventory_json}"
      ;;
  esac
}

SUBCOMMAND_FLAGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run|--execute)
      SUBCOMMAND_FLAGS+=("$1")
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      break
      ;;
  esac
done
if [[ "${#SUBCOMMAND_FLAGS[@]}" -gt 0 ]]; then
  set -- "${SUBCOMMAND_FLAGS[@]}" "$@"
fi

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --variant)
      require_value "$1" "${2-}"
      VARIANT="$2"
      shift 2
      ;;
    --target)
      die_usage "--target has been removed; use --variant"
      ;;
    --stage)
      require_value "$1" "${2-}"
      STAGE="$2"
      shift 2
      ;;
    --output)
      require_value "$1" "${2-}"
      OUTPUT_FORMAT="$2"
      shift 2
      ;;
    *)
      shell_cli_unknown_flag "$(shell_cli_script_name)" "$1"
      exit 2
      ;;
  esac
done

validate_variant "${VARIANT}"
validate_output "${OUTPUT_FORMAT}"

if [[ "${SHELL_CLI_DRY_RUN}" -eq 1 ]]; then
  shell_cli_print_dry_run_summary "would build ${VARIANT} stage ${STAGE} inventory"
  exit 0
fi

if [[ "${SHELL_CLI_EXECUTE}" -ne 1 ]]; then
  usage
  shell_cli_print_dry_run_summary "would build ${VARIANT} stage ${STAGE} inventory"
  exit 0
fi

print_inventory
