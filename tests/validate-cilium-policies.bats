#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export SCRIPT="${REPO_ROOT}/scripts/validate-cilium-policies.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN}"
}

@test "static validation renders policy manifests and kustomize overlays" {
  policy_root="${BATS_TEST_TMPDIR}/cilium"
  render_stub="${BATS_TEST_TMPDIR}/render.sh"
  log_file="${BATS_TEST_TMPDIR}/static.log"

  mkdir -p "${policy_root}/shared"
  cat >"${policy_root}/kustomization.yaml" <<'EOF'
resources:
  - shared
EOF
  cat >"${policy_root}/shared/kustomization.yaml" <<'EOF'
resources:
  - policy.yaml
  - cidr.yaml
EOF
  cat >"${policy_root}/shared/policy.yaml" <<'EOF'
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: allow-demo
spec:
  endpointSelector: {}
EOF
  cat >"${policy_root}/shared/cidr.yaml" <<'EOF'
apiVersion: cilium.io/v2
kind: CiliumCIDRGroup
metadata:
  name: approved-egress
spec:
  externalCIDRs:
    - 10.0.0.0/24
EOF

  cat >"${render_stub}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'render %s\n' "\$1" >>"${log_file}"
EOF
  chmod +x "${render_stub}"

  cat >"${TEST_BIN}/kubectl" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "kustomize" ]]; then
  printf 'kustomize %s\n' "\$2" >>"${log_file}"
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/kubectl"

  cat >"${TEST_BIN}/yq" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
file="${@: -1}"
sed -n 's/^kind:[[:space:]]*//p' "${file}" | head -n 1
EOF
  chmod +x "${TEST_BIN}/yq"

  cat >"${TEST_BIN}/jq" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/jq"

  run env \
    PATH="${TEST_BIN}:/usr/bin:/bin" \
    CILIUM_POLICY_ROOT="${policy_root}" \
    RENDER_CILIUM_POLICY_VALUES_SCRIPT="${render_stub}" \
    KUBECTL_BIN=kubectl \
    /bin/bash "${SCRIPT}" static

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated 1 Cilium policy manifest file(s)"* ]]
  [[ "${output}" == *"rendered 2 Cilium kustomize overlay(s)"* ]]

  run cat "${log_file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"render ${policy_root}/shared/policy.yaml"* ]]
  [[ "${output}" == *"kustomize ${policy_root}"* ]]
  [[ "${output}" == *"kustomize ${policy_root}/shared"* ]]
}

@test "live validation falls back to a containerized cilium-dbg runner" {
  variables_file="${BATS_TEST_TMPDIR}/variables.tf"
  log_file="${BATS_TEST_TMPDIR}/live.log"

  cat >"${variables_file}" <<'EOF'
variable "cilium_version" {
  default = "1.19.1"
}
EOF

  cat >"${TEST_BIN}/kubectl" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$1" == "config" && "\$2" == "view" && "\$3" == "--raw" ]]; then
  cat <<'KUBECONFIG'
apiVersion: v1
clusters:
- cluster:
    server: https://example.invalid
  name: demo
contexts:
- context:
    cluster: demo
    user: demo
  name: demo
current-context: demo
kind: Config
users:
- name: demo
  user:
    token: fake
KUBECONFIG
  exit 0
fi
if [[ "\$1" == "--kubeconfig" ]]; then
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/kubectl"

  cat >"${TEST_BIN}/docker" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$1" == "info" ]]; then
  exit 0
fi
printf '%s\n' "\$*" >>"${log_file}"
EOF
  chmod +x "${TEST_BIN}/docker"

  run env \
    PATH="${TEST_BIN}:/usr/bin:/bin" \
    KUBECTL_BIN=kubectl \
    CILIUM_IMAGE_VERSION_FILE="${variables_file}" \
    KUBECONFIG="${BATS_TEST_TMPDIR}/config" \
    /bin/bash "${SCRIPT}" live

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"quay.io/cilium/cilium:v1.19.1"* ]]
  [[ "${output}" == *"OK   cilium live policy validation"* ]]

  run cat "${log_file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"run --rm"* ]]
  [[ "${output}" == *"cilium-dbg preflight validate-cnp"* ]]
}

@test "live validation prefers an in-cluster cilium-dbg runner before docker" {
  log_file="${BATS_TEST_TMPDIR}/live-in-cluster.log"

  cat >"${TEST_BIN}/kubectl" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$1" == "config" && "\$2" == "view" && "\$3" == "--raw" ]]; then
  cat <<'KUBECONFIG'
apiVersion: v1
clusters:
- cluster:
    server: https://127.0.0.1:6443
  name: demo
contexts:
- context:
    cluster: demo
    user: demo
  name: demo
current-context: demo
kind: Config
users:
- name: demo
  user:
    token: fake
KUBECONFIG
  exit 0
fi
if [[ "\$1" == "--kubeconfig" && "\$3" == "cluster-info" ]]; then
  exit 0
fi
if [[ "\$1" == "--kubeconfig" && "\$5" == "get" && "\$6" == "pods" ]]; then
  printf '%s\n' cilium-abc123
  exit 0
fi
if [[ "\$1" == "--kubeconfig" && "\$5" == "exec" ]]; then
  printf '%s\n' "\$*" >>"${log_file}"
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/kubectl"

  cat >"${TEST_BIN}/docker" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >>"${log_file}"
exit 0
EOF
  chmod +x "${TEST_BIN}/docker"

  run env \
    PATH="${TEST_BIN}:/usr/bin:/bin" \
    KUBECTL_BIN=kubectl \
    KUBECONFIG="${BATS_TEST_TMPDIR}/config" \
    /bin/bash "${SCRIPT}" live

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"INFO using in-cluster cilium-abc123"* ]]
  [[ "${output}" == *"OK   cilium live policy validation"* ]]

  run cat "${log_file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"exec cilium-abc123 -- cilium-dbg preflight validate-cnp"* ]]
  [[ "${output}" != *"run --rm"* ]]
}
