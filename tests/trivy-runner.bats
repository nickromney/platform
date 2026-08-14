#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export TEST_TMPDIR
  TEST_TMPDIR="$(mktemp -d)"
  export ORIGINAL_PATH="${PATH}"
  export TRIVY_CACHE_DIR="${TEST_TMPDIR}/trivy-cache"
  export PATH="${TEST_TMPDIR}/bin:${ORIGINAL_PATH}"
  mkdir -p "${TEST_TMPDIR}/bin"
}

teardown() {
  rm -rf "${TEST_TMPDIR}"
}

write_fake_trivy() {
  local version="$1"

  cat > "${TEST_TMPDIR}/bin/trivy" <<EOF
#!/usr/bin/env bash
set -euo pipefail

if [[ "\${1:-}" == "--version" ]]; then
  printf 'Version: %s\n' "${version}"
  exit 0
fi

printf 'local:%s\n' "\$*"
EOF
  chmod +x "${TEST_TMPDIR}/bin/trivy"
}

write_fake_docker() {
  :
}

# The "missing trivy" cases below must not depend on the host happening to lack
# trivy. setup() prepends the sandbox bin dir to the real PATH, so a trivy
# installed anywhere else (mise, for instance) still resolves and those tests
# fail on a developer machine while passing in CI. Drop every PATH entry that
# provides a trivy so the sandbox is the only possible source.
hide_host_trivy() {
  local filtered="" dir
  local IFS=":"

  for dir in ${ORIGINAL_PATH}; do
    [[ -n "${dir}" ]] || continue
    [[ -x "${dir}/trivy" ]] && continue
    filtered="${filtered:+${filtered}:}${dir}"
  done

  export PATH="${TEST_TMPDIR}/bin:${filtered}"
}

@test "trivy-run uses the local binary when it is available" {
  write_fake_trivy "0.70.0"

  run "${REPO_ROOT}/scripts/trivy-run.sh" --execute -- fs apps/sentiment

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"local:--cache-dir ${TRIVY_CACHE_DIR} fs apps/sentiment"* ]]
}

@test "trivy-run fails cleanly when local trivy is missing" {
  hide_host_trivy

  run "${REPO_ROOT}/scripts/trivy-run.sh" --execute -- fs apps/sentiment

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"local trivy is not available"* ]]
}

@test "trivy-scan-apps prereqs reports unavailable mode when local trivy is missing" {
  hide_host_trivy

  run "${REPO_ROOT}/scripts/trivy-scan-apps.sh" --mode prereqs --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Runner mode: unavailable"* ]]
  [[ "${output}" == *"Scanning is optional."* ]]
}

@test "trivy wrappers support dry-run summaries" {
  run "${REPO_ROOT}/scripts/trivy-run.sh" --dry-run -- fs apps/sentiment

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"INFO dry-run: trivy --cache-dir ${TRIVY_CACHE_DIR} fs apps/sentiment"* ]]

  run "${REPO_ROOT}/scripts/trivy-scan-apps.sh" --mode images --dry-run

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"INFO dry-run: would run Trivy app scan in images mode"* ]]
}

@test "devcontainer assets do not install or reference trivy" {
  for file in \
    "${REPO_ROOT}/.devcontainer/install-toolchain.sh" \
    "${REPO_ROOT}/.devcontainer/Dockerfile"; do
    run grep -in "trivy" "${file}"
    [ "${status}" -eq 1 ]
  done
}

@test "trivy report summaries avoid unknown placeholders for sparse fields" {
  run rg -n '// "unknown"|// "UNKNOWN"|order\[[0-9]+\] = "UNKNOWN"' "${REPO_ROOT}/scripts/trivy-scan-apps.sh"

  [ "${status}" -ne 0 ]

  run rg -n 'target not reported|severity not reported|finding id not reported' "${REPO_ROOT}/scripts/trivy-scan-apps.sh"
  [ "${status}" -eq 0 ]
}
