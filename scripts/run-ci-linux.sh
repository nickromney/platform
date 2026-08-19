#!/usr/bin/env bash
set -euo pipefail

# Run the full Bats gate a second time, inside the devcontainer, and record it
# on the same receipt as the host run.
#
# Why this exists: GitHub CI no longer runs on pull_request (ADR 0011), so the
# only routine gate is local -- and a macOS host cannot see Linux-only
# breakage. Bash 3.2 vs 5, BSD vs GNU sed/awk/grep, and case-sensitive
# filesystems have all produced defects here that a green host run did not.
#
# The container does NOT write the shared receipt. It stamps a throwaway one
# inside /tmp, and this script stamps "linux" on the host only if the container
# run passed. That keeps a container/host fingerprint disagreement -- bind-mount
# file modes, ownership -- from resetting the receipt and silently discarding
# the host result.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/shell-cli.sh"

DEVCONTAINER_CLI="${DEVCONTAINER_CLI:-devcontainer}"
DOCKER_BIN="${DOCKER_BIN:-docker}"
CI_RECEIPT_SCRIPT="${CI_RECEIPT_SCRIPT:-${SCRIPT_DIR}/ci-receipt.sh}"

# shellcheck disable=SC2329 # invoked by name through the shell_cli_* helpers
usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute]

Run make test-ci inside the devcontainer and record "linux" on the gate receipt.

Requires Docker and the devcontainer CLI. The first run builds the image and is
slow; later runs reuse it.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage \
  "would run the full Bats gate inside the devcontainer and stamp linux" "$@"

command -v "${DOCKER_BIN}" >/dev/null 2>&1 || {
  echo "${0##*/}: ${DOCKER_BIN} not found in PATH" >&2
  exit 1
}
"${DOCKER_BIN}" info >/dev/null 2>&1 || {
  echo "${0##*/}: ${DOCKER_BIN} is not running; start it and retry" >&2
  exit 1
}
command -v "${DEVCONTAINER_CLI}" >/dev/null 2>&1 || {
  echo "${0##*/}: ${DEVCONTAINER_CLI} not found in PATH" >&2
  echo "install with: npm install -g @devcontainers/cli" >&2
  exit 1
}

echo "==> starting the devcontainer (first run builds the image)"
"${DEVCONTAINER_CLI}" up --workspace-folder "${REPO_ROOT}"

echo "==> running the full Bats gate inside the devcontainer"
# The workspace is bind-mounted, so git inside the container looks at a
# repository owned by another uid; without this it refuses with "dubious
# ownership" before any test runs. CI_RECEIPT_FILE keeps the container off the
# shared receipt.
# The devcontainer is not a clean room by design: containerEnv rewires the
# kubeconfig paths and the registry host so the container can drive the host's
# kind cluster and registry. Left in place, the gate measures that wiring rather
# than Linux -- kind reports push_host=host.docker.internal, and lima reports
# the *kind* kubeconfig, because KUBECONFIG_PATH is set globally to a
# kind-specific value (worth fixing in devcontainer.json on its own merits).
#
# A plain shell, not a login shell: `bash -lc` re-sources the profile and puts
# the overrides straight back.
#
# shellcheck disable=SC2016 # the inner script expands in the container, not here
PLATFORM_WORKSPACE="${REPO_ROOT}" \
  "${DEVCONTAINER_CLI}" exec --workspace-folder "${REPO_ROOT}" \
  --remote-env "PLATFORM_WORKSPACE=${REPO_ROOT}" \
  bash -c '
    set -euo pipefail
    cd "${PLATFORM_WORKSPACE}"
    git config --global --add safe.directory "$(pwd)" || true
    env -u KUBECONFIG_PATH \
        -u KIND_KUBECONFIG_PATH \
        -u DEFAULT_KUBECONFIG_PATH \
        -u PLATFORM_DEVCONTAINER_HOST_ALIAS \
        -u KIND_DEVCONTAINER_HOST_ALIAS \
        CI_RECEIPT_FILE=/tmp/platform-linux-receipt.json \
        make test-ci
  '

"${CI_RECEIPT_SCRIPT}" --execute --action stamp --environment linux
echo "OK   the devcontainer gate passed; receipt now covers linux"
