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
