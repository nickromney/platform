#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export HELPER="${REPO_ROOT}/kubernetes/kind/scripts/rewrite-devcontainer-kubeconfig.py"
}

@test "rewrite-devcontainer-kubeconfig rewrites localhost server endpoints for host-socket devcontainers" {
  kubeconfig="${BATS_TEST_TMPDIR}/kubeconfig.yaml"

  cat >"${kubeconfig}" <<'EOF'
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: ZHVtbXk=
    server: https://127.0.0.1:6443
    tls-server-name: stale-host
  name: kind-kind-local
EOF

  run python3 "${HELPER}" "${kubeconfig}" host.docker.internal localhost

  [ "${status}" -eq 0 ]
  run cat "${kubeconfig}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"server: https://host.docker.internal:6443"* ]]
  [[ "${output}" == *"tls-server-name: localhost"* ]]
  [[ "${output}" != *"tls-server-name: stale-host"* ]]
}
