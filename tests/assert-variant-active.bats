#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export SCRIPT="${REPO_ROOT}/kubernetes/scripts/assert-variant-active.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  export STATUS_STUB="${BATS_TEST_TMPDIR}/platform-status.sh"
  mkdir -p "${TEST_BIN}"
  export PATH="${TEST_BIN}:${PATH}"
}

@test "blocks checks when another variant owns the machine" {
  kubectl_log="${BATS_TEST_TMPDIR}/kubectl.log"

  cat >"${STATUS_STUB}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' '{"overall_state":"running","active_variant_path":"kubernetes/lima","variants":{"kind":{"path":"kubernetes/kind","state":"absent"},"lima":{"path":"kubernetes/lima","state":"running"},"slicer":{"path":"kubernetes/slicer","state":"absent"}}}'
EOF
  chmod +x "${STATUS_STUB}"

  cat >"${TEST_BIN}/kubectl" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'kubectl %s\n' "\$*" >>"${kubectl_log}"
exit 0
EOF
  chmod +x "${TEST_BIN}/kubectl"

  run env \
    PLATFORM_STATUS_SCRIPT="${STATUS_STUB}" \
    EXPECTED_VARIANT_PATH="kubernetes/kind" \
    KUBECONFIG_PATH="${BATS_TEST_TMPDIR}/kind-kind-local.yaml" \
    "${SCRIPT}" --execute

  [ "${status}" -eq 2 ]
  [[ "${output}" == *"BLOCKED"* ]]
  [[ "${output}" == *"currently owned by kubernetes/lima"* ]]
  [[ "${output}" == *"make -C kubernetes/lima stop-lima"* ]]
  [ ! -e "${kubectl_log}" ]
}

@test "blocks checks when the expected variant is not running" {
  kubectl_log="${BATS_TEST_TMPDIR}/kubectl.log"

  cat >"${STATUS_STUB}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' '{"overall_state":"idle","active_variant_path":null,"variants":{"kind":{"path":"kubernetes/kind","state":"absent"},"lima":{"path":"kubernetes/lima","state":"absent"},"slicer":{"path":"kubernetes/slicer","state":"absent"}}}'
EOF
  chmod +x "${STATUS_STUB}"

  cat >"${TEST_BIN}/kubectl" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'kubectl %s\n' "\$*" >>"${kubectl_log}"
exit 0
EOF
  chmod +x "${TEST_BIN}/kubectl"

  run env \
    PLATFORM_STATUS_SCRIPT="${STATUS_STUB}" \
    EXPECTED_VARIANT_PATH="kubernetes/kind" \
    KUBECONFIG_PATH="${BATS_TEST_TMPDIR}/kind-kind-local.yaml" \
    "${SCRIPT}" --execute

  [ "${status}" -eq 2 ]
  [[ "${output}" == *"BLOCKED"* ]]
  [[ "${output}" == *"kubernetes/kind is not running on this machine"* ]]
  [ ! -e "${kubectl_log}" ]
}

@test "blocks checks when the expected variant owns the machine but is not reachable" {
  kubeconfig_path="${BATS_TEST_TMPDIR}/kind-kind-local.yaml"
  : >"${kubeconfig_path}"

  cat >"${STATUS_STUB}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' '{"overall_state":"running","active_variant_path":"kubernetes/kind","variants":{"kind":{"path":"kubernetes/kind","state":"running"},"lima":{"path":"kubernetes/lima","state":"absent"},"slicer":{"path":"kubernetes/slicer","state":"absent"}}}'
EOF
  chmod +x "${STATUS_STUB}"

  cat >"${TEST_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 1
EOF
  chmod +x "${TEST_BIN}/kubectl"

  run env \
    PLATFORM_STATUS_SCRIPT="${STATUS_STUB}" \
    EXPECTED_VARIANT_PATH="kubernetes/kind" \
    KUBECONFIG_PATH="${kubeconfig_path}" \
    KUBECONFIG_CONTEXT="kind-kind-local" \
    "${SCRIPT}" --execute

  [ "${status}" -eq 2 ]
  [[ "${output}" == *"BLOCKED"* ]]
  [[ "${output}" == *"kubernetes/kind is not reachable via kubeconfig"* ]]
  [[ "${output}" == *"kind-kind-local"* ]]
}

@test "allows checks when the expected variant owns the machine and is reachable" {
  kubeconfig_path="${BATS_TEST_TMPDIR}/kind-kind-local.yaml"
  : >"${kubeconfig_path}"

  cat >"${STATUS_STUB}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' '{"overall_state":"running","active_variant_path":"kubernetes/kind","variants":{"kind":{"path":"kubernetes/kind","state":"running"},"lima":{"path":"kubernetes/lima","state":"absent"},"slicer":{"path":"kubernetes/slicer","state":"absent"}}}'
EOF
  chmod +x "${STATUS_STUB}"

  cat >"${TEST_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/kubectl"

  run env \
    PLATFORM_STATUS_SCRIPT="${STATUS_STUB}" \
    EXPECTED_VARIANT_PATH="kubernetes/kind" \
    KUBECONFIG_PATH="${kubeconfig_path}" \
    KUBECONFIG_CONTEXT="kind-kind-local" \
    "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"OK"* ]]
  [[ "${output}" == *"kubernetes/kind is the active variant on this machine"* ]]
  [[ "${output}" == *"Proceeding with checks."* ]]
}
