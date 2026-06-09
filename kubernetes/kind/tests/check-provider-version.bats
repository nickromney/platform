#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/terraform/kubernetes/scripts/check-provider-version.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN}"
  export PATH="${TEST_BIN}:${PATH}"
}

@test "check-provider-version emits machine-readable JSON" {
  stack_dir="${BATS_TEST_TMPDIR}/stack"
  mkdir -p "${stack_dir}"

  cat >"${stack_dir}/.terraform.lock.hcl" <<'EOF'
provider "registry.opentofu.org/hashicorp/kubernetes" {
  version     = "3.0.1"
  constraints = "~> 3.0"
}

provider "registry.opentofu.org/hashicorp/null" {
  version     = "3.2.4"
  constraints = "~> 3.2"
}
EOF

  cat >"${TEST_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${*: -1}" in
  https://registry.opentofu.org/v1/providers/hashicorp/kubernetes/versions)
    printf '%s\n' '{"versions":[{"version":"3.0.1"},{"version":"3.1.0"}]}'
    ;;
  https://registry.opentofu.org/v1/providers/hashicorp/null/versions)
    printf '%s\n' '{"versions":[{"version":"3.2.4"}]}'
    ;;
  *)
    exit 1
    ;;
esac
EOF
  chmod +x "${TEST_BIN}/curl"

  run env STACK_DIR="${stack_dir}" CHECK_VERSION_FORMAT=json "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  json_output="${output}"

  run jq -r '.summary.outdated_count' <<<"${json_output}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "1" ]

  run jq -r '.providers[] | select(.provider == "hashicorp/kubernetes") | .status' <<<"${json_output}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "update available" ]
}

@test "check-provider-version reports failed registry lookups without unknown placeholders" {
  stack_dir="${BATS_TEST_TMPDIR}/stack"
  mkdir -p "${stack_dir}"

  cat >"${stack_dir}/.terraform.lock.hcl" <<'EOF'
provider "registry.opentofu.org/hashicorp/kubernetes" {
  version     = "3.0.1"
  constraints = "~> 3.0"
}
EOF

  cat >"${TEST_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
exit 22
EOF
  chmod +x "${TEST_BIN}/curl"

  run env STACK_DIR="${stack_dir}" CHECK_VERSION_FORMAT=json "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  json_output="${output}"

  run jq -r '[.providers[0].latest, .providers[0].status] | @tsv' <<<"${json_output}"
  [ "${status}" -eq 0 ]
  [ "${output}" = $'not reported\tregistry lookup failed' ]
}

@test "terraform kubernetes module pins provider constraints in config and lockfile" {
  run grep -Fn 'version = "~> 3.1"' "${REPO_ROOT}/terraform/kubernetes/main.tf"

  [ "${status}" -eq 0 ]

  for expected in \
    'version = "~> 2.4"' \
    'version = "~> 2.9"' \
    'version = "~> 3.3"' \
    'version = "~> 3.9"' \
    'version = "~> 4.3"'; do
    run grep -Fn "${expected}" "${REPO_ROOT}/terraform/kubernetes/main.tf"

    [ "${status}" -eq 0 ]
  done

  run grep -Fn 'version     = "3.2.0"' "${REPO_ROOT}/terraform/kubernetes/.terraform.lock.hcl"

  [ "${status}" -eq 0 ]

  run grep -Fn 'constraints = "~> 3.1"' "${REPO_ROOT}/terraform/kubernetes/.terraform.lock.hcl"

  [ "${status}" -eq 0 ]

  for expected in \
    'version     = "2.4.0"' \
    'constraints = "~> 2.4"' \
    'version     = "2.9.0"' \
    'constraints = "~> 2.9"' \
    'version     = "3.3.0"' \
    'constraints = "~> 3.3"' \
    'version     = "3.9.0"' \
    'constraints = "~> 3.9"' \
    'version     = "4.3.0"' \
    'constraints = "~> 4.3"'; do
    run grep -Fn "${expected}" "${REPO_ROOT}/terraform/kubernetes/.terraform.lock.hcl"

    [ "${status}" -eq 0 ]
  done
}
