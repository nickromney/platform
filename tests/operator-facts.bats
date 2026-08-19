#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/terraform/kubernetes/scripts/operator-facts.sh"
}

@test "operator facts last-wins across tfvars files" {
  dir="${BATS_TEST_TMPDIR}/tfvars"
  mkdir -p "${dir}"
  printf 'enable_sso = false\nplatform_base_domain = "first.example"\n' >"${dir}/a.tfvars"
  printf 'enable_sso = true\n' >"${dir}/b.tfvars"

  TFVARS_FILES=("${dir}/a.tfvars" "${dir}/b.tfvars")
  unset OPERATOR_FACTS_FILE || true
  operator_facts_load

  [ "$(operator_facts_get enable_sso)" = "true" ]
  [ "$(operator_facts_get platform_base_domain)" = "first.example" ]
  [ "$(operator_facts_bool enable_sso)" = "true" ]
}

@test "operator facts file wins over tfvars" {
  dir="${BATS_TEST_TMPDIR}/facts"
  mkdir -p "${dir}"
  printf 'enable_sso = false\n' >"${dir}/stage.tfvars"
  printf '{"enable_sso": true, "cluster_name": "from-json"}\n' >"${dir}/operator-facts.json"

  TFVARS_FILES=("${dir}/stage.tfvars")
  OPERATOR_FACTS_FILE="${dir}/operator-facts.json"
  operator_facts_load

  [ "$(operator_facts_get enable_sso)" = "true" ]
  [ "$(operator_facts_get cluster_name)" = "from-json" ]
}

@test "operator facts map get reads quoted HCL map entries" {
  dir="${BATS_TEST_TMPDIR}/maps"
  mkdir -p "${dir}"
  cat >"${dir}/images.tfvars" <<'EOF'
external_platform_image_refs = {
  "idp-core" = "host.docker.internal:5002/platform/idp-core:target"
  grafana = "dhi.io/grafana:ignored"
}
EOF

  [ "$(operator_facts_map_get "${dir}/images.tfvars" external_platform_image_refs idp-core missing)" = "host.docker.internal:5002/platform/idp-core:target" ]
  [ "$(operator_facts_map_get "${dir}/images.tfvars" external_platform_image_refs missing-key fallback)" = "fallback" ]
  [ "$(operator_facts_map_get "${dir}/absent.tfvars" external_platform_image_refs idp-core fallback)" = "fallback" ]
}

@test "terraform emits operator-facts.json from locals" {
  run grep -n 'resource "local_file" "operator_facts"' \
    "${REPO_ROOT}/terraform/kubernetes/operator-facts.tf"

  [ "${status}" -eq 0 ]

  run grep -n 'filename.*=.*operator-facts.json' \
    "${REPO_ROOT}/terraform/kubernetes/operator-facts.tf"

  [ "${status}" -eq 0 ]
}
