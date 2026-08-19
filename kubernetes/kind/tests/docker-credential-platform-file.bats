#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
  export SCRIPT="${REPO_ROOT}/kubernetes/scripts/docker-credential-platform-file.sh"
  export PLATFORM_DOCKER_CREDS_FILE="${BATS_TEST_TMPDIR}/docker-creds.json"
}

@test "store writes a 0600 JSON credential file and get returns the credential" {
  run bash -c "printf '%s' '{\"ServerURL\":\"dhi.io\",\"Username\":\"mirror-user\",\"Secret\":\"mirror-token\"}' | '${SCRIPT}' store"

  [ "${status}" -eq 0 ]
  [ -f "${PLATFORM_DOCKER_CREDS_FILE}" ]
  # GNU first, BSD second -- and the order is the whole point. The reverse reads
  # like the `date -u -r ... || date -u -d ...` idiom used elsewhere here, but it
  # is not equivalent: GNU `stat -f` means --file-system, so it SUCCEEDS and
  # prints a filesystem dump instead of failing over. The `||` never fires and
  # the comparison is against that dump. BSD `stat -c` really does fail
  # ("illegal option -- c"), so this ordering fails over correctly on both.
  [ "$(stat -c '%a' "${PLATFORM_DOCKER_CREDS_FILE}" 2>/dev/null || stat -f '%Lp' "${PLATFORM_DOCKER_CREDS_FILE}")" = "600" ]

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
