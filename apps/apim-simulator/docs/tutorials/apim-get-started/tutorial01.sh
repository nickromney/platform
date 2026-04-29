#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=../../../scripts/stack-env.sh
source "$ROOT_DIR/scripts/stack-env.sh"
stack_env_init

DOCKER_BIN="${DOCKER_BIN:-docker}"
APIM_BASE="${APIM_BASE:-$APIM_BASE_URL}"
APIM_TENANT_KEY="${APIM_TENANT_KEY:-local-dev-tenant-key}"
OPENAPI_SOURCE="${OPENAPI_SOURCE:-$ROOT_DIR/examples/mock-backend/openapi.json}"
OPENAPI_SOURCE_DISPLAY="${OPENAPI_SOURCE_DISPLAY:-$(stack_env_display_path "$OPENAPI_SOURCE")}"
APIM_API_ID="${APIM_API_ID:-tutorial-api}"
APIM_API_NAME="${APIM_API_NAME:-Tutorial API}"
APIM_API_PATH="${APIM_API_PATH:-tutorial-api}"
APIM_HEALTH_ATTEMPTS="${APIM_HEALTH_ATTEMPTS:-30}"
APIM_HEALTH_DELAY_SECONDS="${APIM_HEALTH_DELAY_SECONDS:-1}"
UV_BIN="${UV_BIN:-uv}"
EXECUTE=0
VERIFY=0
DRY_RUN=0

if [[ -n "${STACK_INSTANCE_SUFFIX:-}" ]]; then
  COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-apim-simulator-tutorial-${STACK_INSTANCE_SUFFIX}}"
  export COMPOSE_PROJECT_NAME
fi

usage() {
  cat <<EOF
Usage: ./docs/tutorials/apim-get-started/tutorial01.sh [--setup|--execute|--verify|--dry-run]

Runs tutorial step 1 for the APIM simulator.

Flags:
  --setup, --execute   Start the local stack and import the tutorial API.
  --verify             Verify the existing tutorial state without restarting it.
  --dry-run           Show this help and preview the setup action without side effects.
  --help, -h           Show this help text.

Environment overrides:
  DOCKER_BIN                   Docker CLI binary. Default: $DOCKER_BIN
  APIM_BASE                    Gateway base URL. Default: $APIM_BASE
  APIM_TENANT_KEY              Management tenant key. Default: $APIM_TENANT_KEY
  OPENAPI_SOURCE               OpenAPI file path or URL. Default: $OPENAPI_SOURCE_DISPLAY
  APIM_API_ID                  API identifier to create. Default: $APIM_API_ID
  APIM_API_NAME                API display name. Default: $APIM_API_NAME
  APIM_API_PATH                Public API path. Default: $APIM_API_PATH
  APIM_HEALTH_ATTEMPTS         Health-check retry attempts. Default: $APIM_HEALTH_ATTEMPTS
  APIM_HEALTH_DELAY_SECONDS    Health-check retry delay. Default: $APIM_HEALTH_DELAY_SECONDS

Examples:
  ./docs/tutorials/apim-get-started/tutorial01.sh --setup
  ./docs/tutorials/apim-get-started/tutorial01.sh --verify
EOF
}

repo_python() {
  "$UV_BIN" run --project "$ROOT_DIR" python "$@"
}

wait_for_gateway() {
  local attempt

  for ((attempt = 1; attempt <= APIM_HEALTH_ATTEMPTS; attempt += 1)); do
    if curl -fsS "$APIM_BASE/apim/health" >/dev/null 2>&1; then
      return 0
    fi
    sleep "$APIM_HEALTH_DELAY_SECONDS"
  done

  echo "Gateway did not become healthy at $APIM_BASE/apim/health" >&2
  return 1
}

start_stack() {
  local compose_log
  local compose_file
  local -a compose_files
  compose_log="$(mktemp)"
  compose_files=(
    "$ROOT_DIR/compose.yml"
    "$ROOT_DIR/compose.public.yml"
  )
  trap 'rm -f "$compose_log"' RETURN

  echo "Compose files:"
  for compose_file in "${compose_files[@]}"; do
    echo "  - $(stack_env_display_path "$compose_file")"
  done
  echo "Running:"
  echo "  $DOCKER_BIN compose \\"
  for compose_file in "${compose_files[@]}"; do
    echo "    -f $(stack_env_display_path "$compose_file") \\"
  done
  echo "    up --build -d"

  if ! "$DOCKER_BIN" compose \
    -f "$ROOT_DIR/compose.yml" \
    -f "$ROOT_DIR/compose.public.yml" \
    up --build -d >"$compose_log" 2>&1; then
    echo "docker compose failed while starting the tutorial 01 stack:" >&2
    cat "$compose_log" >&2
    exit 1
  fi
}

