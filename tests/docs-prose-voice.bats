#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "candidate 10 docs avoid generic contrast prose" {
  local pattern='(\bnot just\b|\bmore than just\b|\bnot merely\b|\bnot only\b|\b[Bb]y contrast\b|\b[Ii]n contrast\b|—)'

  run rg -n --pcre2 "${pattern}" \
    "${REPO_ROOT}/docs/ddd/subnetcalc-analysis.md" \
    "${REPO_ROOT}/docs/plans/archive/guided-workflow-variant-presets-plan.md" \
    "${REPO_ROOT}/sites/docs/content/reference/contracts.mdx" \
    "${REPO_ROOT}/sites/docs/content/reference/makefiles.mdx" \
    "${REPO_ROOT}/sites/docs/content/reference/shell-scripts.mdx" \
    "${REPO_ROOT}/sites/docs/content/operations/health-and-urls.mdx" \
    "${REPO_ROOT}/sites/docs/content/journeys/kubernetes.mdx" \
    "${REPO_ROOT}/sites/docs/content/security/hubble.mdx" \
    "${REPO_ROOT}/sites/docs/content/security/kyverno.mdx"

  if [ "${status}" -ne 1 ]; then
    printf '%s\n' "${output}"
  fi
  [ "${status}" -eq 1 ]
}
