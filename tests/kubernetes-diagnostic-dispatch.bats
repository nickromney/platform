#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "check-health delegates through the shared diagnostic dispatch module with variant contracts" {
  for variant in kind lima slicer; do
    run make -n -C "${REPO_ROOT}/kubernetes/${variant}" check-health STAGE=900

    [ "${status}" -eq 0 ]
    [[ "${output}" == *'kubernetes/scripts/run-diagnostic-check.sh" --execute'* ]]
    [[ "${output}" == *"--variant-json \"${REPO_ROOT}/kubernetes/variants/${variant}/variant.json\""* ]]
    [[ "${output}" == *'--action check-health'* ]]
    [[ "${output}" == *'--stage "900"'* ]]
  done
}

@test "show-urls delegates through the shared diagnostic dispatch module with variant contracts" {
  for variant in kind lima slicer; do
    run make -n -C "${REPO_ROOT}/kubernetes/${variant}" show-urls STAGE=900

    [ "${status}" -eq 0 ]
    [[ "${output}" == *'kubernetes/scripts/run-diagnostic-check.sh" --execute'* ]]
    [[ "${output}" == *"--variant-json \"${REPO_ROOT}/kubernetes/variants/${variant}/variant.json\""* ]]
    [[ "${output}" == *'--action show-urls'* ]]
    [[ "${output}" == *'--stage "900"'* ]]
  done
}

@test "diagnostic dispatch reads cluster access from the variant contract" {
  stack_dir="${BATS_TEST_TMPDIR}/stack"
  home_dir="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${stack_dir}/scripts" "${home_dir}"
  cat >"${stack_dir}/scripts/check-cluster-health.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'mode=%s\n' "${1:-}"
shift || true
printf 'kubeconfig=%s\n' "${KUBECONFIG:-}"
printf 'context=%s\n' "${KUBECONFIG_CONTEXT:-}"
printf 'args=%s\n' "$*"
EOF
  chmod +x "${stack_dir}/scripts/check-cluster-health.sh"

  run env HOME="${home_dir}" \
    "${REPO_ROOT}/kubernetes/scripts/run-diagnostic-check.sh" --execute \
      --variant-json "${REPO_ROOT}/kubernetes/variants/kind/variant.json" \
      --action check-health \
      --stage 900 \
      --stack-dir "${stack_dir}" \
      --var-file first.tfvars \
      --var-file second.tfvars

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"mode=--execute"* ]]
  [[ "${output}" == *"kubeconfig=${home_dir}/.kube/kind-kind-local.yaml"* ]]
  [[ "${output}" == *"context=kind-kind-local"* ]]
  [[ "${output}" == *"args=--var-file first.tfvars --var-file second.tfvars"* ]]
}

@test "diagnostic dispatch maps show-urls to the cluster health URL mode" {
  stack_dir="${BATS_TEST_TMPDIR}/stack"
  home_dir="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${stack_dir}/scripts" "${home_dir}"
  cat >"${stack_dir}/scripts/check-cluster-health.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'mode=%s\n' "${1:-}"
shift || true
printf 'kubeconfig=%s\n' "${KUBECONFIG:-}"
printf 'context=%s\n' "${KUBECONFIG_CONTEXT:-}"
printf 'args=%s\n' "$*"
EOF
  chmod +x "${stack_dir}/scripts/check-cluster-health.sh"

  run env HOME="${home_dir}" \
    "${REPO_ROOT}/kubernetes/scripts/run-diagnostic-check.sh" --execute \
      --variant-json "${REPO_ROOT}/kubernetes/variants/lima/variant.json" \
      --action show-urls \
      --stage 900 \
      --stack-dir "${stack_dir}" \
      --var-file target.tfvars

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"mode=--execute"* ]]
  [[ "${output}" == *"kubeconfig=${home_dir}/.kube/limavm-k3s.yaml"* ]]
  [[ "${output}" == *"context=limavm-k3s"* ]]
  [[ "${output}" == *"args=--show-urls --var-file target.tfvars"* ]]
}