verify_api_metadata() {
  local response

  echo '$ curl -sS -H "X-Apim-Tenant-Key: '"$APIM_TENANT_KEY"'" "'"$APIM_BASE"'/apim/management/apis/'"$APIM_API_ID"'"'
  response="$(curl -fsS -H "X-Apim-Tenant-Key: $APIM_TENANT_KEY" "$APIM_BASE/apim/management/apis/$APIM_API_ID")"

  ACTUAL_JSON="$response" EXPECTED_API_ID="$APIM_API_ID" EXPECTED_API_PATH="$APIM_API_PATH" repo_python - <<'PY'
import json
import os
import sys

data = json.loads(os.environ["ACTUAL_JSON"])
summary = {
    "id": data.get("id"),
    "operations": sorted(item.get("id") for item in data.get("operations", [])),
    "path": data.get("path"),
    "upstream_base_url": data.get("upstream_base_url"),
}
expected = {
    "id": os.environ["EXPECTED_API_ID"],
    "operations": ["echo", "health"],
    "path": os.environ["EXPECTED_API_PATH"],
    "upstream_base_url": "http://mock-backend:8080/api",
}
if summary != expected:
    print("Metadata verification failed.", file=sys.stderr)
    print(json.dumps({"expected": expected, "actual": summary}, indent=2, sort_keys=True), file=sys.stderr)
    sys.exit(1)
print(json.dumps(summary, indent=2, sort_keys=True))
PY
}

verify_health_route() {
  local response

  echo '$ curl -sS "'"$APIM_BASE"'/'"$APIM_API_PATH"'/health"'
  response="$(curl -fsS "$APIM_BASE/$APIM_API_PATH/health")"

  ACTUAL_JSON="$response" repo_python - <<'PY'
import json
import os
import sys

summary = json.loads(os.environ["ACTUAL_JSON"])
expected = {"path": "/api/health", "status": "ok"}
if summary != expected:
    print("Health route verification failed.", file=sys.stderr)
    print(json.dumps({"expected": expected, "actual": summary}, indent=2, sort_keys=True), file=sys.stderr)
    sys.exit(1)
print(json.dumps(summary, indent=2, sort_keys=True))
PY
}

verify_echo_route() {
  local response

  echo '$ curl -sS "'"$APIM_BASE"'/'"$APIM_API_PATH"'/echo"'
  response="$(curl -fsS "$APIM_BASE/$APIM_API_PATH/echo")"

  ACTUAL_JSON="$response" repo_python - <<'PY'
import json
import os
import sys

data = json.loads(os.environ["ACTUAL_JSON"])
summary = {
    "body": data.get("body"),
    "method": data.get("method"),
    "ok": data.get("ok"),
    "path": data.get("path"),
}
expected = {
    "body": "",
    "method": "GET",
    "ok": True,
    "path": "/api/echo",
}
if summary != expected:
    print("Echo route verification failed.", file=sys.stderr)
    print(json.dumps({"expected": expected, "actual": summary}, indent=2, sort_keys=True), file=sys.stderr)
    sys.exit(1)
print(json.dumps(summary, indent=2, sort_keys=True))
PY
}

verify_tutorial() {
  echo "Verifying imported API metadata"
  verify_api_metadata

  echo
  echo "Verifying imported API routes"
  verify_health_route
  echo
  verify_echo_route
  echo
}

run_verify_with_setup_hint() {
  local status

  set +e
  (
    set -e
    verify_tutorial
  )
  status=$?
  set -e

  if [[ "$status" -ne 0 ]]; then
    echo >&2
    echo "Verification could not complete. Ensure the relevant tutorial stack is running and run ./docs/tutorials/apim-get-started/tutorial01.sh --setup first." >&2
    exit "$status"
  fi
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
  run_verify_with_setup_hint
  exit 0
fi

echo "Starting tutorial 01 stack with docker compose"
start_stack

echo "Waiting for gateway health at $APIM_BASE/apim/health"
wait_for_gateway

echo "Importing OpenAPI source into API '$APIM_API_ID'"
APIM_BASE_URL="$APIM_BASE" \
APIM_TENANT_KEY="$APIM_TENANT_KEY" \
OPENAPI_SOURCE="$OPENAPI_SOURCE" \
APIM_API_ID="$APIM_API_ID" \
APIM_API_NAME="$APIM_API_NAME" \
APIM_API_PATH="$APIM_API_PATH" \
repo_python "$ROOT_DIR/scripts/import_openapi.py"
echo
echo "Setup complete. Run ./docs/tutorials/apim-get-started/tutorial01.sh --verify to validate the imported API."
