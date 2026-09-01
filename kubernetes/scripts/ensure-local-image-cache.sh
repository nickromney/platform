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

# A named volume rather than the anonymous one registry:2 declares. Anonymous
# volumes are opaque in `docker volume ls`, and whether `docker system prune
# --volumes` removes one depends on if the container happened to be running, so
# the cache could survive a clean that looked total. That is not hypothetical:
# it made a "from scratch" rebuild measure 13m36s when the real cold figure is
# 20m07s. A named volume makes the cache visible and deliberate to remove.
cache_volume_name="${CACHE_VOLUME_NAME:-platform-local-image-cache-data}"

# registry:2 warns on every start without this, and the warning is legitimate:
# the secret signs upload state, so it has to be stable across restarts or an
# in-flight layer upload breaks when the container recycles. Derived from the
# container name so it is deterministic rather than a checked-in credential;
# this registry is loopback-only and holds no secrets.
cache_http_secret="${CACHE_HTTP_SECRET:-$(printf '%s' "platform-image-cache-${cache_container_name}" | shasum -a 256 | cut -d' ' -f1)}"

# shellcheck disable=SC2329 # invoked by name through the shell_cli_* helpers
usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute]

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
docker volume create "${cache_volume_name}" >/dev/null 2>&1 || true

docker run -d \
  --name "${cache_container_name}" \
  --restart unless-stopped \
  -p "0.0.0.0:${port}:5000" \
  -v "${cache_volume_name}:/var/lib/registry" \
  -e "REGISTRY_HTTP_SECRET=${cache_http_secret}" \
  "${cache_container_image}" >/dev/null

for _ in $(seq 1 20); do
  if curl -fsS "http://${cache_push_host}/v2/" >/dev/null 2>&1; then
    ok "started image cache ${cache_container_name} on ${cache_push_host}"
    exit 0
  fi
  sleep 1
done

fail "timed out waiting for registry cache ${cache_container_name} at http://${cache_push_host}/v2/"
