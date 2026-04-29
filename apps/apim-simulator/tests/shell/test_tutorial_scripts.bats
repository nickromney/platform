#!/usr/bin/env bats

setup() {
  export ROOT
  ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
  export TUTORIAL_DIR="${ROOT}/docs/tutorials/apim-get-started"
  export TUTORIAL_CLEANUP="${TUTORIAL_DIR}/tutorial-cleanup.sh"
  export TEST_BIN="$BATS_TEST_TMPDIR/bin"
  export STATE_DIR="$BATS_TEST_TMPDIR/state"
  export CALL_LOG="$BATS_TEST_TMPDIR/calls.log"
  mkdir -p "$TEST_BIN" "$STATE_DIR"

  export APIM_BASE="http://localhost:8000"
  export APIM_TENANT_KEY="local-dev-tenant-key"
  export GRAFANA_BASE="https://lgtm.apim.127.0.0.1.sslip.io:8443"
  export OPERATOR_CONSOLE_BASE="http://localhost:3007"
  export OPENAPI_SOURCE="$BATS_TEST_TMPDIR/mock-openapi.json"
  printf '{}\n' >"$OPENAPI_SOURCE"

  cat >"$TEST_BIN/docker" <<'EOF'
#!/usr/bin/env bash
printf 'docker %s\n' "$*" >>"$CALL_LOG"
EOF
  chmod +x "$TEST_BIN/docker"

  cat >"$TEST_BIN/uv" <<'EOF'
#!/usr/bin/env bash
printf 'uv %s\n' "$*" >>"$CALL_LOG"
if [[ "${1:-}" == "run" ]]; then
  shift
  if [[ "${1:-}" == "--project" ]]; then
    shift 2
  fi
  if [[ "${1:-}" == "python" && "${2:-}" == "-" ]]; then
    shift
    exec python3 "$@"
  fi
  if [[ "${1:-}" == "python" && "${2:-}" == *"/scripts/import_openapi.py" ]]; then
    printf '{"api_id":"tutorial-api","path":"tutorial-api","operations":["echo","health"],"import":{"diagnostics":[],"format":"openapi+json","operation_count":2,"upstream_base_url":"http://mock-backend:8080/api"}}\n'
    exit 0
  fi
fi
printf '{"api_id":"tutorial-api","path":"tutorial-api","operations":["echo","health"],"import":{"diagnostics":[],"format":"openapi+json","operation_count":2,"upstream_base_url":"http://mock-backend:8080/api"}}\n'
EOF
  chmod +x "$TEST_BIN/uv"

  cat >"$TEST_BIN/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

method="GET"
url=""
data=""
body_file=""
headers_file=""
write_format=""
declare -a request_headers=()

has_header() {
  local expected="$1"
  local item
  for item in "${request_headers[@]}"; do
    if [[ "$item" == "$expected" ]]; then
      return 0
    fi
  done
  return 1
}

header_value() {
  local expected="${1,,}"
  local item key value
  for item in "${request_headers[@]}"; do
    key="${item%%:*}"
    value="${item#*: }"
    if [[ "${key,,}" == "$expected" ]]; then
      printf '%s' "$value"
      return 0
    fi
  done
  return 1
}

while (($# > 0)); do
  case "$1" in
    -X)
      method="$2"
      shift 2
      ;;
    -H)
      request_headers+=("$2")
      shift 2
      ;;
    --data|--data-binary)
      data="$2"
      shift 2
      ;;
    -D)
      headers_file="$2"
      shift 2
      ;;
    -o)
      body_file="$2"
      shift 2
      ;;
    -w)
      write_format="$2"
      shift 2
      ;;
    -*)
      shift
      ;;
    *)
      url="$1"
      shift
      ;;
  esac
done

printf 'curl %s %s\n' "$method" "$url" >>"$CALL_LOG"

response_status=200
response_body='{}'
declare -a response_headers=()

policy_file="$STATE_DIR/tutorial-api-policy"
rate_limit_file="$STATE_DIR/rate-limit-count"
trace_health_id="trace-tutorial05-health"
trace_echo_id="trace-tutorial05-echo"
trace_debug_id="trace-tutorial06-health"

