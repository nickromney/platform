#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export SCRIPT="${REPO_ROOT}/kubernetes/scripts/reconcile-kubeconfig.sh"
}

@test "kind lima and lima delegate default kubeconfig reconciliation to the shared helper" {
  run grep -F 'kubernetes/scripts/reconcile-kubeconfig.sh' \
    "${REPO_ROOT}/kubernetes/kind/scripts/ensure-kind-kubeconfig.sh" \
    "${REPO_ROOT}/kubernetes/lima/scripts/bootstrap-k3s-lima.sh" \
    "${REPO_ROOT}/kubernetes/lima/scripts/bootstrap-k3s-lima.sh"

  [ "${status}" -eq 0 ]
}

@test "shared kubeconfig reconciler merges through manage-kubeconfig helper" {
  helper="${BATS_TEST_TMPDIR}/manage-kubeconfig.sh"
  log="${BATS_TEST_TMPDIR}/helper.log"
  cat >"${helper}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${HELPER_LOG}"
EOF
  chmod +x "${helper}"

  run env HELPER_LOG="${log}" "${SCRIPT}" \
    --execute \
    --source-kubeconfig "${BATS_TEST_TMPDIR}/source.yaml" \
    --target-kubeconfig "${BATS_TEST_TMPDIR}/target.yaml" \
    --context "limavm-k3s" \
    --merge "1" \
    --helper "${helper}"

  [ "${status}" -eq 0 ]
  run grep -F -- "--execute --action merge --source-kubeconfig ${BATS_TEST_TMPDIR}/source.yaml --target-kubeconfig ${BATS_TEST_TMPDIR}/target.yaml --context limavm-k3s" "${log}"
  [ "${status}" -eq 0 ]
}

@test "shared kubeconfig reconciler deletes repo context only when split mode sees a target kubeconfig" {
  helper="${BATS_TEST_TMPDIR}/manage-kubeconfig.sh"
  log="${BATS_TEST_TMPDIR}/helper.log"
  target="${BATS_TEST_TMPDIR}/config"
  touch "${target}"
  cat >"${helper}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${HELPER_LOG}"
EOF
  chmod +x "${helper}"

  run env HELPER_LOG="${log}" "${SCRIPT}" \
    --execute \
    --source-kubeconfig "${BATS_TEST_TMPDIR}/source.yaml" \
    --target-kubeconfig "${target}" \
    --context "lima-k3s" \
    --merge "0" \
    --helper "${helper}"

  [ "${status}" -eq 0 ]
  run grep -F -- "--execute --action ensure-valid --kubeconfig ${target}" "${log}"
  [ "${status}" -eq 0 ]
  run grep -F -- "--execute --action delete-context --kubeconfig ${target} --context lima-k3s --cluster lima-k3s --user lima-k3s" "${log}"
  [ "${status}" -eq 0 ]
}
