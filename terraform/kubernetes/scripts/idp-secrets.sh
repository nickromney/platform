#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"
CATALOG_FILE="${PLATFORM_APP_CATALOG:-${REPO_ROOT}/catalog/platform-apps.json}"
SECRET_FORMAT="${SECRET_FORMAT:-text}"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

fail() { echo "FAIL $*" >&2; exit 1; }

usage() {
  cat <<'EOF' | sed "1s|@SCRIPT_NAME@|${0##*/}|"
Usage: @SCRIPT_NAME@ [--format text|json]

Prints the local IDP secret binding and rotation model from the catalog.
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
      SECRET_FORMAT="${2:-}"
      shift 2
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

shell_cli_maybe_execute_or_preview_summary usage "would inspect the IDP secret lifecycle model"

command -v jq >/dev/null 2>&1 || fail "jq not found in PATH"
[[ -f "${CATALOG_FILE}" ]] || fail "catalog not found: ${CATALOG_FILE}"

case "${SECRET_FORMAT}" in
  json)
    jq '{
      schema_version: "platform.idp.secret-bindings/v1",
      secrets: [.applications[] as $app | $app.secrets[] | . + {app: $app.name, owner: $app.owner}]
    }' "${CATALOG_FILE}"
    ;;
  text)
    jq -r '.applications[] as $app | $app.secrets[] | [$app.name, .name, .binding, .rotation] | @tsv' "${CATALOG_FILE}" |
      awk 'BEGIN { printf "%-18s %-34s %-14s %s\n", "APP", "SECRET", "BINDING", "ROTATION" }
           { printf "%-18s %-34s %-14s %s\n", $1, $2, $3, $4 }'
    ;;
  *)
    fail "Unknown --format ${SECRET_FORMAT}; expected text or json"
    ;;
esac
