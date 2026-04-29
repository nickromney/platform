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
  [[ "${output}" == *"Update uv, npm, and Backstage Yarn locks"* ]]
}

@test "apim simulator update covers uv npm and backstage locks" {
  run make -n -C "${APIM_ROOT}" update

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"uv lock"* ]]
  [[ "${output}" == *"npm --prefix ui install --package-lock-only --ignore-scripts"* ]]
  [[ "${output}" == *"npm --prefix examples/todo-app/frontend-astro install --package-lock-only --ignore-scripts"* ]]
  [[ "${output}" == *"cd backstage/app && yarn install --mode=update-lockfile"* ]]
}
