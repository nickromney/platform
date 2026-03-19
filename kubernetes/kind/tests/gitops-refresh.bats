#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export GITOPS_FILE="${REPO_ROOT}/terraform/kubernetes/gitops.tf"
}

@test "gitops refresh treats managed workloads ready as a soft wait condition" {
  run grep -n 'if \[\[ "\$needs_refresh_reason" == "managed-workloads-ready" \]\]' "${GITOPS_FILE}"

  [ "${status}" -eq 0 ]

  run grep -n 'soft_pending_apps+=("\$app:\$needs_refresh_reason")' "${GITOPS_FILE}"

  [ "${status}" -eq 0 ]

  run grep -n 'hard_pending_apps+=("\$app:\$needs_refresh_reason")' "${GITOPS_FILE}"

  [ "${status}" -eq 0 ]

  run grep -n 'WARN repo-backed Argo CD applications were still waiting on parent health after refresh' "${GITOPS_FILE}"

  [ "${status}" -eq 0 ]
}
