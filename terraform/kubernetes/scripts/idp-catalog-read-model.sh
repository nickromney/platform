#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"
CATALOG_FILE="${PLATFORM_APP_CATALOG:-${REPO_ROOT}/catalog/platform-apps.json}"
PROJECTION=""
OUTPUT_FORMAT="json"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

fail() { echo "FAIL $*" >&2; exit 1; }

usage() {
  cat <<'EOF' | sed "1s|@SCRIPT_NAME@|${0##*/}|"
Usage: @SCRIPT_NAME@ --projection catalog|deployments|secrets|scorecards [--format text|json]

Projects the local IDP service catalog into operator read models.
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

require_value() {
  local flag="$1"
  local value="${2-}"
  if [[ -z "${value}" ]]; then
    shell_cli_missing_value "$(shell_cli_script_name)" "${flag}"
    exit 2
  fi
}

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi
  case "$1" in
    --projection)
      require_value "$1" "${2-}"
      PROJECTION="$2"
      shift 2
      ;;
    --format)
      require_value "$1" "${2-}"
      OUTPUT_FORMAT="$2"
      shift 2
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

shell_cli_maybe_execute_or_preview_summary usage "would inspect the IDP catalog ${PROJECTION:-read-model} projection"

command -v jq >/dev/null 2>&1 || fail "jq not found in PATH"
[[ -f "${CATALOG_FILE}" ]] || fail "catalog not found: ${CATALOG_FILE}"

catalog_json() {
  jq '.' "${CATALOG_FILE}"
}

catalog_text() {
  jq -r '
    .applications[]
    | [
        .name,
        .owner,
        .lifecycle,
        (.environments | map(.name + ":" + (.rbac.group // "not-declared")) | join(",")),
        (.secrets | map(.name) | join(","))
      ]
    | @tsv
  ' "${CATALOG_FILE}" |
    awk 'BEGIN { printf "%-18s %-14s %-10s %-72s %s\n", "APP", "OWNER", "LIFECYCLE", "ENVIRONMENT_RBAC", "SECRETS" }
         { printf "%-18s %-14s %-10s %-72s %s\n", $1, $2, $3, $4, $5 }'
}

deployments_json() {
  jq '{
    schema_version: "platform.idp.deployment-read-model/v1",
    deployments: [
      .applications[]
      | . as $app
      | .environments[]
      | {
          app: $app.name,
          owner: $app.owner,
          environment: .name,
          namespace: .namespace,
          route: .route,
          controller: $app.deployment.controller,
          strategy: $app.deployment.strategy,
          rbac_group: .rbac.group,
          image: (.deployment.image // $app.deployment.image // null),
          health: (.health // $app.health // null),
          sync: (.sync // $app.deployment.sync // null)
        }
    ]
  }' "${CATALOG_FILE}"
}

deployments_text() {
  jq -r '
    .applications[] as $app
    | .environments[]
    | [
        $app.name,
        .name,
        .namespace,
        .route,
        (.rbac.group // "not-declared")
      ]
    | @tsv
  ' "${CATALOG_FILE}" |
    awk 'BEGIN { printf "%-18s %-10s %-12s %-56s %s\n", "APP", "ENV", "NAMESPACE", "ROUTE", "RBAC_GROUP" }
         { printf "%-18s %-10s %-12s %-56s %s\n", $1, $2, $3, $4, $5 }'
}

secrets_json() {
  jq '{
    schema_version: "platform.idp.secret-bindings/v1",
    secrets: [
      .applications[]
      | . as $app
      | .secrets[]
      | . + {
          app: $app.name,
          owner: $app.owner,
          binding: (.binding // "not declared"),
          rotation: (.rotation // "not declared")
        }
    ]
  }' "${CATALOG_FILE}"
}

secrets_text() {
  jq -r '
    .applications[] as $app
    | $app.secrets[]
    | [
        $app.name,
        .name,
        (.binding // "not-declared"),
        (.rotation // "not-declared")
      ]
    | @tsv
  ' "${CATALOG_FILE}" |
    awk 'BEGIN { printf "%-18s %-34s %-14s %s\n", "APP", "SECRET", "BINDING", "ROTATION" }
         { printf "%-18s %-34s %-14s %s\n", $1, $2, $3, $4 }'
}

scorecards_json() {
  jq '{
    schema_version: "platform.idp.scorecard-read-model/v1",
    scorecards: [
      .applications[]
      | {
          app: .name,
          runtime_profile: (.scorecard.runtime_profile // "not declared"),
          has_health_endpoint: (.scorecard.has_health_endpoint // false),
          has_network_policy: (.scorecard.has_network_policy // false),
          has_owner: ((.scorecard.has_owner // false) or ((.owner // "") != "")),
          has_model_card: (if .scorecard.has_model_card == true then true else null end),
          tier: .scorecard.tier
        }
      | with_entries(select(.value != null))
    ]
  }' "${CATALOG_FILE}"
}

scorecards_text() {
  jq -r '
    .applications[]
    | [
        .name,
        (.scorecard.runtime_profile // "not-declared"),
        ((.scorecard.has_health_endpoint // false) | tostring),
        ((.scorecard.has_network_policy // false) | tostring),
        (((.scorecard.has_owner // false) or ((.owner // "") != "")) | tostring),
        (.scorecard.tier // "not-declared")
      ]
    | @tsv
  ' "${CATALOG_FILE}" |
    awk 'BEGIN { printf "%-18s %-18s %-10s %-14s %-10s %s\n", "APP", "RUNTIME_PROFILE", "HEALTH", "NETWORK_POLICY", "OWNER", "TIER" }
         { printf "%-18s %-18s %-10s %-14s %-10s %s\n", $1, $2, $3, $4, $5, $6 }'
}

case "${PROJECTION}:${OUTPUT_FORMAT}" in
  catalog:json) catalog_json ;;
  catalog:text) catalog_text ;;
  deployments:json) deployments_json ;;
  deployments:text) deployments_text ;;
  secrets:json) secrets_json ;;
  secrets:text) secrets_text ;;
  scorecards:json) scorecards_json ;;
  scorecards:text) scorecards_text ;;
  :*) fail "--projection is required" ;;
  *:*) fail "Unknown projection/format ${PROJECTION}:${OUTPUT_FORMAT}; expected projection catalog|deployments|secrets|scorecards and format text|json" ;;
esac
