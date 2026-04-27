#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"
CATALOG_FILE="${PLATFORM_APP_CATALOG:-${REPO_ROOT}/catalog/platform-apps.json}"
CATALOG_FORMAT="${CATALOG_FORMAT:-text}"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

fail() { echo "FAIL $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: idp-catalog.sh [--format text|json]

Prints the local IDP application catalog: owner, lifecycle, environments,
RBAC groups, deployment controller, and secret bindings.
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
      CATALOG_FORMAT="${2:-}"
      shift 2
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

shell_cli_maybe_execute_or_preview_summary usage "would inspect the IDP service catalog"

command -v jq >/dev/null 2>&1 || fail "jq not found in PATH"
[[ -f "${CATALOG_FILE}" ]] || fail "catalog not found: ${CATALOG_FILE}"

case "${CATALOG_FORMAT}" in
  json)
    jq '.' "${CATALOG_FILE}"
    ;;
  text)
    jq -r '
      .applications[]
      | [.name, .owner, .lifecycle, (.environments | map(.name + ":" + .rbac.group) | join(",")), (.secrets | map(.name) | join(","))]
      | @tsv
    ' "${CATALOG_FILE}" |
      awk 'BEGIN { printf "%-18s %-14s %-10s %-72s %s\n", "APP", "OWNER", "LIFECYCLE", "ENVIRONMENT_RBAC", "SECRETS" }
           { printf "%-18s %-14s %-10s %-72s %s\n", $1, $2, $3, $4, $5 }'
    ;;
  *)
    fail "Unknown --format ${CATALOG_FORMAT}; expected text or json"
    ;;
esac
