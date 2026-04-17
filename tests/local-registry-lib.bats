#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export HTTP_FETCH_LIB="${REPO_ROOT}/scripts/lib/http-fetch.sh"
  export REGISTRY_LIB="${REPO_ROOT}/kubernetes/scripts/docker-local-registry-lib.sh"
}

@test "registry_cache_repo_and_tag normalizes image refs" {
  run bash -lc "source '${HTTP_FETCH_LIB}'; source '${REGISTRY_LIB}'; printf '%s\n' \"\$(registry_cache_repo_and_tag 'docker.io/library/nginx:1.2.3')\" \"\$(registry_cache_repo_and_tag 'quay.io/keycloak/keycloak:26.4.7')\""

  [ "${status}" -eq 0 ]
  [ "${output}" = "$(printf 'library/nginx\t1.2.3\nkeycloak/keycloak\t26.4.7')" ]
}

@test "registry_tag_exists checks cached registry tags via HTTP" {
  local stub_bin="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${stub_bin}"

  cat >"${stub_bin}/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"name":"library/nginx","tags":["1.2.3","latest"]}'
EOF
  chmod +x "${stub_bin}/curl"

  run bash -lc "export PATH='${stub_bin}:'\"\$PATH\"; source '${HTTP_FETCH_LIB}'; source '${REGISTRY_LIB}'; if registry_tag_exists '127.0.0.1:5002' 'library/nginx' '1.2.3'; then echo yes; else echo no; fi"

  [ "${status}" -eq 0 ]
  [ "${output}" = "yes" ]
}
