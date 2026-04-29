#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/docs/tutorials/apim-get-started/tutorial01.sh"
  export TEST_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$TEST_BIN"
  export CALL_LOG="$BATS_TEST_TMPDIR/calls.log"
  export OPENAPI_SOURCE="$BATS_TEST_TMPDIR/mock-openapi.json"
  printf '{}\n' >"$OPENAPI_SOURCE"
  export APIM_BASE="http://localhost:18000"
  export APIM_TENANT_KEY="test-tenant-key"
  export APIM_API_ID="tutorial-api"
  export APIM_API_NAME="Tutorial API"
  export APIM_API_PATH="tutorial-api"
  export APIM_HEALTH_ATTEMPTS="1"
  export APIM_HEALTH_DELAY_SECONDS="0"

  cat >"$TEST_BIN/docker" <<'EOF'
#!/usr/bin/env bash
printf 'docker %s\n' "$*" >>"$CALL_LOG"
EOF
  chmod +x "$TEST_BIN/docker"

  cat >"$TEST_BIN/curl" <<'EOF'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >>"$CALL_LOG"
case "$*" in
  *"/apim/health"*)
    printf '{"status":"healthy"}\n'
    ;;
  *"/apim/management/apis/"*)
    printf '{"id":"tutorial-api","path":"tutorial-api","upstream_base_url":"http://mock-backend:8080/api","operations":[{"id":"health"},{"id":"echo"}]}\n'
    ;;
  *"/tutorial-api/health"*)
    printf '{"status":"ok","path":"/api/health"}\n'
    ;;
  *"/tutorial-api/echo"*)
    printf '{"ok":true,"method":"GET","path":"/api/echo","body":"","headers":{"host":"mock-backend:8080"}}\n'
    ;;
esac
EOF
  chmod +x "$TEST_BIN/curl"

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
    printf 'APIM_BASE_URL=%s\n' "${APIM_BASE_URL:-}" >>"$CALL_LOG"
    printf 'OPENAPI_SOURCE=%s\n' "${OPENAPI_SOURCE:-}" >>"$CALL_LOG"
    printf '{"api_id":"tutorial-api"}\n'
    exit 0
  fi
fi
printf 'APIM_BASE_URL=%s\n' "${APIM_BASE_URL:-}" >>"$CALL_LOG"
printf 'OPENAPI_SOURCE=%s\n' "${OPENAPI_SOURCE:-}" >>"$CALL_LOG"
printf '{"api_id":"tutorial-api"}\n'
EOF
  chmod +x "$TEST_BIN/uv"

  export PATH="$TEST_BIN:$PATH"
}

@test "tutorial01.sh imports the API" {
  run "$SCRIPT" --setup

  [ "$status" -eq 0 ]
  [[ "$output" == *"Starting tutorial 01 stack with docker compose"* ]]
  [[ "$output" == *"Compose files:"* ]]
  [[ "$output" == *"./compose.public.yml"* ]]
  [[ "$output" == *"Running:"* ]]
  [[ "$output" == *"up --build -d"* ]]
  [[ "$output" == *"Importing OpenAPI source into API 'tutorial-api'"* ]]
  [[ "$output" == *"Setup complete. Run ./docs/tutorials/apim-get-started/tutorial01.sh --verify"* ]]

  run cat "$CALL_LOG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"docker compose -f ${REPO_ROOT}/compose.yml -f ${REPO_ROOT}/compose.public.yml up --build -d"* ]]
  [[ "$output" == *"curl -fsS http://localhost:18000/apim/health"* ]]
  [[ "$output" == *"uv run --project ${REPO_ROOT} python ${REPO_ROOT}/scripts/import_openapi.py"* ]]
  [[ "$output" == *"APIM_BASE_URL=http://localhost:18000"* ]]
  [[ "$output" == *"OPENAPI_SOURCE=$OPENAPI_SOURCE"* ]]
}

@test "tutorial01.sh without arguments prints help" {
  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: ./docs/tutorials/apim-get-started/tutorial01.sh [--setup|--execute|--verify|--dry-run]"* ]]
  [[ "$output" == *"--setup, --execute"* ]]
  [[ "$output" == *"--verify"* ]]
  [[ "$output" == *"INFO dry-run:"* ]]
}

@test "tutorial01.sh --verify runs the tutorial curl checks" {
  run "$SCRIPT" --setup
  [ "$status" -eq 0 ]
  : >"$CALL_LOG"

  run "$SCRIPT" --verify

  [ "$status" -eq 0 ]
  [[ "$output" != *"Starting tutorial 01 stack with docker compose"* ]]
  [[ "$output" != *"Importing OpenAPI source into API 'tutorial-api'"* ]]
  [[ "$output" == *"Verifying imported API metadata"* ]]
  [[ "$output" == *"Verifying imported API routes"* ]]
  [[ "$output" == *'"operations": ['* ]]
  [[ "$output" == *'"path": "/api/health"'* ]]
  [[ "$output" == *'"path": "/api/echo"'* ]]

  run cat "$CALL_LOG"
  [ "$status" -eq 0 ]
  [[ "$output" != *"docker compose"* ]]
  [[ "$output" != *"${REPO_ROOT}/scripts/import_openapi.py"* ]]
  [[ "$output" == *"curl -fsS -H X-Apim-Tenant-Key: test-tenant-key http://localhost:18000/apim/management/apis/tutorial-api"* ]]
  [[ "$output" == *"curl -fsS http://localhost:18000/tutorial-api/health"* ]]
  [[ "$output" == *"curl -fsS http://localhost:18000/tutorial-api/echo"* ]]
}

@test "tutorial01.sh --verify suggests setup when state is missing" {
  cat >"$TEST_BIN/curl" <<'EOF'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >>"$CALL_LOG"
case "$*" in
  *"/apim/management/apis/"*)
    echo 'curl: (22) The requested URL returned error: 404' >&2
    exit 22
    ;;
  *)
    printf '{}\n'
    ;;
esac
EOF
  chmod +x "$TEST_BIN/curl"

  run "$SCRIPT" --verify

  [ "$status" -ne 0 ]
  [[ "$output" == *"Verification could not complete."* ]]
  [[ "$output" == *"./docs/tutorials/apim-get-started/tutorial01.sh --setup first."* ]]
}
