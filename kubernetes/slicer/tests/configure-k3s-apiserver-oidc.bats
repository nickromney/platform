#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/kubernetes/slicer/scripts/configure-k3s-apiserver-oidc.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export MKCERT_CAROOT="${BATS_TEST_TMPDIR}/mkcert"
  export SLICER_URL="${BATS_TEST_TMPDIR}/slicer.sock"
  mkdir -p "${TEST_BIN}" "${HOME}" "${MKCERT_CAROOT}"
  export PATH="${TEST_BIN}:${PATH}"

  cat >"${TEST_BIN}/slicer" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/slicer"

  cat >"${TEST_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/curl"
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
  [[ "${output}" == *"skipping Slicer apiserver OIDC configuration"* ]]
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

@test "waits for the platform-gateway deployment and service endpoints" {
  run grep -Fn 'NGINX_GATEWAY_NAMESPACE="${NGINX_GATEWAY_NAMESPACE:-nginx-gateway}"' "${SCRIPT}"
  [ "${status}" -eq 0 ]

  run grep -Fn 'kubectl -n "$PLATFORM_GATEWAY_NAMESPACE" rollout status "deploy/${GATEWAY_DEPLOY_NAME}"' "${SCRIPT}"
  [ "${status}" -eq 0 ]

  run grep -Fn 'get endpoints "$PLATFORM_GATEWAY_INTERNAL_SVC"' "${SCRIPT}"
  [ "${status}" -eq 0 ]

  run grep -Fn 'request_gateway_reconcile' "${SCRIPT}"
  [ "${status}" -eq 0 ]

  run grep -Fn 'annotate gateway "$PLATFORM_GATEWAY_NAME"' "${SCRIPT}"
  [ "${status}" -eq 0 ]
}
