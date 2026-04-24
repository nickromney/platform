#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
DEVCONTAINER_CONFIG="${DEVCONTAINER_CONFIG:-${REPO_ROOT}/.devcontainer/devcontainer.json}"
DOCKERFILE_PATH="${DOCKERFILE_PATH:-${REPO_ROOT}/.devcontainer/Dockerfile}"
INSTALL_TOOLCHAIN_SCRIPT="${INSTALL_TOOLCHAIN_SCRIPT:-${REPO_ROOT}/.devcontainer/install-toolchain.sh}"
TOOLCHAIN_VERSIONS_FILE="${TOOLCHAIN_VERSIONS_FILE:-${REPO_ROOT}/.devcontainer/toolchain-versions.sh}"
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

run_inline_python() {
  command -v uv >/dev/null 2>&1 || {
    printf 'uv not found in PATH\n' >&2
    exit 1
  }

  uv run --isolated python - "$@"
}

parse_expected_uv_version() {
  sed -nE 's#^COPY --from=ghcr\.io/astral-sh/uv:([^[:space:]]+) /uv /usr/local/bin/uv#\1#p' "${DOCKERFILE_PATH}" | head -n 1
}

parse_base_image() {
  sed -nE 's/^FROM[[:space:]]+([^[:space:]]+).*/\1/p' "${DOCKERFILE_PATH}" | head -n 1
}

parse_devcontainer_features() {
  run_inline_python "${DEVCONTAINER_CONFIG}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)

features = payload.get("features") or {}
for feature_ref in features:
    feature_id, feature_tag = feature_ref.rsplit(":", 1)
    print(f"{feature_id}\t{feature_tag}")
PY
}

strip_v_prefix() {
  printf '%s\n' "${1#v}"
}

arkade_tool_version() {
  local tool_name="$1"
  local entry=""

  for entry in "${DEVCONTAINER_ARKADE_TOOLS[@]}"; do
    if [[ "${entry%%=*}" == "${tool_name}" ]]; then
      printf '%s\n' "${entry#*=}"
      return 0
    fi
  done

  return 1
}

find_feature_definition() {
  local feature_id="$1"
  awk -F $'\t' -v feature_id="${feature_id}" '$1 == feature_id { print; exit }' <<< "${DEVCONTAINER_FEATURES}"
}

feature_option_value() {
  local feature_ref="$1"
  local option_name="$2"

  run_inline_python "${DEVCONTAINER_CONFIG}" "${feature_ref%:*}" "${option_name}" <<'PY'
import json
import sys

config_path, target_feature_id, option_name = sys.argv[1:4]

with open(config_path, encoding="utf-8") as handle:
    payload = json.load(handle)

features = payload.get("features") or {}
for feature_ref, config in features.items():
    feature_id, _ = feature_ref.rsplit(":", 1)
    if feature_id != target_feature_id:
        continue
    if not isinstance(config, dict):
        break
    value = config.get(option_name)
    if isinstance(value, bool):
        print(str(value).lower())
    elif value is not None:
        print(str(value).strip())
    break
PY
}

check_feature_definition() {
  local feature_ref="$1"
  local feature_id expected_tag definition actual_tag

  feature_id="${feature_ref%:*}"
  expected_tag="${feature_ref##*:}"
  definition="$(find_feature_definition "${feature_id}")"

  if [[ -z "${definition}" ]]; then
    fail_note "devcontainer feature ${feature_id} is missing"
    return 0
  fi

  IFS=$'\t' read -r _ actual_tag <<< "${definition}"

  if [[ "${actual_tag}" == "${expected_tag}" ]]; then
    ok "devcontainer feature ${feature_id} is pinned to ${actual_tag}"
  else
    fail_note "devcontainer feature ${feature_id} resolves to ${actual_tag}, expected ${expected_tag}"
  fi
}

