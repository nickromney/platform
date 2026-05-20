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

Run the Go-only subnetcalc compose smoke test.

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

  if ! curl -fsS "${url}" | grep -q "${expected}"; then
    echo "compose-smoke: ${label} did not contain expected text: ${expected}" >&2
    return 1
  fi
}

cleanup() {
  compose_cmd down --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

shell_cli_handle_standard_no_args usage "would run the Go-only subnetcalc compose smoke test" "$@"

if [ -z "${SUBNETCALC_LOCAL_PLATFORM:-}" ]; then
  case "$(uname -m)" in
    arm64|aarch64)
      export SUBNETCALC_LOCAL_PLATFORM=linux/arm64
      export GOARCH=arm64
      ;;
    *)
      export SUBNETCALC_LOCAL_PLATFORM=linux/amd64
      export GOARCH=amd64
      ;;
  esac
fi

if [ "${SUBNETCALC_COMPOSE_SKIP_BUILD:-0}" != "1" ]; then
  (cd "${APP_DIR}/app" && make build-linux)
fi

compose_cmd down --remove-orphans >/dev/null 2>&1 || true
compose_cmd up -d --build subnetcalc-backend subnetcalc-frontend

wait_for_url "http://localhost:8090/api/v1/health" "backend health"
wait_for_url "http://localhost:8003/" "frontend"
assert_url_contains "http://localhost:8003/" "IPv4 Subnet Calculator" "frontend"

curl -fsS \
  -H "Content-Type: application/json" \
  -d '{"network":"192.168.1.0/24","mode":"Azure"}' \
  "http://localhost:8090/api/v1/ipv4/subnet-info" \
  | grep -q '"first_usable_ip":"192.168.1.4"'

echo "compose-smoke: Go backend/frontend stack passed"
