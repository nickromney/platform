#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"
CATALOG_FILE="${PLATFORM_APP_CATALOG:-${REPO_ROOT}/catalog/platform-apps.json}"
CATALOG_FORMAT="${CATALOG_FORMAT:-text}"
READ_MODEL_SCRIPT="${IDP_CATALOG_READ_MODEL_SCRIPT:-${SCRIPT_DIR}/idp-catalog-read-model.sh}"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

fail() { echo "FAIL $*" >&2; exit 1; }

usage() {
  cat <<'EOF' | sed "1s|@SCRIPT_NAME@|${0##*/}|"
Usage: @SCRIPT_NAME@ [--format text|json]

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

case "${CATALOG_FORMAT}" in
  json|text) PLATFORM_APP_CATALOG="${CATALOG_FILE}" "${READ_MODEL_SCRIPT}" --execute --projection catalog --format "${CATALOG_FORMAT}" ;;
  *)
    fail "Unknown --format ${CATALOG_FORMAT}; expected text or json"
    ;;
esac
