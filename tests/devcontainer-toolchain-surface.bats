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

@test "the devcontainer Go pin matches the go directive every module declares" {
  # GO_VERSION is a patch-level pin (1.26.5) because the Go download URL needs
  # one; the modules declare major.minor (1.26). The image build sees only
  # .devcontainer/, so install-toolchain.sh cannot read go.mod and has to
  # restate it -- which is exactly how the two drift apart unsupervised.
  run bash -lc "
    set -euo pipefail
    cd '${REPO_ROOT}'
    source .devcontainer/toolchain-versions.sh
    declared=\$(git ls-files '*go.mod' | xargs -I{} sed -nE 's/^go[[:space:]]+([0-9]+\.[0-9]+)(\.[0-9]+)?\$/\\1/p' {} | sort -u)
    [ \"\$(printf '%s' \"\${declared}\" | wc -l | tr -d ' ')\" = '0' ] || {
      echo \"modules disagree on the go directive: \${declared}\" >&2
      exit 1
    }
    case \"\${GO_VERSION}\" in
      \"\${declared}\"|\"\${declared}\".*) ;;
      *)
        echo \"GO_VERSION=\${GO_VERSION} does not satisfy the go directive \${declared}\" >&2
        exit 1
        ;;
    esac
    printf 'GO_VERSION=%s satisfies go %s\n' \"\${GO_VERSION}\" \"\${declared}\"
  "

  [ "${status}" -eq 0 ]
}

@test "the devcontainer takes shellcheck and yamllint from pins, not apt" {
  # apt gave shellcheck 0.9.0 and yamllint 1.33.0 while CI ran 0.11.0 and
  # 1.38.0, so `make lint` genuinely disagreed between the devcontainer and CI.
  # 0.9.0 is the version that emits 449 spurious SC2317 findings (#202).
  grep -Fq 'install_shellcheck' "${REPO_ROOT}/.devcontainer/install-toolchain.sh"
  grep -Fq 'install_yamllint' "${REPO_ROOT}/.devcontainer/install-toolchain.sh"
  grep -Fq 'install_go' "${REPO_ROOT}/.devcontainer/install-toolchain.sh"

  for package in shellcheck yamllint ripgrep; do
    run grep -nE "^\s+${package} \\\\$" "${REPO_ROOT}/.devcontainer/Dockerfile"

    [ "${status}" -ne 0 ]
  done
}
