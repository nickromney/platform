#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../../scripts/lib/shell-cli.sh"
RUN_ROOT_DEFAULT="${SCRIPT_DIR}/../.run"
RUN_ID_DEFAULT="cilium-loop-$(date +%Y%m%d-%H%M%S)"

BACKEND_SOCK="${BACKEND_SOCK:-${HOME}/Library/Containers/com.docker.docker/Data/backend.sock}"
KUBECONFIG_CONTEXT="${KUBECONFIG_CONTEXT:-docker-desktop}"
DESIRED_MODE="${DESIRED_MODE:-kind}"
DESIRED_NODE_COUNT="${DESIRED_NODE_COUNT:-2}"
DESIRED_VERSION="${DESIRED_VERSION:-1.35.1}"
CILIUM_VERSION="${CILIUM_VERSION:-1.19.1}"
POD_CIDR_PREFIX="${POD_CIDR_PREFIX:-10.245.}"
MAX_LOOPS="${MAX_LOOPS:-10}"
START_TIMEOUT_SECONDS="${START_TIMEOUT_SECONDS:-600}"
WAIT_TIMEOUT_SECONDS="${WAIT_TIMEOUT_SECONDS:-600}"
RUN_ROOT="${RUN_ROOT:-${RUN_ROOT_DEFAULT}}"
RUN_ID="${RUN_ID:-${RUN_ID_DEFAULT}}"
RUN_DIR="${RUN_ROOT}/${RUN_ID}"

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute]

Exercises the Docker Desktop managed kind + Cilium workload reset loop and
captures status snapshots in the run directory.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage "would run the Docker Desktop Cilium workload loop and capture diagnostics" "$@"

mkdir -p "${RUN_DIR}"

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

backend() {
  curl -sS --unix-socket "${BACKEND_SOCK}" "$@"
}

cluster_status() {
  backend "http://localhost/kubernetes"
}

cluster_status_field() {
  local jq_filter="$1"
  cluster_status | jq -r "${jq_filter}"
}

dump_status() {
  local out_dir="$1"
  mkdir -p "${out_dir}"

  {
    printf '=== docker desktop kubernetes status ===\n'
    docker desktop kubernetes status || true
    printf '\n=== backend /kubernetes ===\n'
    cluster_status | jq . || true
    printf '\n=== kubectl nodes ===\n'
    kubectl --context "${KUBECONFIG_CONTEXT}" get nodes -o wide || true
    printf '\n=== kube-system pods ===\n'
    kubectl --context "${KUBECONFIG_CONTEXT}" -n kube-system get pods -o wide || true
    printf '\n=== recent kube-system events ===\n'
    kubectl --context "${KUBECONFIG_CONTEXT}" -n kube-system get events --sort-by=.lastTimestamp | tail -n 120 || true
  } > "${out_dir}/cluster-status.txt" 2>&1
}

assert_cluster_shape() {
  local mode
  local node_count
  local version

  mode="$(cluster_status_field '.content.mode')"
  node_count="$(cluster_status_field '.content.nodeCount')"
  version="$(cluster_status_field '.content.version')"

  if [[ "${mode}" != "${DESIRED_MODE}" ]]; then
    log "Unexpected Docker Desktop Kubernetes mode: ${mode} (wanted ${DESIRED_MODE})"
    return 1
  fi

  if [[ "${node_count}" != "${DESIRED_NODE_COUNT}" ]]; then
    log "Unexpected Docker Desktop node count: ${node_count} (wanted ${DESIRED_NODE_COUNT})"
    return 1
  fi

  if [[ "${version}" != "${DESIRED_VERSION}" ]]; then
    log "Unexpected Docker Desktop Kubernetes version: ${version} (wanted ${DESIRED_VERSION})"
    return 1
  fi
}

wait_for_api() {
  local deadline=$((SECONDS + START_TIMEOUT_SECONDS))

  while (( SECONDS < deadline )); do
    if kubectl --context "${KUBECONFIG_CONTEXT}" version --request-timeout=5s >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done

  return 1
}

wait_for_nodes_ready() {
  kubectl --context "${KUBECONFIG_CONTEXT}" wait --for=condition=Ready node --all --timeout="${WAIT_TIMEOUT_SECONDS}s"
}

reset_cluster() {
  local previous_id
  local previous_started_at
  local current_id
  local current_started_at

  previous_id="$(cluster_status_field '.id')"
  previous_started_at="$(cluster_status_field '.content.startedAt // 0')"

  log "Resetting the Docker Desktop Kubernetes cluster"
  backend -X POST "http://localhost/kubernetes/reset" >/dev/null

  local deadline=$((SECONDS + WAIT_TIMEOUT_SECONDS))

  while (( SECONDS < deadline )); do
    current_id="$(cluster_status_field '.id')"
    current_started_at="$(cluster_status_field '.content.startedAt // 0')"

    if [[ "${current_id}" != "${previous_id}" || "${current_started_at}" != "${previous_started_at}" ]]; then
      return 0
    fi
    sleep 2
  done

  log "Timed out waiting for cluster reset to start"
  return 1
}

