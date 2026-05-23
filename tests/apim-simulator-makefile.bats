#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export APIM_ROOT="${REPO_ROOT}/apps/apim-simulator"
}

@test "apim simulator make help exposes Go app workflow" {
  run make -C "${APIM_ROOT}" help

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"App:"* ]]
  [[ "${output}" == *"update"* ]]
  [[ "${output}" == *"No dependency locks are managed at this wrapper level"* ]]
}

@test "apim simulator update is a Go-only no-op" {
  run make -n -C "${APIM_ROOT}" update

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"apim-simulator: Go-only app; no package-manager locks to update"* ]]
}

@test "apim simulator app js-check uses Biome and Deno without npm manifests" {
  run make -C "${APIM_ROOT}" app-js-check

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"biome check internal/app/web/app.js internal/app/web/api-types.d.ts internal/app/web/index.html internal/app/web/style.css"* ]]
  [[ "${output}" == *"deno check --check-js internal/app/web/app.js"* ]]
  [ ! -e "${APIM_ROOT}/app/package.json" ]
  [ ! -e "${APIM_ROOT}/app/internal/app/web/package.json" ]
}
