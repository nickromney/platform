#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "--execute" ]]; then
  echo "usage: $0 --execute" >&2
  exit 2
fi

cleanup() {
  make -C "$(dirname "$0")/.." down >/dev/null 2>&1 || true
}
trap cleanup EXIT

make -C "$(dirname "$0")/.." up-direct

base_url="${APIM_DIRECT_URL:-http://localhost:8000}"
for _ in $(seq 1 30); do
  if curl -fsS "${base_url}/apim/health" >/dev/null; then
    break
  fi
  sleep 1
done

health="$(curl -fsS "${base_url}/apim/health")"
echo "${health}" | grep -q '"status":"healthy"'

echo_response="$(curl -fsS "${base_url}/api/echo")"
echo "${echo_response}" | grep -q '"ok":true'

summary="$(curl -fsS -H "X-Apim-Tenant-Key: local-dev-tenant-key" "${base_url}/apim/management/summary")"
echo "${summary}" | grep -q '"demo-api"'
