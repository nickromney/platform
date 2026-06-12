#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "kind and slicer host port preflights call the shared checker through variant manifests" {
  run make -n -C "${REPO_ROOT}/kubernetes/kind" check-kind-host-ports STAGE=100

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'kubernetes/scripts/check-target-host-ports.sh" --execute'* ]]
  [[ "${output}" == *'--variant-json "'*"kubernetes/variants/kind/variant.json"* ]]
  [[ "${output}" != *'PORT_CHECKS="'* ]]
  [[ "${output}" != *'gateway-https|'* ]]
  [[ "${output}" != *'argocd|127.0.0.1|argocd_server_node_port|30080|argocd_server_node_port|30080'* ]]
  [[ "${output}" != *'kubernetes/kind/scripts/check-kind-host-ports.sh'* ]]

  run make -n -C "${REPO_ROOT}/kubernetes/slicer" check-host-ports STAGE=100

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'kubernetes/scripts/check-target-host-ports.sh" --execute'* ]]
  [[ "${output}" == *'--variant-json "'*"kubernetes/variants/slicer/variant.json"* ]]
  [[ "${output}" != *'PORT_CHECKS="'* ]]
  [[ "${output}" != *'gateway-https|'* ]]
  [[ "${output}" != *'argocd|127.0.0.1|argocd_server_node_port|30080|argocd_server_node_port|30080'* ]]
  [[ "${output}" != *'kubernetes/slicer/scripts/check-slicer-host-ports.sh'* ]]
}

@test "shared host port checker derives gateway preflight rows from variant JSON" {
  test_bin="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${test_bin}"
  cat >"${test_bin}/lsof" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *"-iTCP:15443"* ]]; then
  cat <<'OUT'
COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
testd   123 nick 17u IPv4 0xdeadbeef 0t0 TCP 127.0.0.1:15443 (LISTEN)
OUT
  exit 0
fi
exit 1
EOF
  chmod +x "${test_bin}/lsof"

  variant_json="${BATS_TEST_TMPDIR}/variant.json"
  cat >"${variant_json}" <<'EOF'
{
  "schema_version": "platform.variant/v1",
  "id": "variant-test",
  "label": "variant-test",
  "host_access_path": {
    "mode": "kind-nodeports",
    "gateway_host_port": 15443,
    "gateway_target_port": 31070,
    "shared_host_ports": [15443],
    "requires_proxy": false,
    "requires_forward_process": false,
    "can_degrade": false
  }
}
EOF

  run env PATH="${test_bin}:${PATH}" \
    "${REPO_ROOT}/kubernetes/scripts/check-target-host-ports.sh" \
      --execute \
      --variant-json "${variant_json}"

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"FAIL gateway-https host port 127.0.0.1:15443 is already in use"* ]]
  [[ "${output}" == *"Planned mapping: gateway_https_host_port=15443 (<default>) -> variant-test node port gateway_https_node_port=31070 (<default>)"* ]]
  [[ "${output}" != *"127.0.0.1:443"* ]]
}

@test "shared host port checker preserves expose_admin_nodeports gate" {
  test_bin="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${test_bin}"
  cat >"${test_bin}/lsof" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *"-iTCP:30080"* ]]; then
  cat <<'OUT'
COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
testd   123 nick 17u IPv4 0xdeadbeef 0t0 TCP 127.0.0.1:30080 (LISTEN)
OUT
  exit 0
fi
exit 1
EOF
  chmod +x "${test_bin}/lsof"

  tfvars_file="${BATS_TEST_TMPDIR}/admin-nodeports-off.tfvars"
  cat >"${tfvars_file}" <<'EOF'
expose_admin_nodeports = false
gateway_https_host_port = 15444
kind_api_server_port = 16443
EOF

  run env PATH="${test_bin}:${PATH}" \
    "${REPO_ROOT}/kubernetes/scripts/check-target-host-ports.sh" \
      --execute \
      --variant-json "${REPO_ROOT}/kubernetes/variants/kind/variant.json" \
      --var-file "${tfvars_file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"OK   kind host ports available:"* ]]
  [[ "${output}" == *"127.0.0.1:15444"* ]]
  [[ "${output}" == *"127.0.0.1:16443"* ]]
  [[ "${output}" != *"30080"* ]]
}
