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
Usage: ./docs/tutorials/apim-get-started/tutorial04.sh [--setup|--execute|--verify|--dry-run]

Runs tutorial step 4 for the APIM simulator.

Flags:
  --setup, --execute  Start the local stack and apply the tutorial protection policy.
  --verify            Verify the existing tutorial state without restarting it.
  --dry-run           Show this help and preview the setup action without side effects.
  --help, -h          Show this help text.
EOF
}

verify_tutorial() {
  echo "Verifying transform and throttling"

  echo '$ curl -i -H "Ocp-Apim-Subscription-Key: '"$APIM_SUBSCRIPTION_KEY"'" "'"$APIM_BASE"'/'"$APIM_API_PATH"'/health"'
  capture_http_request -H "Ocp-Apim-Subscription-Key: $APIM_SUBSCRIPTION_KEY" "$APIM_BASE/$APIM_API_PATH/health"
  captured_expect_summary \
    '{"custom_header":"My custom value","path":"/api/health","status":"ok","status_code":200}' \
    'summary = {"custom_header": headers.get("custom"), "path": (body_json or {}).get("path"), "status": (body_json or {}).get("status"), "status_code": status}'

  capture_http_request -H "Ocp-Apim-Subscription-Key: $APIM_SUBSCRIPTION_KEY" "$APIM_BASE/$APIM_API_PATH/health"
  capture_http_request -H "Ocp-Apim-Subscription-Key: $APIM_SUBSCRIPTION_KEY" "$APIM_BASE/$APIM_API_PATH/health"

  echo
  echo '$ curl -i -H "Ocp-Apim-Subscription-Key: '"$APIM_SUBSCRIPTION_KEY"'" "'"$APIM_BASE"'/'"$APIM_API_PATH"'/health"'
  capture_http_request -H "Ocp-Apim-Subscription-Key: $APIM_SUBSCRIPTION_KEY" "$APIM_BASE/$APIM_API_PATH/health"
  captured_expect_summary \
    '{"body_text":"Rate limit exceeded","retry_after_present":true,"status_code":429}' \
    'summary = {"body_text": body_text, "retry_after_present": "retry-after" in headers, "status_code": status}'
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
  run_verify_with_setup_hint "./docs/tutorials/apim-get-started/tutorial04.sh" verify_tutorial
  exit 0
fi

echo "Starting tutorial 04 stack with docker compose"
recreate_public_gateway_stack

echo "Waiting for gateway health at $APIM_BASE/apim/health"
wait_for_gateway

import_tutorial_api
echo

echo "Creating product '$APIM_PRODUCT_ID'"
management_put "/apim/management/products/$APIM_PRODUCT_ID" "$(cat <<JSON
{"name":"$APIM_PRODUCT_NAME","description":"$APIM_PRODUCT_DESCRIPTION","require_subscription":true}
JSON
)" >/dev/null

echo "Attaching API '$APIM_API_ID' to product '$APIM_PRODUCT_ID'"
management_put "/apim/management/apis/$APIM_API_ID" "$(cat <<JSON
{"name":"$APIM_API_NAME","path":"$APIM_API_PATH","upstream_base_url":"http://mock-backend:8080/api","products":["$APIM_PRODUCT_ID"]}
JSON
)" >/dev/null

ensure_subscription_absent "$APIM_SUBSCRIPTION_ID"
echo "Creating subscription '$APIM_SUBSCRIPTION_ID'"
management_post "/apim/management/subscriptions" "$(cat <<JSON
{"id":"$APIM_SUBSCRIPTION_ID","name":"$APIM_SUBSCRIPTION_NAME","products":["$APIM_PRODUCT_ID"],"primary_key":"$APIM_SUBSCRIPTION_KEY"}
JSON
)" >/dev/null

echo "Applying transform and rate-limit policy to '$APIM_API_ID'"
policy_response="$(management_put "/apim/management/policies/api/$APIM_API_ID" "$(cat <<JSON
{"xml":"<policies><inbound><rate-limit-by-key calls=\"3\" renewal-period=\"15\" counter-key=\"@(context.Subscription.Id)\" /><base /></inbound><backend><base /></backend><outbound><set-header name=\"Custom\" exists-action=\"override\"><value>My custom value</value></set-header><base /></outbound><on-error><base /></on-error></policies>"}
JSON
)")"
json_expect_summary \
  "$policy_response" \
  "{\"contains_custom_header\":true,\"contains_rate_limit\":true,\"scope_name\":\"$APIM_API_ID\",\"scope_type\":\"api\"}" \
  'summary = {"contains_custom_header": "Custom" in (data.get("xml") or ""), "contains_rate_limit": "rate-limit-by-key" in (data.get("xml") or ""), "scope_name": data.get("scope_name"), "scope_type": data.get("scope_type")}'
echo
echo "Setup complete. Run ./docs/tutorials/apim-get-started/tutorial04.sh --verify to validate the policy behaviour."
