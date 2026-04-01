#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../scripts/lib/shell-cli.sh"

fail() {
  echo "ensure-local-image-cache: $*" >&2
  exit 1
}

ok() {
  echo "OK   $*"
}

cache_push_host="${CACHE_PUSH_HOST:-127.0.0.1:5002}"
cache_container_name="${CACHE_CONTAINER_NAME:-platform-local-image-cache}"
cache_container_image="${CACHE_CONTAINER_IMAGE:-registry:2}"
port="${cache_push_host##*:}"

usage() {
  cat <<EOF
Usage: ensure-local-image-cache.sh [--dry-run] [--execute]

Ensures the local Docker registry cache container exists and is reachable.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage "would ensure the local image cache ${cache_container_name} is reachable on ${cache_push_host}" "$@"

command -v curl >/dev/null 2>&1 || fail "curl not found in PATH"
command -v docker >/dev/null 2>&1 || fail "docker not found in PATH"

if ! docker info >/dev/null 2>&1; then
  fail "docker daemon not reachable"
fi

if curl -fsS "http://${cache_push_host}/v2/" >/dev/null 2>&1; then
  ok "image cache available at http://${cache_push_host}/v2/"
  exit 0
fi

if lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1; then
  fail "port ${port} is already in use and is not responding as a registry cache at http://${cache_push_host}/v2/"
fi

docker rm -f "${cache_container_name}" >/dev/null 2>&1 || true
docker run -d \
  --name "${cache_container_name}" \
  --restart unless-stopped \
  -p "0.0.0.0:${port}:5000" \
  "${cache_container_image}" >/dev/null

for _ in $(seq 1 20); do
  if curl -fsS "http://${cache_push_host}/v2/" >/dev/null 2>&1; then
    ok "started image cache ${cache_container_name} on ${cache_push_host}"
    exit 0
  fi
  sleep 1
done

fail "timed out waiting for registry cache ${cache_container_name} at http://${cache_push_host}/v2/"
