#!/usr/bin/env bash

SCRIPT_DIR_TUTORIAL_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./stack-env.sh
source "$SCRIPT_DIR_TUTORIAL_LIB/stack-env.sh"

init_tutorial_env() {
  stack_env_init

  DOCKER_BIN="${DOCKER_BIN:-docker}"
  UV_BIN="${UV_BIN:-uv}"
  APIM_BASE="${APIM_BASE:-$APIM_BASE_URL}"
  APIM_TENANT_KEY="${APIM_TENANT_KEY:-local-dev-tenant-key}"
  GRAFANA_BASE="${GRAFANA_BASE:-$GRAFANA_BASE_URL}"
  OPERATOR_CONSOLE_BASE="${OPERATOR_CONSOLE_BASE:-$OPERATOR_CONSOLE_URL}"
  OPENAPI_SOURCE="${OPENAPI_SOURCE:-$ROOT_DIR/examples/mock-backend/openapi.json}"
  APIM_API_ID="${APIM_API_ID:-tutorial-api}"
  APIM_API_NAME="${APIM_API_NAME:-Tutorial API}"
  APIM_API_PATH="${APIM_API_PATH:-tutorial-api}"
  APIM_PRODUCT_ID="${APIM_PRODUCT_ID:-tutorial-product}"
  APIM_PRODUCT_NAME="${APIM_PRODUCT_NAME:-Tutorial Product}"
  APIM_PRODUCT_DESCRIPTION="${APIM_PRODUCT_DESCRIPTION:-Product used by the mirrored APIM tutorials.}"
  APIM_SUBSCRIPTION_ID="${APIM_SUBSCRIPTION_ID:-tutorial-sub}"
  APIM_SUBSCRIPTION_NAME="${APIM_SUBSCRIPTION_NAME:-tutorial-sub}"
  APIM_SUBSCRIPTION_KEY="${APIM_SUBSCRIPTION_KEY:-tutorial-key}"
  APIM_HEALTH_ATTEMPTS="${APIM_HEALTH_ATTEMPTS:-30}"
  APIM_HEALTH_DELAY_SECONDS="${APIM_HEALTH_DELAY_SECONDS:-1}"
  APIM_EXPORT_DIR="${APIM_EXPORT_DIR:-/tmp/apim-simulator-tutorial11}"
  TUTORIAL10_REST_FILE="${TUTORIAL10_REST_FILE:-$ROOT_DIR/docs/tutorials/apim-get-started/tutorial10.rest.http}"

  if [[ -n "${STACK_INSTANCE_SUFFIX:-}" ]]; then
    COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-apim-simulator-tutorial-${STACK_INSTANCE_SUFFIX}}"
    export COMPOSE_PROJECT_NAME
  fi
}

tutorial_python() {
  "$UV_BIN" run --project "$ROOT_DIR" python "$@"
}

