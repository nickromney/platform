#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN}"
  export PATH="${TEST_BIN}:${PATH}"
}

@test "ensure-k3s-lima-vms clears SSH_AUTH_SOCK before invoking limactl" {
  export LOG_FILE="${BATS_TEST_TMPDIR}/limactl.log"
  export STATE_FILE="${BATS_TEST_TMPDIR}/started"
  export SSH_AUTH_SOCK="${BATS_TEST_TMPDIR}/agent.sock"

  cat >"${TEST_BIN}/limactl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'sock=<%s> cmd=%s\n' "${SSH_AUTH_SOCK-}" "$*" >>"${LOG_FILE}"
case "${1:-}" in
  list)
    if [ -f "${STATE_FILE}" ]; then
      printf 'k3s-node-1 Running 127.0.0.1:60022\n'
    fi
    ;;
  start)
    : >"${STATE_FILE}"
    ;;
  *)
    echo "unexpected limactl call: $*" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "${TEST_BIN}/limactl"

  config_file="${BATS_TEST_TMPDIR}/lima.yaml"
  touch "${config_file}"

  run env \
    LIMA_INSTANCE_PREFIX="k3s-node" \
    DESIRED_NODES="1" \
    LIMA_CONFIG="${config_file}" \
    "${REPO_ROOT}/kubernetes/lima/scripts/ensure-k3s-lima-vms.sh" --execute

  [ "${status}" -eq 0 ]
  run cat "${LOG_FILE}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"sock=<> cmd=list"* ]]
  [[ "${output}" == *"sock=<> cmd=start --name k3s-node-1 ${config_file} --containerd none --tty=false --timeout=15m"* ]]
}

@test "bootstrap-k3s-lima clears SSH_AUTH_SOCK for limactl shell and k3sup" {
  export LIMACTL_LOG="${BATS_TEST_TMPDIR}/limactl.log"
  export K3SUP_LOG="${BATS_TEST_TMPDIR}/k3sup.log"
  export SSH_AUTH_SOCK="${BATS_TEST_TMPDIR}/agent.sock"
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}/.lima/_config" "${HOME}/.kube"
  touch "${HOME}/.lima/_config/user"

  cat >"${TEST_BIN}/limactl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'sock=<%s> cmd=%s\n' "${SSH_AUTH_SOCK-}" "$*" >>"${LIMACTL_LOG}"
case "${1:-}" in
  list)
    printf 'k3s-node-1 Running 127.0.0.1:60022\n'
    ;;
  shell)
    shift
    name="$1"
    shift
    if [ "${1:-}" = "--" ]; then
      shift
    fi
    case "${1:-}" in
      ip)
        printf '1.1.1.1 via 192.168.5.1 dev eth0 src 192.168.5.15 uid 1000\n'
        ;;
      sudo)
        case "${2:-}" in
          cmp)
            exit 1
            ;;
          cat)
            cat <<'YAML'
apiVersion: v1
kind: Config
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
users:
- name: default
  user:
    token: test
YAML
            ;;
          k3s)
            if [ "${3:-}" = "kubectl" ] && [ "${4:-}" = "get" ] && [ "${5:-}" = "nodes" ]; then
              printf 'k3s-node-1 Ready control-plane 1m v1.35.1\n'
            fi
            ;;
        esac
        ;;
      systemctl)
        exit 1
        ;;
    esac
    ;;
  *)
    echo "unexpected limactl call: $*" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "${TEST_BIN}/limactl"

  cat >"${TEST_BIN}/k3sup" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'sock=<%s> args=%s\n' "${SSH_AUTH_SOCK-}" "$*" >>"${K3SUP_LOG}"
exit 0
EOF
  chmod +x "${TEST_BIN}/k3sup"
  cp "${TEST_BIN}/k3sup" "${TEST_BIN}/k3sup-pro"

  cat >"${TEST_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  config|get)
    exit 0
    ;;
esac
exit 0
EOF
  chmod +x "${TEST_BIN}/kubectl"

  cat >"${TEST_BIN}/kubeconfig-helper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/kubeconfig-helper"

  run env \
    LIMA_INSTANCE_PREFIX="k3s-node" \
    DESIRED_NODES="1" \
    K3SUP_BIN="${TEST_BIN}/k3sup" \
    KUBECONFIG_HELPER="${TEST_BIN}/kubeconfig-helper" \
    KUBECONFIG_PATH="${BATS_TEST_TMPDIR}/limavm-k3s.yaml" \
    DEFAULT_KUBECONFIG_PATH="${BATS_TEST_TMPDIR}/config" \
    "${REPO_ROOT}/kubernetes/lima/scripts/bootstrap-k3s-lima.sh" --execute

  [ "${status}" -eq 0 ]

  run cat "${LIMACTL_LOG}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"sock=<> cmd=shell k3s-node-1 -- ip route get 1.1.1.1"* ]]
  [[ "${output}" == *"sock=<> cmd=shell k3s-node-1 -- sudo cat /etc/rancher/k3s/k3s.yaml"* ]]

  run cat "${K3SUP_LOG}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"sock=<> args=install --ip 127.0.0.1 --ssh-port 60022"* ]]
}
