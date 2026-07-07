#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/kubernetes/kind/scripts/dhi-creds-offline.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  export DOCKER_CONFIG="${BATS_TEST_TMPDIR}/docker"
  export PLATFORM_DOCKER_CREDS_FILE="${BATS_TEST_TMPDIR}/platform/docker-creds.json"
  export PLATFORM_DOCKER_CREDENTIAL_HELPER_BIN_DIR="${TEST_BIN}"
  mkdir -p "${TEST_BIN}" "${DOCKER_CONFIG}"
  export PATH="${TEST_BIN}:${PATH}"
}

install_fake_desktop_helper() {
  cat >"${TEST_BIN}/docker-credential-desktop" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "get" ]]; then
  server="$(cat)"
  case "${server}" in
    dhi.io|https://dhi.io|https://dhi.io/)
      printf '%s\n' '{"Username":"mirror-user","Secret":"mirror-token"}'
      exit 0
      ;;
  esac
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/docker-credential-desktop"
}

write_docker_config() {
  cat >"${DOCKER_CONFIG}/config.json" <<'EOF'
{
  "credsStore": "desktop",
  "auths": {
    "example.test": {}
  }
}
EOF
}

@test "dry-run previews migration without changing Docker config" {
  write_docker_config
  install_fake_desktop_helper

  run "${SCRIPT}" --dry-run

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"would migrate dhi.io Docker credentials to the platform file helper"* ]]
  [[ "${output}" == *"Would back up ${DOCKER_CONFIG}/config.json before setting credHelpers[\"dhi.io\"] = \"platform-file\""* ]]
  [ ! -f "${PLATFORM_DOCKER_CREDS_FILE}" ]
  [ "$(jq -r '.credHelpers["dhi.io"] // empty' "${DOCKER_CONFIG}/config.json")" = "" ]
}

@test "execute migrates desktop credential, installs helper symlink, backs up config, and sets credHelpers" {
  write_docker_config
  install_fake_desktop_helper

  run "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Stored dhi.io credentials in ${PLATFORM_DOCKER_CREDS_FILE}"* ]]
  [[ "${output}" == *"Changed: credHelpers[\"dhi.io\"] = \"platform-file\""* ]]
  [[ "${output}" == *"PATH check: ${TEST_BIN} is on PATH"* ]]
  [[ "${output}" == *"Revert: restore"* ]]

  [ -f "${TEST_BIN}/docker-credential-platform-file" ] && [ -x "${TEST_BIN}/docker-credential-platform-file" ]
  cmp -s "${TEST_BIN}/docker-credential-platform-file" "${REPO_ROOT}/kubernetes/scripts/docker-credential-platform-file.sh"
  [ "$(jq -r '.credHelpers["dhi.io"]' "${DOCKER_CONFIG}/config.json")" = "platform-file" ]
  [ "$(jq -r '.credsStore' "${DOCKER_CONFIG}/config.json")" = "desktop" ]
  [ "$(jq -r '."dhi.io".Username' "${PLATFORM_DOCKER_CREDS_FILE}")" = "mirror-user" ]
  [ "$(jq -r '."dhi.io".Secret' "${PLATFORM_DOCKER_CREDS_FILE}")" = "mirror-token" ]

  run bash -c "ls '${DOCKER_CONFIG}'/config.json.platform-file-creds.*.bak"
  [ "${status}" -eq 0 ]
}