start_compose_stack() {
  local compose_log
  local -a compose_files
  local -a original_args
  local -a remaining_args
  local compose_file
  compose_files=()
  original_args=("$@")
  remaining_args=()
  compose_log="$(mktemp)"

  while (($# > 0)); do
    if [[ "$1" == "-f" ]]; then
      compose_files+=("$2")
      shift 2
      continue
    fi
    remaining_args=("$@")
    break
  done

  echo "Compose files:"
  local compose_file
  for compose_file in "${compose_files[@]}"; do
    echo "  - $(stack_env_display_path "$compose_file")"
  done
  echo "Running:"
  echo "  $DOCKER_BIN compose \\"
  for compose_file in "${compose_files[@]}"; do
    echo "    -f $(stack_env_display_path "$compose_file") \\"
  done
  echo "    ${remaining_args[*]}"

  if ! "$DOCKER_BIN" compose "${original_args[@]}" >"$compose_log" 2>&1; then
    echo "docker compose failed while starting the tutorial stack:" >&2
    cat "$compose_log" >&2
    rm -f "$compose_log"
    exit 1
  fi

  rm -f "$compose_log"
}

start_public_stack() {
  start_compose_stack \
    -f "$ROOT_DIR/compose.yml" \
    -f "$ROOT_DIR/compose.public.yml" \
    up --build -d
}

recreate_public_gateway_stack() {
  start_compose_stack \
    -f "$ROOT_DIR/compose.yml" \
    -f "$ROOT_DIR/compose.public.yml" \
    up --build -d --force-recreate apim-simulator mock-backend
}

start_otel_stack() {
  start_compose_stack \
    -f "$ROOT_DIR/compose.yml" \
    -f "$ROOT_DIR/compose.public.yml" \
    -f "$ROOT_DIR/compose.otel.yml" \
    up --build -d
}

start_ui_stack() {
  start_compose_stack \
    -f "$ROOT_DIR/compose.yml" \
    -f "$ROOT_DIR/compose.public.yml" \
    -f "$ROOT_DIR/compose.ui.yml" \
    up -d
}

wait_for_url() {
  local url="$1"
  local label="$2"
  local attempt

  for ((attempt = 1; attempt <= APIM_HEALTH_ATTEMPTS; attempt += 1)); do
    if curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep "$APIM_HEALTH_DELAY_SECONDS"
  done

  echo "$label did not become ready at $url" >&2
  return 1
}

wait_for_gateway() {
  wait_for_url "$APIM_BASE/apim/health" "Gateway"
}

wait_for_grafana() {
  wait_for_url "$GRAFANA_BASE/api/health" "Grafana"
}

wait_for_operator_console() {
  wait_for_url "$OPERATOR_CONSOLE_BASE" "Operator console"
}

run_verify_with_setup_hint() {
  local script_path="$1"
  shift
  local status

  set +e
  (
    set -e
    "$@"
  )
  status=$?
  set -e

  if [[ "$status" -ne 0 ]]; then
    echo >&2
    echo "Verification could not complete. Ensure the relevant tutorial stack is running and run $script_path --setup first." >&2
    exit "$status"
  fi
}

management_get() {
  curl -fsS -H "X-Apim-Tenant-Key: $APIM_TENANT_KEY" "$APIM_BASE$1"
}

management_put() {
  local path="$1"
  local payload="$2"
  curl -fsS -X PUT \
    -H "X-Apim-Tenant-Key: $APIM_TENANT_KEY" \
    -H "Content-Type: application/json" \
    "$APIM_BASE$path" \
    --data "$payload"
}

management_post() {
  local path="$1"
  local payload="$2"
  curl -fsS -X POST \
    -H "X-Apim-Tenant-Key: $APIM_TENANT_KEY" \
    -H "Content-Type: application/json" \
    "$APIM_BASE$path" \
    --data "$payload"
}

management_patch() {
  local path="$1"
  local payload="$2"
  curl -fsS -X PATCH \
    -H "X-Apim-Tenant-Key: $APIM_TENANT_KEY" \
    -H "Content-Type: application/json" \
    "$APIM_BASE$path" \
    --data "$payload"
}

management_delete() {
  curl -fsS -X DELETE -H "X-Apim-Tenant-Key: $APIM_TENANT_KEY" "$APIM_BASE$1"
}

gateway_get() {
  curl -fsS "$APIM_BASE$1"
}

gateway_get_with_subscription() {
  local path="$1"
  local key="$2"
  curl -fsS -H "Ocp-Apim-Subscription-Key: $key" "$APIM_BASE$path"
}

gateway_get_with_headers() {
  local path="$1"
  shift
  curl -fsS "$@" "$APIM_BASE$path"
}

capture_http_request() {
  local body_file
  local headers_file
  body_file="$(mktemp)"
  headers_file="$(mktemp)"

  CAPTURE_STATUS="$(curl -sS -D "$headers_file" -o "$body_file" "$@" -w '%{http_code}')"
  CAPTURE_BODY="$(cat "$body_file")"
  CAPTURE_HEADERS="$(cat "$headers_file")"

  rm -f "$body_file" "$headers_file"
}

pretty_json() {
  local actual_json="$1"
  ACTUAL_JSON="$actual_json" tutorial_python - <<'PY'
import json
import os

print(json.dumps(json.loads(os.environ["ACTUAL_JSON"]), indent=2, sort_keys=True))
PY
}

json_expect_summary() {
  local actual_json="$1"
  local expected_json="$2"
  local summary_script="$3"
  ACTUAL_JSON="$actual_json" EXPECTED_JSON="$expected_json" SUMMARY_SCRIPT="$summary_script" tutorial_python - <<'PY'
import json
import os
import sys

data = json.loads(os.environ["ACTUAL_JSON"])
expected = json.loads(os.environ["EXPECTED_JSON"])
scope = {"data": data}
exec(os.environ["SUMMARY_SCRIPT"], {}, scope)
summary = scope.get("summary")

if summary != expected:
    print("Verification failed.", file=sys.stderr)
    print(json.dumps({"expected": expected, "actual": summary}, indent=2, sort_keys=True), file=sys.stderr)
    sys.exit(1)

print(json.dumps(summary, indent=2, sort_keys=True))
PY
}

captured_expect_summary() {
  local expected_json="$1"
  local summary_script="$2"
  CAPTURE_STATUS="$CAPTURE_STATUS" \
  CAPTURE_HEADERS="$CAPTURE_HEADERS" \
  CAPTURE_BODY="$CAPTURE_BODY" \
  EXPECTED_JSON="$expected_json" \
  SUMMARY_SCRIPT="$summary_script" \
  tutorial_python - <<'PY'
import json
import os
import sys

status = int(os.environ["CAPTURE_STATUS"])
headers = {}
for line in os.environ["CAPTURE_HEADERS"].splitlines():
    if ":" not in line:
        continue
    name, value = line.split(":", 1)
    headers[name.strip().lower()] = value.strip()

body_text = os.environ["CAPTURE_BODY"]
try:
    body_json = json.loads(body_text)
except json.JSONDecodeError:
    body_json = None

expected = json.loads(os.environ["EXPECTED_JSON"])
scope = {
    "status": status,
    "headers": headers,
    "body_text": body_text,
    "body_json": body_json,
}
exec(os.environ["SUMMARY_SCRIPT"], {}, scope)
summary = scope.get("summary")

if summary != expected:
    print("Verification failed.", file=sys.stderr)
    print(json.dumps({"expected": expected, "actual": summary}, indent=2, sort_keys=True), file=sys.stderr)
    sys.exit(1)

print(json.dumps(summary, indent=2, sort_keys=True))
PY
}

import_tutorial_api() {
  echo "Importing OpenAPI source into API '$APIM_API_ID'"
  APIM_BASE_URL="$APIM_BASE" \
  APIM_TENANT_KEY="$APIM_TENANT_KEY" \
  OPENAPI_SOURCE="$OPENAPI_SOURCE" \
  APIM_API_ID="$APIM_API_ID" \
  APIM_API_NAME="$APIM_API_NAME" \
  APIM_API_PATH="$APIM_API_PATH" \
  tutorial_python "$ROOT_DIR/scripts/import_openapi.py"
}

ensure_subscription_absent() {
  local subscription_id="$1"
  curl -fsS -H "X-Apim-Tenant-Key: $APIM_TENANT_KEY" \
    "$APIM_BASE/apim/management/subscriptions/$subscription_id" >/dev/null 2>&1 || return 0
  management_delete "/apim/management/subscriptions/$subscription_id" >/dev/null
}
