#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "lima host gateway proxy targets call the shared proxy adapter directly" {
  run make -n -C "${REPO_ROOT}/kubernetes/lima" ensure-host-gateway-proxy

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'VARIANT_LABEL="Lima"'* ]]
  [[ "${output}" == *'CONTAINER_NAME="limavm-platform-gateway-443"'* ]]
  [[ "${output}" == *'IMAGE_TAG="platform/lima-gateway-proxy:dev"'* ]]
  [[ "${output}" == *'UPSTREAM_PORT="30070"'* ]]
  [[ "${output}" == *'kubernetes/scripts/host-gateway-proxy.sh" --action ensure --execute'* ]]
  [[ "${output}" != *'kubernetes/lima/scripts/host-gateway-proxy.sh'* ]]

  run make -n -C "${REPO_ROOT}/kubernetes/lima" stop-host-gateway-proxy

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'kubernetes/scripts/host-gateway-proxy.sh" --action stop --execute'* ]]
  [[ "${output}" != *'kubernetes/lima/scripts/host-gateway-proxy.sh'* ]]

  run make -n -C "${REPO_ROOT}/kubernetes/lima" proxy-status

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'kubernetes/scripts/host-gateway-proxy.sh" --action status --execute'* ]]
  [[ "${output}" != *'kubernetes/lima/scripts/host-gateway-proxy.sh'* ]]
}

@test "slicer host gateway proxy targets call the shared proxy adapter directly" {
  run make -n -C "${REPO_ROOT}/kubernetes/slicer" ensure-host-forwards

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'VARIANT_LABEL="Slicer"'* ]]
  [[ "${output}" == *'proxy_name="slicer-platform-gateway-443"'* ]]
  [[ "${output}" == *'proxy_image="platform/slicer-gateway-proxy:dev"'* ]]
  [[ "${output}" == *'CONTAINER_NAME="$proxy_name"'* ]]
  [[ "${output}" == *'IMAGE_TAG="$proxy_image"'* ]]
  [[ "${output}" == *'UPSTREAM_PORT="$gateway_forward_port"'* ]]
  [[ "${output}" == *'kubernetes/scripts/host-gateway-proxy.sh" --action ensure --execute'* ]]
  [[ "${output}" == *'kubernetes/scripts/host-gateway-proxy.sh" --action stop --execute'* ]]
  [[ "${output}" != *'kubernetes/slicer/scripts/host-gateway-proxy.sh'* ]]

  run make -n -C "${REPO_ROOT}/kubernetes/slicer" stop-host-forwards

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'kubernetes/scripts/host-gateway-proxy.sh" --action stop --execute'* ]]
  [[ "${output}" != *'kubernetes/slicer/scripts/host-gateway-proxy.sh'* ]]

  run make -n -C "${REPO_ROOT}/kubernetes/slicer" host-forward-status

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'kubernetes/scripts/host-gateway-proxy.sh" --action status --execute'* ]]
  [[ "${output}" != *'kubernetes/slicer/scripts/host-gateway-proxy.sh'* ]]
}
