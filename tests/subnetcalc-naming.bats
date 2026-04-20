#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "tracked source uses subnetcalc rather than subnet-calculator" {
  run rg -n \
    --glob '!**/node_modules/**' \
    --glob '!**/.pytest_cache/**' \
    --glob '!**/.run/**' \
    --glob '!**/dist/**' \
    --glob '!**/test-results/**' \
    --glob '!**/bun.lock' \
    --glob '!**/package-lock.json' \
    --glob '!**/*.svg' \
    --glob '!tests/subnetcalc-naming.bats' \
    'subnet-calculator' \
    "${REPO_ROOT}"

  [ "${status}" -eq 1 ]
}
