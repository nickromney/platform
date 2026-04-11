#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$ROOT_DIR/scripts/tutorial_lib.sh"

init_tutorial_env
EXECUTE=0
VERIFY=0
CURRENT_REVISION_SOURCE="${CURRENT_REVISION_SOURCE:-service/apim-simulator/apis/tutorial-api;rev=1}"

usage() {
  cat <<EOF
Usage: ./docs/tutorials/apim-get-started/tutorial11.sh [--setup|--execute|--verify]

Runs tutorial step 11 for the APIM simulator.

Flags:
  --setup, --execute  Start the local stack and export the tutorial inventory payloads.
  --verify            Verify the existing tutorial state without restarting it.
  --help, -h          Show this help text.
EOF
}

verify_tutorial() {
  echo "Verifying exported inventory inputs"

  echo '$ curl -sS -H "X-Apim-Tenant-Key: '"$APIM_TENANT_KEY"'" "'"$APIM_BASE"'/apim/management/summary"'
  summary_response="$(management_get "/apim/management/summary")"
  json_expect_summary \
    "$summary_response" \
    '{"api_ids":["default","tutorial-api"],"counts":{"api_releases":1,"api_revisions":2,"api_version_sets":1,"apis":2,"products":2,"subscriptions":1}}' \
    'summary = {"api_ids": sorted(item.get("id") for item in data.get("apis", [])), "counts": {key: (data.get("service") or {}).get("counts", {}).get(key) for key in ["api_releases", "api_revisions", "api_version_sets", "apis", "products", "subscriptions"]}}'

  echo
  echo '$ curl -sS -H "X-Apim-Tenant-Key: '"$APIM_TENANT_KEY"'" "'"$APIM_BASE"'/apim/management/apis"'
  apis_response="$(management_get "/apim/management/apis")"
  json_expect_summary \
    "$apis_response" \
    '{"api_ids":["default","tutorial-api"],"paths":["api","tutorial-api"]}' \
    'summary = {"api_ids": sorted(item.get("id") for item in data), "paths": sorted(item.get("path") for item in data)}'
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
  run_verify_with_setup_hint "./docs/tutorials/apim-get-started/tutorial11.sh" verify_tutorial
  exit 0
fi

echo "Starting tutorial 11 stack with docker compose"
start_public_stack

echo "Waiting for gateway health at $APIM_BASE/apim/health"
wait_for_gateway

import_tutorial_api
echo

echo "Creating inventory that is worth exporting"
management_put "/apim/management/products/$APIM_PRODUCT_ID" "$(cat <<JSON
{"name":"$APIM_PRODUCT_NAME","description":"$APIM_PRODUCT_DESCRIPTION","require_subscription":true}
JSON
)" >/dev/null
management_put "/apim/management/apis/$APIM_API_ID" "$(cat <<JSON
{"name":"$APIM_API_NAME","path":"$APIM_API_PATH","upstream_base_url":"http://mock-backend:8080/api","products":["$APIM_PRODUCT_ID"]}
JSON
)" >/dev/null
ensure_subscription_absent "$APIM_SUBSCRIPTION_ID"
management_post "/apim/management/subscriptions" "$(cat <<JSON
{"id":"$APIM_SUBSCRIPTION_ID","name":"$APIM_SUBSCRIPTION_NAME","products":["$APIM_PRODUCT_ID"],"primary_key":"$APIM_SUBSCRIPTION_KEY"}
JSON
)" >/dev/null
management_put "/apim/management/api-version-sets/public" "$(cat <<JSON
{"display_name":"Public","versioning_scheme":"Header","version_header_name":"x-api-version","default_version":"v1"}
JSON
)" >/dev/null
management_put "/apim/management/apis/$APIM_API_ID/revisions/1" "$(cat <<JSON
{"description":"Initial revision","is_current":false,"is_online":false}
JSON
)" >/dev/null
management_put "/apim/management/apis/$APIM_API_ID/revisions/2" "$(cat <<JSON
{"description":"Current revision","is_current":true,"is_online":true,"source_api_id":"$CURRENT_REVISION_SOURCE"}
JSON
)" >/dev/null
management_put "/apim/management/apis/$APIM_API_ID/releases/public" "$(cat <<JSON
{"notes":"Published revision","revision":"2"}
JSON
)" >/dev/null

echo "Exporting simulator inventory to $APIM_EXPORT_DIR"
mkdir -p "$APIM_EXPORT_DIR"
management_get "/apim/management/summary" >"$APIM_EXPORT_DIR/summary.json"
management_get "/apim/management/apis" >"$APIM_EXPORT_DIR/apis.json"
echo "Wrote $APIM_EXPORT_DIR/summary.json"
echo "Wrote $APIM_EXPORT_DIR/apis.json"
echo
echo "Setup complete. Run ./docs/tutorials/apim-get-started/tutorial11.sh --verify to validate the exported inventory inputs."
