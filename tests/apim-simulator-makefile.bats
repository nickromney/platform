#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export APIM_ROOT="${REPO_ROOT}/apps/apim-simulator"
}

@test "apim simulator make help exposes update workflow" {
  run make -C "${APIM_ROOT}" help

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Code Quality and Tooling:"* ]]
  [[ "${output}" == *"update"* ]]
  [[ "${output}" == *"Update uv and Backstage Yarn locks"* ]]
}

@test "apim simulator update covers uv and backstage locks" {
  run make -n -C "${APIM_ROOT}" update

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"uv lock"* ]]
  [[ "${output}" == *"cd backstage/app && yarn install --mode=update-lockfile"* ]]
}
