#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "sentiment make help exposes the update workflow" {
  run make -C "${REPO_ROOT}/apps/sentiment" help

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"update"* ]]
}

@test "sentiment update documents that the default runtime has no Bun roots" {
  run make -n -C "${REPO_ROOT}/apps/sentiment" update

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"No dependency update required for the default Go sentiment runtime."* ]]
  [[ "${output}" != *"bun update"* ]]
}

@test "sentiment prereqs fails cleanly when the repo env file is missing" {
  missing_env="${BATS_TEST_TMPDIR}/missing.env"

  run env PLATFORM_ENV_FILE="${missing_env}" make -C "${REPO_ROOT}/apps/sentiment" prereqs

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Missing platform env file: ${missing_env}"* ]]
  [[ "${output}" != *"Unknown make goal '${missing_env}'"* ]]
}
