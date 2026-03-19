#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/kubernetes/slicer/scripts/bootstrap-k3s-slicer.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  export PATH="${TEST_BIN}:${PATH}"
  export SLICER_LOG="${BATS_TEST_TMPDIR}/slicer.log"
  export KUBECTL_LOG="${BATS_TEST_TMPDIR}/kubectl.log"
  mkdir -p "${TEST_BIN}"

  cat >"${TEST_BIN}/slicer" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"${SLICER_LOG}"

if [[ "${1:-}" == "vm" && "${2:-}" == "ready" ]]; then
  exit 0
fi

if [[ "${1:-}" == "vm" && "${2:-}" == "list" && "${3:-}" == "--json" ]]; then
  cat <<'JSON'
[
  {
    "hostname": "slicer-1",
    "ip": "192.168.64.2",
    "ram_bytes": 8589934592,
    "cpus": 4,
    "status": "Running"
  }
]
JSON
  exit 0
fi

if [[ "${1:-}" == "vm" && "${2:-}" == "exec" ]]; then
  cmd="${5:-}"
  case "${cmd}" in
    "ip -4 route list 0/0 | awk '{print \$3}' | head -n1")
      printf '192.168.64.1\n'
      ;;
    "sudo chattr -i /etc/resolv.conf || true; printf 'nameserver 192.168.64.1\noptions timeout:1 attempts:2\n' | sudo tee /etc/resolv.conf >/dev/null; sudo chattr +i /etc/resolv.conf || true")
      if [[ "${SLICER_DNS_WRITE_FAIL:-0}" == "1" ]]; then
        exit 1
      fi
      ;;
    "sudo mkdir -p /etc/rancher/k3s; if ! sudo cmp -s /tmp/registries.yaml /etc/rancher/k3s/registries.yaml 2>/dev/null; then sudo mv /tmp/registries.yaml /etc/rancher/k3s/registries.yaml; sudo systemctl is-active --quiet k3s && sudo systemctl restart k3s || true; else rm -f /tmp/registries.yaml; fi")
      ;;
    "sudo test -x /usr/local/bin/k3s && sudo test -f /etc/rancher/k3s/k3s.yaml && sudo /usr/local/bin/k3s kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get --raw=/version")
      printf '{"gitVersion":"v1.35.1+k3s1"}\n'
      ;;
    "sudo systemctl show -p ExecStart --value k3s")
      printf '/usr/local/bin/k3s server --flannel-backend=none --disable-network-policy --disable=traefik --disable=servicelb\n'
      ;;
    *)
      echo "unexpected slicer vm exec command: ${cmd}" >&2
      exit 1
      ;;
  esac
  exit 0
fi

if [[ "${1:-}" == "vm" && "${2:-}" == "cp" ]]; then
  src="${3:-}"
  dst="${4:-}"
  if [[ "${src}" == "slicer-1:/etc/rancher/k3s/k3s.yaml" ]]; then
    cat >"${dst}" <<'YAML'
apiVersion: v1
clusters:
- cluster:
    server: https://127.0.0.1:6443
  name: default
contexts:
- context:
    cluster: default
    user: default
  name: default
current-context: default
kind: Config
users:
- name: default
  user: {}
YAML
  fi
  exit 0
fi

echo "unexpected slicer invocation: $*" >&2
exit 1
EOF
  chmod +x "${TEST_BIN}/slicer"

  cat >"${TEST_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"${KUBECTL_LOG}"

if [[ "${1:-}" == "config" && "${2:-}" == "current-context" ]]; then
  printf 'default\n'
  exit 0
fi

if [[ "${1:-}" == "config" && "${2:-}" == "rename-context" ]]; then
  exit 0
fi

if [[ "${1:-}" == "config" && "${2:-}" == "use-context" ]]; then
  exit 0
fi

if [[ "${1:-}" == "--context" && "${3:-}" == "get" && "${4:-}" == "nodes" ]]; then
  printf 'NAME       STATUS   ROLES           AGE   VERSION\n'
  printf 'slicer-1   Ready    control-plane   1m    v1.35.1+k3s1\n'
  exit 0
fi

echo "unexpected kubectl invocation: $*" >&2
exit 1
EOF
  chmod +x "${TEST_BIN}/kubectl"
}

@test "fails fast when stage 100 sees an already provisioned k3s VM" {
  run env \
    SLICER_URL="${BATS_TEST_TMPDIR}/slicer.sock" \
    KUBECONFIG_PATH="${BATS_TEST_TMPDIR}/slicer-k3s.yaml" \
    DEFAULT_KUBECONFIG_PATH="${BATS_TEST_TMPDIR}/config" \
    MERGE_KUBECONFIG_TO_DEFAULT=0 \
    "${SCRIPT}"

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"existing k3s detected on slicer-1"* ]]
  [[ "${output}" == *"SLICER_ALLOW_EXISTING_K3S=1"* ]]
}

@test "allows explicit reuse of an existing k3s VM to refresh kubeconfig" {
  kubeconfig="${BATS_TEST_TMPDIR}/slicer-k3s.yaml"

  run env \
    SLICER_URL="${BATS_TEST_TMPDIR}/slicer.sock" \
    KUBECONFIG_PATH="${kubeconfig}" \
    DEFAULT_KUBECONFIG_PATH="${BATS_TEST_TMPDIR}/config" \
    MERGE_KUBECONFIG_TO_DEFAULT=0 \
    SLICER_ALLOW_EXISTING_K3S=1 \
    "${SCRIPT}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"refreshing kubeconfig only"* ]]
  [[ -f "${kubeconfig}" ]]
  grep -q "https://192.168.64.2:6443" "${kubeconfig}"
}

@test "dns override failure is reported as a warning and bootstrap continues" {
  kubeconfig="${BATS_TEST_TMPDIR}/slicer-k3s.yaml"

  run env \
    SLICER_URL="${BATS_TEST_TMPDIR}/slicer.sock" \
    KUBECONFIG_PATH="${kubeconfig}" \
    DEFAULT_KUBECONFIG_PATH="${BATS_TEST_TMPDIR}/config" \
    MERGE_KUBECONFIG_TO_DEFAULT=0 \
    SLICER_ALLOW_EXISTING_K3S=1 \
    SLICER_DNS_WRITE_FAIL=1 \
    "${SCRIPT}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"WARN: failed to override DNS on slicer-1"* ]]
  [[ "${output}" == *"refreshing kubeconfig only"* ]]
}
