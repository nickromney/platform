#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$ROOT_DIR/scripts/tutorial_lib.sh"

init_tutorial_env
EXECUTE=0
VERIFY=0
DRY_RUN=0
TRACE_ONE="${TRACE_ONE:-tutorial05-health}"
TRACE_TWO="${TRACE_TWO:-tutorial05-echo}"

usage() {
  cat <<EOF
Usage: ./docs/tutorials/apim-get-started/tutorial05.sh [--setup|--execute|--verify|--dry-run]

Runs tutorial step 5 for the APIM simulator.

Flags:
  --setup, --execute  Start the local OTEL stack and send the tutorial trace traffic.
  --verify            Verify the existing tutorial state without restarting it.
  --dry-run           Show this help and preview the setup action without side effects.
  --help, -h          Show this help text.
EOF
}

verify_tutorial() {
  echo "Verifying observability surfaces"

  echo '$ curl -sS "'"$GRAFANA_BASE"'/api/health"'
  grafana_health="$(curl -fsS "$GRAFANA_BASE/api/health")"
  json_expect_summary \
    "$grafana_health" \
    '{"database":"ok"}' \
    'summary = {"database": data.get("database")}'

  echo
  echo '$ curl -sS -H "X-Apim-Tenant-Key: '"$APIM_TENANT_KEY"'" "'"$APIM_BASE"'/apim/management/traces"'
  traces_response="$(management_get "/apim/management/traces")"
  json_expect_summary \
    "$traces_response" \
    "{\"matching_traces\":[{\"correlation_id\":\"$TRACE_ONE\",\"status\":200,\"upstream_url\":\"http://mock-backend:8080/api/health\"},{\"correlation_id\":\"$TRACE_TWO\",\"status\":200,\"upstream_url\":\"http://mock-backend:8080/api/echo\"}]}" \
    'summary = {"matching_traces": sorted([{"correlation_id": item.get("correlation_id"), "status": item.get("status"), "upstream_url": item.get("upstream_url")} for item in data.get("items", []) if item.get("correlation_id") in {"'"$TRACE_ONE"'","'"$TRACE_TWO"'" }], key=lambda item: 0 if item["correlation_id"] == "'"$TRACE_ONE"'" else 1)}'
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
  run_verify_with_setup_hint "./docs/tutorials/apim-get-started/tutorial05.sh" verify_tutorial
  exit 0
fi

echo "Starting tutorial 05 stack with docker compose"
start_otel_stack

echo "Waiting for gateway health at $APIM_BASE/apim/health"
wait_for_gateway

echo "Waiting for Grafana health at $GRAFANA_BASE/api/health"
wait_for_grafana

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

echo "Sending traced sample traffic"
capture_http_request \
  -H "Ocp-Apim-Subscription-Key: $APIM_SUBSCRIPTION_KEY" \
  -H "x-apim-trace: true" \
  -H "x-correlation-id: $TRACE_ONE" \
  "$APIM_BASE/$APIM_API_PATH/health"
captured_expect_summary \
  "{\"correlation_id\":\"$TRACE_ONE\",\"status_code\":200,\"trace_id_present\":true}" \
  'summary = {"correlation_id": headers.get("x-correlation-id"), "status_code": status, "trace_id_present": bool(headers.get("x-apim-trace-id"))}'
echo

capture_http_request \
  -H "Ocp-Apim-Subscription-Key: $APIM_SUBSCRIPTION_KEY" \
  -H "x-apim-trace: true" \
  -H "x-correlation-id: $TRACE_TWO" \
  "$APIM_BASE/$APIM_API_PATH/echo"
captured_expect_summary \
  "{\"correlation_id\":\"$TRACE_TWO\",\"status_code\":200,\"trace_id_present\":true}" \
  'summary = {"correlation_id": headers.get("x-correlation-id"), "status_code": status, "trace_id_present": bool(headers.get("x-apim-trace-id"))}'
echo
echo "Setup complete. Run ./docs/tutorials/apim-get-started/tutorial05.sh --verify to validate the observability surfaces."
