#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/kubernetes/scripts/k3s-registries-lib.sh"
}

@test "k3s registries renderer emits cache, upstream fallbacks, docker.io canonical endpoint, and optional gitea mirror" {
  image_list="${BATS_TEST_TMPDIR}/preload-images.txt"
  cat >"${image_list}" <<'EOF'
nginx:1.27
ghcr.io/acme/app:v1
localhost:5001/local/app:v2
# comment

EOF

  run bash -lc "source '${SCRIPT}'; k3s_registries_render --image-list '${image_list}' --cache-host 'host.lima.internal:5002' --cache-scheme 'http' --gitea-host 'localhost:30090' --gitea-scheme 'http'"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'"host.lima.internal:5002":'* ]]
  [[ "${output}" == *'"docker.io":'* ]]
  [[ "${output}" == *'https://registry-1.docker.io'* ]]
  [[ "${output}" == *'"ghcr.io":'* ]]
  [[ "${output}" == *'"localhost:5001":'* ]]
  [[ "${output}" == *'"localhost:30090":'* ]]
}

@test "k3s registries renderer emits no payload without cache or gitea mirrors" {
  image_list="${BATS_TEST_TMPDIR}/preload-images.txt"
  printf 'nginx:1.27\n' >"${image_list}"

  run bash -lc "source '${SCRIPT}'; k3s_registries_render --image-list '${image_list}'"

  [ "${status}" -eq 0 ]
  [[ -z "${output}" ]]
}