case "$url" in
  "http://localhost:8000/apim/health")
    response_body='{"status":"healthy"}'
    ;;
  "https://lgtm.apim.127.0.0.1.sslip.io:8443/api/health")
    response_body='{"database":"ok","version":"11.0.0"}'
    ;;
  "http://localhost:3007"| "http://localhost:3007/")
    response_body='<html><body>Operator console</body></html>'
    response_headers+=("content-type: text/html; charset=utf-8")
    ;;
  "http://localhost:8000/apim/management/products/tutorial-product")
    if [[ "$method" == "GET" ]]; then
      response_body='{"id":"tutorial-product","name":"Tutorial Product","require_subscription":true,"subscription_count":1}'
    else
      response_body='{"id":"tutorial-product","name":"Tutorial Product","require_subscription":true,"subscription_count":0}'
    fi
    ;;
  "http://localhost:8000/apim/management/subscriptions/tutorial-sub")
    if [[ "$method" == "DELETE" ]]; then
      response_body='{"deleted":true,"subscription_id":"tutorial-sub","remaining":0}'
    else
      response_body='{"id":"tutorial-sub","name":"tutorial-sub","state":"active","products":["tutorial-product"],"keys":{"primary":"tutorial-key","secondary":"tutorial-key-secondary"}}'
    fi
    ;;
  "http://localhost:8000/apim/management/subscriptions")
    response_body='{"id":"tutorial-sub","name":"tutorial-sub","state":"active","products":["tutorial-product"],"keys":{"primary":"tutorial-key","secondary":"tutorial-key-secondary"}}'
    ;;
  "http://localhost:8000/apim/management/apis/mock-only")
    response_body='{"id":"mock-only","path":"mock-only","upstream_base_url":"http://example.invalid"}'
    ;;
  "http://localhost:8000/apim/management/apis/mock-only/operations/test-call")
    response_body='{"id":"test-call","method":"GET","url_template":"/test","responses":[{"status_code":200,"representations":[{"content_type":"application/json","examples":[{"name":"ok","value":{"sampleField":"test"}}]}]}]}'
    ;;
  "http://localhost:8000/apim/management/policies/operation/mock-only:test-call")
    response_body='{"scope_type":"operation","scope_name":"mock-only:test-call","xml":"<policies><inbound><mock-response status-code=\"200\" content-type=\"application/json\" /></inbound><backend /><outbound /><on-error /></policies>"}'
    ;;
  "http://localhost:8000/mock-only/test")
    response_body='{"sampleField":"test"}'
    ;;
  "http://localhost:8000/apim/management/policies/api/tutorial-api")
    if [[ "$method" == "PUT" ]]; then
      if [[ "$data" == *"x-from-vscode"* ]]; then
        printf 'vscode\n' >"$policy_file"
        response_body='{"scope_type":"api","scope_name":"tutorial-api","xml":"<policies><inbound /><backend /><outbound><set-header name=\"x-from-vscode\" exists-action=\"override\"><value>true</value></set-header></outbound><on-error /></policies>"}'
      else
        printf 'rate-limit\n' >"$policy_file"
        printf '0\n' >"$rate_limit_file"
        response_body='{"scope_type":"api","scope_name":"tutorial-api","xml":"<policies><inbound><rate-limit-by-key calls=\"3\" renewal-period=\"15\" counter-key=\"@(context.Subscription.Id)\" /><base /></inbound><backend><base /></backend><outbound><set-header name=\"Custom\" exists-action=\"override\"><value>My custom value</value></set-header><base /></outbound><on-error><base /></on-error></policies>"}'
      fi
    else
      if [[ -f "$policy_file" ]] && [[ "$(cat "$policy_file")" == "vscode" ]]; then
        response_body='{"scope_type":"api","scope_name":"tutorial-api","xml":"<policies><inbound /><backend /><outbound><set-header name=\"x-from-vscode\" exists-action=\"override\"><value>true</value></set-header></outbound><on-error /></policies>"}'
      else
        response_body='{"scope_type":"api","scope_name":"tutorial-api","xml":"<policies><inbound><rate-limit-by-key calls=\"3\" renewal-period=\"15\" counter-key=\"@(context.Subscription.Id)\" /><base /></inbound><backend><base /></backend><outbound><set-header name=\"Custom\" exists-action=\"override\"><value>My custom value</value></set-header><base /></outbound><on-error><base /></on-error></policies>"}'
      fi
    fi
    ;;
  "http://localhost:8000/apim/management/apis/tutorial-api")
    response_body='{"id":"tutorial-api","path":"tutorial-api","upstream_base_url":"http://mock-backend:8080/api","products":["tutorial-product"],"operations":[{"id":"echo"},{"id":"health"}],"revision":"2","revisions":[{"id":"1","is_current":false},{"id":"2","is_current":true}],"releases":[{"id":"public","revision":"2"}]}'
    ;;
  "http://localhost:8000/apim/management/apis/tutorial-api/revisions/1")
    response_body='{"id":"1","description":"Initial revision","is_current":false,"is_online":false}'
    ;;
  "http://localhost:8000/apim/management/apis/tutorial-api/revisions/2")
    response_body='{"id":"2","description":"Current revision","is_current":true,"is_online":true,"source_api_id":"service/apim-simulator/apis/tutorial-api;rev=1"}'
    ;;
  "http://localhost:8000/apim/management/apis/tutorial-api/revisions")
    response_body='[{"id":"1","is_current":false},{"id":"2","is_current":true}]'
    ;;
  "http://localhost:8000/apim/management/apis/tutorial-api/releases/public")
    response_body='{"id":"public","api_id":"service/apim-simulator/apis/tutorial-api;rev=2","revision":"2","notes":"Published revision"}'
    ;;
  "http://localhost:8000/apim/management/apis/tutorial-api/releases")
    response_body='[{"id":"public","revision":"2"}]'
    ;;
  "http://localhost:8000/apim/management/api-version-sets/public")
    response_body='{"id":"public","default_version":"v1","version_header_name":"x-api-version","versioning_scheme":"Header"}'
    ;;
  "http://localhost:8000/apim/management/apis/versioned-v1")
    response_body='{"id":"versioned-v1","path":"versioned","api_version":"v1"}'
    ;;
  "http://localhost:8000/apim/management/apis/versioned-v2")
    response_body='{"id":"versioned-v2","path":"versioned","api_version":"v2"}'
    ;;
  "http://localhost:8000/apim/management/apis/versioned-v1/operations/echo"|\
  "http://localhost:8000/apim/management/apis/versioned-v2/operations/echo")
    response_body='{"id":"echo","method":"GET","url_template":"/echo"}'
    ;;
  "http://localhost:8000/versioned/echo")
    response_body='{"ok":true,"method":"GET","path":"/api/echo","body":""}'
    if has_header "x-api-version: v2"; then
      response_headers+=("x-version: v2")
    fi
    ;;
  "http://localhost:8000/apim/trace/$trace_debug_id")
    response_body='{"correlation_id":"tutorial06-health","status":200,"upstream_url":"http://mock-backend:8080/api/health"}'
    ;;
  "http://localhost:8000/apim/management/traces")
    response_body='{"items":[{"trace_id":"trace-tutorial06-health","correlation_id":"tutorial06-health","status":200},{"trace_id":"trace-tutorial05-health","correlation_id":"tutorial05-health","status":200,"upstream_url":"http://mock-backend:8080/api/health"},{"trace_id":"trace-tutorial05-echo","correlation_id":"tutorial05-echo","status":200,"upstream_url":"http://mock-backend:8080/api/echo"}]}'
    ;;
  "http://localhost:8000/apim/management/status")
    response_body='{"service":{"name":"apim-simulator"},"gateway_policy_scope":{"scope_name":"gateway"}}'
    ;;
  "http://localhost:8000/apim/management/summary")
    response_body='{"service":{"counts":{"api_releases":1,"api_revisions":2,"api_version_sets":1,"apis":2,"products":2,"subscriptions":1}},"apis":[{"id":"default"},{"id":"tutorial-api"}]}'
    ;;
  "http://localhost:8000/apim/management/apis")
    response_body='[{"id":"default","path":"api"},{"id":"tutorial-api","path":"tutorial-api"}]'
    ;;
  "http://localhost:8000/tutorial-api/echo")
    response_body='{"ok":true,"method":"GET","path":"/api/echo","body":""}'
    if has_header "x-apim-trace: true"; then
      correlation="$(header_value "x-correlation-id")"
      response_headers+=("x-correlation-id: $correlation")
      response_headers+=("x-apim-trace-id: trace-$correlation")
    fi
    ;;
  "http://localhost:8000/tutorial-api/health")
    if has_header "x-apim-trace: true"; then
      correlation="$(header_value "x-correlation-id")"
      response_body='{"status":"ok","path":"/api/health"}'
      response_headers+=("x-correlation-id: $correlation")
      response_headers+=("x-apim-trace-id: trace-$correlation")
    elif has_header "Ocp-Apim-Subscription-Key: tutorial-key"; then
      policy_mode=""
      if [[ -f "$policy_file" ]]; then
        policy_mode="$(cat "$policy_file")"
      fi
      if [[ "$policy_mode" == "rate-limit" ]]; then
        count=0
        if [[ -f "$rate_limit_file" ]]; then
          count="$(cat "$rate_limit_file")"
        fi
        count=$((count + 1))
        printf '%s\n' "$count" >"$rate_limit_file"
        if ((count > 3)); then
          response_status=429
          response_body='Rate limit exceeded'
          response_headers+=("retry-after: 15")
        else
          response_body='{"status":"ok","path":"/api/health"}'
          response_headers+=("custom: My custom value")
        fi
      else
        response_body='{"status":"ok","path":"/api/health"}'
      fi
    else
      policy_mode=""
      if [[ -f "$policy_file" ]]; then
        policy_mode="$(cat "$policy_file")"
      fi
      if [[ "$policy_mode" == "vscode" ]]; then
        response_body='{"status":"ok","path":"/api/health"}'
        response_headers+=("x-from-vscode: true")
      else
        response_status=401
        response_body='{"detail":"Missing subscription key"}'
      fi
    fi
    ;;
  *)
    response_body='{}'
    ;;
