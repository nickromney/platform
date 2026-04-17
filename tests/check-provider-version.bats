#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export SCRIPT="${REPO_ROOT}/terraform/kubernetes/scripts/check-provider-version.sh"
}

@test "check-provider-version caches provider version payloads by source" {
  local stub_bin="${BATS_TEST_TMPDIR}/bin"
  local call_counter="${BATS_TEST_TMPDIR}/curl-count"
  local cache_dir="${BATS_TEST_TMPDIR}/cache"
  mkdir -p "${stub_bin}" "${cache_dir}"

  cat >"${stub_bin}/curl" <<'EOF'
#!/usr/bin/env bash
count_file="${CHECK_PROVIDER_VERSION_TEST_CURL_COUNT_FILE:?}"
count=0
if [ -f "${count_file}" ]; then
  count="$(cat "${count_file}")"
fi
printf '%s\n' "$((count + 1))" >"${count_file}"
printf '%s\n' '{"versions":[{"version":"1.2.3"}]}'
EOF
  chmod +x "${stub_bin}/curl"

  run bash -lc "export CHECK_PROVIDER_VERSION_LIB_ONLY=1 CHECK_PROVIDER_VERSION_CACHE_DIR='${cache_dir}' CHECK_PROVIDER_VERSION_TEST_CURL_COUNT_FILE='${call_counter}' PATH='${stub_bin}:'\"\$PATH\"; source '${SCRIPT}'; printf '%s\n--\n%s\n' \"\$(latest_registry_version 'registry.terraform.io/hashicorp/aws')\" \"\$(latest_registry_version 'registry.terraform.io/hashicorp/aws')\""

  [ "${status}" -eq 0 ]
  [ "$(cat "${call_counter}")" = "1" ]
  [ "${output}" = "$(printf '1.2.3\n--\n1.2.3')" ]
}

@test "check-provider-version fetches provider versions with bounded concurrency" {
  local stack_dir="${BATS_TEST_TMPDIR}/stack"
  local stub_bin="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${stack_dir}" "${stub_bin}"

  cat >"${stack_dir}/.terraform.lock.hcl" <<'EOF'
provider "registry.terraform.io/hashicorp/aws" {
  version     = "1.0.0"
  constraints = ">= 1.0.0"
}

provider "registry.terraform.io/hashicorp/azurerm" {
  version     = "1.0.0"
  constraints = ">= 1.0.0"
}

provider "registry.terraform.io/hashicorp/random" {
  version     = "1.0.0"
  constraints = ">= 1.0.0"
}
EOF

  cat >"${stub_bin}/curl" <<'EOF'
#!/usr/bin/env bash
sleep 1
case "$*" in
  *"/hashicorp/aws/versions"*) printf '%s\n' '{"versions":[{"version":"1.0.1"}]}' ;;
  *"/hashicorp/azurerm/versions"*) printf '%s\n' '{"versions":[{"version":"1.0.1"}]}' ;;
  *"/hashicorp/random/versions"*) printf '%s\n' '{"versions":[{"version":"1.0.1"}]}' ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "${stub_bin}/curl"

  run bash -lc "export STACK_DIR='${stack_dir}' PLATFORM_PARALLEL_JOBS=2 PATH='${stub_bin}:'\"\$PATH\"; start=\$(date +%s); '${SCRIPT}' --execute >/tmp/check-provider-version.out; elapsed=\$(( \$(date +%s) - start )); cat /tmp/check-provider-version.out; printf 'elapsed=%s\n' \"\${elapsed}\" >&2"

  [ "${status}" -eq 0 ]
  [[ "${output}" =~ hashicorp/aws ]]
  [[ "${output}" =~ hashicorp/azurerm ]]
  [[ "${output}" =~ hashicorp/random ]]
  [[ "${stderr}${output}" =~ elapsed=2|elapsed=1 ]]
}
