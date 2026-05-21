#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "subnetcalc make help exposes the Go-only workflows" {
  run make -C "${REPO_ROOT}/apps/subnetcalc" help

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"app-test"* ]]
  [[ "${output}" == *"app-run-backend"* ]]
  [[ "${output}" == *"app-run-frontend"* ]]
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

@test "subnetcalc direct compose stack uses only the Go runtime services" {
  run make -n -C "${REPO_ROOT}/apps/subnetcalc" up-direct

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"make --no-print-directory -C app build-linux"* ]]
  [[ "${output}" == *"up -d --build subnetcalc-backend subnetcalc-frontend"* ]]

  run bash -lc "cd '${REPO_ROOT}' && \
    grep -qE '^  subnetcalc-backend:$' apps/subnetcalc/compose.yml && \
    grep -qE '^  subnetcalc-frontend:$' apps/subnetcalc/compose.yml && \
    ! grep -qE '^  (api-fastapi|frontend-react|frontend-typescript-vite|frontend-python-flask|frontend-html-static|easyauth-router)' apps/subnetcalc/compose.yml"

  [ "${status}" -eq 0 ]
}

@test "subnetcalc wrapper defaults the platform env file when run from its own folder" {
  run make -pRrq -C "${REPO_ROOT}/apps/subnetcalc" -f Makefile -f /dev/stdin __platform_noop <<'MAKE'
.PHONY: __platform_noop
__platform_noop:
MAKE

  [ "${status}" -le 1 ]
  [[ "${output}" == *'PLATFORM_ENV_FILE = $(REPO_ROOT)/.env'* ]]

  run make -n -C "${REPO_ROOT}/apps/subnetcalc" up-direct

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"env_file=\"${REPO_ROOT}/.env\""* ]]
  [[ "${output}" != *'env_file=""'* ]]
}

@test "subnetcalc compose teardown is not profile-gated" {
  run make -n -C "${REPO_ROOT}/apps/subnetcalc" down

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"down --remove-orphans"* ]]
  [[ "${output}" != *"--profile"* ]]
}
