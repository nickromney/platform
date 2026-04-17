#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export HTTP_FETCH_LIB="${REPO_ROOT}/scripts/lib/http-fetch.sh"
}

@test "http_cached_output reuses cached results" {
  local stub_bin="${BATS_TEST_TMPDIR}/bin"
  local cache_dir="${BATS_TEST_TMPDIR}/cache"
  local count_file="${BATS_TEST_TMPDIR}/curl-count"
  mkdir -p "${stub_bin}" "${cache_dir}"

  cat >"${stub_bin}/curl" <<'EOF'
#!/usr/bin/env bash
count=0
if [ -f "${HTTP_FETCH_TEST_COUNT_FILE}" ]; then
  count="$(cat "${HTTP_FETCH_TEST_COUNT_FILE}")"
fi
printf '%s\n' "$((count + 1))" >"${HTTP_FETCH_TEST_COUNT_FILE}"
printf '%s\n' '{"ok":true}'
EOF
  chmod +x "${stub_bin}/curl"

  run bash -lc "export PATH='${stub_bin}:'\"\$PATH\" HTTP_FETCH_CACHE_DIR='${cache_dir}' HTTP_FETCH_TEST_COUNT_FILE='${count_file}'; source '${HTTP_FETCH_LIB}'; fetch_json() { http_json_get 'https://example.test/data'; }; printf '%s\n--\n%s\n' \"\$(http_cached_output example data fetch_json)\" \"\$(http_cached_output example data fetch_json)\""

  [ "${status}" -eq 0 ]
  [ "$(cat "${count_file}")" = "1" ]
  [ "${output}" = "$(printf '{"ok":true}\n--\n{"ok":true}')" ]
}

@test "http_fetch applies timeout defaults" {
  local stub_bin="${BATS_TEST_TMPDIR}/bin"
  local args_file="${BATS_TEST_TMPDIR}/curl-args"
  mkdir -p "${stub_bin}"

  cat >"${stub_bin}/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >"${HTTP_FETCH_TEST_ARGS_FILE}"
EOF
  chmod +x "${stub_bin}/curl"

  run bash -lc "export PATH='${stub_bin}:'\"\$PATH\" HTTP_FETCH_TEST_ARGS_FILE='${args_file}' HTTP_FETCH_CONNECT_TIMEOUT_SECONDS=7 HTTP_FETCH_MAX_TIME_SECONDS=21; source '${HTTP_FETCH_LIB}'; http_fetch -fsSL https://example.test"

  [ "${status}" -eq 0 ]
  run cat "${args_file}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"--connect-timeout 7"* ]]
  [[ "${output}" == *"--max-time 21"* ]]
  [[ "${output}" == *"--retry 0"* ]]
}

@test "http_cache_dir_ensure returns the ensured cache directory path" {
  run bash -lc "source '${HTTP_FETCH_LIB}'; dir=\"\$(http_cache_dir_ensure)\"; printf '%s\n' \"\${dir}\"; test -d \"\${dir}\""

  [ "${status}" -eq 0 ]
  [ -n "${output}" ]
  [ -d "${output}" ]
}
