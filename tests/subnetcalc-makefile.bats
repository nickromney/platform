#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "subnetcalc make help exposes the vendoring workflow" {
  run make -C "${REPO_ROOT}/apps/subnetcalc" help

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"update"* ]]
  [[ "${output}" == *"vendor-apim-simulator"* ]]
  [[ "${output}" == *"start-compose-happy"* ]]
  [[ "${output}" == *"start-compose-backend-container"* ]]
  [[ "${output}" == *"start-compose-frontend-react"* ]]
  [[ "${output}" == *"start-compose-full"* ]]
}

@test "subnetcalc vendor-apim-simulator delegates to the vendoring script" {
  run make -n -C "${REPO_ROOT}/apps/subnetcalc" vendor-apim-simulator \
    APIM_SIMULATOR_SOURCE_REPO=/tmp/apim-simulator \
    APIM_SIMULATOR_SOURCE_REF=v0.4.0

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"\"./scripts/vendor-apim-simulator.sh\" --execute --source \"/tmp/apim-simulator\" --ref \"v0.4.0\""* ]]
}

@test "subnetcalc update delegates to bun and uv roots" {
  run make -n -C "${REPO_ROOT}/apps/subnetcalc" update

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

@test "subnetcalc happy path keeps the backend warm and swaps frontends without deps" {
  run make -n -C "${REPO_ROOT}/apps/subnetcalc" start-compose-happy

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"up -d api-fastapi-container-app"* ]]
  [[ "${output}" == *"up -d --no-deps frontend-typescript-vite"* ]]

  run make -n -C "${REPO_ROOT}/apps/subnetcalc" start-compose-frontend-react

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"up -d api-fastapi-container-app"* ]]
  [[ "${output}" == *"up -d --no-deps frontend-react"* ]]
}

@test "subnetcalc full compose topology is explicit and profile-gated" {
  run make -n -C "${REPO_ROOT}/apps/subnetcalc" start-compose-full

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"--profile function-family"* ]]
  [[ "${output}" == *"--profile oidc"* ]]
  [[ "${output}" == *"--profile mock-easyauth"* ]]
  [[ "${output}" == *"up -d"* ]]

  run bash -lc "cd '${REPO_ROOT}' && \
    grep -qE '^  api-fastapi-azure-function:$' apps/subnetcalc/compose.yml && \
    grep -A3 '^  api-fastapi-azure-function:$' apps/subnetcalc/compose.yml | grep -q 'function-family' && \
    grep -qE '^  keycloak:$' apps/subnetcalc/compose.yml && \
    grep -A3 '^  keycloak:$' apps/subnetcalc/compose.yml | grep -q 'oidc' && \
    grep -qE '^  easyauth-router:$' apps/subnetcalc/compose.yml && \
    grep -A3 '^  easyauth-router:$' apps/subnetcalc/compose.yml | grep -q 'mock-easyauth'"

  [ "${status}" -eq 0 ]
}
