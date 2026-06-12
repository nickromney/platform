#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/kubernetes/slicer/scripts/exercise-k3s-oidc-recovery.sh"
  export SHARED_SCRIPT="${REPO_ROOT}/kubernetes/scripts/exercise-k3s-oidc-recovery.sh"
}

@test "slicer recovery wrapper delegates the shared k3s OIDC recovery harness" {
  run grep -Fn 'K3S_OIDC_RUNTIME="slicer"' "${SCRIPT}"
  [ "${status}" -eq 0 ]

  run grep -Fn 'K3S_OIDC_CONFIGURE_SCRIPT="${CONFIGURE_SCRIPT}"' "${SCRIPT}"
  [ "${status}" -eq 0 ]

  run grep -Fn '"${SHARED_SCRIPT}" "$@"' "${SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "slicer recovery wrapper supports machine-readable dry-run previews" {
  run env OIDC_RECOVERY_FORMAT=json "${SCRIPT}" --dry-run

  [ "${status}" -eq 0 ]
  json_output="${output}"

  run jq -r '[.ok, (.dry_run | tostring), .status_code, .status_group, .force_mode] | @tsv' <<<"${json_output}"

  [ "${status}" -eq 0 ]
  [ "${output}" = $'true\ttrue\tdry_run\tpreview\tk3s-restart' ]

  run jq -r '.summary' <<<"${json_output}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Slicer k3s OIDC restart path"* ]]
}
