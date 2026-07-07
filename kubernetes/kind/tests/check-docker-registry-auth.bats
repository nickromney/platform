#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN}"
  export PATH="${TEST_BIN}:${PATH}"
  export SCRIPT="${REPO_ROOT}/kubernetes/kind/scripts/check-docker-registry-auth.sh"
}

@test "reports ok when the configured Docker credential helper has dhi.io credentials" {
  config_file="${BATS_TEST_TMPDIR}/config.json"
  cat >"${config_file}" <<'EOF'
{
  "credsStore": "desktop",
  "auths": {}
}
EOF

  cat >"${TEST_BIN}/docker-credential-desktop" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "list" ]]; then
  printf '%s\n' '{"https://dhi.io":"user"}'
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/docker-credential-desktop"

  run env DOCKER_CONFIG_PATH="${config_file}" "${SCRIPT}" --execute dhi.io "Docker Hardened Images (dhi.io)"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"OK   Docker Hardened Images (dhi.io) credentials found via docker-credential-desktop"* ]]
}

@test "prefers per-registry platform-file helper over global credsStore" {
  config_file="${BATS_TEST_TMPDIR}/config.json"
  export PLATFORM_DOCKER_CREDS_FILE="${BATS_TEST_TMPDIR}/platform-creds.json"
  ln -s "${REPO_ROOT}/kubernetes/scripts/docker-credential-platform-file.sh" "${TEST_BIN}/docker-credential-platform-file"
  cat >"${config_file}" <<'EOF'
{
  "credsStore": "desktop",
  "credHelpers": {
    "dhi.io": "platform-file"
  },
  "auths": {}
}
EOF

  cat >"${TEST_BIN}/docker-credential-desktop" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "list" ]]; then
  printf '%s\n' '{}'
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/docker-credential-desktop"

  run bash -c "printf '%s' '{\"ServerURL\":\"dhi.io\",\"Username\":\"mirror-user\",\"Secret\":\"mirror-token\"}' | '${TEST_BIN}/docker-credential-platform-file' store"
  [ "${status}" -eq 0 ]

  run env DOCKER_CONFIG_PATH="${config_file}" PLATFORM_DOCKER_CREDS_FILE="${PLATFORM_DOCKER_CREDS_FILE}" \
    "${SCRIPT}" --execute dhi.io "Docker Hardened Images (dhi.io)"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"OK   Docker Hardened Images (dhi.io) credentials found via docker-credential-platform-file"* ]]
}

@test "warns when dhi.io credentials are missing from the configured helper" {
  config_file="${BATS_TEST_TMPDIR}/config.json"
  cat >"${config_file}" <<'EOF'
{
  "credsStore": "desktop",
  "auths": {}
}
EOF

  cat >"${TEST_BIN}/docker-credential-desktop" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "list" ]]; then
  printf '%s\n' '{}'
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/docker-credential-desktop"

  run env DOCKER_CONFIG_PATH="${config_file}" "${SCRIPT}" --execute dhi.io "Docker Hardened Images (dhi.io)"

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"WARN Docker Hardened Images (dhi.io) credentials not found via docker-credential-desktop (run: docker login dhi.io)"* ]]
}

@test "warns without docker login hint when credential helper times out twice" {
  config_file="${BATS_TEST_TMPDIR}/config.json"
  cat >"${config_file}" <<'EOF'
{
  "credsStore": "desktop",
  "auths": {}
}
EOF

  cat >"${TEST_BIN}/docker-credential-desktop" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "list" ]]; then
  sleep 2
  printf '%s\n' '{"https://dhi.io":"user"}'
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/docker-credential-desktop"

  run env DOCKER_CONFIG_PATH="${config_file}" DOCKER_CREDENTIAL_HELPER_TIMEOUT_SECONDS=1 \
    "${SCRIPT}" --execute dhi.io "Docker Hardened Images (dhi.io)"

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"WARN Docker Hardened Images (dhi.io) credential helper docker-credential-desktop timed out after 1s (twice); the helper may be slow or hung; rerun, or increase DOCKER_CREDENTIAL_HELPER_TIMEOUT_SECONDS"* ]]
  [[ "${output}" != *"docker login"* ]]
}

@test "retries once when credential helper times out and then succeeds" {
  config_file="${BATS_TEST_TMPDIR}/config.json"
  state_file="${BATS_TEST_TMPDIR}/helper-state"
  cat >"${config_file}" <<'EOF'
{
  "credsStore": "desktop",
  "auths": {}
}
EOF

  cat >"${TEST_BIN}/docker-credential-desktop" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
state_file="${FAKE_HELPER_STATE_FILE:?}"
if [[ "${1:-}" == "list" ]]; then
  if [[ ! -f "${state_file}" ]]; then
    printf 'called\n' >"${state_file}"
    sleep 2
  fi
  printf '%s\n' '{"https://dhi.io":"user"}'
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/docker-credential-desktop"

  run env DOCKER_CONFIG_PATH="${config_file}" DOCKER_CREDENTIAL_HELPER_TIMEOUT_SECONDS=1 FAKE_HELPER_STATE_FILE="${state_file}" \
    "${SCRIPT}" --execute dhi.io "Docker Hardened Images (dhi.io)"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"OK   Docker Hardened Images (dhi.io) credentials found via docker-credential-desktop"* ]]
}

@test "missing credential helper entries still suggest docker login" {
  config_file="${BATS_TEST_TMPDIR}/config.json"
  cat >"${config_file}" <<'EOF'
{
  "credsStore": "desktop",
  "auths": {}
}
EOF

  cat >"${TEST_BIN}/docker-credential-desktop" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "list" ]]; then
  printf '%s\n' '{}'
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/docker-credential-desktop"

  run env DOCKER_CONFIG_PATH="${config_file}" "${SCRIPT}" --execute dhi.io "Docker Hardened Images (dhi.io)"

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"WARN Docker Hardened Images (dhi.io) credentials not found via docker-credential-desktop (run: docker login dhi.io)"* ]]
}
