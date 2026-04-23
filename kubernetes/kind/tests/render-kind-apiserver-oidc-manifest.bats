#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export HELPER="${REPO_ROOT}/terraform/kubernetes/scripts/render-kind-apiserver-oidc-manifest.py"
}

@test "render-kind-apiserver-oidc-manifest injects OIDC flags and gateway host alias" {
  source_manifest="${BATS_TEST_TMPDIR}/kube-apiserver.yaml"
  rendered_manifest="${BATS_TEST_TMPDIR}/kube-apiserver.rendered.yaml"

  cat >"${source_manifest}" <<'EOF'
apiVersion: v1
kind: Pod
spec:
  containers:
  - command:
    - kube-apiserver
    - --service-cluster-ip-range=10.96.0.0/12
  hostNetwork: true
EOF

  run uv run --isolated python \
    "${HELPER}" \
    "${source_manifest}" \
    "${rendered_manifest}" \
    "https://dex.example.test/dex" \
    "headlamp" \
    "/etc/kubernetes/pki/mkcert-rootCA.pem" \
    "dex.example.test" \
    "10.0.0.25"

  [ "${status}" -eq 0 ]
  run cat "${rendered_manifest}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"--oidc-issuer-url=https://dex.example.test/dex"* ]]
  [[ "${output}" == *"--oidc-client-id=headlamp"* ]]
  [[ "${output}" == *"--oidc-ca-file=/etc/kubernetes/pki/mkcert-rootCA.pem"* ]]
  [[ "${output}" == *'  - ip: "10.0.0.25"'* ]]
  [[ "${output}" == *"    - dex.example.test"* ]]
}

@test "render-kind-apiserver-oidc-manifest refuses unrelated existing host aliases" {
  source_manifest="${BATS_TEST_TMPDIR}/kube-apiserver.yaml"
  rendered_manifest="${BATS_TEST_TMPDIR}/kube-apiserver.rendered.yaml"

  cat >"${source_manifest}" <<'EOF'
apiVersion: v1
kind: Pod
spec:
  hostAliases:
  - ip: "10.0.0.10"
    hostnames:
    - other.example.test
  containers:
  - command:
    - kube-apiserver
    - --service-cluster-ip-range=10.96.0.0/12
  hostNetwork: true
EOF

  run uv run --isolated python \
    "${HELPER}" \
    "${source_manifest}" \
    "${rendered_manifest}" \
    "https://dex.example.test/dex" \
    "headlamp" \
    "/etc/kubernetes/pki/mkcert-rootCA.pem" \
    "dex.example.test" \
    "10.0.0.25"

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"unexpected existing kube-apiserver hostAliases block unrelated to dex.example.test"* ]]
}
