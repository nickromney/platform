#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$ROOT_DIR/scripts/tutorial_lib.sh"

init_tutorial_env
EXECUTE=0
VERIFY=0
DRY_RUN=0

usage() {
  cat <<EOF
Usage: ./docs/tutorials/apim-get-started/tutorial09.sh [--setup|--execute|--verify|--dry-run]

Runs tutorial step 9 for the APIM simulator.

Flags:
  --setup, --execute  Start the operator console stack.
  --verify            Verify the existing tutorial state without restarting it.
  --dry-run           Show this help and preview the setup action without side effects.
  --help, -h          Show this help text.
EOF
}

verify_tutorial() {
  echo "Verifying the closest local equivalent"

  echo '$ curl -sS -H "X-Apim-Tenant-Key: '"$APIM_TENANT_KEY"'" "'"$APIM_BASE"'/apim/management/status"'
  status_response="$(management_get "/apim/management/status")"
  json_expect_summary \
    "$status_response" \
    '{"gateway_scope":"gateway","service_name":"apim-simulator"}' \
    'summary = {"gateway_scope": ((data.get("gateway_policy_scope") or {}).get("scope_name")), "service_name": ((data.get("service") or {}).get("name"))}'

  echo
  echo '$ curl -sS "'"$OPERATOR_CONSOLE_BASE"'"'
  capture_http_request "$OPERATOR_CONSOLE_BASE"
  captured_expect_summary \
    '{"status_code":200}' \
    'summary = {"status_code": status}'
  echo
}

while (($# > 0)); do
  case "$1" in
    --setup|--execute)
      EXECUTE=1
      ;;
    --verify)
      VERIFY=1
      ;;
    --dry-run)
      DRY_RUN=1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [[ "$EXECUTE" -eq 1 && "$VERIFY" -eq 1 ]]; then
  echo "Choose either --setup/--execute or --verify." >&2
  usage >&2
  exit 2
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  usage
  echo "INFO dry-run: would run $(basename "$0") setup; use --verify for read-only validation"
  exit 0
fi

if [[ "$EXECUTE" -eq 0 && "$VERIFY" -eq 0 ]]; then
  usage
  echo "INFO dry-run: would run $(basename "$0") setup; use --verify for read-only validation"
  exit 0
fi

if [[ "$VERIFY" -eq 1 ]]; then
  run_verify_with_setup_hint "./docs/tutorials/apim-get-started/tutorial09.sh" verify_tutorial
  exit 0
fi

echo "Starting tutorial 09 stack with docker compose"
start_ui_stack

echo "Waiting for gateway health at $APIM_BASE/apim/health"
wait_for_gateway

echo "Waiting for operator console at $OPERATOR_CONSOLE_BASE"
wait_for_operator_console

echo "Operator console is available at $OPERATOR_CONSOLE_BASE"
echo "Gateway is available at $APIM_BASE"
echo
echo "Setup complete. Run ./docs/tutorials/apim-get-started/tutorial09.sh --verify to validate the operator console."
