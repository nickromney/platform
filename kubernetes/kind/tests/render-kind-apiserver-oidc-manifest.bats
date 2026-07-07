#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export HELPER="${REPO_ROOT}/terraform/kubernetes/scripts/render-kind-apiserver-oidc-manifest.sh"
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

  run "${HELPER}" \
    "${source_manifest}" \
    "${rendered_manifest}" \
    "headlamp" \
    "/etc/kubernetes/pki/mkcert-rootCA.pem" \
    "10.0.0.25"

  [ "${status}" -eq 0 ]
  run cat "${rendered_manifest}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"--oidc-client-id=headlamp"* ]]
  [[ "${output}" == *"--oidc-username-claim=email"* ]]
  [[ "${output}" == *"--oidc-groups-claim=groups"* ]]
  [[ "${output}" == *"--oidc-ca-file=/etc/kubernetes/pki/mkcert-rootCA.pem"* ]]
  [[ "${output}" == *'  - ip: "10.0.0.25"'* ]]
}

@test "render-kind-apiserver-oidc-manifest accepts Keycloak issuer and host alias" {
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

  run "${HELPER}" \
    "${source_manifest}" \
    "${rendered_manifest}" \
    "https://keycloak.example.test/realms/platform" \
    "headlamp" \
    "/etc/kubernetes/pki/mkcert-rootCA.pem" \
    "keycloak.example.test" \
    "10.0.0.25"

  [ "${status}" -eq 0 ]
  run cat "${rendered_manifest}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"--oidc-issuer-url=https://keycloak.example.test/realms/platform"* ]]
  [[ "${output}" == *"--oidc-groups-claim=groups"* ]]
  [[ "${output}" == *"    - keycloak.example.test"* ]]
}

  source_manifest="${BATS_TEST_TMPDIR}/kube-apiserver.yaml"
  rendered_manifest="${BATS_TEST_TMPDIR}/kube-apiserver.rendered.yaml"

  cat >"${source_manifest}" <<'EOF'
apiVersion: v1
kind: Pod
spec:
  hostAliases:
  - ip: "10.0.0.10"
    hostnames:
  containers:
  - command:
    - kube-apiserver
    - --service-cluster-ip-range=10.96.0.0/12
  hostNetwork: true
EOF

  run "${HELPER}" \
    "${source_manifest}" \
    "${rendered_manifest}" \
    "https://keycloak.example.test/realms/platform" \
    "headlamp" \
    "/etc/kubernetes/pki/mkcert-rootCA.pem" \
    "keycloak.example.test" \
    "10.0.0.25"

  [ "${status}" -eq 0 ]
  run cat "${rendered_manifest}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'  - ip: "10.0.0.25"'* ]]
  [[ "${output}" == *"    - keycloak.example.test"* ]]
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

  run "${HELPER}" \
    "${source_manifest}" \
    "${rendered_manifest}" \
    "headlamp" \
    "/etc/kubernetes/pki/mkcert-rootCA.pem" \
    "10.0.0.25"

  [ "${status}" -eq 1 ]
}
