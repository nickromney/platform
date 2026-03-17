#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    docker compose -f "${APP_DIR}/compose.yml" "$@"
    return
  fi

  if command -v podman-compose >/dev/null 2>&1; then
    podman-compose -f "${APP_DIR}/compose.yml" "$@"
    return
  fi

  echo "compose-smoke: docker compose or podman-compose is required" >&2
  exit 1
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

cleanup() {
  compose_cmd down --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

compose_cmd down --remove-orphans >/dev/null 2>&1 || true
compose_cmd up -d --build api-fastapi-container-app frontend-typescript-vite
compose_cmd up -d --build --no-deps frontend-react-jwt

wait_for_url "http://localhost:8090/api/v1/health" "Container App API"
wait_for_url "http://localhost:8003/" "TypeScript Vite frontend"
wait_for_url "http://localhost:3002/" "React JWT frontend"

curl -fsS "http://localhost:8003/" | grep -q "IPv4 Subnet Calculator"
curl -fsS "http://localhost:8003/runtime-config.js" | grep -q 'AUTH_METHOD: "none"'
curl -fsS "http://localhost:8003/runtime-config.js" | grep -q 'API_BASE_URL: "http://localhost:8090"'
curl -fsS "http://localhost:3002/" | grep -q "IPv4 Subnet Calculator"
curl -fsS "http://localhost:3002/runtime-config.js" | grep -q 'AUTH_METHOD: "jwt"'
curl -fsS "http://localhost:3002/runtime-config.js" | grep -q 'JWT_PASSWORD: "demo-password"'

echo "compose smoke passed for subnet-calculator"
