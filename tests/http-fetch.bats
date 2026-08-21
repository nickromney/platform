#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
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

@test "http_require_curl succeeds when curl exists and fails when it does not" {
  local shim="${BATS_TEST_TMPDIR}/bin-nocurl"
  local bash_bin
  bash_bin="$(command -v bash)"
  mkdir -p "${shim}"

  run bash -c "source '${HTTP_FETCH_LIB}'; http_require_curl"

  [ "${status}" -eq 0 ]

  # An empty PATH is the whole point, so bash itself must be invoked by
  # absolute path: `env PATH=... bash` would fail to find the interpreter and
  # exit 127, which would satisfy a naive nonzero assertion for the wrong
  # reason.
  run env PATH="${shim}" "${bash_bin}" -c "source '${HTTP_FETCH_LIB}'; http_require_curl"

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"curl not found"* ]]
}

@test "http_temp_file prefers the platform mktemp hook and reports success" {
  # The `&&` chain is load-bearing: with `;` the exit status of the whole
  # command is the last `test` alone, and a mutant that returns 1 from the
  # hook branch survives.
  run bash -c "source '${HTTP_FETCH_LIB}'; platform_mktemp_file() { printf -v \"\$1\" '%s' '/stub/mktemp-file'; }; out=''; http_temp_file out && test \"\${out}\" = '/stub/mktemp-file'"

  [ "${status}" -eq 0 ]
}

@test "http_temp_dir prefers the platform mktemp hook and reports success" {
  run bash -c "source '${HTTP_FETCH_LIB}'; platform_mktemp_dir() { printf -v \"\$1\" '%s' '/stub/mktemp-dir'; }; out=''; http_temp_dir out && test \"\${out}\" = '/stub/mktemp-dir'"

  [ "${status}" -eq 0 ]
}

@test "http_cache_dir_ensure ignores a configured-but-missing directory" {
  local bogus="${BATS_TEST_TMPDIR}/configured-but-absent"

  run bash -c "export HTTP_FETCH_CACHE_DIR='${bogus}'; source '${HTTP_FETCH_LIB}'; dir=\"\$(http_cache_dir_ensure)\" && test -d \"\${dir}\" && printf '%s\n' \"\${dir}\""

  [ "${status}" -eq 0 ]
  [ -d "${output}" ]
  [ "${output}" != "${bogus}" ]
}

@test "http_cache_dir_ensure reports success for a usable configured directory" {
  local cache_dir="${BATS_TEST_TMPDIR}/cache-valid"
  mkdir -p "${cache_dir}"

  run bash -c "export HTTP_FETCH_CACHE_DIR='${cache_dir}'; source '${HTTP_FETCH_LIB}'; out=''; http_cache_dir_ensure out && test \"\${out}\" = '${cache_dir}'"

  [ "${status}" -eq 0 ]
  [ "${output}" = "" ]

  run bash -c "export HTTP_FETCH_CACHE_DIR='${cache_dir}'; source '${HTTP_FETCH_LIB}'; dir=\"\$(http_cache_dir_ensure)\" && test \"\${dir}\" = '${cache_dir}'"

  [ "${status}" -eq 0 ]
}

@test "http_cached_output serves a primed cache entry without invoking the command" {
  local cache_dir="${BATS_TEST_TMPDIR}/cache-primed"
  # The cache dir must exist before the call: http_cache_dir_ensure silently
  # substitutes a fresh mktemp dir for a missing one, and the substitution
  # happens inside a subshell, so the primed file would never be consulted.
  mkdir -p "${cache_dir}"

  run bash -c "export HTTP_FETCH_CACHE_DIR='${cache_dir}'; source '${HTTP_FETCH_LIB}'; cf=\"\$(http_cache_file_for_key primed key)\"; printf 'cached-body' > \"\${cf}\"; http_cached_output primed key false"

  [ "${status}" -eq 0 ]
  [ "${output}" = "cached-body" ]
}

@test "http_cached_output fails without caching when the command fails" {
  local cache_dir="${BATS_TEST_TMPDIR}/cache-fail"
  mkdir -p "${cache_dir}"

  run bash -c "export HTTP_FETCH_CACHE_DIR='${cache_dir}'; source '${HTTP_FETCH_LIB}'; cf=\"\$(http_cache_file_for_key failing key)\" && ! http_cached_output failing key sh -c 'exit 3' && test ! -e \"\${cf}\""

  [ "${status}" -eq 0 ]
}

@test "http_status_code tolerates a bare URL under set -e" {
  local stub_bin="${BATS_TEST_TMPDIR}/bin-code"
  mkdir -p "${stub_bin}"

  printf '#!/usr/bin/env bash\nprintf 200\n' >"${stub_bin}/curl"
  chmod +x "${stub_bin}/curl"

  run env PATH="${stub_bin}:${PATH}" bash -ec "source '${HTTP_FETCH_LIB}'; code=\"\$(http_status_code https://example.test/ping)\"; test \"\${code}\" = 200"

  [ "${status}" -eq 0 ]
}

@test "http_status_code forwards extra flags after the URL under set -e" {
  local stub_bin="${BATS_TEST_TMPDIR}/bin-code-flags"
  local args_file="${BATS_TEST_TMPDIR}/curl-status-args"
  mkdir -p "${stub_bin}"

  cat >"${stub_bin}/curl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >'${args_file}'
printf 200
EOF
  chmod +x "${stub_bin}/curl"

  # The URL is positional and comes first; trailing arguments are extra curl
  # flags, and the wrapper reorders them so the URL stays last.
  run env PATH="${stub_bin}:${PATH}" bash -ec "source '${HTTP_FETCH_LIB}'; code=\"\$(http_status_code https://example.test/ping -I)\"; test \"\${code}\" = 200"

  [ "${status}" -eq 0 ]
  run cat "${args_file}"
  [[ "${output}" == *"-I https://example.test/ping"* ]]
}

# Accepted equivalent mutants (documented, not killed): both mutants of
# `shift || true` on http-fetch.sh:118 -- LOGICAL_AND_OR to `shift && true`
# and BOOLEAN_LITERAL to `shift || false`.
#
# The shift only fails when http_status_code is called with no arguments, and
# even then neither mutant is observable. Bash exempts the left-hand side of
# an `&&` list from errexit, so `shift && true` never aborts. And every real
# caller reads the code back with `code="$(http_status_code "${url}")"`, where
# bash does not apply errexit inside the command substitution either -- a
# no-arg call reaches curl identically under all three spellings.
#
# Killing them would take a statement-level no-arg call that no caller makes,
# asserting behaviour on a misuse. The finding worth keeping is the one the
# survivors point at: the guard covers a case real callers cannot reach.
