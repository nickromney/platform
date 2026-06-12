#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "kubernetes launchpad-render targets delegate through the shared adapter" {
  for runtime in kind lima slicer; do
    run make -n -C "${REPO_ROOT}/kubernetes/${runtime}" launchpad-render

    [ "${status}" -eq 0 ]
    [[ "${output}" == *'kubernetes/scripts/render-launchpad.sh" --execute --stack-dir'* ]]
    [[ "${output}" == *'terraform/kubernetes'* ]]

    run make -n -C "${REPO_ROOT}/kubernetes/${runtime}" launchpad-render DRY_RUN=1

    [ "${status}" -eq 0 ]
    [[ "${output}" == *'kubernetes/scripts/render-launchpad.sh" --dry-run --stack-dir'* ]]
  done
}

@test "render-launchpad adapter forwards mode, STACK_DIR, and repeated targets" {
  stack_dir="${BATS_TEST_TMPDIR}/stub-stack"
  render_log="${BATS_TEST_TMPDIR}/render.log"
  mkdir -p "${stack_dir}/scripts"
  cat >"${stack_dir}/scripts/render-platform-launchpad.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
{
  printf 'STACK_DIR=%s\n' "${STACK_DIR:-}"
  printf 'ARGC=%s\n' "$#"
  index=0
  for arg in "$@"; do
    printf 'ARG_%s=%s\n' "${index}" "${arg}"
    index=$((index + 1))
  done
} >"${RENDER_LOG}"
EOF
  chmod +x "${stack_dir}/scripts/render-platform-launchpad.sh"

  run env RENDER_LOG="${render_log}" \
    "${REPO_ROOT}/kubernetes/scripts/render-launchpad.sh" \
    --execute \
    --stack-dir "${stack_dir}" \
    --target "${BATS_TEST_TMPDIR}/grafana.yaml" \
    --target "${BATS_TEST_TMPDIR}/observability.tf"

  [ "${status}" -eq 0 ]
  run grep -Fx "STACK_DIR=${stack_dir}" "${render_log}"
  [ "${status}" -eq 0 ]
  run grep -Fx "ARGC=5" "${render_log}"
  [ "${status}" -eq 0 ]
  run grep -Fx "ARG_0=--execute" "${render_log}"
  [ "${status}" -eq 0 ]
  run grep -Fx "ARG_1=--target" "${render_log}"
  [ "${status}" -eq 0 ]
  run grep -Fx "ARG_2=${BATS_TEST_TMPDIR}/grafana.yaml" "${render_log}"
  [ "${status}" -eq 0 ]
  run grep -Fx "ARG_3=--target" "${render_log}"
  [ "${status}" -eq 0 ]
  run grep -Fx "ARG_4=${BATS_TEST_TMPDIR}/observability.tf" "${render_log}"
  [ "${status}" -eq 0 ]
}
