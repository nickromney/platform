#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export SCRIPT="${REPO_ROOT}/scripts/fmt-hcl.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN}"
}

@test "fmt-hcl fails when neither tofu nor terraform is installed" {
  cat >"${TEST_BIN}/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-C" && "${3:-}" == "ls-files" ]]; then
  printf '%s\0' terraform/root.hcl terraform/kubernetes/main.tf
  exit 0
fi
if [[ "${1:-}" == "-C" && "${3:-}" == "rev-parse" ]]; then
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/git"

  run env \
    PATH="${TEST_BIN}:/usr/bin:/bin" \
    GIT_BIN=git \
    /bin/bash "${SCRIPT}" --execute

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"FAIL neither tofu nor terraform was found in PATH"* ]]
}

@test "fmt-hcl runs tofu and terraform over tracked HCL files" {
  log_file="${BATS_TEST_TMPDIR}/fmt-hcl.log"

  cat >"${TEST_BIN}/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-C" && "${3:-}" == "ls-files" ]]; then
  printf '%s\0' terraform/root.hcl terraform/kubernetes/main.tf kubernetes/lima/stages/900-sso.tfvars
  exit 0
fi
if [[ "${1:-}" == "-C" && "${3:-}" == "rev-parse" ]]; then
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/git"

  cat >"${TEST_BIN}/tofu" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "version" ]]; then
  printf 'OpenTofu v1.9.0\n'
  exit 0
fi
printf 'tofu %s\n' "\$*" >>"${log_file}"
EOF
  chmod +x "${TEST_BIN}/tofu"

  cat >"${TEST_BIN}/terraform" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "version" ]]; then
  printf 'Terraform v1.11.0\n'
  exit 0
fi
printf 'terraform %s\n' "\$*" >>"${log_file}"
EOF
  chmod +x "${TEST_BIN}/terraform"

  run env \
    PATH="${TEST_BIN}:/usr/bin:/bin" \
    GIT_BIN=git \
    /bin/bash "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"INFO skipping 1 generic HCL file(s) unsupported by tofu/terraform fmt"* ]]
  [[ "${output}" == *"OpenTofu v1.9.0"* ]]
  [[ "${output}" == *"Terraform v1.11.0"* ]]

  run cat "${log_file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"tofu fmt terraform/kubernetes/main.tf kubernetes/lima/stages/900-sso.tfvars"* ]]
  [[ "${output}" == *"terraform fmt terraform/kubernetes/main.tf kubernetes/lima/stages/900-sso.tfvars"* ]]
}
