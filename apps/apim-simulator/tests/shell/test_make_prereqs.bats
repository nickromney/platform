#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
  export TEST_BIN="$BATS_TEST_TMPDIR/bin"
  export TEST_CAROOT="$BATS_TEST_TMPDIR/mkcert-caroot"
  mkdir -p "$TEST_BIN" "$TEST_CAROOT"

  write_docker_stub
  write_lsof_stub
}

write_docker_stub() {
  cat >"$TEST_BIN/docker" <<'EOF'
#!/usr/bin/env bash
set -eu

case "${1:-}" in
  compose)
    if [ "${2:-}" = "version" ]; then
      exit 0
    fi
    echo "docker stub only supports compose version" >&2
    exit 1
    ;;
  info)
    exit 0
    ;;
  *)
    echo "docker stub only supports compose version and info" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "$TEST_BIN/docker"
}

write_lsof_stub() {
  cat >"$TEST_BIN/lsof" <<'EOF'
#!/usr/bin/env bash
set -eu

exit 0
EOF
  chmod +x "$TEST_BIN/lsof"
}

write_mkcert_stub() {
  cat >"$TEST_BIN/mkcert" <<'EOF'
#!/usr/bin/env bash
set -eu

if [ "${1:-}" = "-CAROOT" ]; then
  printf '%s\n' "$TEST_CAROOT"
  exit 0
fi

echo "mkcert stub only supports -CAROOT" >&2
exit 1
EOF
  chmod +x "$TEST_BIN/mkcert"
}

@test "make prereqs fails when mkcert is missing" {
  run env PATH="$TEST_BIN:/usr/bin:/bin" make -C "$REPO_ROOT" prereqs

  [ "$status" -ne 0 ]
  [[ "$output" == *"mkcert is required but was not found in PATH."* ]]
}

@test "make prereqs accepts a ready mkcert installation" {
  write_mkcert_stub
  printf 'root-cert' >"$TEST_CAROOT/rootCA.pem"
  printf 'root-key' >"$TEST_CAROOT/rootCA-key.pem"

  run env PATH="$TEST_BIN:/usr/bin:/bin" make -C "$REPO_ROOT" prereqs

  [ "$status" -eq 0 ]
}
