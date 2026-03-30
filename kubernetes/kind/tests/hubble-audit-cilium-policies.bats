#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT_UNDER_TEST="${REPO_ROOT}/terraform/kubernetes/scripts/hubble-audit-cilium-policies.sh"
  export TEST_ROOT="${BATS_TEST_TMPDIR}/audit-forward"
  export SCRIPT_DIR="${TEST_ROOT}/terraform/kubernetes/scripts"
  export FORWARD_LOG="${BATS_TEST_TMPDIR}/forward.log"

  mkdir -p "${SCRIPT_DIR}"
  cp "${SCRIPT_UNDER_TEST}" "${SCRIPT_DIR}/hubble-audit-cilium-policies.sh"
  chmod +x "${SCRIPT_DIR}/hubble-audit-cilium-policies.sh"

  cat > "${SCRIPT_DIR}/hubble-observe-cilium-policies.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" > "${FORWARD_LOG}"
EOF
  chmod +x "${SCRIPT_DIR}/hubble-observe-cilium-policies.sh"
}

@test "hubble-audit-cilium-policies forwards new capture speed flags to observe" {
  run "${SCRIPT_DIR}/hubble-audit-cilium-policies.sh" \
    --capture-strategy adaptive \
    --sample-target 1000 \
    --sample-min 200 \
    --namespace-workers 2

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"renamed to hubble-observe-cilium-policies.sh; forwarding"* ]]

  run cat "${FORWARD_LOG}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"--capture-strategy adaptive"* ]]
  [[ "${output}" == *"--sample-target 1000"* ]]
  [[ "${output}" == *"--sample-min 200"* ]]
  [[ "${output}" == *"--namespace-workers 2"* ]]
}
