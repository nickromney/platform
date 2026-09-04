#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
  export SCRIPT="${REPO_ROOT}/kubernetes/scripts/sync-local-image-cache.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  export LOG_FILE="${BATS_TEST_TMPDIR}/docker.log"
  export IMAGE_LIST_FILE="${BATS_TEST_TMPDIR}/images.txt"
  mkdir -p "${TEST_BIN}"
  export PATH="${TEST_BIN}:${PATH}"
}

@test "shared image cache sync skips cleanly when cache is unavailable in optional mode" {
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

  run env OPTIONAL=1 IMAGE_LIST_FILE="${IMAGE_LIST_FILE}" CACHE_PUSH_HOST="127.0.0.1:5002" "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"local cache not reachable"* ]]
}

@test "shared image cache sync normalizes docker hub library images before pushing to the cache" {
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

  run env IMAGE_LIST_FILE="${IMAGE_LIST_FILE}" CACHE_PUSH_HOST="127.0.0.1:5002" LOG_FILE="${LOG_FILE}" "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  grep -F 'tag python:3.13-slim 127.0.0.1:5002/library/python:3.13-slim' "${LOG_FILE}"
  grep -F 'tag quay.io/argoproj/argocd:v3.3.4 127.0.0.1:5002/argoproj/argocd:v3.3.4' "${LOG_FILE}"
}

@test "shared image cache reports both push attempts when an image cannot be mirrored" {
  cat >"${TEST_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${@: -1}" in
  http://127.0.0.1:5002/v2/) printf '{}' ;;
  http://127.0.0.1:5002/v2/*/tags/list) printf '{"tags":[]}' ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "${TEST_BIN}/curl"

  cat >"${TEST_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  image|tag) exit 0 ;;
  push)
    echo 'cannot push manifest index: registry returned 400' >&2
    exit 1
    ;;
  buildx)
    echo 'server gave HTTP response to HTTPS client' >&2
    exit 1
    ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "${TEST_BIN}/docker"

  printf 'quay.io/jetstack/cert-manager-controller:v1.21.1\n' >"${IMAGE_LIST_FILE}"

  run env IMAGE_LIST_FILE="${IMAGE_LIST_FILE}" CACHE_PUSH_HOST="127.0.0.1:5002" "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"could not cache 127.0.0.1:5002/jetstack/cert-manager-controller:v1.21.1"* ]]
  [[ "${output}" == *"docker push: cannot push manifest index: registry returned 400"* ]]
  [[ "${output}" == *"imagetools: server gave HTTP response to HTTPS client"* ]]
}
