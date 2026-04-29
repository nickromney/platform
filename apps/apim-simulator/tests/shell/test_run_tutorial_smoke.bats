#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/scripts/run_tutorial_smoke.sh"
  export TUTORIAL_DIR="$BATS_TEST_TMPDIR/tutorials"
  export CALL_LOG="$BATS_TEST_TMPDIR/calls.log"
  mkdir -p "$TUTORIAL_DIR"

  cat >"$TUTORIAL_DIR/tutorial-cleanup.sh" <<'EOF'
#!/usr/bin/env bash
printf 'cleanup\n' >>"$CALL_LOG"
EOF
  chmod +x "$TUTORIAL_DIR/tutorial-cleanup.sh"
  export TUTORIAL_CLEANUP="$TUTORIAL_DIR/tutorial-cleanup.sh"

  cat >"$TUTORIAL_DIR/tutorial02.sh" <<'EOF'
#!/usr/bin/env bash
printf 'tutorial02 %s\n' "$1" >>"$CALL_LOG"
EOF
  chmod +x "$TUTORIAL_DIR/tutorial02.sh"

  cat >"$TUTORIAL_DIR/tutorial03.sh" <<'EOF'
#!/usr/bin/env bash
printf 'tutorial03 %s\n' "$1" >>"$CALL_LOG"
EOF
  chmod +x "$TUTORIAL_DIR/tutorial03.sh"
}

@test "run_tutorial_smoke.sh runs discovered tutorials without mapfile" {
  run "$SCRIPT" --execute

  [ "$status" -eq 0 ]
  [[ "$output" == *"Running live tutorial smoke sequence"* ]]
  [[ "$output" == *"$TUTORIAL_DIR/tutorial02.sh"* ]]
  [[ "$output" == *"$TUTORIAL_DIR/tutorial03.sh"* ]]
  [[ "$output" == *"Live tutorial smoke passed"* ]]

  run cat "$CALL_LOG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cleanup"* ]]
  [[ "$output" == *"tutorial02 --setup"* ]]
  [[ "$output" == *"tutorial02 --verify"* ]]
  [[ "$output" == *"tutorial03 --setup"* ]]
  [[ "$output" == *"tutorial03 --verify"* ]]
}

@test "run_tutorial_smoke.sh resolves requested selectors" {
  run "$SCRIPT" --execute 03

  [ "$status" -eq 0 ]
  [[ "$output" == *"$TUTORIAL_DIR/tutorial03.sh"* ]]
  [[ "$output" != *"$TUTORIAL_DIR/tutorial02.sh"* ]]

  run cat "$CALL_LOG"
  [ "$status" -eq 0 ]
  [[ "$output" != *"tutorial02"* ]]
  [[ "$output" == *"tutorial03 --setup"* ]]
  [[ "$output" == *"tutorial03 --verify"* ]]
}
