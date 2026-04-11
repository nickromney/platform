#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$ROOT_DIR/scripts/tutorial_lib.sh"

init_tutorial_env
EXECUTE=0
VERIFY=0
TRACE_CORRELATION_ID="${TRACE_CORRELATION_ID:-tutorial06-health}"
TRACE_ID=""

usage() {
  cat <<EOF
Usage: ./docs/tutorials/apim-get-started/tutorial06.sh [--setup|--execute|--verify]

Runs tutorial step 6 for the APIM simulator.

Flags:
  --setup, --execute  Start the local stack and create the traceable tutorial setup.
  --verify            Verify the existing tutorial state without restarting it.
  --help, -h          Show this help text.
EOF
}

verify_tutorial() {
  echo "Verifying stored trace details"

  echo '$ curl -sS -H "X-Apim-Tenant-Key: '"$APIM_TENANT_KEY"'" "'"$APIM_BASE"'/apim/management/traces"'
  traces_response="$(management_get "/apim/management/traces")"
  TRACE_ID="$(ACTUAL_JSON="$traces_response" TRACE_CORRELATION_ID="$TRACE_CORRELATION_ID" python3 - <<'PY'
import json
import os

items = [
    item for item in json.loads(os.environ["ACTUAL_JSON"]).get("items", [])
    if item.get("correlation_id") == os.environ["TRACE_CORRELATION_ID"]
]

if len(items) == 1 and items[0].get("trace_id"):
    print(items[0]["trace_id"])
PY
)"

  if [[ -z "$TRACE_ID" ]]; then
    echo "Did not find a stored trace for correlation ID '$TRACE_CORRELATION_ID'." >&2
    exit 1
  fi

  json_expect_summary \
    "$traces_response" \
    '{"matching_traces":1}' \
    'summary = {"matching_traces": len([item for item in data.get("items", []) if item.get("correlation_id") == "'"$TRACE_CORRELATION_ID"'"])}'

  echo
  echo '$ curl -sS "'"$APIM_BASE"'/apim/trace/<trace-id>"'
  trace_response="$(curl -fsS "$APIM_BASE/apim/trace/$TRACE_ID")"
  json_expect_summary \
    "$trace_response" \
    "{\"correlation_id\":\"$TRACE_CORRELATION_ID\",\"status\":200,\"upstream_url\":\"http://mock-backend:8080/api/health\"}" \
    'summary = {"correlation_id": data.get("correlation_id"), "status": data.get("status"), "upstream_url": data.get("upstream_url")}'
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
  run_verify_with_setup_hint "./docs/tutorials/apim-get-started/tutorial06.sh" verify_tutorial
  exit 0
fi

echo "Starting tutorial 06 stack with docker compose"
start_public_stack

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

echo "Requesting a trace-enabled call"
capture_http_request \
  -H "Ocp-Apim-Subscription-Key: $APIM_SUBSCRIPTION_KEY" \
  -H "x-apim-trace: true" \
  -H "x-correlation-id: $TRACE_CORRELATION_ID" \
  "$APIM_BASE/$APIM_API_PATH/health"
captured_expect_summary \
  "{\"correlation_id\":\"$TRACE_CORRELATION_ID\",\"status_code\":200,\"trace_id_present\":true}" \
  'summary = {"correlation_id": headers.get("x-correlation-id"), "status_code": status, "trace_id_present": bool(headers.get("x-apim-trace-id"))}'

TRACE_ID="$(CAPTURE_HEADERS="$CAPTURE_HEADERS" python3 - <<'PY'
import os

for line in os.environ["CAPTURE_HEADERS"].splitlines():
    if ":" not in line:
        continue
    name, value = line.split(":", 1)
    if name.strip().lower() == "x-apim-trace-id":
        print(value.strip())
        break
PY
)"

if [[ -z "$TRACE_ID" ]]; then
  echo "Trace ID was not returned by the gateway." >&2
  exit 1
fi
echo
echo "Setup complete. Run ./docs/tutorials/apim-get-started/tutorial06.sh --verify to validate the stored trace."
