#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "subnetcalc make help exposes the Go-only workflows" {
  run make -C "${REPO_ROOT}/apps/subnetcalc" help

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"app-go-test"* ]]
  [[ "${output}" == *"app-go-run-backend"* ]]
  [[ "${output}" == *"app-go-run-frontend"* ]]
  [[ "${output}" == *"compose-smoke"* ]]
  [[ "${output}" != *"frontend-react"* ]]
  [[ "${output}" != *"api-fastapi"* ]]
  [[ "${output}" != *"bruno"* ]]
}

@test "subnetcalc update is a no-op for the Go-only wrapper" {
  run make -n -C "${REPO_ROOT}/apps/subnetcalc" update

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Go-only app; no package-manager locks to update"* ]]
  [[ "${output}" != *"bun"* ]]
  [[ "${output}" != *"uv lock"* ]]
}

@test "subnetcalc compose stack uses only the Go runtime services" {
  run make -n -C "${REPO_ROOT}/apps/subnetcalc" up

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"make --no-print-directory -C app-go build-linux"* ]]
  [[ "${output}" == *"up -d --build subnetcalc-backend subnetcalc-frontend"* ]]

  run bash -lc "cd '${REPO_ROOT}' && \
    grep -qE '^  subnetcalc-backend:$' apps/subnetcalc/compose.yml && \
    grep -qE '^  subnetcalc-frontend:$' apps/subnetcalc/compose.yml && \
    ! grep -qE '^  (api-fastapi|frontend-react|frontend-typescript-vite|frontend-python-flask|frontend-html-static|keycloak|easyauth-router)' apps/subnetcalc/compose.yml"

  [ "${status}" -eq 0 ]
}

@test "subnetcalc compose teardown is not profile-gated" {
  run make -n -C "${REPO_ROOT}/apps/subnetcalc" down

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"down --remove-orphans"* ]]
  [[ "${output}" != *"--profile"* ]]
}
