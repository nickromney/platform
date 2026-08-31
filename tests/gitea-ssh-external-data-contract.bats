#!/usr/bin/env bats

# fetch-gitea-ssh-public-keys.sh is the program behind
# `data "external" "gitea_ssh_public_keys_cluster"` in gitops.tf. Terraform
# requires that program's stdout to be a single JSON object and nothing else.
# wait-for-gitea-ssh.sh, which it sources, runs `kubectl rollout status`; on
# success kubectl prints `deployment "gitea" successfully rolled out`. When that
# landed on stdout the data source failed the whole stage-900 apply with
# `Result Error: invalid character 'd' looking for beginning of value`.

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
  export WAIT_SCRIPT="${REPO_ROOT}/terraform/kubernetes/scripts/wait-for-gitea-ssh.sh"
  export FETCH_SCRIPT="${REPO_ROOT}/terraform/kubernetes/scripts/fetch-gitea-ssh-public-keys.sh"
}

@test "strict-mode rollout status keeps stdout clean for the external data source" {
  # The best-effort branch already discards it; the strict branch is the one the
  # data source takes (fetch-gitea-ssh-public-keys.sh sets MODE=strict).
  run grep -nE 'rollout status deployment/gitea --timeout="\$\{timeout\}s"$' "${WAIT_SCRIPT}"

  # No occurrence may end without a redirect away from stdout.
  [ "${status}" -ne 0 ]
}

@test "every rollout status call in wait-for-gitea-ssh redirects off stdout" {
  run bash -lc "grep -n 'rollout status' '${WAIT_SCRIPT}' | grep -vE '>&2|>/dev/null'"

  [ "${status}" -ne 0 ]
}

@test "the external data source program still sets strict mode" {
  # If this stops being strict the test above guards the wrong branch.
  run grep -q 'WAIT_FOR_GITEA_SSH_MODE=strict' "${FETCH_SCRIPT}"
  [ "${status}" -eq 0 ]
}
