#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export SCRIPT="${REPO_ROOT}/terraform/kubernetes/scripts/run-opentofu-tests.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN}"
}

@test "OpenTofu runner initializes module and runs optional filtered test with split kubeconfig defaults" {
  module_dir="${BATS_TEST_TMPDIR}/module"
  mkdir -p "${module_dir}"
  log_file="${BATS_TEST_TMPDIR}/tofu.log"
  kubeconfig="${BATS_TEST_TMPDIR}/kind-kind-local.yaml"

  cat >"${TEST_BIN}/tofu" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'args:%s\n' "\$*" >>"${log_file}"
printf 'env:KUBECONFIG=%s TF_VAR_kubeconfig_path=%s TF_VAR_kubeconfig_context=%s\n' "\${KUBECONFIG:-}" "\${TF_VAR_kubeconfig_path:-}" "\${TF_VAR_kubeconfig_context:-}" >>"${log_file}"
EOF
  chmod +x "${TEST_BIN}/tofu"

  run env \
    PATH="${TEST_BIN}:/usr/bin:/bin" \
    KUBECONFIG_PATH="${kubeconfig}" \
    KUBECONFIG_CONTEXT="kind-kind-local" \
    /bin/bash "${SCRIPT}" --execute \
      --module-dir "${module_dir}" \
      --filter "tests/gitops_features.tftest.hcl" \
      --timeout-seconds 9

  [ "${status}" -eq 0 ]

  run cat "${log_file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"args:-chdir=${module_dir} init -backend=false -input=false"* ]]
  [[ "${output}" == *"args:-chdir=${module_dir} test -filter=tests/gitops_features.tftest.hcl"* ]]
  [[ "${output}" == *"env:KUBECONFIG=${kubeconfig} TF_VAR_kubeconfig_path=${kubeconfig} TF_VAR_kubeconfig_context=kind-kind-local"* ]]
}

@test "OpenTofu runner can use Terraform-compatible CLI binary" {
  module_dir="${BATS_TEST_TMPDIR}/module"
  mkdir -p "${module_dir}"
  log_file="${BATS_TEST_TMPDIR}/terraform.log"

  cat >"${TEST_BIN}/terraform" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'terraform:%s\n' "\$*" >>"${log_file}"
EOF
  chmod +x "${TEST_BIN}/terraform"

  run env PATH="${TEST_BIN}:/usr/bin:/bin" /bin/bash "${SCRIPT}" --execute \
    --module-dir "${module_dir}" \
    --binary terraform \
    --timeout-seconds 9

  [ "${status}" -eq 0 ]

  run cat "${log_file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"terraform:-chdir=${module_dir} init -backend=false -input=false"* ]]
  [[ "${output}" == *"terraform:-chdir=${module_dir} test"* ]]
}

@test "OpenTofu runner adds Terraform 1.15 validation before tests" {
  module_dir="${BATS_TEST_TMPDIR}/module"
  mkdir -p "${module_dir}"
  log_file="${BATS_TEST_TMPDIR}/terraform-1-15.log"

  cat >"${TEST_BIN}/terraform" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$*" == "version" ]]; then
  printf 'Terraform v1.15.0\n'
  exit 0
fi
printf 'terraform:%s\n' "\$*" >>"${log_file}"
EOF
  chmod +x "${TEST_BIN}/terraform"

  run env PATH="${TEST_BIN}:/usr/bin:/bin" /bin/bash "${SCRIPT}" --execute \
    --module-dir "${module_dir}" \
    --binary terraform \
    --timeout-seconds 9

  [ "${status}" -eq 0 ]

  run cat "${log_file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"terraform:-chdir=${module_dir} init -backend=false -input=false"* ]]
  [[ "${output}" == *"terraform:-chdir=${module_dir} validate"* ]]
  [[ "${output}" == *"terraform:-chdir=${module_dir} test"* ]]
}

@test "OpenTofu runner adds OpenTofu 1.12 validation before tests" {
  module_dir="${BATS_TEST_TMPDIR}/module"
  mkdir -p "${module_dir}"
  log_file="${BATS_TEST_TMPDIR}/opentofu-1-12.log"

  cat >"${TEST_BIN}/tofu" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$*" == "version" ]]; then
  printf 'OpenTofu v1.12.0-rc1\n'
  exit 0
fi
printf 'tofu:%s\n' "\$*" >>"${log_file}"
EOF
  chmod +x "${TEST_BIN}/tofu"

  run env PATH="${TEST_BIN}:/usr/bin:/bin" /bin/bash "${SCRIPT}" --execute \
    --module-dir "${module_dir}" \
    --timeout-seconds 9

  [ "${status}" -eq 0 ]

  run cat "${log_file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"tofu:-chdir=${module_dir} init -backend=false -input=false"* ]]
  [[ "${output}" == *"tofu:-chdir=${module_dir} validate"* ]]
  [[ "${output}" == *"tofu:-chdir=${module_dir} test"* ]]
}

@test "OpenTofu runner can capture OpenTofu 1.12 JSON logs without losing human output" {
  module_dir="${BATS_TEST_TMPDIR}/module"
  json_log_dir="${BATS_TEST_TMPDIR}/json-logs"
  mkdir -p "${module_dir}"
  log_file="${BATS_TEST_TMPDIR}/opentofu-json.log"

  cat >"${TEST_BIN}/tofu" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$*" == "version" ]]; then
  printf 'OpenTofu v1.12.0-rc1\n'
  exit 0
fi
printf 'tofu:%s\n' "\$*" >>"${log_file}"
EOF
  chmod +x "${TEST_BIN}/tofu"

  run env PATH="${TEST_BIN}:/usr/bin:/bin" /bin/bash "${SCRIPT}" --execute \
    --module-dir "${module_dir}" \
    --json-log-dir "${json_log_dir}" \
    --timeout-seconds 9

  [ "${status}" -eq 0 ]
  [ -d "${json_log_dir}" ]

  run cat "${log_file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"tofu:-chdir=${module_dir} init -backend=false -input=false -json-into=${json_log_dir}/init.jsonl"* ]]
  [[ "${output}" == *"tofu:-chdir=${module_dir} validate -json-into=${json_log_dir}/validate.jsonl"* ]]
  [[ "${output}" == *"tofu:-chdir=${module_dir} test -json-into=${json_log_dir}/test.jsonl"* ]]
}

@test "OpenTofu runner does not pass OpenTofu JSON log flags to Terraform" {
  module_dir="${BATS_TEST_TMPDIR}/module"
  json_log_dir="${BATS_TEST_TMPDIR}/terraform-json-logs"
  mkdir -p "${module_dir}"
  log_file="${BATS_TEST_TMPDIR}/terraform-json.log"

  cat >"${TEST_BIN}/terraform" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$*" == "version" ]]; then
  printf 'Terraform v1.15.0\n'
  exit 0
fi
printf 'terraform:%s\n' "\$*" >>"${log_file}"
EOF
  chmod +x "${TEST_BIN}/terraform"

  run env PATH="${TEST_BIN}:/usr/bin:/bin" /bin/bash "${SCRIPT}" --execute \
    --module-dir "${module_dir}" \
    --binary terraform \
    --json-log-dir "${json_log_dir}" \
    --timeout-seconds 9

  [ "${status}" -eq 0 ]

  run cat "${log_file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"terraform:-chdir=${module_dir} validate"* ]]
  [[ "${output}" != *"-json-into="* ]]
}
