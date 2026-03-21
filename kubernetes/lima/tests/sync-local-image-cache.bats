#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/kubernetes/lima/scripts/sync-local-image-cache.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  export LOG_FILE="${BATS_TEST_TMPDIR}/docker.log"
  export IMAGE_LIST_FILE="${BATS_TEST_TMPDIR}/images.txt"
  mkdir -p "${TEST_BIN}"
  export PATH="${TEST_BIN}:${PATH}"
}

@test "skips cleanly when cache is unavailable in optional mode" {
  cat >"${TEST_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 1
EOF
  chmod +x "${TEST_BIN}/curl"

  cat >"${TEST_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/docker"

  printf 'quay.io/argoproj/argocd:v3.3.4\n' >"${IMAGE_LIST_FILE}"

  run env OPTIONAL=1 IMAGE_LIST_FILE="${IMAGE_LIST_FILE}" CACHE_PUSH_HOST="127.0.0.1:5002" "${SCRIPT}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"local cache not reachable"* ]]
}

@test "normalizes docker hub library images before pushing to the cache" {
  cat >"${TEST_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
url="${@: -1}"
case "${url}" in
  http://127.0.0.1:5002/v2/)
    printf '{}'
    ;;
  http://127.0.0.1:5002/v2/*/tags/list)
    printf '{"tags":[]}'
    ;;
  *)
    exit 1
    ;;
esac
EOF
  chmod +x "${TEST_BIN}/curl"

  cat >"${TEST_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${LOG_FILE}"
case "${1:-}" in
  image)
    exit 0
    ;;
  tag|push)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF
  chmod +x "${TEST_BIN}/docker"

  printf 'python:3.13-slim\nquay.io/argoproj/argocd:v3.3.4\n' >"${IMAGE_LIST_FILE}"

  run env IMAGE_LIST_FILE="${IMAGE_LIST_FILE}" CACHE_PUSH_HOST="127.0.0.1:5002" LOG_FILE="${LOG_FILE}" "${SCRIPT}"

  [ "${status}" -eq 0 ]
  grep -F 'tag python:3.13-slim 127.0.0.1:5002/library/python:3.13-slim' "${LOG_FILE}"
  grep -F 'tag quay.io/argoproj/argocd:v3.3.4 127.0.0.1:5002/argoproj/argocd:v3.3.4' "${LOG_FILE}"
}
