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

@test "the fallback kills exactly at the budget tick without a grace sleep" {
  # Mutation triage target: timeout.sh's expiry check is `-ge`. A `-gt` mutant
  # must not pass, so the first poll lands on elapsed == seconds exactly: the
  # real code kills immediately, the mutant takes one more loop turn. The
  # difference is asserted via a stub sleep's call log, never wall-clock.
  shim="${BATS_TEST_TMPDIR}/shim-boundary"
  state="${BATS_TEST_TMPDIR}/state"
  mkdir -p "${shim}" "${state}"
  # Only tools that stay real get symlinks; date and sleep are replaced by
  # stubs below, and linking them first would make the heredoc write through
  # the symlink into the system binary.
  for tool in bash sh tail; do
    target="$(command -v "${tool}" 2>/dev/null || true)"
    [ -n "${target}" ] || continue
    ln -sf "${target}" "${shim}/${tool}"
  done

  # The stub must use shell builtins only: the stripped PATH it runs under
  # has no cat/awk, and any external dependency silently resets the counter
  # and busy-loops the fallback.
  cat >"${shim}/date" <<'STUB'
#!/bin/sh
f="${SHIM_STATE}/date-count"
n=0
if [ -r "${f}" ]; then
  read -r n <"${f}"
fi
n=$((n + 1))
printf '%s\n' "${n}" >"${f}"
if [ "${n}" -eq 1 ]; then
  echo 1000
elif [ "${n}" -eq 2 ]; then
  echo 1003
else
  echo 1004
fi
STUB
  chmod +x "${shim}/date"

  cat >"${shim}/sleep" <<'STUB'
#!/bin/sh
printf '%s\n' "$@" >>"${SHIM_STATE}/sleep-calls"
STUB
  chmod +x "${shim}/sleep"

  run env PATH="${shim}" SHIM_STATE="${state}" \
    bash -c "source '${LIB}'; run_with_timeout 3 tail -f /dev/null"

  [ "${status}" -eq 124 ]
  [ ! -s "${state}/sleep-calls" ]
}

# Accepted equivalent mutants (documented, not killed): the `|| true` guards
# on kill/wait inside the fallback's expiry branch (timeout.sh:41-42). Their
# LOGICAL_AND_OR and BOOLEAN_LITERAL mutants differ only when kill or wait
# fails mid-expiry. Both are shell builtins, so PATH shims cannot reach them;
# manufacturing their failure needs a race between kill -0 and signal
# delivery whose failure mode hangs the ORIGINAL code too. No honest oracle
# distinguishes them, so they are recorded as accepted survivors instead of
# being "killed" with a flaky or self-hanging test.

@test "the k3s bootstrap lib keeps its old name as an alias over the shared wrapper" {
  # bootstrap-k3s-lima.sh still calls k3s_bootstrap_run_with_timeout.
  lib="${REPO_ROOT}/kubernetes/scripts/k3s-bootstrap-lib.sh"

  grep -Fq 'source "${K3S_BOOTSTRAP_LIB_DIR}/timeout.sh"' "${lib}"
  grep -Fq 'run_with_timeout "$@"' "${lib}"

  run bash -c "source '${lib}'; k3s_bootstrap_run_with_timeout 1 sleep 10"

  [ "${status}" -eq 124 ]
}