check_feature_option() {
  local feature_ref="$1"
  local option_name="$2"
  local expected_value="$3"
  local feature_id actual_value

  feature_id="${feature_ref%:*}"
  actual_value="$(feature_option_value "${feature_ref}" "${option_name}" 2>/dev/null || true)"
  actual_value="$(trim "${actual_value}")"

  if [[ "${actual_value}" == "${expected_value}" ]]; then
    ok "devcontainer feature ${feature_id} option ${option_name} is pinned to ${actual_value}"
  else
    fail_note "devcontainer feature ${feature_id} option ${option_name} is ${actual_value:-unset}, expected ${expected_value}"
  fi
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
  run_inline_python "$1" <<'PY'
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

check_tool_absent() {
  local label="$1"
  local command="$2"
  local actual=""

  actual="$(run_in_live_env "${command}" 2>/dev/null || true)"
  actual="$(trim "${actual}")"

  if [[ -z "${actual}" ]]; then
    ok "${label} is intentionally absent from the live devcontainer environment"
  else
    fail_note "${label} should be absent from the live devcontainer environment, found ${actual}"
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
require_file "${TOOLCHAIN_VERSIONS_FILE}"

# shellcheck source=/dev/null
source "${TOOLCHAIN_VERSIONS_FILE}"

if ! [[ "${DEVCONTAINER_CHECK_STALE_DAYS}" =~ ^[0-9]+$ ]]; then
  printf 'DEVCONTAINER_CHECK_STALE_DAYS must be an integer, got: %s\n' "${DEVCONTAINER_CHECK_STALE_DAYS}" >&2
  exit 1
fi

EXPECTED_UV_VERSION="$(parse_expected_uv_version)"
BASE_IMAGE="$(parse_base_image)"
DEVCONTAINER_FEATURES="$(parse_devcontainer_features 2>/dev/null || true)"

section "Definition"

if [[ -n "${BASE_IMAGE}" ]]; then
  ok "base image tracks ${BASE_IMAGE}"
else
  fail_note "could not resolve the devcontainer base image from ${DOCKERFILE_PATH}"
fi

if [[ -n "${DEVCONTAINER_FEATURES}" ]]; then
  check_feature_definition "${DEVCONTAINER_DOCKER_FEATURE_REF}"
  check_feature_option "${DEVCONTAINER_DOCKER_FEATURE_REF}" "version" "${DEVCONTAINER_DOCKER_CLI_VERSION}"
  check_feature_option "${DEVCONTAINER_DOCKER_FEATURE_REF}" "mobyBuildxVersion" "${DEVCONTAINER_DOCKER_BUILDX_VERSION}"
  check_feature_option "${DEVCONTAINER_DOCKER_FEATURE_REF}" "dockerDashComposeVersion" "${DEVCONTAINER_DOCKER_COMPOSE_CHANNEL}"
  check_feature_definition "${DEVCONTAINER_NODE_FEATURE_REF}"
  check_feature_option "${DEVCONTAINER_NODE_FEATURE_REF}" "version" "${DEVCONTAINER_NODE_VERSION}"
  check_feature_option "${DEVCONTAINER_NODE_FEATURE_REF}" "nvmVersion" "${DEVCONTAINER_NODE_NVM_VERSION}"
  check_feature_option "${DEVCONTAINER_NODE_FEATURE_REF}" "pnpmVersion" "${DEVCONTAINER_NODE_PNPM_VERSION}"
else
  warn "could not resolve any devcontainer feature definitions from ${DEVCONTAINER_CONFIG}"
fi

if [[ -n "${EXPECTED_UV_VERSION}" ]]; then
  ok "uv is pinned to ${EXPECTED_UV_VERSION} in the Dockerfile"
else
  fail_note "could not resolve the pinned uv version from ${DOCKERFILE_PATH}"
fi

ok "OpenTofu is pinned to ${OPENTOFU_VERSION} in toolchain-versions.sh"
ok "Bun is pinned to ${BUN_VERSION}"
ok "Starship is pinned to ${STARSHIP_VERSION}"
ok "step is pinned to ${STEP_VERSION}"
ok "Kyverno is pinned to ${KYVERNO_VERSION}"
ok "Lima is pinned to ${LIMA_VERSION}"
ok "arkade is pinned to ${ARKADE_VERSION}"
ok "mkcert is pinned to ${MKCERT_VERSION}"
ok "pnpm is disabled in the Node feature via ${DEVCONTAINER_NODE_PNPM_VERSION}"
ok "slicer is intentionally omitted from the devcontainer toolchain"
ok "Node feature subtools are pinned: nvm ${DEVCONTAINER_NODE_NVM_VERSION}, pnpm disabled"
ok "Docker feature subtools are pinned: buildx ${DEVCONTAINER_DOCKER_BUILDX_VERSION}, docker-compose channel ${DEVCONTAINER_DOCKER_COMPOSE_CHANNEL}"
ok "arkade-managed tools are pinned: $(printf '%s, ' "${DEVCONTAINER_ARKADE_TOOLS[@]}" | sed 's/, $//')"

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
  check_pinned_tool_version "docker" "${DEVCONTAINER_DOCKER_CLI_VERSION}" "docker --version 2>/dev/null | sed -nE 's/^Docker version ([0-9.]+).*/\\1/p'"
  check_pinned_tool_version "docker buildx" "${DEVCONTAINER_DOCKER_BUILDX_VERSION}" "docker buildx version 2>/dev/null | sed -nE 's/.* v?([0-9][^[:space:]]*).*/\\1/p' | sed -E 's/-[0-9]+$//' | head -n 1"
  check_pinned_tool_version "node" "${DEVCONTAINER_NODE_VERSION}" "node --version 2>/dev/null | sed 's/^v//'"
  check_tool_absent "pnpm" "command -v pnpm 2>/dev/null | head -n 1"
  check_pinned_tool_version "nvm" "${DEVCONTAINER_NODE_NVM_VERSION}" "export NVM_DIR=\"\${NVM_DIR:-/usr/local/share/nvm}\"; [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\" && nvm --version 2>/dev/null | head -n 1"
  check_pinned_tool_version "OpenTofu" "${OPENTOFU_VERSION}" "tofu -version 2>/dev/null | sed -n '1s/^OpenTofu v//p'"
  check_pinned_tool_version "uv" "${EXPECTED_UV_VERSION}" "uv --version 2>/dev/null | awk 'NR==1 { print \$2; exit }'"
  check_pinned_tool_version "bun" "${BUN_VERSION#bun-v}" "bun --version 2>/dev/null | head -n 1"
  check_pinned_tool_version "starship" "$(strip_v_prefix "${STARSHIP_VERSION}")" "starship --version 2>/dev/null | awk 'NR==1 { print \$2; exit }'"
  check_pinned_tool_version "step" "$(strip_v_prefix "${STEP_VERSION}")" "step version 2>/dev/null | sed -nE 's/^Smallstep CLI\\/([0-9][^[:space:]]*).*/\\1/p' | head -n 1"
  check_pinned_tool_version "arkade" "$(strip_v_prefix "${ARKADE_VERSION}")" "arkade version 2>/dev/null | tr -d '\\033' | sed -E 's/\\[[0-9;]*[[:alpha:]]//g' | sed -nE 's/^Version:[[:space:]]*([0-9][^[:space:]]*).*/\\1/p' | head -n 1"
  check_pinned_tool_version "terragrunt" "$(strip_v_prefix "$(arkade_tool_version terragrunt)")" "terragrunt --version 2>/dev/null | sed -E 's/.* v?([0-9][^[:space:]]*).*/\\1/' | head -n 1"
  check_pinned_tool_version "kind" "$(arkade_tool_version kind)" "kind version 2>/dev/null | awk 'NR==1 { print \$2; exit }'"
  check_pinned_tool_version "kubectl" "$(strip_v_prefix "$(arkade_tool_version kubectl)")" "kubectl version --client --output=yaml 2>/dev/null | sed -n 's/^  gitVersion: v//p' | head -n 1"
  check_pinned_tool_version "helm" "$(strip_v_prefix "$(arkade_tool_version helm)")" "helm version --short 2>/dev/null | sed -E 's/^v//; s/[+].*$//'"
  check_pinned_tool_version "cilium" "$(strip_v_prefix "$(arkade_tool_version cilium)")" "cilium version --client 2>/dev/null | awk '/cilium-cli:/ { sub(/^v/, \"\", \$2); print \$2; exit }'"
  check_pinned_tool_version "hubble" "$(strip_v_prefix "$(arkade_tool_version hubble)")" "hubble version 2>&1 | sed -nE '1s/^hubble v?([^[:space:]]+).*/\\1/p' | sed 's/@.*$//'"
  check_pinned_tool_version "k3sup" "$(arkade_tool_version k3sup)" "k3sup version 2>&1 | tr -d '\\033' | sed -E 's/\\[[0-9;]*[[:alpha:]]//g' | sed -nE 's/^Version:[[:space:]]+([0-9][^[:space:]]*).*/\\1/p' | head -n 1"
  check_pinned_tool_version "kubie" "$(strip_v_prefix "$(arkade_tool_version kubie)")" "kubie --version 2>/dev/null | sed -E 's/^kubie[[:space:]]+v?//' | head -n 1"
  check_pinned_tool_version "kyverno" "$(strip_v_prefix "${KYVERNO_VERSION}")" "kyverno version 2>/dev/null | awk '/Version:/ { sub(/^v/, \"\", \$2); print \$2; exit }'"
  check_pinned_tool_version "limactl" "$(strip_v_prefix "${LIMA_VERSION}")" "limactl --version 2>&1 | sed -E 's/^limactl version v?//' | head -n 1"
  check_pinned_tool_version "mkcert" "$(strip_v_prefix "${MKCERT_VERSION}")" "mkcert -version 2>/dev/null | sed 's/^v//'"
  check_tool_absent "slicer" "command -v slicer 2>/dev/null | head -n 1"
  check_pinned_tool_version "yq" "$(strip_v_prefix "$(arkade_tool_version yq)")" "yq --version 2>/dev/null | sed -nE 's/^.* version v?([0-9][^[:space:]]*).*/\\1/p' | head -n 1"
  check_pinned_tool_version "jq" "$(arkade_tool_version jq)" "jq --version 2>/dev/null | head -n 1"
else
  warn "live tool-version checks were skipped because no running devcontainer is available"
fi

if [[ "${FAILURES}" -gt 0 ]]; then
  exit 1
fi
