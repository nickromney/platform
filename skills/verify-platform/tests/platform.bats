#!/usr/bin/env bats
# App-specific tests for the platform verification skill (the shared contract is in contract.bats).
# Runs under macOS /bin/bash 3.2. docker, lsof, make, bun, node and curl are stubs on PATH that only
# record their calls, so no case builds, starts containers, or touches a real compose project.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/control.sh"
  BASH32="${VERIFY_TEST_BASH:-/bin/bash}"
  export VERIFY_BASE_DIR="$BATS_TEST_TMPDIR/base"
  export VERIFY_EVIDENCE_ROOT="$BATS_TEST_TMPDIR/evidence"
  export VERIFY_RUN_ID="platform-run"
  export STUB_CALLS="$BATS_TEST_TMPDIR/stub-calls.log"
  STUBS="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$STUBS"
  cat > "$STUBS/docker" <<'STUB'
#!/bin/sh
echo "docker $*" >> "$STUB_CALLS"
if [ "$1" = compose ] && [ "$2" = ls ]; then printf '%s' "${STUB_COMPOSE_LS:-}"; fi
if [ "$1" = ps ]; then printf '%s\n' "${STUB_PS_OWNER:-}"; fi
if [ "$1" = compose ] && [ "$2" = -p ] && [ "$4" = ps ]; then printf '%s\n' "${STUB_SERVICES:-}"; fi
if [ "$1" = logs ]; then echo "log $2"; exit "${STUB_LOGS_RC:-0}"; fi
exit 0
STUB
  cat > "$STUBS/lsof" <<'STUB'
#!/bin/sh
echo "lsof $*" >> "$STUB_CALLS"
if [ -n "${STUB_LSOF_PID:-}" ]; then echo "$STUB_LSOF_PID"; exit 0; fi
exit 1
STUB
  cat > "$STUBS/make" <<'STUB'
#!/bin/sh
echo "make $*" >> "$STUB_CALLS"
exit "${STUB_MAKE_RC:-0}"
STUB
  cat > "$STUBS/curl" <<'STUB'
#!/bin/sh
echo "curl $*" >> "$STUB_CALLS"
case "$*" in
  *'%{redirect_url}'*) printf '%s' "${STUB_REDIRECT:-}"; exit 0 ;;
  *apim/health*) exit "${STUB_APIM_RC:-0}" ;;
esac
exit 0
STUB
  for tool in bun node; do
    cat > "$STUBS/$tool" <<'STUB'
