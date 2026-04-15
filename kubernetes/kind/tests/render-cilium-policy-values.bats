#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/terraform/kubernetes/scripts/render-cilium-policy-values.sh"
  export TMPDIR_RENDER_CILIUM
  TMPDIR_RENDER_CILIUM="$(mktemp -d)"
}

teardown() {
  rm -rf "${TMPDIR_RENDER_CILIUM}"
}

@test "render-cilium-policy-values rewrites a single spec into a specs list" {
  run "${SCRIPT}" --execute "${REPO_ROOT}/terraform/kubernetes/cluster-policies/cilium/shared/shared-baseline.yaml"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *$'metadata:\n  name: shared-baseline'* ]]
  [[ "${output}" == *$'specs:\n  - description:'* ]]
  [[ "${output}" == *'port: "53"'* ]]
  [[ "${output}" != *$'\nkind:'* ]]
  [[ "${output}" != *$'\napiVersion:'* ]]
}

@test "render-cilium-policy-values supports list and wrap keys for multi-document input" {
  run "${SCRIPT}" --execute --list-key policies --wrap-key networkPolicy \
    "${REPO_ROOT}/terraform/kubernetes/cluster-policies/cilium/projects/sentiment/sentiment-runtime.yaml"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *$'networkPolicy:\n  policies:'* ]]
  [[ "${output}" == *'name: sentiment-router-ingress'* ]]
  [[ "${output}" == *'name: sentiment-backend-ingress'* ]]
  [[ "${output}" == *$'      specs:\n        - description:'* ]]
}

@test "render-cilium-policy-values writes one file per document with split-dir" {
  run "${SCRIPT}" --execute --split-dir "${TMPDIR_RENDER_CILIUM}" \
    "${REPO_ROOT}/terraform/kubernetes/cluster-policies/cilium/projects/subnetcalc/subnetcalc-runtime.yaml"

  [ "${status}" -eq 0 ]
  [ -f "${TMPDIR_RENDER_CILIUM}/01-subnetcalc-router-ingress.yaml" ]
  [ -f "${TMPDIR_RENDER_CILIUM}/02-subnetcalc-frontend-ingress.yaml" ]

  run sed -n '1,40p' "${TMPDIR_RENDER_CILIUM}/01-subnetcalc-router-ingress.yaml"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *$'metadata:\n  name: subnetcalc-router-ingress'* ]]
  [[ "${output}" == *$'specs:\n  - description:'* ]]
}

@test "render-cilium-policy-values can inject a namespace for namespaced policy input" {
  run "${SCRIPT}" --execute --set-namespace karpenter \
    "${REPO_ROOT}/terraform/kubernetes/cluster-policies/cilium/dev/overrides/subnetcalc-cloudflare-live-fetch.yaml"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *$'metadata:\n  name: subnetcalc-cloudflare-live-fetch\n  namespace: karpenter'* ]]
  [[ "${output}" == *$'specs:\n  - description:'* ]]
}

@test "render-cilium-policy-values rejects namespace injection for clusterwide input" {
  run "${SCRIPT}" --execute --set-namespace karpenter \
    "${REPO_ROOT}/terraform/kubernetes/cluster-policies/cilium/shared/shared-baseline.yaml"

  [ "${status}" -ne 0 ]
  [[ "${output}" == *'--set-namespace cannot be used with CiliumClusterwideNetworkPolicy input'* ]]
}

@test "observability source manifest renders to the checked-in category output" {
  local source_file
  local rendered_file
  local rendered_output

  source_file="${REPO_ROOT}/terraform/kubernetes/cluster-policies/cilium/cilium-module/sources/observability/cnp-observability-otel-collector-allow-otlp-from-app-workloads.yaml"
  rendered_file="${REPO_ROOT}/terraform/kubernetes/cluster-policies/cilium/cilium-module/categories/observability/cnp-observability-otel-collector-allow-otlp-from-app-workloads.yaml"
  rendered_output="${TMPDIR_RENDER_CILIUM}/observability-rendered.yaml"

  run "${SCRIPT}" --execute "${source_file}"

  [ "${status}" -eq 0 ]
  printf '%s\n' "${output}" > "${rendered_output}"

  run diff -u "${rendered_file}" "${rendered_output}"

  [ "${status}" -eq 0 ]
}
