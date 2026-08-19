#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
DEVCONTAINER_CONFIG="${DEVCONTAINER_CONFIG:-${REPO_ROOT}/.devcontainer/devcontainer.json}"
DOCKERFILE_PATH="${DOCKERFILE_PATH:-${REPO_ROOT}/.devcontainer/Dockerfile}"
DOCKER_BIN="${DOCKER_BIN:-docker}"
DEVCONTAINER_CLI="${DEVCONTAINER_CLI:-devcontainer}"
DEVCONTAINER_REMOTE_USER="${DEVCONTAINER_REMOTE_USER:-vscode}"
INSTALL_TOOLCHAIN_SCRIPT="${INSTALL_TOOLCHAIN_SCRIPT:-${REPO_ROOT}/.devcontainer/install-toolchain.sh}"
NORMALIZE_NODE_TOOLCHAIN_SCRIPT="${NORMALIZE_NODE_TOOLCHAIN_SCRIPT:-${REPO_ROOT}/.devcontainer/normalize-node-toolchain.sh}"
TOOLCHAIN_VERSIONS_FILE="${TOOLCHAIN_VERSIONS_FILE:-${REPO_ROOT}/.devcontainer/toolchain-versions.sh}"
MISE_CONFIG_FILE="${MISE_CONFIG_FILE:-${REPO_ROOT}/mise.toml}"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

FAILURES=0

if [[ -t 1 ]]; then
  RED=$'\033[0;31m'
  GREEN=$'\033[0;32m'
  YELLOW=$'\033[1;33m'
  NC=$'\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  NC=''
fi

ok() { printf '%sOK%s   %s\n' "${GREEN}" "${NC}" "$*"; }
warn() { printf '%sWARN%s %s\n' "${YELLOW}" "${NC}" "$*"; }
fail_note() { printf '%sFAIL%s %s\n' "${RED}" "${NC}" "$*"; FAILURES=$((FAILURES + 1)); }
section() { printf '\n%s\n' "$*"; }

usage() {
  cat <<EOF
Usage: check-toolchain-surface.sh [--dry-run] [--execute]

Validates the platform devcontainer toolchain surface without requiring a
successful devcontainer image load.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage "would validate the resolved devcontainer toolchain surface without loading the workspace image" "$@"

require_file() {
  local path="$1"
  [[ -f "${path}" ]] || {
    printf 'missing required file: %s\n' "${path}" >&2
    exit 1
  }
}

run_inline_python() {
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$@"
    return 0
  fi

  if command -v uv >/dev/null 2>&1; then
    uv run --isolated python - "$@"
    return 0
  fi

  printf 'python3 or uv is required for %s\n' "$(shell_cli_script_name)" >&2
  exit 1
}

parse_base_image() {
  sed -nE 's/^FROM[[:space:]]+([^[:space:]]+).*/\1/p' "${DOCKERFILE_PATH}" | head -n 1
}

resolved_configuration_json() {
  "${DEVCONTAINER_CLI}" read-configuration \
    --workspace-folder "${REPO_ROOT}" \
    --include-features-configuration \
    --log-format json 2>&1 | awk '/^\{"configuration":/ { print; found=1 } END { exit(found ? 0 : 1) }'
}

# `devcontainer read-configuration` shells out to `docker ps`, so it fails on
# any host where Docker is simply not running. That is an unmet precondition,
# not a broken devcontainer definition, and reporting it as FAIL trains people
# to ignore a red line -- the Feature Install Surface section below already
# treats the same condition as a skip.
docker_available() {
  command -v "${DOCKER_BIN}" >/dev/null 2>&1 && "${DOCKER_BIN}" info >/dev/null 2>&1
}

resolved_node_feature_assignments() {
  run_inline_python "$1" <<'PY'
import json
import shlex
import sys

payload = json.loads(sys.argv[1])
feature_sets = payload.get("featuresConfiguration", {}).get("featureSets", [])
node_feature = None
for feature_set in feature_sets:
    for feature in feature_set.get("features", []):
        if feature.get("id") == "node":
            node_feature = feature
            break
    if node_feature:
        break

if not node_feature:
    raise SystemExit("node feature was not present in the resolved devcontainer configuration")

value = node_feature.get("value") or {}
fields = {
    "RESOLVED_NODE_FEATURE_CACHE_PATH": node_feature.get("cachePath", ""),
    "RESOLVED_NODE_VERSION": value.get("version", ""),
    "RESOLVED_NODE_PNPM_VERSION": value.get("pnpmVersion", ""),
    "RESOLVED_NODE_NVM_VERSION": value.get("nvmVersion", ""),
}

for key, raw_value in fields.items():
    value = "" if raw_value is None else str(raw_value)
    print(f"{key}={shlex.quote(value)}")
PY
}

check_file_lacks_slicer_install() {
  if grep -Eq 'arkade oci install .*slicer|SLICER_IMAGE_REF' "${INSTALL_TOOLCHAIN_SCRIPT}" "${TOOLCHAIN_VERSIONS_FILE}" "${REPO_ROOT}/.devcontainer/check-devcontainer-version.sh" "${REPO_ROOT}/.devcontainer/README.md"; then
    fail_note "slicer unexpectedly reappeared in the devcontainer toolchain surface"
  else
    ok "slicer is absent from the devcontainer toolchain surface"
  fi
}

# The committed mise.toml is hand-written, so it silently goes stale the moment
# update-versions.sh --apply moves a pin in toolchain-versions.sh. Every tool the
# two files share must agree; mise.toml may still carry host-only extras that
# have no devcontainer pin, which are reported but not treated as drift.
mise_pin_variable_for() {
  case "$1" in
    mkcert) printf 'MKCERT_VERSION\n' ;;
    opentofu) printf 'OPENTOFU_VERSION\n' ;;
    kyverno) printf 'KYVERNO_VERSION\n' ;;
    lefthook) printf 'LEFTHOOK_VERSION\n' ;;
    ripgrep) printf 'RIPGREP_VERSION\n' ;;
    lima) printf 'LIMA_VERSION\n' ;;
    starship) printf 'STARSHIP_VERSION\n' ;;
    step) printf 'STEP_VERSION\n' ;;
    arkade) printf 'ARKADE_VERSION\n' ;;
    *) return 1 ;;
  esac
}

