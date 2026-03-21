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
  [[ "${output}" == *"make 100 apply"* ]]
  [[ "${output}" == *"make apply 100"* ]]
  [[ "${output}" == *"900 - full stack + sso"* ]]
  [[ "${output}" == *"Linux -> Docker Engine or Docker Desktop"* ]]
  [[ "${output}" == *"make merge-default-kubeconfig"* ]]
  [[ "${output}" == *"split by default"* ]]
  [[ "${output}" == *"KIND_WORKER_COUNT=1|2|..."* ]]
  [[ "${output}" == *"KIND_IMAGE_DISTRIBUTION_MODE=load|registry|hybrid|baked"* ]]
  [[ "${output}" == *"image distribution mode (default: registry)"* ]]
  [[ "${output}" == *"make status"* ]]
}

@test "kind run_step helper preserves shell arguments instead of invoking macOS apply" {
  run grep -Fn '"$${@}"' "${REPO_ROOT}/kubernetes/kind/Makefile"

  [ "${status}" -eq 0 ]
}

@test "kind stage without action shows guidance" {
  run make -C "${REPO_ROOT}/kubernetes/kind" 100

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Stage 100 requires an action."* ]]
  [[ "${output}" == *"make 100 apply AUTO_APPROVE=1"* ]]
  [[ "${output}" == *"make 100 check-security"* ]]
}

@test "kind typo suggests the closest workflow action" {
  run make -C "${REPO_ROOT}/kubernetes/kind" 100 aplly

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Did you mean 'apply'?"* ]]
}

@test "kind apply with a missing env file fails cleanly instead of treating it as a make goal" {
  missing_env="${BATS_TEST_TMPDIR}/missing.env"

  run env PLATFORM_ENV_FILE="${missing_env}" make -C "${REPO_ROOT}/kubernetes/kind" 100 apply

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Missing platform env file: ${missing_env}"* ]]
  [[ "${output}" != *"Unknown make goal '${missing_env}'"* ]]
}

@test "kind supports stage-first check-security syntax" {
  run make -n -C "${REPO_ROOT}/kubernetes/kind" 900 check-security

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"check-security.sh"* ]]
}

@test "kind apply refreshes kubeconfig after a successful apply" {
  run grep -Fn 'if [ $$rc -eq 0 ]; then \' "${REPO_ROOT}/kubernetes/kind/Makefile"

  [ "${status}" -eq 0 ]

  run grep -Fn 'KUBECONFIG_PATH="$(KUBECONFIG_PATH)" GLOBAL_KUBECONFIG_PATH="$(DEFAULT_KUBECONFIG_PATH)" KUBECONFIG_HELPER="$(KUBECONFIG_HELPER)" MERGE_KUBECONFIG_TO_DEFAULT="$(MERGE_KUBECONFIG_TO_DEFAULT)" "$(ENSURE_KIND_KUBECONFIG)"; \' "${REPO_ROOT}/kubernetes/kind/Makefile"

  [ "${status}" -eq 0 ]
}

@test "kind stage 900 apply waits for cluster health before browser SSO E2E verification" {
  run grep -Fn 'run_step "check-health" $(MAKE) -C "$(MAKEFILE_DIR)" check-health STAGE="$(STAGE)";' \
    "${REPO_ROOT}/kubernetes/kind/Makefile"

  [ "${status}" -eq 0 ]
}

@test "kind stage 900 apply runs browser SSO E2E verification after a successful apply" {
  run grep -Fn 'run_step "check-sso-e2e" $(MAKE) -C "$(MAKEFILE_DIR)" check-sso-e2e STAGE="$(STAGE)";' \
    "${REPO_ROOT}/kubernetes/kind/Makefile"

  [ "${status}" -eq 0 ]
}

@test "kind check-kubeconfig refreshes the split kind kubeconfig first" {
  run grep -Fn '$(MAKE) ensure-kind-kubeconfig >/dev/null; \' "${REPO_ROOT}/kubernetes/kind/Makefile"

  [ "${status}" -eq 0 ]
}

@test "kind prereqs surfaces Docker registry auth status" {
  run grep -Fn 'echo "Docker registry auth:"; \' "${REPO_ROOT}/kubernetes/kind/Makefile"

  [ "${status}" -eq 0 ]

  run grep -Fn '"$(CHECK_DOCKER_REGISTRY_AUTH)" dhi.io "Docker Hardened Images (dhi.io)" || true; \' "${REPO_ROOT}/kubernetes/kind/Makefile"

  [ "${status}" -eq 0 ]
}

@test "kind prereqs groups tool checks and does not run shell audit" {
  run env PATH="/usr/bin:/bin" make -C "${REPO_ROOT}/kubernetes/kind" prereqs STAGE=100

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Tool installation verification:"* ]]
  [[ "${output}" == *"Install hints:"* ]]
  [[ "${output}" != *"Shell audit:"* ]]
}

@test "kind ensure-kind-running revives a stopped cluster before terraform" {
  state_file="${BATS_TEST_TMPDIR}/docker-state"
  printf 'stopped' >"${state_file}"

  cat >"${TEST_BIN}/docker" <<EOF
#!/usr/bin/env bash
set -euo pipefail
state_file="${state_file}"
cmd="\${1:-}"
shift || true
case "\${cmd}" in
  info)
    exit 0
    ;;
  ps)
    include_all=0
    while [[ \$# -gt 0 ]]; do
      case "\$1" in
        -a)
          include_all=1
          shift
          ;;
        --format)
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    if [[ "\${include_all}" == "1" ]]; then
      printf '%s\n' kind-local-control-plane kind-local-worker
      exit 0
    fi
    if [[ "\$(cat "\${state_file}")" == "running" ]]; then
      printf '%s\n' kind-local-control-plane kind-local-worker
    fi
    exit 0
    ;;
  start)
    printf 'running' >"\${state_file}"
    exit 0
    ;;