#!/bin/sh
echo "$(basename "$0") $*" >> "$STUB_CALLS"
exit 0
STUB
  done
  chmod +x "$STUBS"/*
}

run_control() { run "$BASH32" "$SCRIPT" "$@"; }
use_stubs() { export PATH="$STUBS:$PATH"; }
assert_no_stub_call() {
  if [ -f "$STUB_CALLS" ] && grep -q -- "$1" "$STUB_CALLS"; then
    echo "stub call matched $1:"; cat "$STUB_CALLS"; return 1
  fi
}
assert_no_stub_calls() {
  if [ -s "$STUB_CALLS" ]; then echo "unexpected tool calls:"; cat "$STUB_CALLS"; return 1; fi
}

@test "doctor refuses and names the launch when this run did not launch a stack" {
  use_stubs
  run_control --execute doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: this run did not launch a stack"* ]]
  assert_no_stub_calls
}

@test "drive refuses when this run did not launch a stack" {
  use_stubs
  run_control --execute drive lookup 10.0.0.0/24
  [ "$status" -eq 1 ]
  [[ "$output" == *"no stack launched by run platform-run"* ]]
  assert_no_stub_calls
}

@test "cleanup when this run did not launch leaves compose alone (no docker or make call)" {
  use_stubs
  run_control --execute cleanup
  [ "$status" -eq 0 ]
  [[ "$output" == *"leaving any running compose project alone"* ]]
  assert_no_stub_calls
}

assert_no_run_artifacts() {
  # The shared claim may create roots; refusal must leave no run data or live claim.
  [ ! -e "$VERIFY_BASE_DIR/$VERIFY_RUN_ID" ]
  [ ! -e "$VERIFY_BASE_DIR/current" ]
  [ ! -e "$VERIFY_BASE_DIR/.verify-kit-owners/$VERIFY_RUN_ID" ]
  [ ! -d "$VERIFY_BASE_DIR" ] || [ -z "$(find "$VERIFY_BASE_DIR" -mindepth 1 ! -path "$VERIFY_BASE_DIR/.verify-kit-owners" -print -quit)" ]
  [ ! -d "$VERIFY_EVIDENCE_ROOT" ] || [ -z "$(find "$VERIFY_EVIDENCE_ROOT" -mindepth 1 -print -quit)" ]
}

@test "launch refuses when a compose project named compose already exists" {
  use_stubs
  # shellcheck disable=SC2030 # stub settings are exported per test on purpose
  export STUB_COMPOSE_LS='[{"Name":"compose","Status":"running(7)"}]'
  run_control --execute launch
  [ "$status" -eq 1 ]
  [[ "$output" == *"it is not ours"* ]]
  assert_no_run_artifacts
  assert_no_stub_call '^make '
  assert_no_stub_call '^bun '
}

@test "launch refuses when something else already listens on :8443" {
  use_stubs
  export STUB_LSOF_PID=4242
  run_control --execute launch
  [ "$status" -eq 1 ]
  [[ "$output" == *"it is not ours"* ]]
  assert_no_run_artifacts
  assert_no_stub_call '^make '
}

@test "verify plan names the lookup and APIM proofs and the evidence root" {
  run_control --dry-run verify
  [ "$status" -eq 0 ]
  [[ "$output" == *"drive lookup 10.0.0.0/24"* ]]
  [[ "$output" == *"Usable Addresses"* ]]
  [[ "$output" == *"path=/api/v1/ipv4/subnet-info status=200"* ]]
  [[ "$output" == *"$VERIFY_EVIDENCE_ROOT/platform-run/evidence"* ]]
}

@test "verify and drive plans name the browsers and the per-browser evidence path" {
  run_control --dry-run verify
  [ "$status" -eq 0 ]
  [[ "$output" == *"in each of: chromium firefox webkit"* ]]
  VERIFY_BROWSER=webkit run_control --dry-run drive lookup 10.0.0.0/24
  [ "$status" -eq 0 ]
  [[ "$output" == *"headless webkit"* ]]
  [[ "$output" == *"-lookup-webkit"* ]]
}

@test "the default evidence root is the repo's .run/verify" {
  unset VERIFY_EVIDENCE_ROOT VERIFY_BASE_DIR
  run_control --dry-run verify
  [ "$status" -eq 0 ]
  [[ "$output" == *"/.run/verify/platform-run/evidence"* ]]
}

@test "drive plan shows the node driver with its arguments" {
  run_control --dry-run drive lookup 10.0.0.0/24
  [ "$status" -eq 0 ]
  [[ "$output" == *"drive.mjs lookup 10.0.0.0/24"* ]]
  assert_no_stub_calls
}

# Helpers for the state-based cases. A launched run is the state marker plus the revision record
# that launch would write; the healthy stack is the set of stub answers doctor reads.
mark_launched() {
  mkdir -p "$VERIFY_BASE_DIR/platform-run/state" "$VERIFY_EVIDENCE_ROOT/platform-run/evidence"
  : > "$VERIFY_BASE_DIR/platform-run/state/launched"
  : > "$VERIFY_EVIDENCE_ROOT/platform-run/evidence/unrelated-containers.before.txt"
  printf '%s\n' "recorded-revision" > "$VERIFY_EVIDENCE_ROOT/platform-run/evidence/revision.txt"
}
healthy_stack() {
  # shellcheck disable=SC2031 # reads this test's own export
  export STUB_COMPOSE_LS='[{"Name":"compose","Status":"running(7)"}]'
  export STUB_PS_OWNER=compose-edge-1
  export STUB_REDIRECT="https://dex.compose.127.0.0.1.sslip.io:8443/dex/auth"
  export STUB_APIM_RC=0
  export STUB_SERVICES=apim-simulator
}
# stack_ready is reached only from launch's 120s wait loop, so test the predicate on a copy of
# control.sh with its final `vk_main` line dropped (the copy is a git checkout so the root resolves).
harness_control() {
  local d="$BATS_TEST_TMPDIR/harness/scripts"
  mkdir -p "$d"
  cp "$BATS_TEST_DIRNAME/../scripts/verify-lib.sh" "$d/"
  sed '$d' "$BATS_TEST_DIRNAME/../scripts/control.sh" > "$d/control.sh"
  git -C "$(dirname "$d")" init -q
  printf '%s\n' "$d/control.sh"
}

@test "doctor passes for this run's healthy stack and names the running services" {
  use_stubs
  mark_launched
  healthy_stack
  run_control --execute doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK services=apim-simulator,"* ]]
  [[ "$output" == *"(now $(git -C "$BATS_TEST_DIRNAME" rev-parse HEAD))"* ]]
  [[ "$output" == *"revision recorded-revision"* ]]
}

@test "doctor fails naming a listed browser that is not installed, with the install command" {
  use_stubs
  mark_launched
  healthy_stack
  printf '#!/bin/sh\nexit 1\n' > "$STUBS/node"
  VERIFY_BROWSERS=firefox run_control --execute doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: Playwright firefox is not installed; run: cd tests/kubernetes/sso && bunx playwright install firefox"* ]]
}

@test "doctor fails when :8443 is published by a container other than compose-edge-1" {
  use_stubs
  mark_launched
  healthy_stack
  # shellcheck disable=SC2030 # stub settings are exported per test on purpose
  export STUB_PS_OWNER=other-edge-1
  run_control --execute doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *":8443 published by 'other-edge-1', not compose-edge-1"* ]]
}

@test "doctor reports 'nothing' when no container publishes :8443" {
  use_stubs
  mark_launched
  healthy_stack
  # shellcheck disable=SC2031 # reads this test's own export
  export STUB_PS_OWNER=
  run_control --execute doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *":8443 published by 'nothing', not compose-edge-1"* ]]
}

@test "doctor fails when the compose project is not running" {
  use_stubs
  mark_launched
  healthy_stack
  export STUB_COMPOSE_LS=
  run_control --execute doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: compose project 'compose' is not running"* ]]
}

@test "doctor fails when the app does not redirect to Dex" {
  use_stubs
  mark_launched
  healthy_stack
  # shellcheck disable=SC2030 # stub settings are exported per test on purpose
  export STUB_REDIRECT="https://login.example.test/"
  run_control --execute doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not redirect to Dex"* ]]
}

@test "doctor fails when the APIM health check fails" {
  use_stubs
  mark_launched
  healthy_stack
  # shellcheck disable=SC2030 # stub settings are exported per test on purpose
  export STUB_APIM_RC=7
  run_control --execute doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: APIM health"* ]]
}

# Equivalent mutants (accepted): `return 0` after vk_fail (doctor and drive refusal guards) is
# unreachable, because vk_fail returns 1 and set -e exits with that status before the return runs.
@test "stack_ready needs both the Dex redirect and a healthy APIM" {
  use_stubs
  local h
  h="$(harness_control)"
  # shellcheck disable=SC2031 # reads this test's own export
  export STUB_REDIRECT="https://dex.compose.127.0.0.1.sslip.io:8443/dex/auth"
  # shellcheck disable=SC2031 # reads this test's own export
  export STUB_APIM_RC=0
  # shellcheck disable=SC2016 # expanded by the child shell, not here
  run "$BASH32" -c '. "$0"; stack_ready' "$h"
  [ "$status" -eq 0 ]
  export STUB_APIM_RC=7
  # shellcheck disable=SC2016 # expanded by the child shell, not here
  run "$BASH32" -c '. "$0"; stack_ready' "$h"
  [ "$status" -ne 0 ]  # the status is curl's own (7), so only "not ready" is asserted
  export STUB_APIM_RC=0
  export STUB_REDIRECT="https://login.example.test/"
  # shellcheck disable=SC2016 # expanded by the child shell, not here
  run "$BASH32" -c '. "$0"; stack_ready' "$h"
  [ "$status" -eq 1 ]
}

@test "logs writes one file per service into a logs evidence directory" {
  use_stubs
  # shellcheck disable=SC2030 # stub settings are exported per test on purpose
  export STUB_LOGS_RC=0
  run_control --execute logs
  [ "$status" -eq 0 ]
  local dir
  dir="$(ls -d "$VERIFY_EVIDENCE_ROOT/platform-run/evidence/"*-logs)"
  [ -f "$dir/apim-simulator.log" ]
  [ -f "$dir/subnetcalc-router-dev.log" ]
  [ -f "$dir/subnetcalc-api-dev.log" ]
  [ -f "$dir/oauth2-proxy-subnetcalc-dev.log" ]
  grep -q 'log compose-apim-simulator-1' "$dir/apim-simulator.log"
  [[ "$output" == *"evidence: $dir"* ]]
}

@test "logs still succeeds and keeps every file when a service has no container logs" {
  use_stubs
  # shellcheck disable=SC2031 # reads this test's own export
  export STUB_LOGS_RC=1
  run_control --execute logs
  [ "$status" -eq 0 ]
  local dir
  dir="$(ls -d "$VERIFY_EVIDENCE_ROOT/platform-run/evidence/"*-logs)"
  [ -f "$dir/apim-simulator.log" ]
  [ -f "$dir/oauth2-proxy-subnetcalc-dev.log" ]
  [[ "$output" == *"evidence: $dir"* ]]
}

# Equivalent mutants (accepted): `docker logs ... && true` (logs loop) and `rmdir ... && true`
# (cleanup) fail without errexit, since the failing command is not the last one of the && list,
# so status and output match the `|| true` original.
@test "cleanup of this run's stack runs compose down, removes only the marker and empty state" {
  use_stubs
  mark_launched
  run_control --execute cleanup
  [ "$status" -eq 0 ]
  grep -q '^make -C docker/compose down$' "$STUB_CALLS"
  [ ! -e "$VERIFY_BASE_DIR/platform-run/state/launched" ]
  [ ! -d "$VERIFY_BASE_DIR/platform-run/state" ]
  [ -f "$VERIFY_EVIDENCE_ROOT/platform-run/evidence/down.log" ]
  [[ "$output" == *"cleaned run=platform-run; evidence kept at"* ]]
}

@test "cleanup retains ownership and reports failure when compose down fails" {
  use_stubs
  mark_launched
  export STUB_MAKE_RC=1
  run_control --execute cleanup
  [ "$status" -ne 0 ]
  [ -e "$VERIFY_BASE_DIR/platform-run/state/launched" ]
  [[ "$output" == *"ownership marker and evidence retained for retry"* ]]
}

@test "cleanup keeps a state directory that holds files other than the marker" {
  use_stubs
  mark_launched
  : > "$VERIFY_BASE_DIR/platform-run/state/keep.txt"
  run_control --execute cleanup
  [ "$status" -eq 0 ]
  [ ! -e "$VERIFY_BASE_DIR/platform-run/state/launched" ]
  [ -f "$VERIFY_BASE_DIR/platform-run/state/keep.txt" ]
}

@test "cleanup fails and retains ownership when an unrelated container disappears" {
  use_stubs
  mark_launched
  printf '%s\n' 'unrelated-container true original-start' > "$VERIFY_EVIDENCE_ROOT/platform-run/evidence/unrelated-containers.before.txt"
  run_control --execute cleanup
  [ "$status" -ne 0 ]
  [ -e "$VERIFY_BASE_DIR/platform-run/state/launched" ]
  [[ "$output" == *"unrelated runtime changed"* ]]
  [ -f "$VERIFY_EVIDENCE_ROOT/platform-run/evidence/unrelated-containers.after.txt" ]
}
