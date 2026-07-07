#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "gateway URL diagnostics avoid unknown placeholders for missing status fields" {
  script="${REPO_ROOT}/terraform/kubernetes/scripts/check-gateway-urls.sh"

  run rg -n ':-unknown|desired=\$\{desired:-unknown\}|Programmed=\$\{programmed:-unknown\}|Certificate Ready=\$\{cert_ready:-unknown\}|Accepted=\$\{accepted:-unknown\}' "${script}"
  [ "${status}" -ne 0 ]

  run rg -n 'not reported' "${script}"
  [ "${status}" -eq 0 ]
}

@test "operator diagnostic fallbacks avoid unknown placeholders" {
  run rg -n ':-unknown|unknown-context|mode unknown|status unknown|echo "unknown"|printf "unknown\\n"|version: \$\{[^}]+:-unknown\}|MemTotal=\$\{[^}]+:-unknown\}|Skipping \$\$vm \(\$\{status:-unknown\}\)' \
    "${REPO_ROOT}/terraform/kubernetes/scripts/check-sso.sh" \
    "${REPO_ROOT}/terraform/kubernetes/scripts/check-security.sh" \
    "${REPO_ROOT}/terraform/kubernetes/scripts/check-cluster-health.sh" \
    "${REPO_ROOT}/terraform/kubernetes/scripts/hubble-observe-cilium-policies.sh" \
    "${REPO_ROOT}/kubernetes/kind/scripts/render-operator-overrides.sh" \
    "${REPO_ROOT}/kubernetes/lima/Makefile"

  [ "${status}" -ne 0 ]
}

@test "Hubble flow summaries avoid unknown placeholders for missing flow fields" {
  script="${REPO_ROOT}/terraform/kubernetes/scripts/hubble-summarise-flows.sh"

  run rg -n '"unknown"|"UNKNOWN"|else "unknown"|// "UNKNOWN"' "${script}"
  [ "${status}" -ne 0 ]

  run rg -n 'not reported|unclassified' "${script}"
  [ "${status}" -eq 0 ]
}

@test "OIDC recovery drill state defaults avoid unknown placeholders" {
  run rg -n 'PRE_STATE="unknown"|POST_STATE="unknown"' \
    "${REPO_ROOT}/terraform/kubernetes/scripts/exercise-kind-oidc-recovery.sh" \
    "${REPO_ROOT}/kubernetes/lima/scripts/exercise-k3s-oidc-recovery.sh"

  [ "${status}" -ne 0 ]

  run rg -n 'PRE_STATE="not_checked"|POST_STATE="not_checked"' \
    "${REPO_ROOT}/terraform/kubernetes/scripts/exercise-kind-oidc-recovery.sh" \
    "${REPO_ROOT}/kubernetes/lima/scripts/exercise-k3s-oidc-recovery.sh"

  [ "${status}" -eq 0 ]
}

@test "operator diagnostics avoid residual unknown placeholders in user-facing fallbacks" {
  run rg -n ':-unknown|<unknown>|echo unknown|echo "unknown"|printf "unknown\\n"|// "Unknown"' \
    "${REPO_ROOT}/kubernetes/kind/scripts/audit-bootstrap.sh" \
    "${REPO_ROOT}/tests/observability-log-quality.bats" \
    "${REPO_ROOT}/apps/sentiment/tests/test-tls.sh"

  [ "${status}" -ne 0 ]

  run rg -n 'not reported|no cipher reported' \
    "${REPO_ROOT}/kubernetes/kind/scripts/audit-bootstrap.sh" \
    "${REPO_ROOT}/tests/observability-log-quality.bats" \
    "${REPO_ROOT}/apps/sentiment/tests/test-tls.sh"

  [ "${status}" -eq 0 ]
}
