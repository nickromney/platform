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

@test "apim simulator frontend check uses Biome and Deno without npm UI manifests" {
  run make -C "${APIM_ROOT}" frontend-check

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"test -f ui/api-types.d.ts"* ]]
  [[ "${output}" == *"biome check ui/app.js ui/api-types.d.ts ui/index.html ui/styles.css"* ]]
  [[ "${output}" == *"deno check --check-js ui/app.js"* ]]
  [[ "${output}" == *"! test -f ui/package.json"* ]]
}
