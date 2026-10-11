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
exit 0
STUB
  cat > "$STUBS/lsof" <<'STUB'
#!/bin/sh
echo "lsof $*" >> "$STUB_CALLS"
if [ -n "${STUB_LSOF_PID:-}" ]; then echo "$STUB_LSOF_PID"; exit 0; fi
exit 1
STUB
  for tool in make bun node curl; do
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

@test "launch refuses when a compose project named compose already exists" {
  use_stubs
  export STUB_COMPOSE_LS='[{"Name":"compose","Status":"running(7)"}]'
  run_control --execute launch
  [ "$status" -eq 1 ]
  [[ "$output" == *"it is not ours"* ]]
  [ ! -e "$VERIFY_BASE_DIR" ]
  assert_no_stub_call '^make '
  assert_no_stub_call '^bun '
}

@test "launch refuses when something else already listens on :8443" {
  use_stubs
  export STUB_LSOF_PID=4242
  run_control --execute launch
  [ "$status" -eq 1 ]
  [[ "$output" == *"it is not ours"* ]]
  [ ! -e "$VERIFY_BASE_DIR" ]
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