esac

if [[ -n "$headers_file" ]]; then
  {
    for item in "${response_headers[@]}"; do
      printf '%s\n' "$item"
    done
  } >"$headers_file"
fi

if [[ -n "$body_file" ]]; then
  printf '%s' "$response_body" >"$body_file"
else
  printf '%s' "$response_body"
fi

if [[ -n "$write_format" ]]; then
  printf '%s' "$response_status"
fi
EOF
  chmod +x "$TEST_BIN/curl"

  export PATH="$TEST_BIN:$PATH"
}

@test "tutorial02-11 without arguments print help" {
  local script
  for script in "$TUTORIAL_DIR"/tutorial{02,03,04,05,06,07,08,09,10,11}.sh; do
    run "$script"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[--setup|--execute|--verify|--dry-run]"* ]]
    [[ "$output" == *"INFO dry-run:"* ]]
  done
}

@test "tutorial-cleanup.sh stops the tutorial compose stacks" {
  run "$TUTORIAL_CLEANUP" --execute

  [ "$status" -eq 0 ]
  [[ "$output" == *"Stopping all tutorial stack variants with docker compose"* ]]
  [[ "$output" == *"Compose files:"* ]]
  [[ "$output" == *"./compose.public.yml"* ]]
  [[ "$output" == *"./compose.otel.yml"* ]]
  [[ "$output" == *"./compose.ui.yml"* ]]
  [[ "$output" == *"Running:"* ]]
  [[ "$output" == *"down --remove-orphans"* ]]

  run cat "$CALL_LOG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"docker compose -f ${ROOT}/compose.yml -f ${ROOT}/compose.public.yml -f ${ROOT}/compose.otel.yml -f ${ROOT}/compose.ui.yml down --remove-orphans"* ]]
}

