#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export MODULE_ROOT="${REPO_ROOT}/terraform/kubernetes/cluster-policies/cilium/cilium-module"
  export RENDER_SCRIPT="${REPO_ROOT}/terraform/kubernetes/scripts/render-cilium-policy-values.sh"
  export TMPDIR_CILIUM_MODULE_RENDERERS
  TMPDIR_CILIUM_MODULE_RENDERERS="$(mktemp -d)"
}

teardown() {
  rm -rf "${TMPDIR_CILIUM_MODULE_RENDERERS}"
}

@test "render-category.sh renders observability into the checked-in category output" {
  local source_file
  local rendered_file
  local rendered_output

  source_file="${MODULE_ROOT}/sources/observability/cnp-observability-otel-collector-allow-otlp-from-app-workloads.yaml"
  rendered_file="${MODULE_ROOT}/categories/observability/cnp-observability-otel-collector-allow-otlp-from-app-workloads.yaml"
  rendered_output="${TMPDIR_CILIUM_MODULE_RENDERERS}/helper-rendered.yaml"

  run "${MODULE_ROOT}/render-category.sh" observability

  [ "${status}" -eq 0 ]

  run "${RENDER_SCRIPT}" "${source_file}"

  [ "${status}" -eq 0 ]
  printf '%s\n' "${output}" > "${rendered_output}"

  run diff -u "${rendered_file}" "${rendered_output}"

  [ "${status}" -eq 0 ]
}

@test "observability render.sh delegates cleanly to the shared renderer" {
  local source_file
  local rendered_file
  local rendered_output

  source_file="${MODULE_ROOT}/sources/observability/cnp-observability-otel-collector-allow-otlp-from-app-workloads.yaml"
  rendered_file="${MODULE_ROOT}/categories/observability/cnp-observability-otel-collector-allow-otlp-from-app-workloads.yaml"
  rendered_output="${TMPDIR_CILIUM_MODULE_RENDERERS}/wrapper-rendered.yaml"

  run "${MODULE_ROOT}/sources/observability/render.sh"

  [ "${status}" -eq 0 ]

  run "${RENDER_SCRIPT}" "${source_file}"

  [ "${status}" -eq 0 ]
  printf '%s\n' "${output}" > "${rendered_output}"

  run diff -u "${rendered_file}" "${rendered_output}"

  [ "${status}" -eq 0 ]
}
