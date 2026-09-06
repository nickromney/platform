#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
  export REPO_ROOT
}

@test "the Gitea wait spends real seconds, not one per unreachable probe" {
  # The budget is named in seconds. Counting iterations instead meant each
  # unreachable probe burned its curl timeouts, and a 600 budget waited close
  # to two hours before failing.
  run bash -c "
    set -euo pipefail
    source '${REPO_ROOT}/terraform/kubernetes/scripts/gitea-local-access.sh'
    gitea_wait_http_code() { sleep 1; echo 000; }
    export GITEA_HTTP_BASE=http://gitea.invalid
    start=\$SECONDS
    gitea_wait_until_reachable 3 && echo UNEXPECTED_SUCCESS
    echo \"elapsed=\$((SECONDS - start))\"
  "

  [ "${status}" -eq 0 ]
  elapsed="$(sed -n 's/^elapsed=//p' <<<"${output}")"
  [ "${elapsed}" -ge 3 ]
  [ "${elapsed}" -le 8 ]
  [[ "${output}" != *UNEXPECTED_SUCCESS* ]]
}

@test "the Gitea wait returns as soon as the API answers" {
  run bash -c "
    set -euo pipefail
    source '${REPO_ROOT}/terraform/kubernetes/scripts/gitea-local-access.sh'
    gitea_wait_http_code() { echo 200; }
    export GITEA_HTTP_BASE=http://gitea.invalid
    gitea_wait_until_reachable 30
  "

  [ "${status}" -eq 0 ]
}
