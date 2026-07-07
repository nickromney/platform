#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "local Kubernetes variants share the stage-first read-only helper surface" {
  expected="check-health check-security check-rbac check-gateway-urls show-urls check-sso check-sso-e2e"

  for variant in kind lima; do
    run bash -c 'make -pn -C "$1" __noop__ 2>/dev/null | awk -F " := " '"'"'/^VALID_STAGE_HELPERS :=/{ print $2; exit }'"'" \
      bash "${REPO_ROOT}/kubernetes/${variant}"

    [ "${status}" -eq 0 ]
    [ "${output}" = "${expected}" ]
  done
}

@test "local Kubernetes variants dispatch stage-first show-urls as a read-only helper" {
  for variant in kind lima; do
    run make -n -C "${REPO_ROOT}/kubernetes/${variant}" 900 show-urls DRY_RUN=1

    [ "${status}" -eq 0 ]
    [[ "${output}" == *'if [ -z "" ] && [ -z "show-urls" ]; then'* ]]
    [[ "${output}" == *"--show-urls"* ]]
    [[ "${output}" == *"--dry-run"* ]]
  done
}
