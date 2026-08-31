#!/usr/bin/env bats

# The kind apply retries once on failures that a re-plan actually fixes. Two are
# known, and both are bootstrap ordering problems rather than real breakage:
#
#   1. CA mismatch: the kubeconfig on disk predates the current cluster.
#   2. Empty-kubeconfig fallback: locals.tf picks the provider's kubeconfig with
#      fileexists(), evaluated at PLAN time. `make reset` deletes the kubeconfig,
#      so the provider binds the committed empty fallback and dials localhost:80.
#      kind writes the real kubeconfig during apply, too late for the already
#      configured provider. Re-running re-plans, fileexists() is now true, and it
#      succeeds -- so without this the first apply after every reset fails.
#
# These tests run the Makefile's own retry expression against real failure text,
# so they check the regex behaves, not merely that it is present.

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
  export KIND_MAKEFILE="${REPO_ROOT}/kubernetes/kind/Makefile"
}

# Pull the retry condition's grep pattern straight out of the Makefile.
retry_pattern() {
  sed -n 's/.*grep -qiE "\([^"]*\)" "\$\$tg_apply_log".*/\1/p' "${KIND_MAKEFILE}" | head -n 1
}

matches_retry() {
  local text="$1" pattern
  pattern="$(retry_pattern)"
  [[ -n "${pattern}" ]] || return 2
  printf '%s\n' "${text}" | grep -qiE "${pattern}"
}

@test "the retry expression is an extended-regex alternation, not a single fixed string" {
  run retry_pattern
  [ "${status}" -eq 0 ]
  [[ -n "${output}" ]]
  [[ "${output}" == *"|"* ]]
}

@test "the empty-kubeconfig bootstrap failure is classified as retryable" {
  run matches_retry 'Error: Post "http://localhost/api/v1/namespaces": dial tcp [::1]:80: connect: connection refused'
  [ "${status}" -eq 0 ]
}

@test "the IPv4 loopback form of the same failure is classified as retryable" {
  run matches_retry 'Error: Get "http://localhost/api/v1/namespaces/gitea": dial tcp 127.0.0.1:80: connect: connection refused'
  [ "${status}" -eq 0 ]
}

@test "the pre-existing CA mismatch failure is still classified as retryable" {
  run matches_retry 'Error: Get "https://127.0.0.1:6443/api": x509: certificate signed by unknown authority'
  [ "${status}" -eq 0 ]
}

@test "an ordinary apply failure is not retried" {
  # A real error must still fail fast rather than burn a second full apply.
  run matches_retry 'Error: creating Deployment: admission webhook denied the request'
  [ "${status}" -ne 0 ]

  run matches_retry 'Error: Kubernetes cluster unreachable: context deadline exceeded'
  [ "${status}" -ne 0 ]
}
