#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/kubernetes/lima/scripts/configure-k3s-apiserver-oidc.sh"
  export SHARED_SCRIPT="${REPO_ROOT}/kubernetes/scripts/configure-k3s-apiserver-oidc.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export MKCERT_CAROOT="${BATS_TEST_TMPDIR}/mkcert"
  mkdir -p "${TEST_BIN}" "${HOME}" "${MKCERT_CAROOT}"
  export PATH="${TEST_BIN}:${PATH}"

  cat >"${TEST_BIN}/limactl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/limactl"

  cat >"${TEST_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/curl"
}

@test "lima wrapper delegates shared OIDC workflow with Lima transport config" {
  run grep -Fn 'K3S_OIDC_RUNTIME="lima"' "${SCRIPT}"
  [ "${status}" -eq 0 ]

  run grep -Fn '"${SHARED_SCRIPT}" "$@"' "${SCRIPT}"
  [ "${status}" -eq 0 ]

  run grep -Fn 'gateway_data_plane_ready' "${SCRIPT}"
  [ "${status}" -eq 1 ]

  run grep -Fn 'oidc-issuer-url=' "${SCRIPT}"
  [ "${status}" -eq 1 ]
}

@test "shared OIDC workflow owns gateway readiness and config behavior" {
  run grep -Fn 'NGINX_GATEWAY_NAMESPACE="${NGINX_GATEWAY_NAMESPACE:-nginx-gateway}"' "${SHARED_SCRIPT}"
  [ "${status}" -eq 0 ]

  run grep -Fn 'kubectl -n "$PLATFORM_GATEWAY_NAMESPACE" rollout status "deploy/${GATEWAY_DEPLOY_NAME}"' "${SHARED_SCRIPT}"
  [ "${status}" -eq 0 ]

  run grep -Fn 'get endpoints "$PLATFORM_GATEWAY_INTERNAL_SVC"' "${SHARED_SCRIPT}"
  [ "${status}" -eq 0 ]

  run grep -Fn 'request_gateway_reconcile' "${SHARED_SCRIPT}"
  [ "${status}" -eq 0 ]

  run grep -Fn 'oidc-issuer-url=${OIDC_ISSUER_URL}' "${SHARED_SCRIPT}"
  [ "${status}" -eq 0 ]

  run grep -Fn "kubectl get --raw='/readyz'" "${SHARED_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "shared OIDC workflow exposes standard CLI without runtime env" {
  run "${SHARED_SCRIPT}" --dry-run
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"would configure the Lima k3s API server for OIDC-issued tokens"* ]]

  run "${SHARED_SCRIPT}" --shell-entrypoint-descriptor
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'"supports":["--help","--dry-run","--execute"]'* ]]
}

@test "skips cleanly when mkcert is unavailable" {
  cat >"${TEST_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/kubectl"

  run "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"skipping Lima apiserver OIDC configuration"* ]]
}

@test "fails when the gateway service clusterIP is unavailable" {
  cat >"${TEST_BIN}/mkcert" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-CAROOT" ]]; then
  printf '%s\n' "${MKCERT_CAROOT}"
fi
EOF
  chmod +x "${TEST_BIN}/mkcert"
  echo "test-ca" >"${MKCERT_CAROOT}/rootCA.pem"

  cat >"${TEST_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-n" && "${4:-}" == "svc" ]]; then
  exit 0
fi
exit 0
EOF
  chmod +x "${TEST_BIN}/kubectl"

  run "${SCRIPT}" --execute

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Could not determine clusterIP"* ]]
}
