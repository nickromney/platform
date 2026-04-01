#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DOCKERFILE_PATH="${PLATFORM_DIR}/docker/host-gateway-proxy.Dockerfile"
# shellcheck source=/dev/null
source "${PLATFORM_DIR}/../../scripts/lib/shell-cli.sh"

COMMAND=""
CONTAINER_NAME="${CONTAINER_NAME:-slicer-platform-gateway-443}"
IMAGE_TAG="${IMAGE_TAG:-platform/slicer-gateway-proxy:dev}"
LISTEN_PORT="${LISTEN_PORT:-443}"
UPSTREAM_HOST="${UPSTREAM_HOST:-host.docker.internal}"
UPSTREAM_PORT="${UPSTREAM_PORT:-8443}"

usage() {
  cat <<EOF
Usage: host-gateway-proxy.sh [--action ensure|stop|status] [--dry-run] [--execute]

Manages the Slicer host gateway proxy container.

Positional compatibility:
  host-gateway-proxy.sh [ensure|stop|status]

$(shell_cli_standard_options)
EOF
}

positional=()
shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --action)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--action"
        exit 1
      }
      COMMAND="$2"
      shift 2
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        positional+=("$1")
        shift
      done
      ;;
    -*)
      shell_cli_unknown_flag "$(shell_cli_script_name)" "$1"
      exit 1
      ;;
    *)
      positional+=("$1")
      shift
      ;;
  esac
done

if [[ -z "${COMMAND}" ]]; then
  COMMAND="${positional[0]:-ensure}"
fi
if [[ "${#positional[@]}" -gt 1 ]]; then
  shell_cli_unexpected_arg "$(shell_cli_script_name)" "${positional[1]}"
  exit 1
fi

shell_cli_maybe_execute_or_preview_summary usage \
  "would ${COMMAND} the Slicer host gateway proxy container"

require_docker() {
  command -v docker >/dev/null 2>&1 || {
    echo "docker not found in PATH" >&2
    exit 1
  }
  docker info >/dev/null 2>&1 || {
    echo "docker daemon not reachable" >&2
    exit 1
  }
}

build_image() {
  docker build -f "${DOCKERFILE_PATH}" -t "${IMAGE_TAG}" "${PLATFORM_DIR}/docker" >/dev/null
}

container_exists() {
  docker ps -a --format '{{.Names}}' | grep -Fxq "${CONTAINER_NAME}"
}

container_running() {
  docker ps --format '{{.Names}}' | grep -Fxq "${CONTAINER_NAME}"
}

ensure_container() {
  if container_running; then
    echo "OK   host gateway proxy running (${CONTAINER_NAME} :${LISTEN_PORT} -> ${UPSTREAM_HOST}:${UPSTREAM_PORT})"
    return 0
  fi

  if container_exists; then
    docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
  fi

  build_image

  if ! docker run -d \
    --name "${CONTAINER_NAME}" \
    -p "${LISTEN_PORT}:${LISTEN_PORT}" \
    -e LISTEN_PORT="${LISTEN_PORT}" \
    -e UPSTREAM_HOST="${UPSTREAM_HOST}" \
    -e UPSTREAM_PORT="${UPSTREAM_PORT}" \
    "${IMAGE_TAG}" >/dev/null; then
    echo "failed to start ${CONTAINER_NAME}; host port ${LISTEN_PORT} may already be in use" >&2
    exit 1
  fi

  sleep 2
  echo "OK   started host gateway proxy (${CONTAINER_NAME} :${LISTEN_PORT} -> ${UPSTREAM_HOST}:${UPSTREAM_PORT})"
}

stop_container() {
  if container_exists; then
    docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
    echo "OK   stopped host gateway proxy (${CONTAINER_NAME})"
  else
    echo "OK   host gateway proxy not running"
  fi
}

print_status() {
  if container_running; then
    echo "RUNNING ${CONTAINER_NAME} :${LISTEN_PORT} -> ${UPSTREAM_HOST}:${UPSTREAM_PORT}"
  else
    echo "STOPPED ${CONTAINER_NAME}"
  fi
}

require_docker

case "${COMMAND}" in
  ensure)
    ensure_container
    ;;
  stop)
    stop_container
    ;;
  status)
    print_status
    ;;
  *)
    usage
    exit 1
    ;;
esac
