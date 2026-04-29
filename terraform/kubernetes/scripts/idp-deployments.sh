#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"
CATALOG_FILE="${PLATFORM_APP_CATALOG:-${REPO_ROOT}/catalog/platform-apps.json}"
DEPLOYMENT_FORMAT="${DEPLOYMENT_FORMAT:-json}"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

fail() { echo "FAIL $*" >&2; exit 1; }

usage() {
  cat <<'EOF' | sed "1s|@SCRIPT_NAME@|${0##*/}|"
Usage: @SCRIPT_NAME@ [--format json|text]

Prints the deployment read model from the local IDP catalog. When a cluster is
available, this can be joined with Argo CD and kubectl status output by callers.
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi
  case "$1" in
    --format)
      DEPLOYMENT_FORMAT="${2:-}"
      shift 2
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

shell_cli_maybe_execute_or_preview_summary usage "would inspect the IDP deployment read model"

command -v jq >/dev/null 2>&1 || fail "jq not found in PATH"
[[ -f "${CATALOG_FILE}" ]] || fail "catalog not found: ${CATALOG_FILE}"

case "${DEPLOYMENT_FORMAT}" in
  json)
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
            rbac_group: .rbac.group
          }
      ]
    }' "${CATALOG_FILE}"
    ;;
  text)
    jq -r '.applications[] as $app | .environments[] | [$app.name, .name, .namespace, .route, .rbac.group] | @tsv' "${CATALOG_FILE}" |
      awk 'BEGIN { printf "%-18s %-10s %-12s %-56s %s\n", "APP", "ENV", "NAMESPACE", "ROUTE", "RBAC_GROUP" }
           { printf "%-18s %-10s %-12s %-56s %s\n", $1, $2, $3, $4, $5 }'
    ;;
  *)
    fail "Unknown --format ${DEPLOYMENT_FORMAT}; expected json or text"
    ;;
esac
