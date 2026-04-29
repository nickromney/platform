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
Usage: ./docs/tutorials/apim-get-started/tutorial02.sh [--setup|--execute|--verify|--dry-run]

Runs tutorial step 2 for the APIM simulator.

Flags:
  --setup, --execute  Start the local stack and create the tutorial product setup.
  --verify            Verify the existing tutorial state without restarting it.
  --dry-run           Show this help and preview the setup action without side effects.
  --help, -h          Show this help text.
EOF
}

verify_tutorial() {
  echo "Verifying product and subscription metadata"

  echo '$ curl -sS -H "X-Apim-Tenant-Key: '"$APIM_TENANT_KEY"'" "'"$APIM_BASE"'/apim/management/products/'"$APIM_PRODUCT_ID"'"'
  product_verify="$(management_get "/apim/management/products/$APIM_PRODUCT_ID")"
  json_expect_summary \
    "$product_verify" \
    "{\"id\":\"$APIM_PRODUCT_ID\",\"require_subscription\":true,\"subscription_count\":1}" \
    'summary = {"id": data.get("id"), "require_subscription": data.get("require_subscription"), "subscription_count": data.get("subscription_count")}'

  echo
  echo '$ curl -sS -H "X-Apim-Tenant-Key: '"$APIM_TENANT_KEY"'" "'"$APIM_BASE"'/apim/management/subscriptions/'"$APIM_SUBSCRIPTION_ID"'"'
  subscription_verify="$(management_get "/apim/management/subscriptions/$APIM_SUBSCRIPTION_ID")"
  json_expect_summary \
    "$subscription_verify" \
    "{\"id\":\"$APIM_SUBSCRIPTION_ID\",\"products\":[\"$APIM_PRODUCT_ID\"],\"primary_key\":\"$APIM_SUBSCRIPTION_KEY\",\"state\":\"active\"}" \
    'summary = {"id": data.get("id"), "products": data.get("products"), "primary_key": (data.get("keys") or {}).get("primary"), "state": data.get("state")}'

  echo
  echo "Verifying subscription-backed access"

  echo '$ curl -i "'"$APIM_BASE"'/'"$APIM_API_PATH"'/health"'
  capture_http_request "$APIM_BASE/$APIM_API_PATH/health"
  captured_expect_summary \
    '{"detail":"Missing subscription key","status_code":401}' \
    'summary = {"detail": (body_json or {}).get("detail"), "status_code": status}'

  echo
  echo '$ curl -sS -H "Ocp-Apim-Subscription-Key: '"$APIM_SUBSCRIPTION_KEY"'" "'"$APIM_BASE"'/'"$APIM_API_PATH"'/health"'
  authorized_response="$(gateway_get_with_subscription "/$APIM_API_PATH/health" "$APIM_SUBSCRIPTION_KEY")"
  json_expect_summary \
    "$authorized_response" \
    '{"path":"/api/health","status":"ok"}' \
    'summary = {"path": data.get("path"), "status": data.get("status")}'
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
  run_verify_with_setup_hint "./docs/tutorials/apim-get-started/tutorial02.sh" verify_tutorial
  exit 0
fi

echo "Starting tutorial 02 stack with docker compose"
start_public_stack

echo "Waiting for gateway health at $APIM_BASE/apim/health"
wait_for_gateway

import_tutorial_api
echo

echo "Creating product '$APIM_PRODUCT_ID'"
product_response="$(management_put "/apim/management/products/$APIM_PRODUCT_ID" "$(cat <<JSON
{"name":"$APIM_PRODUCT_NAME","description":"$APIM_PRODUCT_DESCRIPTION","require_subscription":true}
JSON
)")"
json_expect_summary \
  "$product_response" \
  "{\"id\":\"$APIM_PRODUCT_ID\",\"name\":\"$APIM_PRODUCT_NAME\",\"require_subscription\":true,\"subscription_count\":0}" \
  'summary = {"id": data.get("id"), "name": data.get("name"), "require_subscription": data.get("require_subscription"), "subscription_count": data.get("subscription_count")}'
echo

echo "Attaching API '$APIM_API_ID' to product '$APIM_PRODUCT_ID'"
api_response="$(management_put "/apim/management/apis/$APIM_API_ID" "$(cat <<JSON
{"name":"$APIM_API_NAME","path":"$APIM_API_PATH","upstream_base_url":"http://mock-backend:8080/api","products":["$APIM_PRODUCT_ID"]}
JSON
)")"
json_expect_summary \
  "$api_response" \
  "{\"id\":\"$APIM_API_ID\",\"path\":\"$APIM_API_PATH\",\"products\":[\"$APIM_PRODUCT_ID\"]}" \
  'summary = {"id": data.get("id"), "path": data.get("path"), "products": data.get("products")}'
echo

ensure_subscription_absent "$APIM_SUBSCRIPTION_ID"

echo "Creating subscription '$APIM_SUBSCRIPTION_ID'"
subscription_response="$(management_post "/apim/management/subscriptions" "$(cat <<JSON
{"id":"$APIM_SUBSCRIPTION_ID","name":"$APIM_SUBSCRIPTION_NAME","products":["$APIM_PRODUCT_ID"],"primary_key":"$APIM_SUBSCRIPTION_KEY"}
JSON
)")"
json_expect_summary \
  "$subscription_response" \
  "{\"id\":\"$APIM_SUBSCRIPTION_ID\",\"name\":\"$APIM_SUBSCRIPTION_NAME\",\"products\":[\"$APIM_PRODUCT_ID\"],\"primary_key\":\"$APIM_SUBSCRIPTION_KEY\"}" \
  'summary = {"id": data.get("id"), "name": data.get("name"), "products": data.get("products"), "primary_key": (data.get("keys") or {}).get("primary")}'
echo
echo "Setup complete. Run ./docs/tutorials/apim-get-started/tutorial02.sh --verify to validate product access."
