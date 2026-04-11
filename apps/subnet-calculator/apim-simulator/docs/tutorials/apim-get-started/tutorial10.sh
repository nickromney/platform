#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$ROOT_DIR/scripts/tutorial_lib.sh"

init_tutorial_env
EXECUTE=0
VERIFY=0

usage() {
  cat <<EOF
Usage: ./docs/tutorials/apim-get-started/tutorial10.sh [--setup|--execute|--verify]

Runs tutorial step 10 for the APIM simulator.

Flags:
  --setup, --execute  Start the local stack and apply the tutorial REST Client policy.
  --verify            Verify the existing tutorial state without restarting it.
  --help, -h          Show this help text.
EOF
}

verify_tutorial() {
  echo "Verifying the authored policy and gateway response"

  echo '$ curl -sS -H "X-Apim-Tenant-Key: '"$APIM_TENANT_KEY"'" "'"$APIM_BASE"'/apim/management/policies/api/'"$APIM_API_ID"'"'
  fetched_policy="$(management_get "/apim/management/policies/api/$APIM_API_ID")"
  json_expect_summary \
    "$fetched_policy" \
    "{\"contains_vscode_header\":true,\"scope_name\":\"$APIM_API_ID\",\"scope_type\":\"api\"}" \
    'summary = {"contains_vscode_header": "x-from-vscode" in (data.get("xml") or ""), "scope_name": data.get("scope_name"), "scope_type": data.get("scope_type")}'

  echo
  echo '$ curl -i "'"$APIM_BASE"'/'"$APIM_API_PATH"'/health"'
  capture_http_request "$APIM_BASE/$APIM_API_PATH/health"
  captured_expect_summary \
    '{"path":"/api/health","status":"ok","status_code":200,"x_from_vscode":"true"}' \
    'summary = {"path": (body_json or {}).get("path"), "status": (body_json or {}).get("status"), "status_code": status, "x_from_vscode": headers.get("x-from-vscode")}'
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

if [[ "$EXECUTE" -eq 0 && "$VERIFY" -eq 0 ]]; then
  usage
  exit 0
fi

if [[ "$VERIFY" -eq 1 ]]; then
  run_verify_with_setup_hint "./docs/tutorials/apim-get-started/tutorial10.sh" verify_tutorial
  exit 0
fi

echo "Starting tutorial 10 stack with docker compose"
start_public_stack

echo "Waiting for gateway health at $APIM_BASE/apim/health"
wait_for_gateway

import_tutorial_api
echo

echo "REST Client example: $TUTORIAL10_REST_FILE"
echo "Applying the REST Client policy update to '$APIM_API_ID'"
policy_response="$(management_put "/apim/management/policies/api/$APIM_API_ID" "$(cat <<JSON
{"xml":"<policies><inbound /><backend /><outbound><set-header name=\"x-from-vscode\" exists-action=\"override\"><value>true</value></set-header></outbound><on-error /></policies>"}
JSON
)")"
json_expect_summary \
  "$policy_response" \
  "{\"contains_vscode_header\":true,\"scope_name\":\"$APIM_API_ID\",\"scope_type\":\"api\"}" \
  'summary = {"contains_vscode_header": "x-from-vscode" in (data.get("xml") or ""), "scope_name": data.get("scope_name"), "scope_type": data.get("scope_type")}'
echo
echo "Setup complete. Run ./docs/tutorials/apim-get-started/tutorial10.sh --verify to validate the authored policy."