ensure_cluster_running() {
  local status

  status="$(cluster_status_field '.status')"
  if [[ "${status}" == "disabled" ]]; then
    log "Starting the Docker Desktop Kubernetes cluster"
    backend -X POST "http://localhost/kubernetes/start" >/dev/null
  else
    log "Waiting for the reset cluster to come back"
  fi

  if ! wait_for_api; then
    log "Timed out waiting for the Kubernetes API to come up"
    return 1
  fi

  wait_for_nodes_ready
}

prepull_images() {
  local node
  local image
  local -a nodes=(desktop-control-plane desktop-worker)
  local -a images=(
    "quay.io/cilium/cilium:v1.19.1"
    "quay.io/cilium/operator-generic:v1.19.1"
    "quay.io/cilium/cilium-envoy:v1.35.9-1770979049-232ed4a26881e4ab4f766f251f258ed424fff663"
    "registry.k8s.io/pause:3.10"
  )

  for node in "${nodes[@]}"; do
    for image in "${images[@]}"; do
      docker exec "${node}" crictl pull "${image}" >/dev/null 2>&1 || true
    done
  done
}

install_cilium() {
  log "Installing Cilium ${CILIUM_VERSION} in migration mode"

  cilium install \
    --context "${KUBECONFIG_CONTEXT}" \
    --version "${CILIUM_VERSION}" \
    --wait \
    --wait-duration 10m \
    --set routingMode=tunnel \
    --set tunnelProtocol=vxlan \
    --set tunnelPort=8473 \
    --set cni.customConf=true \
    --set cni.uninstall=false \
    --set ipam.mode=cluster-pool \
    --set 'ipam.operator.clusterPoolIPv4PodCIDRList[0]=10.245.0.0/16' \
    --set policyEnforcementMode=never \
    --set bpf.hostLegacyRouting=true
}

apply_migration_config() {
  log "Applying Cilium node-migration config and labeling both nodes"

  kubectl --context "${KUBECONFIG_CONTEXT}" apply -f - <<'YAML'
apiVersion: cilium.io/v2alpha1
kind: CiliumNodeConfig
metadata:
  namespace: kube-system
  name: cilium-default
spec:
  defaults:
    write-cni-conf-when-ready: /host/etc/cni/net.d/05-cilium.conflist
    custom-cni-conf: "false"
    cni-exclusive: "true"
  nodeSelector:
    matchLabels:
      io.cilium.migration/cilium-default: "true"
YAML

  kubectl --context "${KUBECONFIG_CONTEXT}" label node desktop-control-plane io.cilium.migration/cilium-default=true --overwrite
  kubectl --context "${KUBECONFIG_CONTEXT}" label node desktop-worker io.cilium.migration/cilium-default=true --overwrite
}

recycle_cilium_pods() {
  local pod
  local -a pods=()

  while IFS= read -r pod; do
    [[ -n "${pod}" ]] && pods+=("${pod}")
  done < <(
    kubectl --context "${KUBECONFIG_CONTEXT}" -n kube-system get pods -l k8s-app=cilium -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
  )

  log "Recycling Cilium agent pods so each node rewrites its CNI config"
  if [[ "${#pods[@]}" -eq 0 ]]; then
    log "No Cilium agent pods were found"
    return 1
  fi

  for pod in "${pods[@]}"; do
    kubectl --context "${KUBECONFIG_CONTEXT}" -n kube-system delete pod "${pod}" --wait=false
  done

  wait_for_cilium_pods
}

wait_for_cilium_pods() {
  local deadline=$((SECONDS + WAIT_TIMEOUT_SECONDS))
  local count
  local node_count

  while (( SECONDS < deadline )); do
    read -r count node_count < <(
      kubectl --context "${KUBECONFIG_CONTEXT}" -n kube-system get pods -l k8s-app=cilium -o wide --no-headers 2>/dev/null \
        | awk '
            $2 == "1/1" && $3 == "Running" {
              count++
              nodes[$7] = 1
            }
            END {
              node_count = 0
              for (node in nodes) {
                node_count++
              }
              print count + 0, node_count
            }
          '
    )

    if [[ "${count}" == "2" && "${node_count}" == "2" ]]; then
      return 0
    fi

    sleep 5
  done

  return 1
}

assert_cni_files() {
  local node
  for node in desktop-control-plane desktop-worker; do
    docker exec "${node}" test -f /etc/cni/net.d/05-cilium.conflist
  done
}

recycle_coredns() {
  log "Recycling CoreDNS so new pods are created through the Cilium CNI path"
  kubectl --context "${KUBECONFIG_CONTEXT}" -n kube-system delete pod -l k8s-app=kube-dns --wait=false || true
}

