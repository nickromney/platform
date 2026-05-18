#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${APP_DIR}/../.." && pwd)"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/compose-cli.sh"

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute]

Run the subnetcalc compose smoke matrix.

$(shell_cli_standard_options)
EOF
}

compose_cmd() {
  compose_cli -f "${APP_DIR}/compose.yml" "$@"
}

wait_for_url() {
  local url="$1"
  local label="$2"

  for _ in $(seq 1 60); do
    if curl -fsS "${url}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  echo "compose-smoke: timed out waiting for ${label} (${url})" >&2
  return 1
}

assert_url_contains() {
  local url="$1"
  local expected="$2"
  local label="$3"

  for _ in $(seq 1 30); do
    if curl -fsS "${url}" | grep -q "${expected}"; then
      return 0
    fi
    sleep 1
  done

  echo "compose-smoke: ${label} did not contain expected text: ${expected}" >&2
  return 1
}

assert_frontend() {
  local url="$1"
  local expected="$2"
  local label="$3"

  wait_for_url "${url}" "${label}"
  assert_url_contains "${url}" "${expected}" "${label}"
}

assert_post_status() {
  local url="$1"
  local expected_status="$2"
  local label="$3"
  local actual_status

  actual_status="$(
    curl -sS -o /dev/null -w "%{http_code}" \
      -H "Content-Type: application/json" \
      -d '{"address":"192.168.1.1"}' \
      "${url}"
  )"

  if [ "${actual_status}" != "${expected_status}" ]; then
    echo "compose-smoke: ${label} returned ${actual_status}, expected ${expected_status}" >&2
    return 1
  fi
}

cleanup() {
  compose_cmd --profile function-family --profile oidc --profile mock-easyauth down --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

shell_cli_handle_standard_no_args usage "would run the subnetcalc compose smoke workflow" "$@"

export OAUTH2_PROXY_COOKIE_SECRET="${OAUTH2_PROXY_COOKIE_SECRET:-dev-cookie-secret-32-bytes-minimum}"
export OAUTH2_PROXY_CLIENT_SECRET="${OAUTH2_PROXY_CLIENT_SECRET:-dev-oauth-secret}"
export STACK12_APIM_SUBSCRIPTION_KEY="${STACK12_APIM_SUBSCRIPTION_KEY:-dev-subscription-key}"
export STACK12_ADMIN_APIM_SUBSCRIPTION_KEY="${STACK12_ADMIN_APIM_SUBSCRIPTION_KEY:-dev-admin-subscription-key}"
if [ -z "${SUBNETCALC_LOCAL_PLATFORM:-}" ]; then
  case "$(uname -m)" in
    arm64|aarch64)
      export SUBNETCALC_LOCAL_PLATFORM=linux/arm64
      ;;
    *)
      export SUBNETCALC_LOCAL_PLATFORM=linux/amd64
      ;;
  esac
fi
case "${SUBNETCALC_LOCAL_PLATFORM}" in
  linux/arm64)
    export GOARCH=arm64
    ;;
  linux/amd64)
    export GOARCH=amd64
    ;;
  *)
    echo "compose-smoke: unsupported SUBNETCALC_LOCAL_PLATFORM=${SUBNETCALC_LOCAL_PLATFORM}" >&2
    exit 1
    ;;
esac

if [ "${SUBNETCALC_COMPOSE_SKIP_BUILD:-0}" != "1" ]; then
  (cd "${APP_DIR}/app-go" && make build-linux)
fi

compose_cmd --profile function-family down --remove-orphans >/dev/null 2>&1 || true

if [ "${SUBNETCALC_COMPOSE_SKIP_BUILD:-0}" = "1" ]; then
  echo "compose-smoke: using existing matrix images"
else
  echo "compose-smoke: prebuilding matrix images"
  compose_cmd build \
    subnetcalc-backend \
    subnetcalc-frontend \
    api-fastapi-container-app \
    frontend-html-static \
    frontend-python-flask-container-app \
    frontend-typescript-vite \
    frontend-react
  compose_cmd --profile function-family build \
    api-fastapi-azure-function \
    frontend-python-flask \
    frontend-typescript-vite-jwt \
    frontend-react-jwt \
    frontend-react-server-jwt \
    frontend-react-proxy
