#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TRIVY_CACHE_DIR="${TRIVY_CACHE_DIR:-${REPO_ROOT}/.run/trivy-cache}"
TRIVY_IMAGE="${TRIVY_IMAGE:-aquasec/trivy:0.69.3}"

mkdir -p "${TRIVY_CACHE_DIR}"

if command -v trivy >/dev/null 2>&1; then
  exec trivy --cache-dir "${TRIVY_CACHE_DIR}" "$@"
fi

command -v docker >/dev/null 2>&1 || {
  echo "trivy-run: neither trivy nor docker is available" >&2
  exit 1
}

docker_args=(
  run
  --rm
  -v "${TRIVY_CACHE_DIR}:/root/.cache/trivy"
  -v "${REPO_ROOT}:/workspace"
  -w /workspace
  -e TRIVY_CACHE_DIR=/root/.cache/trivy
)

if [[ -S /var/run/docker.sock ]]; then
  docker_args+=(
    -v /var/run/docker.sock:/var/run/docker.sock
    -e DOCKER_HOST=unix:///var/run/docker.sock
  )
fi

exec docker "${docker_args[@]}" "${TRIVY_IMAGE}" "$@"
