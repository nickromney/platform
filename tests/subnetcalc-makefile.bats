#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "subnet-calculator make help exposes the vendoring workflow" {
  run make -C "${REPO_ROOT}/apps/subnet-calculator" help

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"vendor-apim-simulator"* ]]
}

@test "subnet-calculator vendor-apim-simulator delegates to the vendoring script" {
  run make -n -C "${REPO_ROOT}/apps/subnet-calculator" vendor-apim-simulator \
    APIM_SIMULATOR_SOURCE_REPO=/tmp/apim-simulator \
    APIM_SIMULATOR_SOURCE_REF=v0.2.0

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"\"./scripts/vendor-apim-simulator.sh\" --execute --source \"/tmp/apim-simulator\" --ref \"v0.2.0\""* ]]
}
