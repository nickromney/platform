#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export SCRIPT="${REPO_ROOT}/scripts/validate-kyverno-policies.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN}"
}

@test "static validation renders Kyverno overlays and executes kyverno tests" {
  policy_root="${BATS_TEST_TMPDIR}/kyverno"
  log_file="${BATS_TEST_TMPDIR}/static.log"

  mkdir -p "${policy_root}/shared"
  cat >"${policy_root}/kustomization.yaml" <<'EOF'
resources:
  - shared
EOF
  cat >"${policy_root}/shared/kustomization.yaml" <<'EOF'
resources:
  - policy.yaml
EOF
  cat >"${policy_root}/shared/policy.yaml" <<'EOF'
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: demo
spec:
  validationFailureAction: Audit
  rules: []
EOF
  cat >"${policy_root}/shared/kyverno-test.yaml" <<'EOF'
apiVersion: cli.kyverno.io/v1alpha1
kind: Test
metadata:
  name: demo
policies:
  - policy.yaml
resources: []
results: []
EOF

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

  cat >"${TEST_BIN}/kyverno" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >>"${log_file}"
EOF
  chmod +x "${TEST_BIN}/kyverno"

  run env \
    PATH="${TEST_BIN}:/usr/bin:/bin" \
    KYVERNO_POLICY_ROOT="${policy_root}" \
    KYVERNO_TEST_ROOT="${policy_root}" \
    KUBECTL_BIN=kubectl \
    KYVERNO_BIN=kyverno \
    /bin/bash "${SCRIPT}" --execute static

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"rendered 2 Kyverno kustomize overlay(s)"* ]]
  [[ "${output}" == *"executed 1 Kyverno test suite(s)"* ]]

  run cat "${log_file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"kustomize ${policy_root}"* ]]
  [[ "${output}" == *"kustomize ${policy_root}/shared"* ]]
  [[ "${output}" == *"test ${policy_root} --require-tests --remove-color"* ]]
}

@test "live validation renders the repo policies and applies them to the cluster" {
  policy_root="${BATS_TEST_TMPDIR}/kyverno"
  log_file="${BATS_TEST_TMPDIR}/live.log"

  mkdir -p "${policy_root}"
  cat >"${policy_root}/kustomization.yaml" <<'EOF'
resources: []
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
if [[ "\$1" == "kustomize" ]]; then
  printf '%s\n' 'apiVersion: kyverno.io/v1'
  printf '%s\n' 'kind: ClusterPolicy'
  printf '%s\n' 'metadata:'
  printf '%s\n' '  name: demo'
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/kubectl"

  cat >"${TEST_BIN}/kyverno" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >>"${log_file}"
EOF
  chmod +x "${TEST_BIN}/kyverno"

  run env \
    PATH="${TEST_BIN}:/usr/bin:/bin" \
    KYVERNO_POLICY_ROOT="${policy_root}" \
    KUBECTL_BIN=kubectl \
    KYVERNO_BIN=kyverno \
    KUBECONFIG="${BATS_TEST_TMPDIR}/config" \
    /bin/bash "${SCRIPT}" --execute live

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"OK   kyverno live policy validation"* ]]

  run cat "${log_file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"apply "* ]]
  [[ "${output}" == *"--cluster"* ]]
  [[ "${output}" == *"--policy-report"* ]]
  [[ "${output}" == *"--remove-color"* ]]
  [[ "${output}" == *"--kubeconfig "* ]]
}
