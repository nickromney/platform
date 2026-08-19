#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
  export SCRIPT="${REPO_ROOT}/.devcontainer/check-toolchain-surface.sh"
}

# Structural rather than behavioural on purpose: running the script reaches for
# the devcontainer CLI and the Docker daemon, which is exactly the environment
# dependence being guarded against. Executing it in the gate would make this
# test flaky for the same reason the check itself was noisy.

@test "an unavailable Docker daemon is a skip, not a failure" {
  # read-configuration shells out to `docker ps`, so it fails on any host where
  # Docker simply is not running. Reporting that as FAIL trains people to
  # ignore a red line; the Feature Install Surface section already skips on the
  # same condition.
  grep -Fq 'docker_available() {' "${SCRIPT}"

  run bash -lc "
    awk '/^if \[\[ -z \"\\\$\{RESOLVED_CONFIG_JSON\}\" \]\]; then\$/,/^fi\$/' '${SCRIPT}' |
      head -20
  "

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"docker_available"* ]]
  [[ "${output}" == *"warn "* ]]

  # A genuine read-configuration breakage on a host WITH Docker must still fail,
  # or the skip has swallowed the signal it was narrowing.
  [[ "${output}" == *"fail_note "* ]]
}

@test "ripgrep is pinned rather than apt-installed across every environment" {
  # One ripgrep for the devcontainer, Ubuntu on slicer-mac, Arch on omarchy and
  # CI. Distro packages drift by years, and ten gated Bats files call rg.
  grep -Fq 'install_ripgrep' "${REPO_ROOT}/.devcontainer/install-toolchain.sh"
  grep -Fq 'RIPGREP_VERSION' "${REPO_ROOT}/.devcontainer/install-toolchain.sh"

  # Removed from the apt layer, or the image would carry two of them.
  run grep -nE '^\s+ripgrep \\$' "${REPO_ROOT}/.devcontainer/Dockerfile"

  [ "${status}" -ne 0 ]

  # Host pin and devcontainer pin must name the same version; the drift check in
  # check-toolchain-surface.sh enforces it, this asserts it is wired up at all.
  grep -Fq "ripgrep) printf 'RIPGREP_VERSION\\n' ;;" "${SCRIPT}"

  run bash -lc "
    mise_version=\$(sed -nE 's/^ripgrep = \"([^\"]+)\"\$/\\1/p' '${REPO_ROOT}/mise.toml')
    pin_version=\$(sed -nE 's/^RIPGREP_VERSION=\"\\\$\{RIPGREP_VERSION:-([^}]+)\}\"\$/\\1/p' '${REPO_ROOT}/.devcontainer/toolchain-versions.sh')
    [ -n \"\${mise_version}\" ] && [ \"\${mise_version}\" = \"\${pin_version}\" ]
  "

  [ "${status}" -eq 0 ]
}