fi

run_api_conformance() {
  local backend_name="$1"
  local base_url="$2"
  local auth_mode="$3"

  echo "compose-smoke: API contract ${backend_name} (${auth_mode})"
  wait_for_url "${base_url}/api/v1/health" "${backend_name} backend"
  if [ "${auth_mode}" = "jwt" ]; then
    "${APP_DIR}/tests/conformance/subnetcalc_contract.py" \
      --base-url "${base_url}" \
      --jwt-username "demo@dev.test" \
      --jwt-password "demo-password"
  else
    "${APP_DIR}/tests/conformance/subnetcalc_contract.py" --base-url "${base_url}"
  fi
}

run_frontend_pair() {
  local backend_name="$1"
  local backend_service="$2"
  local backend_profile="$3"
  local backend_auth_mode="$4"
  local backend_external_base="$5"
  local backend_internal_root="$6"
  local backend_internal_api_base="$7"
  local frontend_name="$8"
  local frontend_service="$9"
  local frontend_profile="${10}"
  local frontend_url="${11}"
  local expected_text="${12}"
  local frontend_auth_mode="${13}"

  echo "compose-smoke: frontend ${frontend_name} -> backend ${backend_name} (${backend_auth_mode})"
  compose_cmd --profile function-family down --remove-orphans >/dev/null 2>&1 || true

  local -a env_args=(
    "SUBNETCALC_CONTAINER_AUTH_METHOD=none"
    "SUBNETCALC_FUNCTION_AUTH_METHOD=jwt"
    "SUBNETCALC_FRONTEND_AUTH_METHOD=${frontend_auth_mode}"
    "SUBNETCALC_FRONTEND_API_BROWSER_BASE_URL=${backend_external_base}"
    "SUBNETCALC_FRONTEND_API_INTERNAL_BASE_URL=${backend_internal_api_base}"
    "SUBNETCALC_FRONTEND_API_PROXY_UPSTREAM=${backend_internal_root}"
    "SUBNETCALC_GO_FRONTEND_BACKEND_URL=${backend_internal_root}"
    "SUBNETCALC_FRONTEND_STACK_NAME=${frontend_name} + ${backend_name}"
  )

  if [ "${backend_service}" = "api-fastapi-container-app" ]; then
    env_args+=("SUBNETCALC_CONTAINER_AUTH_METHOD=${backend_auth_mode}")
  fi
  if [ "${backend_service}" = "api-fastapi-azure-function" ]; then
    env_args+=("SUBNETCALC_FUNCTION_AUTH_METHOD=${backend_auth_mode}")
  fi
  if [ "${frontend_auth_mode}" = "jwt" ]; then
    env_args+=("SUBNETCALC_FRONTEND_JWT_USERNAME=demo@dev.test")
    env_args+=("SUBNETCALC_FRONTEND_JWT_PASSWORD=demo-password")
  else
    env_args+=("SUBNETCALC_FRONTEND_JWT_USERNAME=")
    env_args+=("SUBNETCALC_FRONTEND_JWT_PASSWORD=")
  fi

  local -a profile_args=()
  if [ -n "${backend_profile}" ]; then
    profile_args+=(--profile "${backend_profile}")
  fi
  if [ -n "${frontend_profile}" ] && [ "${frontend_profile}" != "${backend_profile}" ]; then
    profile_args+=(--profile "${frontend_profile}")
  fi

  (
    export "${env_args[@]}"
    compose_cmd "${profile_args[@]}" up -d --no-build "${backend_service}" "${frontend_service}"
  )

  wait_for_url "${backend_external_base}/api/v1/health" "${backend_name} backend"
  assert_frontend "${frontend_url}" "${expected_text}" "${frontend_name} frontend"
}

