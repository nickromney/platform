#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
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
  local cache_dir="${BATS_TEST_TMPDIR}/cache"
  mkdir -p "${stack_dir}" "${stub_bin}" "${cache_dir}"

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
# Records observed concurrency instead of leaning on wall-clock. The previous
# version asserted an elapsed band (>=4s and <6s) derived from 3 providers at
# concurrency 2 with a 2s sleep. Load inflates every one of those landmarks, so
# under `make test-ci BATS_JOBS=auto` the test failed for the machine being busy
# rather than for the code being wrong -- and no widening of the band fixes that,
# because loaded-bounded and idle-serial overlap.
#
# Each invocation registers a marker for its lifetime and logs how many markers
# exist while it holds one. The peak of that log is the concurrency actually
# reached, which is the property under test and is independent of how fast the
# box happens to be.
marker_dir="${FAKE_CURL_MARKER_DIR:?}"
mkdir -p "${marker_dir}"
marker="${marker_dir}/$$"
: >"${marker}"
ls -1 "${marker_dir}" | wc -l | tr -d ' ' >>"${FAKE_CURL_CONCURRENCY_LOG:?}"
sleep 2
rm -f "${marker}"
case "$*" in
  *"/hashicorp/aws/versions"*) printf '%s\n' '{"versions":[{"version":"1.0.1"}]}' ;;
  *"/hashicorp/azurerm/versions"*) printf '%s\n' '{"versions":[{"version":"1.0.1"}]}' ;;
  *"/hashicorp/random/versions"*) printf '%s\n' '{"versions":[{"version":"1.0.1"}]}' ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "${stub_bin}/curl"

  # Output goes to BATS_TEST_TMPDIR, not a fixed /tmp path. The old fixed path
  # meant two concurrent runs of this file clobbered each other's output.
  local out_file="${BATS_TEST_TMPDIR}/check-provider-version.out"
  local marker_dir="${BATS_TEST_TMPDIR}/curl-markers"
  local concurrency_log="${BATS_TEST_TMPDIR}/curl-concurrency"
  : >"${concurrency_log}"

  run bash -lc "export STACK_DIR='${stack_dir}' CHECK_PROVIDER_VERSION_CACHE_DIR='${cache_dir}' PLATFORM_PARALLEL_JOBS=2 FAKE_CURL_MARKER_DIR='${marker_dir}' FAKE_CURL_CONCURRENCY_LOG='${concurrency_log}' PATH='${stub_bin}:'\"\$PATH\"; '${SCRIPT}' --execute >'${out_file}'; cat '${out_file}'"

  [ "${status}" -eq 0 ]
  [[ "${output}" =~ hashicorp/aws ]]
  [[ "${output}" =~ hashicorp/azurerm ]]
  [[ "${output}" =~ hashicorp/random ]]
  # The property, stated directly: fetches ran concurrently (peak > 1) but were
  # capped at PLATFORM_PARALLEL_JOBS (peak <= 2). Serial execution peaks at 1;
  # unbounded execution peaks at 3, the provider count.
  local peak
  peak="$(sort -n "${concurrency_log}" | tail -n 1)"
  [ -n "${peak}" ]
  [ "${peak}" -gt 1 ]
  [ "${peak}" -le 2 ]
}
