#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root

  LIB="${REPO_ROOT}/terraform/kubernetes/scripts/kind-apiserver-oidc-lib.sh"
  STUB_DIR="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${STUB_DIR}"
}

# Stubs kubectl so the deployment predicates can be driven from fixed values.
# The state is passed through files rather than interpolated into the stub, so
# the stub body can be a quoted heredoc with no escaping to get wrong.
write_kubectl_stub() {
  printf '%s' "$1" >"${BATS_TEST_TMPDIR}/state"
  printf '%s' "$2" >"${BATS_TEST_TMPDIR}/reason"
  printf '%s' "${3:-fail}" >"${BATS_TEST_TMPDIR}/rollout"

  cat >"${STUB_DIR}/kubectl" <<'EOF'
#!/usr/bin/env bash
tmpdir="${STUB_STATE_DIR}"
for arg in "$@"; do
  case "${arg}" in
    *observedGeneration*) cat "${tmpdir}/state"; exit 0 ;;
    *Progressing*) cat "${tmpdir}/reason"; exit 0 ;;
    status) [ "$(cat "${tmpdir}/rollout")" = "ok" ]; exit $? ;;
  esac
done
exit 1
EOF
  chmod +x "${STUB_DIR}/kubectl"
}

# Runs a snippet against the stubbed kubectl.
run_with_stub() {
  run env "PATH=${STUB_DIR}:${PATH}" "STUB_STATE_DIR=${BATS_TEST_TMPDIR}" \
    bash -c "source '${LIB}'; $1"
}

@test "deployment_is_fully_available accepts a deployment at full availability" {
  write_kubectl_stub "1/4/4/1/1/1" ""

  run_with_stub "deployment_is_fully_available nginx-gateway nginx-gateway"

  [ "${status}" -eq 0 ]
}

@test "deployment_is_fully_available rejects a stale observedGeneration" {
  # The controller has not yet acted on generation 5, so the availability
  # numbers still describe the previous spec and must not be trusted.
  write_kubectl_stub "1/4/5/1/1/1" ""

  run_with_stub "deployment_is_fully_available nginx-gateway nginx-gateway"

  [ "${status}" -ne 0 ]
}

@test "deployment_is_fully_available rejects a partially ready deployment" {
  write_kubectl_stub "3/4/4/3/2/2" ""

  run_with_stub "deployment_is_fully_available nginx-gateway nginx-gateway"

  [ "${status}" -ne 0 ]
}

@test "deployment_is_fully_available rejects a scaled-to-zero deployment" {
  write_kubectl_stub "0/4/4/0/0/0" ""

  run_with_stub "deployment_is_fully_available nginx-gateway nginx-gateway"

  [ "${status}" -ne 0 ]
}

@test "deployment_is_fully_available rejects a deployment kubectl cannot describe" {
  write_kubectl_stub "" ""

  run_with_stub "deployment_is_fully_available nginx-gateway nginx-gateway"

  [ "${status}" -ne 0 ]
}

@test "deployment_progress_deadline_exceeded detects the latched condition" {
  write_kubectl_stub "1/4/4/1/1/1" "ProgressDeadlineExceeded"

  run_with_stub "deployment_progress_deadline_exceeded nginx-gateway nginx-gateway"

  [ "${status}" -eq 0 ]
}

@test "deployment_progress_deadline_exceeded ignores a healthy Progressing reason" {
  write_kubectl_stub "1/4/4/1/1/1" "NewReplicaSetAvailable"

  run_with_stub "deployment_progress_deadline_exceeded nginx-gateway nginx-gateway"

  [ "${status}" -ne 0 ]
}

@test "the rollout wait returns promptly when rollout status is stale but the deployment is available" {
  # This is the 35-minute OIDC recovery: rollout status never succeeds, but the
  # workload is healthy, so the wait must not burn its whole timeout.
  write_kubectl_stub "1/4/4/1/1/1" "ProgressDeadlineExceeded" "fail"

  run_with_stub "SECONDS=0; wait_for_deployment_rollout_with_early_recycle ns dep 900 'nginx gateway control plane'; echo \"elapsed=\${SECONDS}\""

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"fully available"* ]]
  # The bug was burning the whole 900s timeout on a healthy deployment.
  [[ "${output}" == *"elapsed=0"* ]] || [[ "${output}" == *"elapsed=1"* ]]
}

@test "the rollout wait still succeeds normally when rollout status is happy" {
  write_kubectl_stub "1/4/4/1/1/1" "NewReplicaSetAvailable" "ok"

  run_with_stub "wait_for_deployment_rollout_with_early_recycle ns dep 900 'nginx gateway control plane'"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"ready"* ]]
}

# The gateway address the apiserver resolves the OIDC issuer to differs by mode:
# NGF exposes an internal Service with a clusterIP, Cilium binds the listener on
# the node's host network and has no Service with endpoints at all.
write_gateway_ip_stub() {
  printf '%s' "$1" >"${BATS_TEST_TMPDIR}/clusterip"
  printf '%s' "$2" >"${BATS_TEST_TMPDIR}/nodeip"

  cat >"${STUB_DIR}/kubectl" <<'EOF'
#!/usr/bin/env bash
tmpdir="${STUB_STATE_DIR}"
for arg in "$@"; do
  case "${arg}" in
    *clusterIP*) cat "${tmpdir}/clusterip"; exit 0 ;;
    *InternalIP*) cat "${tmpdir}/nodeip"; exit 0 ;;
  esac
done
exit 1
EOF
  chmod +x "${STUB_DIR}/kubectl"
}

run_gateway_ip() {
  run env "PATH=${STUB_DIR}:${PATH}" "STUB_STATE_DIR=${BATS_TEST_TMPDIR}" \
    bash -c "source '${LIB}'; $1"
}

@test "the gateway resolves to the node running the host-network listener" {
  write_gateway_ip_stub "10.96.72.111" "172.18.0.3"

  run_gateway_ip "resolve_gateway_ingress_ip kind-local-control-plane"

  [ "${status}" -eq 0 ]
  # The clusterIP still resolves in this mode, but it fronts a Service with no
  # endpoints -- taking it is the bug, so it must not be what comes back.
  [[ "${output}" == *"172.18.0.3"* ]]
  [[ "${output}" != *"10.96.72.111"* ]]
}