check_mise_pin_drift() {
  if [[ ! -f "${MISE_CONFIG_FILE}" ]]; then
    warn "no mise.toml at ${MISE_CONFIG_FILE}; skipping host pin drift check"
    return 0
  fi

  local tool raw_version expected_var expected actual checked=0

  while IFS=$'\t' read -r tool raw_version; do
    [[ -n "${tool}" ]] || continue

    if ! expected_var="$(mise_pin_variable_for "${tool}")"; then
      warn "mise.toml pins ${tool}=${raw_version}, which has no devcontainer equivalent to compare"
      continue
    fi

    expected="${!expected_var:-}"
    if [[ -z "${expected}" ]]; then
      fail_note "mise.toml pins ${tool}, but ${expected_var} is unset in ${TOOLCHAIN_VERSIONS_FILE}"
      continue
    fi

    # Compare bare versions: mise.toml omits the leading v that several
    # toolchain-versions.sh pins carry (KYVERNO_VERSION=v1.18.2 vs kyverno = "1.18.2").
    expected="${expected#v}"
    actual="${raw_version#v}"
    checked=$((checked + 1))

    if [[ "${actual}" == "${expected}" ]]; then
      ok "mise.toml pins ${tool} ${raw_version} in step with ${expected_var}"
    else
      fail_note "mise.toml pins ${tool} ${raw_version}, but ${expected_var} is ${!expected_var}; run make update-versions or edit mise.toml to match"
    fi
  done < <(
    awk '
      /^[[:space:]]*\[/ { in_tools = ($0 ~ /^[[:space:]]*\[tools\][[:space:]]*$/); next }
      !in_tools { next }
      /^[[:space:]]*#/ { next }
      /=/ {
        split($0, parts, "=")
        name = parts[1]
        value = parts[2]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
        gsub(/^[[:space:]]*"|"[[:space:]]*$|^[[:space:]]+|[[:space:]]+$/, "", value)
        if (name != "" && value != "") { printf "%s\t%s\n", name, value }
      }
    ' "${MISE_CONFIG_FILE}"
  )

  if [[ "${checked}" -eq 0 ]]; then
    warn "mise.toml shared no pins with ${TOOLCHAIN_VERSIONS_FILE}; drift cannot be detected"
  fi
}

check_dockerfile_base_packages() {
  local missing=0
  local package

  # ripgrep is no longer an apt package: install-toolchain.sh fetches the
  # pinned release so the devcontainer, Ubuntu and Arch hosts, and CI all run
  # one version. check_mise_pin_drift keeps the host pin in step.
  for package in bats shellcheck yamllint; do
    if grep -Eq "^[[:space:]]*${package}[[:space:]]*\\\\" "${DOCKERFILE_PATH}"; then
      ok "Dockerfile installs ${package}"
    else
      fail_note "Dockerfile does not install required package: ${package}"
      missing=1
    fi
  done

  return "${missing}"
}

check_node_feature_resolution() {
  if [[ -n "${RESOLVED_NODE_FEATURE_CACHE_PATH}" ]] && [[ -f "${RESOLVED_NODE_FEATURE_CACHE_PATH}/install.sh" ]]; then
    ok "resolved node feature cache is available at ${RESOLVED_NODE_FEATURE_CACHE_PATH}"
  else
    fail_note "resolved node feature cache path is missing or incomplete"
  fi

  if [[ "${RESOLVED_NODE_VERSION}" == "${DEVCONTAINER_NODE_VERSION}" ]]; then
    ok "resolved node feature pins Node ${RESOLVED_NODE_VERSION}"
  else
    fail_note "resolved node feature pins Node ${RESOLVED_NODE_VERSION:-unset}, expected ${DEVCONTAINER_NODE_VERSION}"
  fi

  if [[ "${RESOLVED_NODE_NVM_VERSION}" == "${DEVCONTAINER_NODE_NVM_VERSION}" ]]; then
    ok "resolved node feature pins nvm ${RESOLVED_NODE_NVM_VERSION}"
  else
    fail_note "resolved node feature pins nvm ${RESOLVED_NODE_NVM_VERSION:-unset}, expected ${DEVCONTAINER_NODE_NVM_VERSION}"
  fi

  if [[ "${RESOLVED_NODE_PNPM_VERSION}" == "${DEVCONTAINER_NODE_PNPM_VERSION}" ]]; then
    ok "resolved node feature keeps pnpm ${RESOLVED_NODE_PNPM_VERSION}"
  else
    fail_note "resolved node feature keeps pnpm ${RESOLVED_NODE_PNPM_VERSION:-unset}, expected ${DEVCONTAINER_NODE_PNPM_VERSION}"
  fi
}

verify_node_feature_install_surface() {
  local base_image="$1"

  # shellcheck disable=SC2016 # the inner bash script expands in the container, not on the host
  if ! "${DOCKER_BIN}" run --rm \
    -e "VERSION=${DEVCONTAINER_NODE_VERSION}" \
    -e "PNPMVERSION=${DEVCONTAINER_NODE_PNPM_VERSION}" \
    -e "NVMVERSION=${DEVCONTAINER_NODE_NVM_VERSION}" \
    -e "USERNAME=${DEVCONTAINER_REMOTE_USER}" \
    -e "EXPECTED_NODE_VERSION=${DEVCONTAINER_NODE_VERSION}" \
    -e "EXPECTED_NVM_VERSION=${DEVCONTAINER_NODE_NVM_VERSION}" \
    -v "${RESOLVED_NODE_FEATURE_CACHE_PATH}:/tmp/platform-devcontainer-node-feature:ro" \
    -v "${NORMALIZE_NODE_TOOLCHAIN_SCRIPT}:/tmp/platform-devcontainer-normalize-node-toolchain.sh:ro" \
    "${base_image}" \
    bash -lc '
      set -euo pipefail
      cp -R /tmp/platform-devcontainer-node-feature /tmp/platform-devcontainer-node-feature-work
      bash /tmp/platform-devcontainer-node-feature-work/install.sh
      bash /tmp/platform-devcontainer-normalize-node-toolchain.sh --execute
      export NVM_DIR=/usr/local/share/nvm
      . "${NVM_DIR}/nvm.sh"
      nvm use default >/dev/null
      [ "$(node --version | sed "s/^v//")" = "${EXPECTED_NODE_VERSION}" ]
      [ "$(nvm --version)" = "${EXPECTED_NVM_VERSION}" ]
      if command -v pnpm >/dev/null 2>&1; then
        printf "pnpm unexpectedly installed at %s\n" "$(command -v pnpm)" >&2
        exit 1
      fi
    '; then
    fail_note "resolved node feature did not install cleanly with pnpm disabled"
    return 0
  fi

  ok "resolved node feature installs Node ${DEVCONTAINER_NODE_VERSION}, nvm ${DEVCONTAINER_NODE_NVM_VERSION}, and no pnpm"
}

require_file "${DEVCONTAINER_CONFIG}"
require_file "${DOCKERFILE_PATH}"
require_file "${INSTALL_TOOLCHAIN_SCRIPT}"
require_file "${NORMALIZE_NODE_TOOLCHAIN_SCRIPT}"
require_file "${TOOLCHAIN_VERSIONS_FILE}"

# shellcheck source=/dev/null
source "${TOOLCHAIN_VERSIONS_FILE}"

BASE_IMAGE="$(parse_base_image)"
RESOLVED_CONFIG_JSON="$(resolved_configuration_json || true)"

section "Definition"

if [[ -n "${BASE_IMAGE}" ]]; then
  ok "base image tracks ${BASE_IMAGE}"
else
  fail_note "could not resolve the devcontainer base image from ${DOCKERFILE_PATH}"
fi

check_file_lacks_slicer_install
check_dockerfile_base_packages
check_mise_pin_drift

if [[ -z "${RESOLVED_CONFIG_JSON}" ]]; then
  if docker_available; then
    fail_note "could not resolve the devcontainer feature configuration with ${DEVCONTAINER_CLI} read-configuration"
  else
    warn "devcontainer feature checks skipped: ${DOCKER_BIN} is not available, and ${DEVCONTAINER_CLI} read-configuration runs docker ps"
  fi
else
  eval "$(resolved_node_feature_assignments "${RESOLVED_CONFIG_JSON}")"
  check_node_feature_resolution
fi

section "Feature Install Surface"

if [[ -z "${RESOLVED_CONFIG_JSON}" ]]; then
  warn "node feature install-surface checks were skipped because the resolved devcontainer configuration was unavailable"
elif [[ -z "${BASE_IMAGE}" ]]; then
  warn "node feature install-surface checks were skipped because the devcontainer base image could not be resolved"
else
  verify_node_feature_install_surface "${BASE_IMAGE}"
fi

if [[ "${FAILURES}" -gt 0 ]]; then
  exit 1
fi