@test "tutorial02.sh --verify bootstraps product access" {
  run "$TUTORIAL_DIR/tutorial02.sh" --setup
  [ "$status" -eq 0 ]

  run "$TUTORIAL_DIR/tutorial02.sh" --verify

  [ "$status" -eq 0 ]
  [[ "$output" != *"Starting tutorial 02 stack with docker compose"* ]]
  [[ "$output" == *"Verifying product and subscription metadata"* ]]
  [[ "$output" == *'"subscription_count": 1'* ]]
  [[ "$output" == *'"detail": "Missing subscription key"'* ]]
  [[ "$output" == *'"status": "ok"'* ]]
}

@test "tutorial02.sh --verify suggests setup when state is missing" {
  cat >"$TEST_BIN/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

method="GET"
url=""

while (($# > 0)); do
  case "$1" in
    -X)
      method="$2"
      shift 2
      ;;
    -H|-D|-o|-w|--data|--data-binary)
      shift 2
      ;;
    -*)
      shift
      ;;
    *)
      url="$1"
      shift
      ;;
  esac
done

printf 'curl %s %s\n' "$method" "$url" >>"$CALL_LOG"

case "$url" in
  "http://localhost:8000/apim/management/products/tutorial-product")
    echo 'curl: (22) The requested URL returned error: 404' >&2
    exit 22
    ;;
  *)
    printf '{}'
    ;;
esac
EOF
  chmod +x "$TEST_BIN/curl"

  run "$TUTORIAL_DIR/tutorial02.sh" --verify

  [ "$status" -ne 0 ]
  [[ "$output" == *"Verification could not complete."* ]]
  [[ "$output" == *"./docs/tutorials/apim-get-started/tutorial02.sh --setup first."* ]]
}

@test "tutorial03.sh --verify configures mock-response" {
  run "$TUTORIAL_DIR/tutorial03.sh" --setup
  [ "$status" -eq 0 ]

  run "$TUTORIAL_DIR/tutorial03.sh" --verify

  [ "$status" -eq 0 ]
  [[ "$output" != *"Starting tutorial 03 stack with docker compose"* ]]
  [[ "$output" == *"Verifying mocked response"* ]]
  [[ "$output" == *'"sampleField": "test"'* ]]
}

