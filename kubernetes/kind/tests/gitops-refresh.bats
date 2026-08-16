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
  # Asserts the intent, not a literal. This read `end=$((SECONDS + 300))` until
  # the wait was refactored behind local.platform_wait_seconds so
  # PLATFORM_TIMEOUT_SCALE could stretch it for slow hosts. The literal vanished,
  # the assertion kept looking for it, and the file sits outside CI_BATS_TESTS so
  # nothing reported it -- the same shape as the kind dry-run assertion in
  # section 19.3 of docs/plans/omarchy-portability-followups.md.
  run grep -Fn 'end=$((SECONDS + ${local.platform_wait_seconds.rollout_default}))' "${GITOPS_FILE}"

  [ "${status}" -eq 0 ]

  # And that the scaled default is still the Lima-length 300s at scale 1.
  run grep -En 'rollout_default[[:space:]]*=[[:space:]]*ceil\(300 \* var\.platform_timeout_scale\)' \
    "${REPO_ROOT}/terraform/kubernetes/locals.tf"

  [ "${status}" -eq 0 ]
}

@test "gitops refresh soft-waits unknown sync when managed workloads are ready" {
  run grep -Fn 'if [[ "$sync_status" == "Unknown" && -z "$comparison_msg" ]] && managed_workloads_ready "$app"; then' "${GITOPS_FILE}"

  [ "${status}" -eq 0 ]
}
