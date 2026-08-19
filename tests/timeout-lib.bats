#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
  export LIB="${REPO_ROOT}/scripts/lib/timeout.sh"
}

# GNU `timeout` is absent on stock macOS and on minimal Arch/Ubuntu images.
# Assuming it made kind/tests/check-version.bats skip on macOS rather than run,
# and #204 had to strip a bare `timeout` out of the Kind 900 apply path.

@test "run_with_timeout returns the command status when it finishes in time" {
  run bash -c "source '${LIB}'; run_with_timeout 5 true"

  [ "${status}" -eq 0 ]

  run bash -c "source '${LIB}'; run_with_timeout 5 sh -c 'exit 7'"

  [ "${status}" -eq 7 ]
}

@test "run_with_timeout returns 124 when the command outlives the budget" {
  # 124 is what coreutils returns, so callers branch on the status without
  # knowing which of the three implementations ran.
  run bash -c "source '${LIB}'; run_with_timeout 1 sleep 10"

  [ "${status}" -eq 124 ]
}

@test "the shell fallback behaves like coreutils when neither binary exists" {
  # The path that actually runs on a stock Mac. PATH is stripped to a shim
  # directory so `command -v timeout` and `gtimeout` both miss.
  shim="${BATS_TEST_TMPDIR}/shim"
  mkdir -p "${shim}"
  for tool in bash sh sleep date kill wait true; do
    target="$(command -v "${tool}" 2>/dev/null || true)"
    [ -n "${target}" ] || continue
    ln -sf "${target}" "${shim}/${tool}"
  done

  run env PATH="${shim}" bash -c "source '${LIB}'; timeout_implementation"

  [ "${status}" -eq 0 ]
  [ "${output}" = "shell-fallback" ]

  run env PATH="${shim}" bash -c "source '${LIB}'; run_with_timeout 1 sleep 10"

  [ "${status}" -eq 124 ]

  run env PATH="${shim}" bash -c "source '${LIB}'; run_with_timeout 5 sh -c 'exit 7'"

  [ "${status}" -eq 7 ]
}

@test "the k3s bootstrap lib keeps its old name as an alias over the shared wrapper" {
  # bootstrap-k3s-lima.sh still calls k3s_bootstrap_run_with_timeout.
  lib="${REPO_ROOT}/kubernetes/scripts/k3s-bootstrap-lib.sh"

  grep -Fq 'source "${K3S_BOOTSTRAP_LIB_DIR}/timeout.sh"' "${lib}"
  grep -Fq 'run_with_timeout "$@"' "${lib}"

  run bash -c "source '${lib}'; k3s_bootstrap_run_with_timeout 1 sleep 10"

  [ "${status}" -eq 124 ]
}
