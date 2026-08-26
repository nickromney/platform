#!/usr/bin/env bash
#
# First oracle for scripts/lib/compose-cli.sh. Mutation testing says nothing
# about a script with no suite, so this exists before any refactoring does.
#
# Every backend probe shells out, so each test builds a PATH containing only
# the stubs it wants found. An empty TEST_BIN is therefore "no container
# runtime installed", which is the case the fallback chain exists to handle.

setup() {
  local root
  root="$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)"
  export LIB="${root}/scripts/lib/compose-cli.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN}"
}

# Write a stub that exits 0 for the given "$*" patterns and 1 for anything
# else, so a probe can be made to pass or fail one subcommand at a time.
write_stub() {
  local name="$1"
  shift
  local pattern
  {
    printf '#!/bin/sh\n'
    printf 'case "$*" in\n'
    for pattern in "$@"; do
      printf "  '%s') exit 0 ;;\n" "${pattern}"
    done
    printf '  *) exit 1 ;;\n'
    printf 'esac\n'
  } >"${TEST_BIN}/${name}"
  chmod +x "${TEST_BIN}/${name}"
}

backend() {
  run /bin/bash -c "export PATH='${TEST_BIN}'; source '${LIB}'; compose_cli_backend"
}

@test "picks docker compose when the plugin and the daemon both answer" {
  write_stub docker 'compose version' 'info'

  backend

  [ "${status}" -eq 0 ]
  [ "${output}" = "docker compose" ]
}

@test "skips docker when the compose plugin is missing" {
  # The docker binary exists and the daemon is up, but there is no compose
  # subcommand. Each probe in the chain has to hold on its own: an installed
  # docker is not evidence that `docker compose` works.
  write_stub docker 'info'
  write_stub nerdctl 'version' 'info'

  backend

  [ "${status}" -eq 0 ]
  [ "${output}" = "nerdctl compose" ]
}

@test "skips docker when the daemon is unreachable" {
  # The mirror image of the case above: the compose plugin is installed but
  # dockerd is not running, which is the ordinary state on a laptop that has
  # Docker Desktop installed and stopped.
  write_stub docker 'compose version'
  write_stub nerdctl 'version' 'info'

  backend

  [ "${status}" -eq 0 ]
  [ "${output}" = "nerdctl compose" ]
}

@test "skips nerdctl when its daemon is unreachable" {
  write_stub nerdctl 'version'
  write_stub colima 'nerdctl info'

  backend

  [ "${status}" -eq 0 ]
  [ "${output}" = "colima nerdctl compose" ]
}

@test "falls back to podman compose" {
  write_stub podman 'compose version' 'info'

  backend

  [ "${status}" -eq 0 ]
  [ "${output}" = "podman compose" ]
}

@test "falls back to podman-compose when podman has no compose subcommand" {
  # podman is up but too old for `podman compose`, so the standalone
  # podman-compose binary is the last resort before giving up.
  write_stub podman 'info'
  write_stub podman-compose 'version'

  backend

  [ "${status}" -eq 0 ]
  [ "${output}" = "podman-compose" ]
}

@test "reports failure when no backend is available" {
  backend

  [ "${status}" -eq 1 ]
  [ -z "${output}" ]
}

@test "compose_cli runs the resolved backend with the caller's arguments" {
  # Also pins the word split of a two-word backend: "docker compose" has to
  # reach execution as two argv entries, not one command named "docker compose".
  cat >"${TEST_BIN}/docker" <<'EOF'
#!/bin/sh
case "$*" in
  'compose version'|'info') exit 0 ;;
esac
printf 'invoked: %s\n' "$*"
EOF
  chmod +x "${TEST_BIN}/docker"

  run /bin/bash -c "export PATH='${TEST_BIN}'; source '${LIB}'; compose_cli up -d --wait"

  [ "${status}" -eq 0 ]
  [ "${output}" = "invoked: compose up -d --wait" ]
}

@test "compose_cli explains itself when no backend is available" {
  run /bin/bash -c "export PATH='${TEST_BIN}'; source '${LIB}'; compose_cli up -d"

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"a supported compose backend is required"* ]]
}

@test "skips nerdctl when the version probe fails" {
  # Kills LOGICAL_AND_OR at compose-cli.sh:14. ORed, an installed nerdctl short
  # -circuits past its own version probe, so a nerdctl too old for `nerdctl
  # compose` is still chosen as the backend as long as its daemon answers.
  write_stub nerdctl 'info'
  write_stub colima 'nerdctl info'

  backend

  [ "${status}" -eq 0 ]
  [ "${output}" = "colima nerdctl compose" ]
}

@test "skips colima when its nerdctl cannot be reached" {
  # Kills LOGICAL_AND_OR at compose-cli.sh:19. ORed, merely having the colima
  # binary installed is enough to claim the backend, even with the VM stopped --
  # which is the normal state of colima on a machine that is not using it.
  write_stub colima
  write_stub podman 'compose version' 'info'

  backend

  [ "${status}" -eq 0 ]
  [ "${output}" = "podman compose" ]
}

@test "does not offer podman-compose when podman itself is unavailable" {
  # Kills LOGICAL_AND_OR at compose-cli.sh:29. podman-compose is a front end; it
  # cannot do anything without a podman to drive. ORed, its mere presence wins
  # the chain and compose_cli then hands work to a backend that cannot run it.
  write_stub podman-compose 'version'

  backend

  [ "${status}" -eq 1 ]
  [ -z "${output}" ]
}
