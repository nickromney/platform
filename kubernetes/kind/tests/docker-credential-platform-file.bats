#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/kubernetes/scripts/docker-credential-platform-file.sh"
  export PLATFORM_DOCKER_CREDS_FILE="${BATS_TEST_TMPDIR}/docker-creds.json"
}

@test "store writes a 0600 JSON credential file and get returns the credential" {
  run bash -c "printf '%s' '{\"ServerURL\":\"dhi.io\",\"Username\":\"mirror-user\",\"Secret\":\"mirror-token\"}' | '${SCRIPT}' store"

  [ "${status}" -eq 0 ]
  [ -f "${PLATFORM_DOCKER_CREDS_FILE}" ]
  [ "$(stat -f '%Lp' "${PLATFORM_DOCKER_CREDS_FILE}" 2>/dev/null || stat -c '%a' "${PLATFORM_DOCKER_CREDS_FILE}")" = "600" ]

  run bash -c "printf '%s' 'dhi.io' | '${SCRIPT}' get"

  [ "${status}" -eq 0 ]
  [ "$(printf '%s' "${output}" | jq -r '.Username')" = "mirror-user" ]
  [ "$(printf '%s' "${output}" | jq -r '.Secret')" = "mirror-token" ]
}

@test "get accepts https registry aliases for dhi.io" {
  run bash -c "printf '%s' '{\"ServerURL\":\"dhi.io\",\"Username\":\"mirror-user\",\"Secret\":\"mirror-token\"}' | '${SCRIPT}' store"
  [ "${status}" -eq 0 ]

  run bash -c "printf '%s' 'https://dhi.io/' | '${SCRIPT}' get"

  [ "${status}" -eq 0 ]
  [ "$(printf '%s' "${output}" | jq -r '.Username')" = "mirror-user" ]
  [ "$(printf '%s' "${output}" | jq -r '.Secret')" = "mirror-token" ]
}

@test "list returns docker credential-helper map of server to username" {
  run bash -c "printf '%s' '{\"ServerURL\":\"dhi.io\",\"Username\":\"mirror-user\",\"Secret\":\"mirror-token\"}' | '${SCRIPT}' store"
  [ "${status}" -eq 0 ]

  run "${SCRIPT}" list

  [ "${status}" -eq 0 ]
  [ "$(printf '%s' "${output}" | jq -r '."dhi.io"')" = "mirror-user" ]
}

@test "erase removes matching registry aliases" {
  run bash -c "printf '%s' '{\"ServerURL\":\"https://dhi.io/\",\"Username\":\"mirror-user\",\"Secret\":\"mirror-token\"}' | '${SCRIPT}' store"
  [ "${status}" -eq 0 ]

  run bash -c "printf '%s' 'dhi.io' | '${SCRIPT}' erase"
  [ "${status}" -eq 0 ]

  run "${SCRIPT}" list
  [ "${status}" -eq 0 ]
  [ "${output}" = "{}" ]

  run bash -c "printf '%s' 'dhi.io' | '${SCRIPT}' get"
  [ "${status}" -eq 1 ]
}
