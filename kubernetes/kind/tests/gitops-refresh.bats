#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
  export GITOPS_REFRESH_SCRIPT="${REPO_ROOT}/terraform/kubernetes/scripts/refresh-argocd-gitops-repo-apps.sh"
  export GITOPS_FILE="${REPO_ROOT}/terraform/kubernetes/gitops.tf"
}

@test "gitops refresh treats managed workloads ready as a soft wait condition" {
  run grep -n 'if \[\[ "\$needs_refresh_reason" == "managed-workloads-ready" \]\]' "${GITOPS_REFRESH_SCRIPT}"

  [ "${status}" -eq 0 ]

  run grep -n 'soft_pending_apps+=("\$app:\$needs_refresh_reason")' "${GITOPS_REFRESH_SCRIPT}"

  [ "${status}" -eq 0 ]

  run grep -n 'hard_pending_apps+=("\$app:\$needs_refresh_reason")' "${GITOPS_REFRESH_SCRIPT}"

  [ "${status}" -eq 0 ]

  run grep -n 'soft_only_stable_passes=0' "${GITOPS_REFRESH_SCRIPT}"

  [ "${status}" -eq 0 ]

  run grep -n 'if \[\[ "\${#hard_pending_apps\[@\]}" -eq 0 && "\${#soft_pending_apps\[@\]}" -gt 0 \]\]' "${GITOPS_REFRESH_SCRIPT}"

  [ "${status}" -eq 0 ]

  run grep -Fn 'soft_only_stable_passes=$((soft_only_stable_passes + 1))' "${GITOPS_REFRESH_SCRIPT}"

  [ "${status}" -eq 0 ]

  run grep -n 'WARN repo-backed Argo CD applications were still waiting on parent health after refresh' "${GITOPS_REFRESH_SCRIPT}"

  [ "${status}" -eq 0 ]
}

@test "gitops refresh allows Lima-length Argo comparison settling" {
  run grep -Fn 'end=$((SECONDS + ROLLOUT_TIMEOUT_SECONDS))' "${GITOPS_REFRESH_SCRIPT}"

  [ "${status}" -eq 0 ]

  run grep -n 'ROLLOUT_TIMEOUT_SECONDS   = tostring(local.platform_wait_seconds.rollout_default)' "${GITOPS_FILE}"

  [ "${status}" -eq 0 ]

  # And that the scaled default is still the Lima-length 300s at scale 1.
  run grep -En 'rollout_default[[:space:]]*=[[:space:]]*ceil\(300 \* var\.platform_timeout_scale\)' \
    "${REPO_ROOT}/terraform/kubernetes/locals.tf"

  [ "${status}" -eq 0 ]
}

@test "gitops refresh soft-waits unknown sync when managed workloads are ready" {
  run grep -Fn 'if [[ "$sync_status" == "Unknown" && -z "$comparison_msg" ]] && managed_workloads_ready "$app"; then' "${GITOPS_REFRESH_SCRIPT}"

  [ "${status}" -eq 0 ]
}

@test "gitops refresh local-exec delegates to the extracted script" {
  run grep -F 'scripts/refresh-argocd-gitops-repo-apps.sh' "${GITOPS_FILE}"

  [ "${status}" -eq 0 ]

  run grep -E 'command[[:space:]]*=[[:space:]]*<<' "${GITOPS_FILE}"

  [ "${status}" -ne 0 ]
}
