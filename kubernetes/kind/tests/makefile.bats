#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN}"
  export PATH="${TEST_BIN}:${PATH}"
}

@test "kind help documents the 900 stage ladder" {
  run make -C "${REPO_ROOT}/kubernetes/kind" help

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"900 - full stack + sso"* ]]
}

@test "stage monotonicity check passes for the current stage files" {
  run make -C "${REPO_ROOT}/kubernetes/kind" check-stage-monotonicity

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"OK   stage monotonicity"* ]]
}

@test "kind host port preflight passes when no listeners are present" {
  cat >"${TEST_BIN}/lsof" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 1
EOF
  chmod +x "${TEST_BIN}/lsof"

  run make -C "${REPO_ROOT}/kubernetes/kind" check-kind-host-ports STAGE=100

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"OK   kind host ports available:"* ]]
}

@test "kind host port preflight reports listener conflicts with overridden tfvars" {
  cat >"${TEST_BIN}/lsof" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *"-iTCP:4443"* ]]; then
  cat <<'OUT'
COMMAND     PID USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
com.docke 27719 nick  168u  IPv6 0xdeadbeef      0t0  TCP *:4443 (LISTEN)
OUT
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/lsof"

  cat >"${TEST_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "ps" ]]; then
  printf '%s\n' $'laemp-test-debian\t0.0.0.0:4443->443/tcp, [::]:4443->443/tcp'
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/docker"

  override_file="${BATS_TEST_TMPDIR}/kind-port-overrides.tfvars"
  cat >"${override_file}" <<'EOF'
gateway_https_host_port = 4443
EOF

  run env PLATFORM_TFVARS="${override_file}" make -C "${REPO_ROOT}/kubernetes/kind" check-kind-host-ports STAGE=100

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"FAIL gateway-https host port 127.0.0.1:4443 is already in use"* ]]
  [[ "${output}" == *"Planned mapping: gateway_https_host_port=4443"* ]]
  [[ "${output}" == *"Conflicting Docker publishers:"* ]]
  [[ "${output}" == *"laemp-test-debian: 0.0.0.0:4443->443/tcp, [::]:4443->443/tcp"* ]]
  [[ "${output}" == *"TCP *:4443 (LISTEN)"* ]]
}

@test "kind host port preflight reports overlapping planned host ports" {
  cat >"${TEST_BIN}/lsof" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 1
EOF
  chmod +x "${TEST_BIN}/lsof"

  override_file="${BATS_TEST_TMPDIR}/kind-port-overlap.tfvars"
  cat >"${override_file}" <<'EOF'
gateway_https_host_port = 30080
EOF

  run env PLATFORM_TFVARS="${override_file}" make -C "${REPO_ROOT}/kubernetes/kind" check-kind-host-ports STAGE=100

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"FAIL planned kind host port overlap: gateway-https (127.0.0.1:30080) conflicts with argocd (127.0.0.1:30080)"* ]]
}
