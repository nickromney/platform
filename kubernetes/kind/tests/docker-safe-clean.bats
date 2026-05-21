#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/kubernetes/kind/scripts/docker-safe-clean.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  export DOCKER_LOG="${BATS_TEST_TMPDIR}/docker.log"
  mkdir -p "${TEST_BIN}"
  export PATH="${TEST_BIN}:${PATH}"
}

install_fake_docker() {
  cat >"${TEST_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${DOCKER_LOG}"

if [[ "${1:-}" == "info" ]]; then
  exit 0
fi

if [[ "${1:-}" == "system" && "${2:-}" == "df" ]]; then
  cat <<'OUT'
TYPE            TOTAL     ACTIVE    SIZE      RECLAIMABLE
Images          396       16        147.5GB   56.21GB (38%)
Containers      24        6         1.149GB   844.2MB (73%)
Local Volumes   4         3         24.69GB   0B (0%)
Build Cache     1437      0         89.56GB   9.984GB
OUT
  exit 0
fi

if [[ "${1:-}" == "ps" ]]; then
  if [[ "$*" == *"{{.ID}}	{{.Names}}"* ]]; then
    cat <<'OUT'
abc123	old-compose-1
kindcp	kind-local-control-plane
cache	platform-local-image-cache
OUT
    exit 0
  fi

  if [[ "$*" == *"{{.Names}}	{{.Image}}	{{.Status}}"* ]]; then
    cat <<'OUT'
kind-local-control-plane	kindest/node:v1.35.1	Exited (0) 2 hours ago
platform-local-image-cache	registry:2	Exited (0) 2 hours ago
old-compose-1	example:latest	Exited (0) 2 hours ago
OUT
    exit 0
  fi

  if [[ "$*" == *"{{.Image}}"* ]]; then
    cat <<'OUT'
kindest/node:v1.35.1
registry:2
example:latest
OUT
    exit 0
  fi
fi

if [[ "${1:-}" == "image" && "${2:-}" == "inspect" ]]; then
  case "${5:-}" in
    kindest/node:v1.35.1) echo "sha256:kindimg" ;;
    registry:2) echo "sha256:registryimg" ;;
    example:latest) echo "sha256:usedimg" ;;
    *) exit 1 ;;
  esac
  exit 0
fi

if [[ "${1:-}" == "image" && "${2:-}" == "ls" ]]; then
  cat <<'OUT'
kindimg	kindest/node:v1.35.1	989MB
registryimg	registry:2	26.7MB
usedimg	example:latest	12MB
platformimg	127.0.0.1:5002/platform/sentiment-api:latest	12MB
oldimg	old-tool:latest	3.1GB
oldimg	old-tool:v1	3.1GB
otherimg	other-tool:latest	2.4GB
dangling	<none>:<none>	100MB
OUT
  exit 0
fi

if [[ "${1:-}" == "builder" && "${2:-}" == "prune" ]]; then
  echo "builder pruned"
  exit 0
fi

if [[ "${1:-}" == "image" && "${2:-}" == "prune" ]]; then
  echo "images pruned"
  exit 0
fi

if [[ "${1:-}" == "rm" ]]; then
  echo "removed ${*:2}"
  exit 0
fi

if [[ "${1:-}" == "rmi" ]]; then
  echo "removed images ${*:3}"
  exit 0
fi

printf 'unexpected docker args: %s\n' "$*" >&2
exit 1
EOF
  chmod +x "${TEST_BIN}/docker"
}

@test "docker-safe-clean dry-run shows conservative cleanup without side effects" {
  install_fake_docker

  run "${SCRIPT}" --dry-run

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"INFO dry-run: would run conservative Docker cleanup"* ]]
  [[ "${output}" == *"docker builder prune -f --filter until=24h"* ]]
  [[ "${output}" == *"docker image prune -f"* ]]
  [[ "${output}" == *"old-tool:latest"* ]]
  [[ "${output}" == *"other-tool:latest"* ]]
  [[ "${output}" != *"kindimg	kindest/node:v1.35.1"* ]]
  [[ "${output}" != *"registryimg	registry:2"* ]]
  [[ "${output}" != *"platformimg	127.0.0.1:5002/platform/sentiment-api:latest"* ]]
  [[ "${output}" == *"old-compose-1"* ]]
  [[ "${output}" == *"skipped: docker system prune -a"* ]]
  [[ "${output}" == *"skipped: docker volume prune"* ]]

  run grep -E '^(builder prune|image prune|rmi|rm)' "${DOCKER_LOG}"
  [ "${status}" -eq 1 ]
}

@test "docker-safe-clean execute removes only stopped non-kind containers" {
  install_fake_docker

  run "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"builder pruned"* ]]
  [[ "${output}" == *"images pruned"* ]]
  [[ "${output}" == *"removed images oldimg otherimg"* ]]
  [[ "${output}" == *"removed abc123"* ]]
  [[ "${output}" != *"removed kindcp"* ]]
  [[ "${output}" != *"removed cache"* ]]

  run grep '^rm ' "${DOCKER_LOG}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "rm abc123" ]

  run grep '^rmi ' "${DOCKER_LOG}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "rmi -f oldimg otherimg" ]
}

@test "docker-safe-clean supports a custom builder-cache age gate" {
  install_fake_docker

  run "${SCRIPT}" --execute --builder-cache-until 168h

  [ "${status}" -eq 0 ]

  run grep '^builder prune' "${DOCKER_LOG}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "builder prune -f --filter until=168h" ]
}
