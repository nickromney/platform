#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
DEVCONTAINER_CONFIG="${DEVCONTAINER_CONFIG:-${REPO_ROOT}/.devcontainer/devcontainer.json}"
DOCKERFILE_PATH="${DOCKERFILE_PATH:-${REPO_ROOT}/.devcontainer/Dockerfile}"
INSTALL_TOOLCHAIN_SCRIPT="${INSTALL_TOOLCHAIN_SCRIPT:-${REPO_ROOT}/.devcontainer/install-toolchain.sh}"
DEVCONTAINER_CHECK_STALE_DAYS="${DEVCONTAINER_CHECK_STALE_DAYS:-14}"
DEVCONTAINER_REMOTE_USER="${DEVCONTAINER_REMOTE_USER:-vscode}"

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
Usage: check-version.sh [--dry-run] [--execute]

Inspects the platform devcontainer definition plus any existing workspace
container/image to surface stale builds and tool-version drift.

$(shell_cli_standard_options)

Environment:
  DEVCONTAINER_CHECK_STALE_DAYS=14  Maximum acceptable workspace image age in days.
EOF
}

shell_cli_handle_standard_no_args usage "would inspect the devcontainer toolchain and workspace image freshness" "$@"

require_file() {
  local path="$1"
  [[ -f "${path}" ]] || {
    printf 'missing required file: %s\n' "${path}" >&2
    exit 1
  }
}

trim() {
  printf '%s' "$1" | awk '{$1=$1; print}'
}

docker_available() {
  command -v docker >/dev/null 2>&1
}

inside_devcontainer() {
  [[ "${PLATFORM_DEVCONTAINER:-}" == "1" ]] || [[ -f "/.dockerenv" ]]
}

parse_expected_opentofu_version() {
  sed -nE 's/^OPENTOFU_VERSION="\$\{OPENTOFU_VERSION:-([^}]*)\}".*/\1/p' "${INSTALL_TOOLCHAIN_SCRIPT}" | head -n 1
}

parse_expected_uv_version() {
  sed -nE 's#^COPY --from=ghcr\.io/astral-sh/uv:([^[:space:]]+) /uv /usr/local/bin/uv#\1#p' "${DOCKERFILE_PATH}" | head -n 1
}

parse_base_image() {
  sed -nE 's/^FROM[[:space:]]+([^[:space:]]+).*/\1/p' "${DOCKERFILE_PATH}" | head -n 1
}

parse_devcontainer_feature_versions() {
  python3 - "${DEVCONTAINER_CONFIG}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)

features = payload.get("features") or {}
for feature_name, config in features.items():
    if isinstance(config, dict):
        version = str(config.get("version", "")).strip()
    else:
        version = str(config).strip()
    print(f"{feature_name}\t{version}")
PY
}

parse_arkade_tools() {
  awk '
    /^arkade_tools=\(/ { in_list=1; next }
    in_list && /^\)/ { in_list=0; exit }
    in_list {
      line=$0
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (line != "") {
        print line
      }
    }
  ' "${INSTALL_TOOLCHAIN_SCRIPT}" | paste -sd ',' - | sed 's/,/, /g'
}

select_workspace_container_id() {
  local ids selected

  ids="$(
    docker ps -aq \
      --filter "label=devcontainer.local_folder=${REPO_ROOT}" \
      --filter "label=devcontainer.config_file=${DEVCONTAINER_CONFIG}" 2>/dev/null || true
  )"

  [[ -n "${ids}" ]] || return 1

  selected="$(
    while IFS= read -r id; do
      [[ -n "${id}" ]] || continue
      printf '%s\t%s\n' "$(docker inspect --format '{{.Created}}' "${id}" 2>/dev/null || true)" "${id}"
    done <<< "${ids}" | LC_ALL=C sort -r | head -n 1 | cut -f 2
  )"

  [[ -n "${selected}" ]] || return 1
  printf '%s\n' "${selected}"
}

age_days_from_iso() {
  python3 - "$1" <<'PY'
from datetime import datetime, timezone
import re
import sys

value = sys.argv[1].strip()
if not value:
    sys.exit(1)

match = re.match(r"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(\.\d+)?(Z|[+-]\d{2}:\d{2})$", value)
if not match:
    sys.exit(1)

base, fraction, offset = match.groups()
fraction = (fraction or "")[:7]
if fraction:
    digits = fraction[1:]
    fraction = "." + digits[:6].ljust(6, "0")
offset = "+00:00" if offset == "Z" else offset

timestamp = datetime.fromisoformat(base + fraction + offset)
age_days = (datetime.now(timezone.utc) - timestamp.astimezone(timezone.utc)).total_seconds() / 86400
print(f"{age_days:.1f}")
PY
}

age_exceeds_threshold() {
  local age_days="$1"

  awk "BEGIN { exit !(${age_days} > ${DEVCONTAINER_CHECK_STALE_DAYS}) }"
}

