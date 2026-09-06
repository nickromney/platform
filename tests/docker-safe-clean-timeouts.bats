#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
  export REPO_ROOT
}

@test "a Docker read that outruns its timeout degrades instead of aborting" {
  # print_docker_df already degraded; docker_read did not, so a slow daemon
  # returned 124 and set -e killed the whole preview. The shell audit runs
  # every entrypoint bare, so that failed lint as well.
  run bash -c "
    set -euo pipefail
    REPO_ROOT='${REPO_ROOT}'
    source '${REPO_ROOT}/scripts/lib/timeout.sh'
    DOCKER_READ_TIMEOUT=1
    run_with_timeout() { return 124; }
    $(sed -n '/^docker_read() {/,/^}/p' "${REPO_ROOT}/kubernetes/kind/scripts/docker-safe-clean.sh")
    docker_read image ls
    echo \"survived rc=\$?\"
  "

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"survived rc=0"* ]]
  [[ "${output}" == *"timed out"* ]]
}
