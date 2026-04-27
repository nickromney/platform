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

  run grep -n 'soft_only_stable_passes=0' "${GITOPS_FILE}"

  [ "${status}" -eq 0 ]

  run grep -n 'if \[\[ "\$\${#hard_pending_apps\[@\]}" -eq 0 && "\$\${#soft_pending_apps\[@\]}" -gt 0 \]\]' "${GITOPS_FILE}"

  [ "${status}" -eq 0 ]

  run grep -Fn 'soft_only_stable_passes=$((soft_only_stable_passes + 1))' "${GITOPS_FILE}"

  [ "${status}" -eq 0 ]

  run grep -n 'WARN repo-backed Argo CD applications were still waiting on parent health after refresh' "${GITOPS_FILE}"

  [ "${status}" -eq 0 ]
}

@test "gitops refresh allows Lima-length Argo comparison settling" {
  run grep -Fn 'end=$((SECONDS + 300))' "${GITOPS_FILE}"

  [ "${status}" -eq 0 ]
}

@test "gitops refresh soft-waits unknown sync when managed workloads are ready" {
  run grep -Fn 'if [[ "$sync_status" == "Unknown" && -z "$comparison_msg" ]] && managed_workloads_ready "$app"; then' "${GITOPS_FILE}"

  [ "${status}" -eq 0 ]
}
