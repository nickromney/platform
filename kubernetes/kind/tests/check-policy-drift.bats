#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
  export SCRIPT="${REPO_ROOT}/terraform/kubernetes/scripts/check-policy-drift.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN}"
  export PATH="${TEST_BIN}:${PATH}"
  export STUB_DIR="${BATS_TEST_TMPDIR}/stub"
  mkdir -p "${STUB_DIR}"
}

# kubectl stub: "kustomize" prints RENDERED_FILE, "get" prints the live spec for
# the requested policy from LIVE_DIR (absent file means the policy is not
# applied), and "cluster-info" controls reachability.
write_kubectl_stub() {
  cat >"${TEST_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  cluster-info)
    if [[ "${CLUSTER_REACHABLE:-1}" == "1" ]]; then exit 0; fi
    exit 1
    ;;
  kustomize)
    cat "${RENDERED_FILE:?}"
    ;;
  get)
    name="${3:-}"
    if [[ -f "${LIVE_DIR:?}/${name}.json" ]]; then
      cat "${LIVE_DIR}/${name}.json"
    else
      echo "Error from server (NotFound)" >&2
      exit 1
    fi
    ;;
esac
EOF
  chmod +x "${TEST_BIN}/kubectl"
}

seed_rendered() {
  export RENDERED_FILE="${STUB_DIR}/rendered.yaml"
  cat >"${RENDERED_FILE}" <<'EOF'
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: demo-egress
spec:
  description: demo
  egress:
    - toFQDNs:
        - matchName: allowed.example.com
EOF
}

seed_live() {
  export LIVE_DIR="${STUB_DIR}/live"
  mkdir -p "${LIVE_DIR}"
  cat >"${LIVE_DIR}/demo-egress.json" <<EOF
{"spec": $1}
EOF
}

@test "reports no drift when live policy matches the rendered source" {
  write_kubectl_stub
  seed_rendered
  seed_live '{"description":"demo","egress":[{"toFQDNs":[{"matchName":"allowed.example.com"}]}]}'

  run "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"match the rendered source"* ]]
}

@test "detects a missing FQDN in the live policy" {
  # This is the gitea regression: the source allows the redirect target, the
  # live policy does not, and the Application still reads Synced from cache.
  write_kubectl_stub
  seed_rendered
  seed_live '{"description":"demo","egress":[{"toFQDNs":[]}]}'

  run "${SCRIPT}" --execute

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"demo-egress"* ]]
  [[ "${output}" == *"allowed.example.com"* ]]
}

@test "treats a policy that was never applied as drift" {
  write_kubectl_stub
  seed_rendered
  export LIVE_DIR="${STUB_DIR}/live"
  mkdir -p "${LIVE_DIR}"

  run "${SCRIPT}" --execute

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"demo-egress"* ]]
  [[ "${output}" == *"not present"* ]]
}

@test "accepts --policy-dir alongside the standard flags" {
  # Regression guard: the shell-cli no-args helper rejects any non-standard
  # flag, so a script with its own options must not route through it.
  write_kubectl_stub
  seed_rendered
  seed_live '{"description":"demo","egress":[{"toFQDNs":[{"matchName":"allowed.example.com"}]}]}'

  run "${SCRIPT}" --execute --policy-dir "${STUB_DIR}"

  [ "${status}" -eq 0 ]
  [[ "${output}" != *"unknown flag"* ]]
}

@test "skips cleanly when the cluster is unreachable" {
  write_kubectl_stub
  seed_rendered
  seed_live '{"description":"demo","egress":[{"toFQDNs":[{"matchName":"allowed.example.com"}]}]}'
  export CLUSTER_REACHABLE=0

  run "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"skip"* ]] || [[ "${output}" == *"unreachable"* ]]
}
