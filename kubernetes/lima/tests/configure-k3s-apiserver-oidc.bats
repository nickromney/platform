#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/kubernetes/lima/scripts/configure-k3s-apiserver-oidc.sh"
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
