#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/kubernetes/kind/scripts/annotate-apply-progress.sh"
  export FIXTURE="${REPO_ROOT}/kubernetes/kind/tests/fixtures/apply-progress.log"
}

@test "annotate-apply-progress emits known phases in order" {
  run "${SCRIPT}" --execute <"${FIXTURE}"

  [ "${status}" -eq 0 ]
  phases="$(printf '%s\n' "${output}" | grep '^PHASE ')"
  [ "${phases}" = $'PHASE 1/11: Prereqs and local image build (typically 1-2m)\nPHASE 2/11: OpenTofu apply planning (typically seconds)\nPHASE 3/11: Cilium install (typically <1m)\nPHASE 4/11: Argo CD install (typically <1m)\nPHASE 5/11: Gitea bootstrap (typically ~1m)\nPHASE 6/11: Policies repo sync (typically <1m)\nPHASE 7/11: App-of-apps sync (typically <1m)\nPHASE 8/11: Keycloak deployment (typically 1-2m)\nPHASE 9/11: cert-manager and gateway TLS wait (typically 1-3m)\nPHASE 10/11: API server OIDC and post-OIDC health (typically 1-3m)\nPHASE 11/11: Post-apply verification and E2E (typically ~1m)' ]
}

@test "annotate-apply-progress passes unmatched lines through untouched" {
  run "${SCRIPT}" --execute <<<"unmatched apply line"

  [ "${status}" -eq 0 ]
  [ "${output}" = "unmatched apply line" ]
}

@test "annotate-apply-progress can be disabled with KIND_APPLY_PROGRESS=0" {
  run env KIND_APPLY_PROGRESS=0 "${SCRIPT}" --execute <"${FIXTURE}"

  [ "${status}" -eq 0 ]
  [ "${output}" = "$(cat "${FIXTURE}")" ]
}

@test "annotate-apply-progress pipeline preserves successful wrapped command status" {
  run bash -c '
    set -o pipefail
    wrapped() {
      printf "%s\n" "module.stack.helm_release.argocd[0]: Creating..."
      return 0
    }
    set +e
    wrapped | "$1" --execute >/dev/null
    rc=${PIPESTATUS[0]}
    set -e
    exit "${rc}"
  ' _ "${SCRIPT}"

  [ "${status}" -eq 0 ]
}

@test "annotate-apply-progress pipeline preserves failing wrapped command status" {
  run bash -c '
    set -o pipefail
    wrapped() {
      printf "%s\n" "module.stack.helm_release.argocd[0]: Creating..."
      return 42
    }
    set +e
    wrapped | "$1" --execute >/dev/null
    rc=${PIPESTATUS[0]}
    set -e
    exit "${rc}"
  ' _ "${SCRIPT}"

  [ "${status}" -eq 42 ]
}
