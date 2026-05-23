#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

OUTPUT_FORMAT="json"
STATUS_SCRIPT="${PLATFORM_STATUS_READ_MODEL_STATUS_SCRIPT:-${REPO_ROOT}/scripts/platform-status.sh}"

usage() {
  cat <<'EOF' | sed "1s|@SCRIPT_NAME@|${0##*/}|"
Usage: @SCRIPT_NAME@ [--output json|text] [--dry-run] [--execute]

Builds a read-only ownership, readiness, blocker, and recommended-action
projection from platform-status JSON. It does not probe the platform directly
or change platform-status behavior.
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

validate_output() {
  case "$1" in
    json|text) ;;
    *) die_usage "Invalid --output '${1}'. Expected json or text" ;;
  esac
}

build_read_model_json() {
  local status_json=""

  status_json="$("${STATUS_SCRIPT}" --execute --output json)"

  jq -n --argjson status "${status_json}" '
    def blocker_facts($variant_key; $variant_path):
      (.blockers // [])
      | to_entries
      | map(
          (.value | tostring) as $message
          | (
              if ($message | test("^(?<claim>.+) claimed by (?<owner>.+)$")) then
                ($message | capture("^(?<claim>.+) claimed by (?<owner>.+)$"))
              else
                null
              end
            ) as $claim
          | {
              id: ($variant_key + "-blocker-" + (.key | tostring)),
              variant: $variant_key,
              variant_path: $variant_path,
              message: $message,
              blocks_readiness: true,
              claim: (if $claim then $claim.claim else null end),
              blocking_owner: (if $claim then $claim.owner else null end)
            }
        );

    def action_facts($actions; $variant_key):
      ($actions // [])
      | map(select(.variant == $variant_key))
      | map({
          id,
          label,
          command,
          enabled,
          reason,
          dangerous
        });

    def recommended_action($actions; $variant_key):
      (action_facts($actions; $variant_key)) as $facts
      | (
          $facts
          | map(select(.enabled and (.dangerous | not)))
          | .[0]
        ) // (
          $facts
          | map(select(.enabled))
          | .[0]
        ) // (
          $facts
          | .[0]
        ) // null;

    $status as $s
    | {
        schema_version: "0.1",
        generated_at: $s.generated_at,
        source: {
          name: "platform-status",
          observed_live_state: true,
          terraform_truth: false
        },
        overall_state: $s.overall_state,
        active_owner: {
          variant: $s.active_variant,
          variant_path: $s.active_variant_path
        },
        variants_order: ($s.variants_order // []),
        variants: (
          reduce (($s.variants_order // [])[]) as $key ({};
            ($s.variants[$key] // {}) as $variant
            | ($variant.path // null) as $variant_path
            | .[$key] = {
                ownership: {
                  variant: $key,
                  variant_path: $variant_path,
                  label: ($variant.label // $key),
                  runtime_family: ($variant.runtime_family // null),
                  active_owner: ($s.active_variant == $key),
                  serving: ($variant.serving // false),
                  runtime_present: ($variant.runtime_present // false)
                },
                readiness: {
                  state: ($variant.state // "not reported"),
                  ready: ((($variant.blockers // []) | length) == 0),
                  checks: ($variant.readiness // {})
                },
                blockers: ($variant | blocker_facts($key; $variant_path)),
                recommended_action: recommended_action($s.actions; $key),
                actions: action_facts($s.actions; $key)
              }
          )
        )
      }'
}

print_read_model() {
  local read_model_json=""

  read_model_json="$(build_read_model_json)"
  case "${OUTPUT_FORMAT}" in
    json)
      printf '%s\n' "${read_model_json}"
      ;;
    text)
      jq -r '
        "Overall: \(.overall_state // "not reported")",
        "Active owner: \(.active_owner.variant_path // "none")",
        (
          .variants_order[] as $key
          | .variants[$key] as $variant
          | "\($variant.ownership.variant_path): \($variant.readiness.state) blocker_count=\($variant.blockers | length) recommended=\($variant.recommended_action.command // "none")"
        )
      ' <<<"${read_model_json}"
      ;;
  esac
}

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
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

validate_output "${OUTPUT_FORMAT}"

if [[ "${SHELL_CLI_DRY_RUN}" -eq 1 ]]; then
  shell_cli_print_dry_run_summary "would build platform status read model"
  exit 0
fi

if [[ "${SHELL_CLI_EXECUTE}" -ne 1 ]]; then
  usage
  shell_cli_print_dry_run_summary "would build platform status read model"
  exit 0
fi

print_read_model
