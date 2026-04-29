#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "subnetcalc make help exposes the compose workflows" {
  run make -C "${REPO_ROOT}/apps/subnetcalc" help

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"update"* ]]
  [[ "${output}" == *"start-compose-happy"* ]]
  [[ "${output}" == *"start-compose-backend-container"* ]]
  [[ "${output}" == *"start-compose-frontend-react"* ]]
  [[ "${output}" == *"start-compose-full"* ]]
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

@test "subnetcalc full compose teardown includes the profiled services" {
  run make -n -C "${REPO_ROOT}/apps/subnetcalc" test-bruno-compose-full OAUTH2_PROXY_COOKIE_SECRET=fake-secret

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"--profile function-family --profile oidc --profile mock-easyauth up -d --build"* ]]
  [[ "${output}" == *"--profile function-family --profile oidc --profile mock-easyauth down"* ]]

  run make -n -C "${REPO_ROOT}/apps/subnetcalc" down OAUTH2_PROXY_COOKIE_SECRET=fake-secret

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"--profile function-family --profile oidc --profile mock-easyauth down --remove-orphans"* ]]
}

@test "subnetcalc function-family compose path chooses the right function dockerfile for the host arch" {
  host_arch="$(uname -m)"

  run make -n -C "${REPO_ROOT}/apps/subnetcalc" test-bruno-compose-full OAUTH2_PROXY_COOKIE_SECRET=fake-secret

  [ "${status}" -eq 0 ]
  if [[ "${host_arch}" == "arm64" || "${host_arch}" == "aarch64" ]]; then
    [[ "${output}" == *"SUBNETCALC_AZURE_FUNCTION_DOCKERFILE=Dockerfile.uvicorn"* ]]
  else
    [[ "${output}" == *"SUBNETCALC_AZURE_FUNCTION_DOCKERFILE=Dockerfile"* ]]
  fi

  run bash -lc "cd '${REPO_ROOT}' && [ \"\$(rg -c 'dockerfile: \\$\\{SUBNETCALC_AZURE_FUNCTION_DOCKERFILE:-Dockerfile\\}' apps/subnetcalc/compose.yml)\" = '2' ]"

  [ "${status}" -eq 0 ]
}

@test "subnetcalc compose prereqs fails cleanly when the repo env file is missing" {
  missing_env="${BATS_TEST_TMPDIR}/missing.env"

  run env PLATFORM_ENV_FILE="${missing_env}" make -C "${REPO_ROOT}/apps/subnetcalc" prereqs

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Missing platform env file: ${missing_env}"* ]]
  [[ "${output}" != *"Unknown make goal '${missing_env}'"* ]]
}