wait_for_coredns() {
  local deadline=$((SECONDS + WAIT_TIMEOUT_SECONDS))
  local good_count
  local node_count

  while (( SECONDS < deadline )); do
    read -r good_count node_count < <(
      kubectl --context "${KUBECONFIG_CONTEXT}" -n kube-system get pods -l k8s-app=kube-dns -o wide --no-headers 2>/dev/null \
        | awk -v prefix="${POD_CIDR_PREFIX}" '
            $2 == "1/1" && $3 == "Running" && index($6, prefix) == 1 {
              count++
              nodes[$7] = 1
            }
            END {
              node_count = 0
              for (node in nodes) {
                node_count++
              }
              print count + 0, node_count
            }
          '
    )

    if [[ "${good_count}" == "2" && "${node_count}" -ge "1" ]]; then
      return 0
    fi

    sleep 5
  done

  return 1
}

deploy_smoke_daemonset() {
  local loop_id="$1"
  local namespace="dd-loop-${loop_id}"

  log "Deploying a smoke DaemonSet workload onto both nodes"

  kubectl --context "${KUBECONFIG_CONTEXT}" apply -f - <<YAML
apiVersion: v1
kind: Namespace
metadata:
  name: ${namespace}
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: smoke
  namespace: ${namespace}
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: smoke
  template:
    metadata:
      labels:
        app.kubernetes.io/name: smoke
    spec:
      tolerations:
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
          effect: NoSchedule
      containers:
        - name: pause
          image: registry.k8s.io/pause:3.10
YAML

  kubectl --context "${KUBECONFIG_CONTEXT}" -n "${namespace}" rollout status daemonset/smoke --timeout="${WAIT_TIMEOUT_SECONDS}s"
}

assert_smoke_daemonset() {
  local loop_id="$1"
  local namespace="dd-loop-${loop_id}"
  local count
  local node_count

  count="$(
    kubectl --context "${KUBECONFIG_CONTEXT}" -n "${namespace}" get pods -l app.kubernetes.io/name=smoke -o wide --no-headers 2>/dev/null \
      | awk -v prefix="${POD_CIDR_PREFIX}" '
          $2 == "1/1" && $3 == "Running" && index($6, prefix) == 1 {
            count++
            nodes[$7] = 1
          }
          END {
            node_count = 0
            for (node in nodes) {
              node_count++
            }
            print count + 0
          }
        '
  )"

  node_count="$(
    kubectl --context "${KUBECONFIG_CONTEXT}" -n "${namespace}" get pods -l app.kubernetes.io/name=smoke -o wide --no-headers 2>/dev/null \
      | awk -v prefix="${POD_CIDR_PREFIX}" '
          $2 == "1/1" && $3 == "Running" && index($6, prefix) == 1 {
            nodes[$7] = 1
          }
          END {
            node_count = 0
            for (node in nodes) {
              node_count++
            }
            print node_count
          }
        '
  )"

  if [[ "${count}" != "2" ]]; then
    return 1
  fi

  if [[ "${node_count}" != "2" ]]; then
    return 1
  fi

  kubectl --context "${KUBECONFIG_CONTEXT}" -n "${namespace}" get pods -l app.kubernetes.io/name=smoke -o wide --no-headers \
    | awk -v prefix="${POD_CIDR_PREFIX}" '$2 == "1/1" && $3 == "Running" && index($6, prefix) == 1 { print $7 "\t" $6 }' \
    > "${RUN_DIR}/loop-${loop_id}/smoke-pods.tsv"
}

run_loop() {
  local loop_id="$1"
  local loop_dir="${RUN_DIR}/loop-${loop_id}"

  mkdir -p "${loop_dir}"
  log "Starting loop ${loop_id}"

  {
    set -euo pipefail
    assert_cluster_shape
    reset_cluster
    ensure_cluster_running
    assert_cluster_shape
    dump_status "${loop_dir}/after-start"
    prepull_images
    install_cilium
    apply_migration_config
    recycle_cilium_pods
    assert_cni_files
    recycle_coredns
    wait_for_coredns
    deploy_smoke_daemonset "${loop_id}"
    assert_smoke_daemonset "${loop_id}"
    dump_status "${loop_dir}/after-smoke"
  } > "${loop_dir}/run.log" 2>&1
}

main() {
  local loop
  local successes=0
  local failures=0
  local summary_file="${RUN_DIR}/summary.tsv"

  printf 'loop\tresult\n' > "${summary_file}"

  log "Writing loop artifacts to ${RUN_DIR}"
  assert_cluster_shape

  for loop in $(seq -w 1 "${MAX_LOOPS}"); do
    if run_loop "${loop}"; then
      log "Loop ${loop} succeeded"
      printf '%s\tsuccess\n' "${loop}" >> "${summary_file}"
      successes=$((successes + 1))
    else
      log "Loop ${loop} failed; collecting diagnostics"
      printf '%s\tfailure\n' "${loop}" >> "${summary_file}"
      failures=$((failures + 1))
      dump_status "${RUN_DIR}/loop-${loop}/failure-diagnostics"
    fi
  done

  log "Completed ${MAX_LOOPS} loop(s): ${successes} success, ${failures} failure"
  log "Summary: ${summary_file}"

  if (( successes == 0 )); then
    return 1
  fi
}

main "$@"