run_anonymous_backend_matrix() {
  local backend_name="$1"
  local backend_service="$2"
  local backend_profile="$3"
  local backend_external_base="$4"
  local backend_internal_root="$5"
  local backend_internal_api_base="$6"

  run_frontend_pair "${backend_name}" "${backend_service}" "${backend_profile}" "none" "${backend_external_base}" "${backend_internal_root}" "${backend_internal_api_base}" "go" "subnetcalc-frontend" "" "http://localhost:8003/" "IPv4 Subnet Calculator" "none"
  curl -fsS "http://localhost:8003/api/v1/health" | grep -q '"status":"healthy"'

  run_frontend_pair "${backend_name}" "${backend_service}" "${backend_profile}" "none" "${backend_external_base}" "${backend_internal_root}" "${backend_internal_api_base}" "static-html" "frontend-html-static" "" "http://localhost:8001/" "IPv4 Subnet Calculator" "none"
  curl -fsS "http://localhost:8001/api/v1/health" | grep -q '"status":"healthy"'

  run_frontend_pair "${backend_name}" "${backend_service}" "${backend_profile}" "none" "${backend_external_base}" "${backend_internal_root}" "${backend_internal_api_base}" "flask" "frontend-python-flask-container-app" "" "http://localhost:8002/" "IP Subnet Calculator" "none"

  run_frontend_pair "${backend_name}" "${backend_service}" "${backend_profile}" "none" "${backend_external_base}" "${backend_internal_root}" "${backend_internal_api_base}" "vite" "frontend-typescript-vite" "" "http://localhost:8003/" "IPv4 Subnet Calculator" "none"
  curl -fsS "http://localhost:8003/runtime-config.js" | grep -q "${backend_external_base}"

  run_frontend_pair "${backend_name}" "${backend_service}" "${backend_profile}" "none" "${backend_external_base}" "${backend_internal_root}" "${backend_internal_api_base}" "react" "frontend-react" "" "http://localhost:8004/" "IPv4 Subnet Calculator" "none"
  curl -fsS "http://localhost:8004/runtime-config.js" | grep -q "${backend_external_base}"
}

run_jwt_backend_matrix() {
  local backend_name="$1"
  local backend_service="$2"
  local backend_profile="$3"
  local backend_external_base="$4"
  local backend_internal_root="$5"
  local backend_internal_api_base="$6"

  run_frontend_pair "${backend_name}" "${backend_service}" "${backend_profile}" "jwt" "${backend_external_base}" "${backend_internal_root}" "${backend_internal_api_base}" "go-unauthenticated" "subnetcalc-frontend" "" "http://localhost:8003/" "IPv4 Subnet Calculator" "none"
  assert_post_status "http://localhost:8003/api/v1/ipv4/validate" "401" "go frontend without token against ${backend_name}"

  run_frontend_pair "${backend_name}" "${backend_service}" "${backend_profile}" "jwt" "${backend_external_base}" "${backend_internal_root}" "${backend_internal_api_base}" "static-html-unauthenticated" "frontend-html-static" "" "http://localhost:8001/" "IPv4 Subnet Calculator" "none"
  assert_post_status "http://localhost:8001/api/v1/ipv4/validate" "401" "static frontend without token against ${backend_name}"

  run_frontend_pair "${backend_name}" "${backend_service}" "${backend_profile}" "jwt" "${backend_external_base}" "${backend_internal_root}" "${backend_internal_api_base}" "flask-jwt" "frontend-python-flask-container-app" "" "http://localhost:8002/" "IP Subnet Calculator" "jwt"

  run_frontend_pair "${backend_name}" "${backend_service}" "${backend_profile}" "jwt" "${backend_external_base}" "${backend_internal_root}" "${backend_internal_api_base}" "vite-jwt" "frontend-typescript-vite-jwt" "function-family" "http://localhost:3001/" "IPv4 Subnet Calculator" "jwt"
  curl -fsS "http://localhost:3001/runtime-config.js" | grep -q "AUTH_METHOD.*jwt"

  run_frontend_pair "${backend_name}" "${backend_service}" "${backend_profile}" "jwt" "${backend_external_base}" "${backend_internal_root}" "${backend_internal_api_base}" "react-jwt" "frontend-react-jwt" "function-family" "http://localhost:3002/" "IPv4 Subnet Calculator" "jwt"
  curl -fsS "http://localhost:3002/runtime-config.js" | grep -q "AUTH_METHOD.*jwt"

  run_frontend_pair "${backend_name}" "${backend_service}" "${backend_profile}" "jwt" "${backend_external_base}" "${backend_internal_root}" "${backend_internal_api_base}" "react-server-jwt" "frontend-react-server-jwt" "function-family" "http://localhost:3004/" "IPv4 Subnet Calculator" "jwt"

  run_frontend_pair "${backend_name}" "${backend_service}" "${backend_profile}" "jwt" "${backend_external_base}" "${backend_internal_root}" "${backend_internal_api_base}" "react-proxy-jwt" "frontend-react-proxy" "function-family" "http://localhost:3005/" "IPv4 Subnet Calculator" "jwt"
  curl -fsS "http://localhost:3005/" | grep -q '"API_PROXY_ENABLED":"true"'
}

