#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "subnet-calculator make help exposes the vendoring workflow" {
  run make -C "${REPO_ROOT}/apps/subnet-calculator" help

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"update"* ]]
  [[ "${output}" == *"vendor-apim-simulator"* ]]
}

@test "subnet-calculator vendor-apim-simulator delegates to the vendoring script" {
  run make -n -C "${REPO_ROOT}/apps/subnet-calculator" vendor-apim-simulator \
    APIM_SIMULATOR_SOURCE_REPO=/tmp/apim-simulator \
    APIM_SIMULATOR_SOURCE_REF=v0.4.0

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"\"./scripts/vendor-apim-simulator.sh\" --execute --source \"/tmp/apim-simulator\" --ref \"v0.4.0\""* ]]
}

@test "subnet-calculator update delegates to bun and uv roots" {
  run make -n -C "${REPO_ROOT}/apps/subnet-calculator" update

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"cd . && bun update --latest"* ]]
  [[ "${output}" == *"cd shared-frontend && bun update --latest"* ]]
  [[ "${output}" == *"make --no-print-directory -C frontend-react update"* ]]
  [[ "${output}" == *"make --no-print-directory -C frontend-typescript-vite update"* ]]
  [[ "${output}" == *"cd api-fastapi-azure-function && uv lock --upgrade && uv sync --extra dev"* ]]
  [[ "${output}" == *"cd api-fastapi-container-app && uv lock --upgrade && uv sync --extra dev"* ]]
  [[ "${output}" == *"make --no-print-directory -C frontend-html-static update"* ]]
  [[ "${output}" == *"make --no-print-directory -C frontend-python-flask update"* ]]
}