@test "tutorial04.sh --verify checks throttling" {
  run "$TUTORIAL_DIR/tutorial04.sh" --setup
  [ "$status" -eq 0 ]

  run "$TUTORIAL_DIR/tutorial04.sh" --verify

  [ "$status" -eq 0 ]
  [[ "$output" != *"Starting tutorial 04 stack with docker compose"* ]]
  [[ "$output" == *'"custom_header": "My custom value"'* ]]
  [[ "$output" == *'"status_code": 429'* ]]
  [[ "$output" == *'"retry_after_present": true'* ]]
}

@test "tutorial05.sh --verify checks grafana and traces" {
  run "$TUTORIAL_DIR/tutorial05.sh" --setup
  [ "$status" -eq 0 ]

  run "$TUTORIAL_DIR/tutorial05.sh" --verify

  [ "$status" -eq 0 ]
  [[ "$output" != *"Starting tutorial 05 stack with docker compose"* ]]
  [[ "$output" == *'"database": "ok"'* ]]
  [[ "$output" == *'"correlation_id": "tutorial05-health"'* ]]
  [[ "$output" == *'"upstream_url": "http://mock-backend:8080/api/echo"'* ]]
}

@test "tutorial06.sh --verify looks up the captured trace" {
  run "$TUTORIAL_DIR/tutorial06.sh" --setup
  [ "$status" -eq 0 ]

  run "$TUTORIAL_DIR/tutorial06.sh" --verify

  [ "$status" -eq 0 ]
  [[ "$output" != *"Starting tutorial 06 stack with docker compose"* ]]
  [[ "$output" == *'/apim/trace/<trace-id>'* ]]
  [[ "$output" == *'"upstream_url": "http://mock-backend:8080/api/health"'* ]]
  [[ "$output" == *'"matching_traces": 1'* ]]
}

@test "tutorial07.sh --verify records revisions and releases" {
  run "$TUTORIAL_DIR/tutorial07.sh" --setup
  [ "$status" -eq 0 ]

  run "$TUTORIAL_DIR/tutorial07.sh" --verify

  [ "$status" -eq 0 ]
  [[ "$output" != *"Starting tutorial 07 stack with docker compose"* ]]
  [[ "$output" == *'"id": "public"'* ]]
  [[ "$output" == *'"revision_ids": ['* ]]
  [[ "$output" == *'"releases": ['* ]]
}

@test "tutorial08.sh --verify routes by version header" {
  run "$TUTORIAL_DIR/tutorial08.sh" --setup
  [ "$status" -eq 0 ]

  run "$TUTORIAL_DIR/tutorial08.sh" --verify

  [ "$status" -eq 0 ]
  [[ "$output" != *"Starting tutorial 08 stack with docker compose"* ]]
  [[ "$output" == *'"version_header_name": "x-api-version"'* ]]
  [[ "$output" == *'"x_version": null'* ]]
  [[ "$output" == *'"x_version": "v2"'* ]]
}

@test "tutorial09.sh --verify checks the operator console" {
  run "$TUTORIAL_DIR/tutorial09.sh" --setup
  [ "$status" -eq 0 ]

  run "$TUTORIAL_DIR/tutorial09.sh" --verify

  [ "$status" -eq 0 ]
  [[ "$output" != *"Starting tutorial 09 stack with docker compose"* ]]
  [[ "$output" == *'"service_name": "apim-simulator"'* ]]
  [[ "$output" == *'"status_code": 200'* ]]
}

@test "tutorial10.sh --verify applies the VS Code policy example" {
  run "$TUTORIAL_DIR/tutorial10.sh" --setup
  [ "$status" -eq 0 ]

  run "$TUTORIAL_DIR/tutorial10.sh" --verify

  [ "$status" -eq 0 ]
  [[ "$output" != *"Starting tutorial 10 stack with docker compose"* ]]
  [[ "$output" == *"Verifying the authored policy and gateway response"* ]]
  [[ "$output" == *'"contains_vscode_header": true'* ]]
  [[ "$output" == *'"x_from_vscode": "true"'* ]]
}

@test "tutorial11.sh --verify exports simulator inventory" {
  run "$TUTORIAL_DIR/tutorial11.sh" --setup
  [ "$status" -eq 0 ]

  run "$TUTORIAL_DIR/tutorial11.sh" --verify

  [ "$status" -eq 0 ]
  [[ "$output" != *"Starting tutorial 11 stack with docker compose"* ]]
  [[ "$output" == *"Verifying exported inventory inputs"* ]]
  [[ "$output" == *'"api_version_sets": 1'* ]]
  [[ "$output" == *'"paths": ['* ]]
}