echo "compose-smoke: API backend matrix"
(
  export SUBNETCALC_CONTAINER_AUTH_METHOD=none SUBNETCALC_FUNCTION_AUTH_METHOD=jwt
  compose_cmd up -d --no-build subnetcalc-backend
)
run_api_conformance "go" "http://localhost:8090" "none"
compose_cmd --profile function-family down --remove-orphans >/dev/null 2>&1 || true

(
  export SUBNETCALC_CONTAINER_AUTH_METHOD=none SUBNETCALC_FUNCTION_AUTH_METHOD=jwt
  compose_cmd up -d --no-build api-fastapi-container-app
)
run_api_conformance "fastapi-container" "http://localhost:8090" "none"
compose_cmd --profile function-family down --remove-orphans >/dev/null 2>&1 || true

(
  export SUBNETCALC_CONTAINER_AUTH_METHOD=jwt SUBNETCALC_FUNCTION_AUTH_METHOD=jwt
  compose_cmd up -d --no-build api-fastapi-container-app
)
run_api_conformance "fastapi-container" "http://localhost:8090" "jwt"
compose_cmd --profile function-family down --remove-orphans >/dev/null 2>&1 || true

(
  export SUBNETCALC_FUNCTION_AUTH_METHOD=none
  compose_cmd --profile function-family up -d --no-build api-fastapi-azure-function
)
run_api_conformance "azure-function" "http://localhost:8080" "none"
compose_cmd --profile function-family down --remove-orphans >/dev/null 2>&1 || true

(
  export SUBNETCALC_FUNCTION_AUTH_METHOD=jwt
  compose_cmd --profile function-family up -d --no-build api-fastapi-azure-function
)
run_api_conformance "azure-function" "http://localhost:8080" "jwt"
compose_cmd --profile function-family down --remove-orphans >/dev/null 2>&1 || true

echo "compose-smoke: anonymous frontend x backend matrix"
run_anonymous_backend_matrix "go" "subnetcalc-backend" "" "http://localhost:8090" "http://subnetcalc-backend:8080" "http://subnetcalc-backend:8080/api/v1"
run_anonymous_backend_matrix "fastapi-container" "api-fastapi-container-app" "" "http://localhost:8090" "http://api-fastapi-container-app:8000" "http://api-fastapi-container-app:8000/api/v1"
run_anonymous_backend_matrix "azure-function" "api-fastapi-azure-function" "function-family" "http://localhost:8080" "http://api-fastapi-azure-function:8080" "http://api-fastapi-azure-function:8080/api/v1"

echo "compose-smoke: jwt-capable frontend x backend matrix"
run_jwt_backend_matrix "fastapi-container" "api-fastapi-container-app" "" "http://localhost:8090" "http://api-fastapi-container-app:8000" "http://api-fastapi-container-app:8000/api/v1"
run_jwt_backend_matrix "azure-function" "api-fastapi-azure-function" "function-family" "http://localhost:8080" "http://api-fastapi-azure-function:8080" "http://api-fastapi-azure-function:8080/api/v1"

echo "compose smoke matrix passed for subnetcalc"