run_in_live_env() {
  local command="$1"

  if inside_devcontainer; then
    bash -lc "${command}"
    return 0
  fi

  if [[ -n "${WORKSPACE_CONTAINER_ID:-}" ]] && [[ "${WORKSPACE_CONTAINER_STATUS:-}" == "running" ]]; then
    docker exec --user "${DEVCONTAINER_REMOTE_USER}" "${WORKSPACE_CONTAINER_ID}" bash -lc "${command}"
    return 0
  fi

  return 1
}

check_pinned_tool_version() {
  local label="$1"
  local expected="$2"
  local command="$3"
  local actual=""

  actual="$(run_in_live_env "${command}" 2>/dev/null || true)"
  actual="$(trim "${actual}")"

  if [[ -z "${actual}" ]]; then
    fail_note "${label} is not available in the live devcontainer environment"
    return 0
  fi

  if [[ "${actual}" == "${expected}" ]]; then
    ok "${label} ${actual} matches the pinned definition"
  else
    fail_note "${label} ${actual} does not match the pinned definition ${expected}"
  fi
}

report_live_tool_version() {
  local label="$1"
  local command="$2"
  local actual=""

  actual="$(run_in_live_env "${command}" 2>/dev/null || true)"
  actual="$(trim "${actual}")"

  if [[ -z "${actual}" ]]; then
    warn "${label} is not available in the live devcontainer environment"
    return 0
  fi

  ok "${label} ${actual}"
}

require_file "${DEVCONTAINER_CONFIG}"
require_file "${DOCKERFILE_PATH}"
require_file "${INSTALL_TOOLCHAIN_SCRIPT}"

if ! [[ "${DEVCONTAINER_CHECK_STALE_DAYS}" =~ ^[0-9]+$ ]]; then
  printf 'DEVCONTAINER_CHECK_STALE_DAYS must be an integer, got: %s\n' "${DEVCONTAINER_CHECK_STALE_DAYS}" >&2
  exit 1
fi

EXPECTED_OPENTOFU_VERSION="$(parse_expected_opentofu_version)"
EXPECTED_UV_VERSION="$(parse_expected_uv_version)"
BASE_IMAGE="$(parse_base_image)"
DEVCONTAINER_FEATURE_VERSIONS="$(parse_devcontainer_feature_versions 2>/dev/null || true)"
ARKADE_TOOLS="$(parse_arkade_tools)"

section "Definition"

if [[ -n "${BASE_IMAGE}" ]]; then
  ok "base image tracks ${BASE_IMAGE}"
else
  fail_note "could not resolve the devcontainer base image from ${DOCKERFILE_PATH}"
fi

if [[ -n "${DEVCONTAINER_FEATURE_VERSIONS}" ]]; then
  while IFS=$'\t' read -r feature_name feature_version; do
    [[ -n "${feature_name}" ]] || continue

    if [[ -z "${feature_version}" || "${feature_version}" == "latest" ]]; then
      warn "devcontainer feature ${feature_name} tracks ${feature_version:-its default version}"
    else
      ok "devcontainer feature ${feature_name} is pinned to ${feature_version}"
    fi
  done <<< "${DEVCONTAINER_FEATURE_VERSIONS}"
else
  warn "could not resolve any devcontainer feature versions from ${DEVCONTAINER_CONFIG}"
fi

if [[ -n "${EXPECTED_UV_VERSION}" ]]; then
  ok "uv is pinned to ${EXPECTED_UV_VERSION} in the Dockerfile"
else
  fail_note "could not resolve the pinned uv version from ${DOCKERFILE_PATH}"
fi

if [[ -n "${EXPECTED_OPENTOFU_VERSION}" ]]; then
  ok "OpenTofu is pinned to ${EXPECTED_OPENTOFU_VERSION} in install-toolchain.sh"
else
  fail_note "could not resolve the pinned OpenTofu version from ${INSTALL_TOOLCHAIN_SCRIPT}"
fi

warn "bun resolves from the upstream install script at build time"
warn "Lima resolves from the latest GitHub release at build time"
warn "Kyverno resolves from the latest GitHub release at build time"
if [[ -n "${ARKADE_TOOLS}" ]]; then
  warn "arkade-managed tools resolve at build time: ${ARKADE_TOOLS}"
else
  warn "arkade-managed tool list could not be resolved from install-toolchain.sh"
fi
warn "slicer resolves from ghcr.io/openfaasltd/slicer:latest at build time"

WORKSPACE_CONTAINER_ID=""
WORKSPACE_CONTAINER_STATUS=""
WORKSPACE_CONTAINER_CREATED=""
WORKSPACE_IMAGE_ID=""
WORKSPACE_IMAGE_CREATED=""