esac
exit 1
EOF
  chmod +x "${TEST_BIN}/docker"

  cat >"${TEST_BIN}/kind" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "get" && "${2:-}" == "clusters" ]]; then
  printf '%s\n' kind-local
  exit 0
fi
if [[ "${1:-}" == "export" && "${2:-}" == "kubeconfig" ]]; then
  kubeconfig=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --kubeconfig)
        kubeconfig="$2"
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done
  mkdir -p "$(dirname "${kubeconfig}")"
  cat >"${kubeconfig}" <<'YAML'
apiVersion: v1
clusters: []
contexts: []
current-context: ""
kind: Config
preferences: {}
users: []
YAML
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/kind"

  cat >"${TEST_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
args="$*"
if [[ "${args}" == *"config get-contexts"* ]]; then
  exit 0
fi
if [[ "${args}" == *"config use-context"* ]]; then
  exit 0
fi
if [[ "${args}" == *"get --raw=/readyz"* ]]; then
  exit 0
fi
if [[ "${args}" == *"get nodes -o wide"* ]]; then
  printf '%s\n' 'NAME STATUS ROLES AGE VERSION'
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/kubectl"

  cat >"${TEST_BIN}/lsof" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 1
EOF
  chmod +x "${TEST_BIN}/lsof"

  cat >"${TEST_BIN}/ps" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/ps"

  cat >"${TEST_BIN}/limactl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/limactl"

  run env \
    KIND_CHECK_SLICER_SOCKET="${BATS_TEST_TMPDIR}/missing.sock" \
    KUBECONFIG_HELPER=/bin/true \
    KUBECONFIG_PATH="${BATS_TEST_TMPDIR}/kind-kind-local.yaml" \
    DEFAULT_KUBECONFIG_PATH="${BATS_TEST_TMPDIR}/config" \
    make -C "${REPO_ROOT}/kubernetes/kind" ensure-kind-running

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"kind-local exists but is stopped; starting node containers..."* ]]
  [[ "${output}" == *"kind-local is running again."* ]]
  [[ "$(cat "${state_file}")" == "running" ]]
}

@test "kind reset prepares invalid kubeconfigs for cleanup instead of blindly backing them up" {
  run grep -Fn 'KUBECONFIG_RESET_AUTO_APPROVE="$(AUTO_APPROVE)" "$(KUBECONFIG_HELPER)" prepare-for-reset' \
    "${REPO_ROOT}/kubernetes/kind/Makefile"

  [ "${status}" -eq 0 ]
}

@test "kind ensure-kind-running fails before docker start when planned host ports are occupied" {
  state_file="${BATS_TEST_TMPDIR}/docker-state"
  printf 'stopped' >"${state_file}"

  cat >"${TEST_BIN}/docker" <<EOF
#!/usr/bin/env bash
set -euo pipefail
state_file="${state_file}"
cmd="\${1:-}"
shift || true
case "\${cmd}" in
  ps)
    include_all=0
    while [[ \$# -gt 0 ]]; do
      case "\$1" in
        -a)
          include_all=1
          shift
          ;;
        --format)
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    if [[ "\${include_all}" == "1" ]]; then
      printf '%s\n' kind-local-control-plane kind-local-worker
      exit 0
    fi
    if [[ "\$(cat "\${state_file}")" == "running" ]]; then
      printf '%s\n' kind-local-control-plane kind-local-worker
    fi
    exit 0
    ;;
  start)
    printf 'running' >"\${state_file}"
    exit 0
    ;;
esac
exit 1
EOF
  chmod +x "${TEST_BIN}/docker"

  cat >"${TEST_BIN}/kind" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "get" && "${2:-}" == "clusters" ]]; then
  printf '%s\n' kind-local
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/kind"

  cat >"${TEST_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/kubectl"

  cat >"${TEST_BIN}/lsof" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *"-iTCP:30080"* ]]; then
  cat <<'OUT'
COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
limactl 13774 nick   29u  IPv4 0xdeadbeef      0t0  TCP 127.0.0.1:30080 (LISTEN)
OUT
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/lsof"

  cat >"${TEST_BIN}/ps" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/ps"

  cat >"${TEST_BIN}/limactl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/limactl"

  run env \
    KIND_CHECK_SLICER_SOCKET="${BATS_TEST_TMPDIR}/missing.sock" \
    KUBECONFIG_HELPER=/bin/true \
    KUBECONFIG_PATH="${BATS_TEST_TMPDIR}/kind-kind-local.yaml" \
    DEFAULT_KUBECONFIG_PATH="${BATS_TEST_TMPDIR}/config" \
    make -C "${REPO_ROOT}/kubernetes/kind" ensure-kind-running

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"FAIL argocd host port 127.0.0.1:30080 is already in use"* ]]
  [[ "${output}" != *"Starting kind-local node containers..."* ]]
  [[ "$(cat "${state_file}")" == "stopped" ]]
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