if docker_available; then
  WORKSPACE_CONTAINER_ID="$(select_workspace_container_id || true)"
  if [[ -n "${WORKSPACE_CONTAINER_ID}" ]]; then
    WORKSPACE_CONTAINER_STATUS="$(docker inspect --format '{{.State.Status}}' "${WORKSPACE_CONTAINER_ID}" 2>/dev/null || true)"
    WORKSPACE_CONTAINER_CREATED="$(docker inspect --format '{{.Created}}' "${WORKSPACE_CONTAINER_ID}" 2>/dev/null || true)"
    WORKSPACE_IMAGE_ID="$(docker inspect --format '{{.Image}}' "${WORKSPACE_CONTAINER_ID}" 2>/dev/null || true)"
    if [[ -n "${WORKSPACE_IMAGE_ID}" ]]; then
      WORKSPACE_IMAGE_CREATED="$(docker image inspect --format '{{.Created}}' "${WORKSPACE_IMAGE_ID}" 2>/dev/null || true)"
    fi
  fi
fi

section "Workspace"

if inside_devcontainer; then
  ok "running inside the devcontainer"
fi

if [[ -n "${WORKSPACE_CONTAINER_ID}" ]]; then
  short_container_id="${WORKSPACE_CONTAINER_ID:0:12}"
  ok "workspace container ${short_container_id} is ${WORKSPACE_CONTAINER_STATUS:-unknown}"

  if [[ -n "${WORKSPACE_CONTAINER_CREATED}" ]]; then
    container_age_days="$(age_days_from_iso "${WORKSPACE_CONTAINER_CREATED}" 2>/dev/null || true)"
    if [[ -n "${container_age_days}" ]]; then
      if age_exceeds_threshold "${container_age_days}"; then
        fail_note "workspace container is ${container_age_days} day(s) old; rebuild with make -C .devcontainer build"
      else
        ok "workspace container age ${container_age_days} day(s)"
      fi
    fi
  fi

  if [[ -n "${WORKSPACE_IMAGE_ID}" ]]; then
    short_image_id="${WORKSPACE_IMAGE_ID#sha256:}"
    short_image_id="${short_image_id:0:12}"
    ok "workspace image ${short_image_id} is available locally"
  fi

  if [[ -n "${WORKSPACE_IMAGE_CREATED}" ]]; then
    image_age_days="$(age_days_from_iso "${WORKSPACE_IMAGE_CREATED}" 2>/dev/null || true)"
    if [[ -n "${image_age_days}" ]]; then
      if age_exceeds_threshold "${image_age_days}"; then
        fail_note "workspace image is ${image_age_days} day(s) old; rebuild with make -C .devcontainer build"
      else
        ok "workspace image age ${image_age_days} day(s)"
      fi
    fi
  fi
else
  warn "no workspace devcontainer was found; run build/run to validate the live toolchain"
fi

section "Live Toolchain"

if inside_devcontainer || [[ "${WORKSPACE_CONTAINER_STATUS:-}" == "running" ]]; then
  check_pinned_tool_version "OpenTofu" "${EXPECTED_OPENTOFU_VERSION}" "tofu -version 2>/dev/null | sed -n '1s/^OpenTofu v//p'"
  check_pinned_tool_version "uv" "${EXPECTED_UV_VERSION}" "uv --version 2>/dev/null | awk 'NR==1 { print \$2; exit }'"
  report_live_tool_version "terragrunt" "terragrunt --version 2>/dev/null | sed -E 's/.* v?([0-9][^[:space:]]*).*/\\1/' | head -n 1"
  report_live_tool_version "kind" "kind version 2>/dev/null | awk 'NR==1 { print \$2; exit }'"
  report_live_tool_version "kubectl" "kubectl version --client --output=yaml 2>/dev/null | sed -n 's/^  gitVersion: v//p' | head -n 1"
  report_live_tool_version "helm" "helm version --short 2>/dev/null | sed -E 's/^v//; s/[+].*$//'"
  report_live_tool_version "bun" "bun --version 2>/dev/null | head -n 1"
  report_live_tool_version "cilium" "cilium version --client 2>/dev/null | awk '/cilium-cli:/ { sub(/^v/, \"\", \$2); print \$2; exit }'"
  report_live_tool_version "hubble" "hubble version 2>&1 | sed -nE '1s/^hubble v?([^[:space:]]+).*/\\1/p'"
  report_live_tool_version "k3sup" "k3sup version 2>&1 | tr -d '\\033' | sed -E 's/\\[[0-9;]*[[:alpha:]]//g' | sed -nE 's/^Version:[[:space:]]+([0-9][^[:space:]]*).*/\\1/p' | head -n 1"
  report_live_tool_version "kubie" "kubie --version 2>/dev/null | sed -E 's/^kubie[[:space:]]+v?//' | head -n 1"
  report_live_tool_version "kyverno" "kyverno version 2>/dev/null | awk '/Version:/ { sub(/^v/, \"\", \$2); print \$2; exit }'"
  report_live_tool_version "limactl" "limactl --version 2>&1 | sed -E 's/^limactl version v?//' | head -n 1"
  report_live_tool_version "mkcert" "mkcert -version 2>/dev/null | sed 's/^v//'"
else
  warn "live tool-version checks were skipped because no running devcontainer is available"
fi

if [[ "${FAILURES}" -gt 0 ]]; then
  exit 1
fi
