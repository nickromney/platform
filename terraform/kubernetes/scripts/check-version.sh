#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/http-fetch.sh"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/parallel.sh"

CHECK_VERSION_FORMAT="${CHECK_VERSION_FORMAT:-text}"

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
NC=$'\033[0m'

json_mode() {
  [ "${CHECK_VERSION_FORMAT}" = "json" ]
}

ok() {
  if json_mode; then
    return 0
  fi
  echo "${GREEN}✔${NC} $*"
}

warn() {
  if json_mode; then
    return 0
  fi
  echo "${YELLOW}⚠${NC} $*"
}

fail() { echo "${RED}✖${NC} $*" >&2; exit 1; }
progress() {
  if json_mode; then
    return 0
  fi
  printf '... %s\n' "$*" >&2
}

section() {
  if json_mode; then
    return 0
  fi
  printf '\n%s\n' "$*"
}

usage() {
  cat <<EOF
Usage: check-version.sh [--dry-run] [--execute]

Checks pinned platform component versions against current upstream releases and
the live cluster when reachable.

Environment:
  CHECK_VERSION_INCLUDE_CANARY=1      Include canary releases in latest-version checks
  CHECK_VERSION_INCLUDE_ALPHA=1       Include alpha releases in latest-version checks
  CHECK_VERSION_INCLUDE_PRERELEASE=1  Include other prerelease channels (beta/dev/rc/preview/next)
                                      All prerelease channels default to off

$(shell_cli_standard_options)
EOF
}

if [ "${CHECK_VERSION_LIB_ONLY:-0}" != "1" ]; then
  shell_cli_handle_standard_no_args usage "would compare pinned platform component versions against current upstream releases" "$@"
fi

CHECK_VERSION_HEARTBEAT_SECONDS="${CHECK_VERSION_HEARTBEAT_SECONDS:-10}"
CHECK_VERSION_HEARTBEAT_PID=""
HTTP_FETCH_MAX_TIME_SECONDS="${HTTP_FETCH_MAX_TIME_SECONDS:-${CHECK_VERSION_CURL_MAX_TIME_SECONDS:-15}}"
HTTP_FETCH_CONNECT_TIMEOUT_SECONDS="${HTTP_FETCH_CONNECT_TIMEOUT_SECONDS:-${CHECK_VERSION_CURL_CONNECT_TIMEOUT_SECONDS:-5}}"
CHECK_VERSION_INCLUDE_PRERELEASE="${CHECK_VERSION_INCLUDE_PRERELEASE:-0}"
CHECK_VERSION_INCLUDE_CANARY="${CHECK_VERSION_INCLUDE_CANARY:-0}"
CHECK_VERSION_INCLUDE_ALPHA="${CHECK_VERSION_INCLUDE_ALPHA:-0}"

start_heartbeat() {
  local message="$1"
  local interval="${CHECK_VERSION_HEARTBEAT_SECONDS}"

  case "${interval}" in
    ''|*[!0-9]*|0)
      return 0
      ;;
  esac

  (
    while :; do
      sleep "${interval}" || exit 0
      printf '... %s\n' "${message}" >&2
    done
  ) &
  CHECK_VERSION_HEARTBEAT_PID=$!
}

stop_heartbeat() {
  local pid="${CHECK_VERSION_HEARTBEAT_PID:-}"

  if [ -z "${pid}" ]; then
    return 0
  fi

  kill "${pid}" >/dev/null 2>&1 || true
  wait "${pid}" >/dev/null 2>&1 || true
  CHECK_VERSION_HEARTBEAT_PID=""
}

require() {
  local bin="$1"
  command -v "$bin" >/dev/null 2>&1 || fail "$bin not found in PATH"
}

run_inline_python() {
  if command -v uv >/dev/null 2>&1; then
    uv run --isolated python - "$@"
    return 0
  fi

  python3 - "$@"
}

cluster_reachable() {
  if ! command -v kubectl >/dev/null 2>&1; then
    return 1
  fi

  # Fast failure when kubeconfig/current-context isn't set.
  local ctx
  ctx=$(kubectl config current-context 2>/dev/null || true)
  if [ -z "$ctx" ]; then
    return 1
  fi

  # Keep this very short; we only want to know whether the API server is reachable.
  kubectl get ns --request-timeout=2s >/dev/null 2>&1
}

kind_get_clusters_safe() {
  local timeout="${CHECK_VERSION_KIND_GET_CLUSTERS_TIMEOUT_SECONDS:-5}"
  local tmp pid start elapsed rc

  tmp="$(mktemp)"
  kind get clusters >"${tmp}" 2>/dev/null &
  pid=$!
  start="$(date +%s)"

  while kill -0 "${pid}" >/dev/null 2>&1; do
    elapsed=$(( $(date +%s) - start ))
    if [ "${elapsed}" -ge "${timeout}" ]; then
      kill "${pid}" >/dev/null 2>&1 || true
      wait "${pid}" >/dev/null 2>&1 || true
      rm -f "${tmp}"
      return 124
    fi
    sleep 1
  done

  wait "${pid}"
  rc=$?
  cat "${tmp}"
  rm -f "${tmp}"
  return "${rc}"
}

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
STACK_DIR="${STACK_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"
STAGES_DIR="${STAGES_DIR:-${REPO_ROOT}/kubernetes/kind/stages}"
TARGET_TFVARS="${TARGET_TFVARS:-}"
PRELOAD_IMAGES_FILE="${PRELOAD_IMAGES_FILE:-${REPO_ROOT}/kubernetes/kind/preload-images.txt}"
ARGOCD_APPS_DIR="${ARGOCD_APPS_DIR:-${STACK_DIR}/apps/argocd-apps}"
APIM_SIMULATOR_VENDOR_DIR="${CHECK_VERSION_APIM_SIMULATOR_VENDOR_DIR:-${REPO_ROOT}/apps/subnet-calculator/apim-simulator}"
export VARIABLES_FILE="${VARIABLES_FILE:-${STACK_DIR}/variables.tf}"
HELM_READY_REPOS=""
CHECK_VERSION_CACHE_DIR="${CHECK_VERSION_CACHE_DIR:-}"
HTTP_FETCH_CACHE_DIR="${HTTP_FETCH_CACHE_DIR:-${CHECK_VERSION_CACHE_DIR:-}}"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/tf-defaults.sh"

tfvar_get_from_file() {
  local file="$1"
  local key="$2"
  if [ ! -f "$file" ]; then
    echo ""
    return 0
  fi
  local line
  line=$(grep -E "^[[:space:]]*${key}[[:space:]]*=[[:space:]]*" "$file" 2>/dev/null | tail -n 1 || true)
  if [ -z "$line" ]; then
    echo ""
    return 0
  fi
  echo "$line" | sed -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"?([^\"#]+)\"?.*$/\1/" | xargs
}

tfvar_get() {
  tfvar_get_from_file "$1" "$2"
}

tfvar_get_any_stage() {
  local key="$1"
  local value

  if [ -n "${TARGET_TFVARS}" ] && [ -f "${TARGET_TFVARS}" ]; then
    value=$(tfvar_get_from_file "${TARGET_TFVARS}" "${key}")
    if [ -n "${value}" ]; then
      echo "${value}"
      return 0
    fi
  fi

  local line
  line=$(grep -hE "^[[:space:]]*${key}[[:space:]]*=[[:space:]]*" "${STAGES_DIR}"/*.tfvars 2>/dev/null | head -n 1 || true)
  if [ -z "$line" ]; then
    echo ""
    return 0
  fi
  echo "$line" | sed -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"?([^\"#]+)\"?.*$/\1/" | xargs
}

tfvar_get_any_stage_or_default() {
  local key="$1"
  local fallback="$2"
  local v
  v=$(tfvar_get_any_stage "$key")
  if [ -n "$v" ]; then
    echo "$v"
  else
    echo "$fallback"
  fi
}

tfvar_get_any_stage_bool_or_default() {
  local key="$1"
  local fallback="$2"
  local value

  value="$(tfvar_get_any_stage "$key")"
  case "${value}" in
    true|false)
      printf '%s\n' "${value}"
      ;;
    *)
      printf '%s\n' "${fallback}"
      ;;
  esac
}

uri_encode() {
  jq -rn --arg value "$1" '$value | @uri'
}

normalize_python_package_name() {
  printf '%s\n' "$1" | tr '[:upper:]' '[:lower:]' | tr '_' '-'
}

js_dependency_cooldown_seconds() {
  local app_dir="$1"
  local bunfig="${app_dir}/bunfig.toml"
  local npmrc="${app_dir}/.npmrc"
  local value=""

  if [ -f "${bunfig}" ]; then
    value="$(awk -F= '/minimumReleaseAge[[:space:]]*=/{gsub(/[[:space:]"]/, "", $2); print $2; exit}' "${bunfig}" 2>/dev/null || true)"
    if [[ "${value}" =~ ^[0-9]+$ ]]; then
      printf '%s\n' "${value}"
      return 0
    fi
  fi

  if [ -f "${npmrc}" ]; then
    value="$(awk -F= '/^min-release-age=/{gsub(/[[:space:]]/, "", $2); print $2; exit}' "${npmrc}" 2>/dev/null || true)"
    if [[ "${value}" =~ ^[0-9]+$ ]]; then
      printf '%s\n' "$((value * 86400))"
      return 0
    fi
  fi

  printf '\n'
}

python_dependency_cooldown_cutoff() {
  local app_dir="$1"
  local uv_lock="${app_dir}/uv.lock"

  if [ -f "${uv_lock}" ]; then
    awk -F'"' '/^exclude-newer = "/ { print $2; exit }' "${uv_lock}" 2>/dev/null || true
    return 0
  fi

  printf '\n'
}

package_json_direct_dependencies() {
  local package_json="$1"

  if [ ! -f "${package_json}" ]; then
    return 0
  fi

  jq -r \
    '(.dependencies // {} | to_entries[]? | [.key, .value] | @tsv),
     (.devDependencies // {} | to_entries[]? | [.key, .value] | @tsv)' \
    "${package_json}" 2>/dev/null || true
}

js_dependency_spec_status() {
  local spec="$1"

  case "${spec}" in
    file:*|link:*|workspace:*)
      printf 'local/path dependency\n'
      ;;
    git+*|github:*|http://*|https://*)
      printf 'direct-url dependency\n'
      ;;
    *)
      printf '\n'
      ;;
  esac
}

bun_lock_resolved_version() {
  local lockfile="$1"
  local dep="$2"
  local line=""
  local marker=""

  if [ ! -f "${lockfile}" ]; then
    printf '\n'
    return 0
  fi

  line="$(grep -F "\"${dep}\": [\"${dep}@" "${lockfile}" 2>/dev/null | head -n 1 || true)"
  if [ -z "${line}" ]; then
    printf '\n'
    return 0
  fi

  marker="\"${dep}\": [\"${dep}@"
  line="${line#*"${marker}"}"
  line="${line%%\"*}"
  printf '%s\n' "${line}" | xargs || true
}

trim_surrounding_whitespace() {
  local value="$1"

  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s\n' "${value}"
}

pyproject_project_dependencies() {
  local pyproject="$1"

  [ -f "${pyproject}" ] || return 0

  run_inline_python "${pyproject}" <<'PY' 2>/dev/null || true
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
in_project = False
collecting = False
buffer = []

def array_closed(fragment: str) -> bool:
    in_string = False
    escaped = False
    in_comment = False

    for char in fragment:
        if in_comment:
            if char == "\n":
                in_comment = False
            continue

        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue

        if char == "#":
            in_comment = True
        elif char == '"':
            in_string = True
        elif char == "]":
            return True

    return False

for line in text.splitlines(keepends=True):
    stripped = line.strip()

    if collecting:
        buffer.append(line)
        if array_closed(line):
            break
        continue

    if stripped.startswith("[") and stripped.endswith("]"):
        in_project = stripped == "[project]"
        continue

    if not in_project:
        continue

    before, sep, after = line.partition("=")
    if not sep or before.strip() != "dependencies":
        continue

    bracket_index = after.find("[")
    if bracket_index == -1:
        continue

    fragment = after[bracket_index:]
    buffer.append(fragment if fragment.endswith("\n") else fragment + "\n")
    if array_closed(fragment):
        break
    collecting = True

if not buffer:
    raise SystemExit(0)

array_text = "".join(buffer)
in_string = False
escaped = False
in_comment = False
current = []

for char in array_text:
    if in_comment:
        if char == "\n":
            in_comment = False
        continue

    if in_string:
        if escaped:
            current.append(char)
            escaped = False
        elif char == "\\":
            current.append(char)
            escaped = True
        elif char == '"':
            print("".join(current))
            current = []
            in_string = False
        else:
            current.append(char)
        continue

    if char == "#":
        in_comment = True
    elif char == '"':
        in_string = True
    elif char == "]":
        break
PY
}

python_requirement_name() {
  local requirement="$1"
  local name=""

  requirement="$(trim_surrounding_whitespace "${requirement}")"
  name="$(printf '%s\n' "${requirement}" | sed -E 's/\[.*$//; s/[<>=!~].*$//; s/[[:space:]].*$//')"
  normalize_python_package_name "${name}"
}

python_requirement_status() {
  local requirement="$1"
  local trimmed=""

  trimmed="$(trim_surrounding_whitespace "${requirement}")"
  if [ -z "${trimmed}" ] || [[ "${trimmed}" == \#* ]]; then
    printf 'skip\n'
    return 0
  fi

  case "${trimmed}" in
    *" @ file:"*|*" @ ../"*|*" @ /"*)
      printf 'local/path dependency\n'
      ;;
    *" @ git+"*|*" @ http://"*|*" @ https://"*)
      printf 'direct-url dependency\n'
      ;;
    *)
      printf '\n'
      ;;
  esac
}

check_version_flag_enabled() {
  case "${1:-0}" in
    1|true|TRUE|yes|YES|on|ON)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

check_version_include_prerelease() {
  check_version_flag_enabled "${CHECK_VERSION_INCLUDE_PRERELEASE}"
}

check_version_include_canary() {
  check_version_flag_enabled "${CHECK_VERSION_INCLUDE_CANARY}"
}

check_version_include_alpha() {
  check_version_flag_enabled "${CHECK_VERSION_INCLUDE_ALPHA}"
}

version_prerelease_channel() {
  local version

  version="$(printf '%s\n' "$1" | tr '[:upper:]' '[:lower:]')"

  case "${version}" in
    *canary*)
      printf 'canary\n'
      return 0
      ;;
    *alpha*)
      printf 'alpha\n'
      return 0
      ;;
    *beta*|*preview*|*dev*|*next*)
      printf 'other\n'
      return 0
      ;;
  esac

  if [[ "${version}" =~ [0-9]a[0-9] ]]; then
    printf 'alpha\n'
    return 0
  fi

  if [[ "${version}" =~ [0-9]b[0-9] ]] || [[ "${version}" =~ [0-9]rc[0-9] ]]; then
    printf 'other\n'
    return 0
  fi

  if [[ "${version}" =~ (^|[._-])pre([._-]|[0-9]|$) ]] || [[ "${version}" =~ (^|[._-])rc([._-]|[0-9]|$) ]]; then
    printf 'other\n'
    return 0
  fi

  printf 'stable\n'
}

version_is_prerelease() {
  [ "$(version_prerelease_channel "$1")" != "stable" ]
}

version_prerelease_allowed() {
  case "$(version_prerelease_channel "$1")" in
    stable)
      return 0
      ;;
    canary)
      check_version_include_canary
      ;;
    alpha)
      check_version_include_alpha
      ;;
    *)
      check_version_include_prerelease
      ;;
  esac
}

filter_prerelease_versions() {
  local version

  while IFS= read -r version; do
    [ -n "${version}" ] || continue
    if version_prerelease_allowed "${version}"; then
      printf '%s\n' "${version}"
    fi
  done
}

version_gte() {
  local left="$1"
  local right="$2"

  [ "${left}" = "${right}" ] || [ "$(printf '%s\n%s\n' "${left}" "${right}" | sort -V | tail -n 1)" = "${left}" ]
}

uv_lock_resolved_version() {
  local lockfile="$1"
  local dep

  dep="$(normalize_python_package_name "$2")"
  if [ ! -f "${lockfile}" ]; then
    printf '\n'
    return 0
  fi

  awk -v dep="${dep}" '
    /^\[\[package\]\]$/ {
      in_pkg = 1
      name = ""
      version = ""
      next
    }
    in_pkg && /^name = "/ {
      line = $0
      sub(/^name = "/, "", line)
      sub(/".*$/, "", line)
      gsub(/_/, "-", line)
      name = tolower(line)
      next
    }
    in_pkg && /^version = "/ {
      line = $0
      sub(/^version = "/, "", line)
      sub(/".*$/, "", line)
      version = line
      next
    }
    in_pkg && name == dep && version != "" {
      print version
      exit
    }
  ' "${lockfile}" 2>/dev/null | xargs || true
}

npm_registry_payload() {
  local dep="$1"
  local encoded_dep cache_file

  encoded_dep="$(uri_encode "${dep}")"
  cache_file="$(http_cache_file_for_key "npm" "${encoded_dep}")"
  if [ ! -f "${cache_file}" ]; then
    http_fetch -fsSL "https://registry.npmjs.org/${encoded_dep}" >"${cache_file}" 2>/dev/null || {
      rm -f "${cache_file}"
      return 1
    }
  fi

  cat "${cache_file}"
}

warm_npm_registry_payload() {
  local dep="$1"
  npm_registry_payload "${dep}" >/dev/null || true
}

pypi_package_payload() {
  local dep="$1"
  local normalized_dep cache_file

  normalized_dep="$(normalize_python_package_name "${dep}")"
  cache_file="$(http_cache_file_for_key "pypi" "${normalized_dep}")"
  if [ ! -f "${cache_file}" ]; then
    http_fetch -fsSL "https://pypi.org/pypi/${normalized_dep}/json" >"${cache_file}" 2>/dev/null || {
      rm -f "${cache_file}"
      return 1
    }
  fi

  cat "${cache_file}"
}

warm_pypi_package_payload() {
  local dep="$1"
  pypi_package_payload "${dep}" >/dev/null || true
}

npm_latest_overall_version() {
  local dep="$1"
  local payload

  payload="$(npm_registry_payload "${dep}" 2>/dev/null || true)"
  if [ -z "${payload}" ]; then
    printf '\n'
    return 0
  fi

  jq -r '."dist-tags".latest // empty' <<<"${payload}" 2>/dev/null | xargs || true
}

npm_latest_eligible_version() {
  local dep="$1"
  local cooldown_seconds="$2"
  local payload cutoff versions

  if [ -z "${cooldown_seconds}" ]; then
    npm_latest_overall_version "${dep}"
    return 0
  fi

  payload="$(npm_registry_payload "${dep}" 2>/dev/null || true)"
  if [ -z "${payload}" ]; then
    printf '\n'
    return 0
  fi

  cutoff="$(( $(date +%s) - cooldown_seconds ))"
  versions="$(
    jq -r --argjson cutoff "${cutoff}" '
      .time // {} | to_entries[]
      | select(.key != "created" and .key != "modified")
      | (.value | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601?) as $published
      | select($published != null and $published <= $cutoff)
      | .key
    ' <<<"${payload}" 2>/dev/null || true
  )"
  printf '%s\n' "${versions}" | sed '/^$/d' | filter_prerelease_versions | sort -V | tail -n 1
}

pypi_latest_overall_version() {
  local dep="$1"
  local payload

  payload="$(pypi_package_payload "${dep}" 2>/dev/null || true)"
  if [ -z "${payload}" ]; then
    printf '\n'
    return 0
  fi

  jq -r '.info.version // empty' <<<"${payload}" 2>/dev/null | xargs || true
}

pypi_latest_eligible_version() {
  local dep="$1"
  local cutoff_iso="$2"
  local payload versions

  if [ -z "${cutoff_iso}" ]; then
    pypi_latest_overall_version "${dep}"
    return 0
  fi

  payload="$(pypi_package_payload "${dep}" 2>/dev/null || true)"
  if [ -z "${payload}" ]; then
    printf '\n'
    return 0
  fi

  versions="$(
    jq -r --arg cutoff "${cutoff_iso}" '
      ($cutoff | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601?) as $cutoff_epoch
      | if $cutoff_epoch == null then
          empty
        else
          .releases
          | to_entries[]
          | select(.value | length > 0)
          | select(any(.value[]?;
              ((."upload_time_iso_8601" // .upload_time // empty)
                | if . == "" then null else (sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601?) end) as $uploaded
              | $uploaded != null and $uploaded <= $cutoff_epoch))
          | .key
        end
    ' <<<"${payload}" 2>/dev/null || true
  )"
  printf '%s\n' "${versions}" | sed '/^$/d' | filter_prerelease_versions | sort -V | tail -n 1
}

dependency_update_status() {
  local current="$1"
  local latest_eligible="$2"
  local latest_overall="$3"

  if [ -z "${current}" ] || [ -z "${latest_overall}" ]; then
    if [ -z "${current}" ]; then
      printf 'lockfile missing or unresolved\n'
    else
      printf 'latest lookup failed\n'
    fi
    return 0
  fi

  if [ "${current}" = "${latest_overall}" ]; then
    printf 'current\n'
    return 0
  fi

  if version_gte "${current}" "${latest_overall}"; then
    printf 'current\n'
    return 0
  fi

  if [ -n "${latest_eligible}" ] && [ "${current}" != "${latest_eligible}" ]; then
    printf 'update available\n'
    return 0
  fi

  if [ -n "${latest_eligible}" ] && [ "${latest_eligible}" != "${latest_overall}" ]; then
    printf 'cooldown active\n'
    return 0
  fi

  printf 'update available\n'
}

external_image_update_status() {
  local current="$1"
  local latest="$2"

  if [ -z "${current}" ] || [ -z "${latest}" ]; then
    printf 'latest lookup failed\n'
    return 0
  fi

  if [ "${current}" = "${latest}" ]; then
    printf 'current\n'
    return 0
  fi

  if version_gte "${current}" "${latest}"; then
    printf 'current\n'
    return 0
  fi

  printf 'update available\n'
}

image_ref_registry() {
  local image_ref="$1"
  local no_digest first_segment

  no_digest="${image_ref%@*}"
  if [[ "${no_digest}" != */* ]]; then
    printf 'docker.io\n'
    return 0
  fi

  first_segment="${no_digest%%/*}"
  if [[ "${first_segment}" == *.* || "${first_segment}" == *:* || "${first_segment}" == "localhost" ]]; then
    printf '%s\n' "${first_segment}"
  else
    printf 'docker.io\n'
  fi
}

image_ref_repository() {
  local image_ref="$1"
  local no_digest no_tag first_segment

  no_digest="${image_ref%@*}"
  no_tag="${no_digest}"
  if [[ "${no_digest##*/}" == *:* ]]; then
    no_tag="${no_digest%:*}"
  fi

  first_segment="${no_tag%%/*}"
  if [[ "${first_segment}" == *.* || "${first_segment}" == *:* || "${first_segment}" == "localhost" ]]; then
    printf '%s\n' "${no_tag#*/}"
  else
    printf '%s\n' "${no_tag}"
  fi
}

image_ref_is_internal() {
  local image_ref="$1"

  case "${image_ref}" in
    *\$\{*|localhost:*|127.0.0.1:*|platform/*|platform-*|subnet-calculator-*|subnetcalc-*|apim-simulator*|csharp-*)
      return 0
      ;;
  esac

  return 1
}

docker_hub_latest_tag_for_ref() {
  local image_ref="$1"
  local current_tag repository namespace repo_path suffix tags candidate_tags current_series

  current_tag="$(image_tag_from_ref "${image_ref}")"
  if [ -z "${current_tag}" ]; then
    printf '\n'
    return 0
  fi

  if [ "$(tag_version_segment_count "${current_tag}")" -lt 3 ]; then
    printf '\n'
    return 0
  fi

  repo_path="$(image_ref_repository "${image_ref}")"
  if [[ "${repo_path}" == */* ]]; then
    namespace="${repo_path%%/*}"
    repository="${repo_path#*/}"
  else
    namespace="library"
    repository="${repo_path}"
  fi

  tags="$(docker_hub_repo_tags "${namespace}" "${repository}" 2>/dev/null || true)"
  if [ -z "${tags}" ]; then
    printf '\n'
    return 0
  fi

  current_series="$(tag_release_series_key "${current_tag}")"
  suffix="$(tag_suffix_after_version_prefix "${current_tag}")"
  candidate_tags="$(
    while IFS= read -r tag; do
      [ -n "${tag}" ] || continue
      if [ -n "$(tag_version_prefix "${tag}")" ] && \
         [ "$(tag_release_series_key "${tag}")" = "${current_series}" ] && \
         [ "$(tag_suffix_after_version_prefix "${tag}")" = "${suffix}" ]; then
        printf '%s\n' "${tag}"
      fi
    done <<<"${tags}"
  )"

  if [ -n "${candidate_tags}" ]; then
    printf '%s\n' "${candidate_tags}" | sort -V | tail -n 1
    return 0
  fi

  printf '\n'
}

oci_registry_latest_tag_for_ref() {
  local image_ref="$1"
  local current_tag registry repository suffix tags candidate_tags current_series

  current_tag="$(image_tag_from_ref "${image_ref}")"
  if [ -z "${current_tag}" ]; then
    printf '\n'
    return 0
  fi

  if [ "$(tag_version_segment_count "${current_tag}")" -lt 3 ]; then
    printf '\n'
    return 0
  fi

  registry="$(image_ref_registry "${image_ref}")"
  repository="$(image_ref_repository "${image_ref}")"
  tags="$(oci_registry_repo_tags "${registry}" "${repository}" 2>/dev/null || true)"
  if [ -z "${tags}" ]; then
    printf '\n'
    return 0
  fi

  current_series="$(tag_release_series_key "${current_tag}")"
  suffix="$(tag_suffix_after_version_prefix "${current_tag}")"
  candidate_tags="$(
    while IFS= read -r tag; do
      [ -n "${tag}" ] || continue
      if [ -n "$(tag_version_prefix "${tag}")" ] && \
         [ "$(tag_release_series_key "${tag}")" = "${current_series}" ] && \
         [ "$(tag_suffix_after_version_prefix "${tag}")" = "${suffix}" ]; then
        printf '%s\n' "${tag}"
      fi
    done <<<"${tags}"
  )"

  if [ -n "${candidate_tags}" ]; then
    printf '%s\n' "${candidate_tags}" | sort -V | tail -n 1
    return 0
  fi

  printf '\n'
}

image_ref_has_template_placeholders() {
  local image_ref="$1"

  case "${image_ref}" in
    *"\${"*|__*__/*|*'__'*'__'*)
      return 0
      ;;
  esac

  return 1
}

image_status_when_latest_unknown() {
  local image_ref="$1"
  local registry="$2"
  local availability=""

  if image_ref_has_template_placeholders "${image_ref}"; then
    printf 'templated image reference\n'
    return 0
  fi

  case "${registry}" in
    dhi.io)
      printf 'vendor-managed mirror\n'
      return 0
      ;;
  esac

  availability="$(image_ref_availability "${image_ref}")"
  case "${availability}" in
    available)
      printf 'current tag verified; latest unresolved\n'
      ;;
    auth-required)
      printf 'registry auth required\n'
      ;;
    missing)
      printf 'current tag missing from registry\n'
      ;;
    *)
      printf 'latest lookup failed\n'
      ;;
  esac
}

collect_declared_image_refs() {
  local scan_root file line lineno ref

  for scan_root in "${REPO_ROOT}/terraform/kubernetes/apps" "${REPO_ROOT}/docker/compose" "${REPO_ROOT}/apps"; do
    [ -d "${scan_root}" ] || continue
    while IFS= read -r file; do
      case "${file}" in
        *.yaml|*.yml)
          while IFS=: read -r lineno line; do
            ref="$(printf '%s\n' "${line}" | sed -E 's/^[[:space:]]*image:[[:space:]]*//; s/[[:space:]]+#.*$//; s/^"//; s/"$//; s/^'\''//; s/'\''$//')"
            [ -n "${ref}" ] || continue
            printf '%s:%s\t%s\n' "${file}" "${lineno}" "${ref}"
          done < <(grep -nE '^[[:space:]]*image:[[:space:]]+' "${file}" 2>/dev/null || true)
          ;;
        *)
          while IFS=: read -r lineno line; do
            ref="$(printf '%s\n' "${line}" | sed -E 's/^[[:space:]]*FROM[[:space:]]+//I; s/[[:space:]]+AS[[:space:]].*$//I')"
            ref="$(printf '%s\n' "${ref}" | awk '{for (i = 1; i <= NF; i++) if ($i !~ /^--platform=/) { print $i; exit }}')"
            [ -n "${ref}" ] || continue
            printf '%s:%s\t%s\n' "${file}" "${lineno}" "${ref}"
          done < <(grep -nEi '^[[:space:]]*FROM[[:space:]]+' "${file}" 2>/dev/null || true)
          ;;
      esac
    done < <(
      find "${scan_root}" \
        \( \
          -path '*/.git' -o \
          -path '*/.terraform' -o \
          -path '*/.venv' -o \
          -path '*/venv' -o \
          -path '*/node_modules' -o \
          -path '*/dist' -o \
          -path '*/build' -o \
          -path "${APIM_SIMULATOR_VENDOR_DIR}" -o \
          -path "${APIM_SIMULATOR_VENDOR_DIR}/*" \
        \) -prune \
        -o -type f \( -name '*.yaml' -o -name '*.yml' -o -name 'Dockerfile*' \) -print \
        | LC_ALL=C sort
    )
  done
}

ensure_helm_repo_ready() {
  local repo_name="$1"
  local repo_url="$2"

  case " ${HELM_READY_REPOS} " in
    *" ${repo_name} "*) return 0 ;;
  esac

  helm repo add "${repo_name}" "${repo_url}" --force-update >/dev/null 2>&1 || true
  HELM_READY_REPOS="${HELM_READY_REPOS} ${repo_name}"
}

ensure_check_version_cache_dir() {
  HTTP_FETCH_CACHE_DIR="${HTTP_FETCH_CACHE_DIR:-${CHECK_VERSION_CACHE_DIR:-}}"
  HTTP_FETCH_CACHE_DIR="$(http_cache_dir_ensure)"
  CHECK_VERSION_CACHE_DIR="${HTTP_FETCH_CACHE_DIR}"
}

chart_app_version_cache_file() {
  local repo_name="$1"
  local chart="$2"
  local version="$3"

  ensure_check_version_cache_dir
  printf "%s/%s\n" "${CHECK_VERSION_CACHE_DIR}" "$(printf '%s__%s__%s' "${repo_name}" "${chart}" "${version}" | tr '/:@' '____')"
}

helm_latest_chart_version() {
  local repo_name="$1"
  local repo_url="$2"
  local chart="$3"

  ensure_helm_repo_ready "${repo_name}" "${repo_url}"
  helm search repo "${repo_name}/${chart}" --versions -o json 2>/dev/null | jq -r '.[0].version // empty' || true
}

helm_chart_app_version() {
  local repo_name="$1"
  local repo_url="$2"
  local chart="$3"
  local version="$4"
  local cache_file
  local result

  if [ -z "${version}" ]; then
    echo ""
    return 0
  fi

  cache_file="$(chart_app_version_cache_file "${repo_name}" "${chart}" "${version}")"
  if [ -f "${cache_file}" ]; then
    cat "${cache_file}"
    return 0
  fi

  ensure_helm_repo_ready "${repo_name}" "${repo_url}"
  result="$(
    helm show chart "${repo_name}/${chart}" --version "${version}" 2>/dev/null | \
      awk -F': ' '$1=="appVersion"{print $2; exit}' | tr -d '"' | xargs || true
  )"
  printf "%s" "${result}" >"${cache_file}"
  printf "%s\n" "${result}"
}

image_tag_from_ref() {
  local image_ref="$1"
  local no_digest last_segment

  if [ -z "${image_ref}" ]; then
    echo ""
    return 0
  fi

  no_digest="${image_ref%@*}"
  last_segment="${no_digest##*/}"
  if [[ "${last_segment}" == *:* ]]; then
    echo "${last_segment##*:}"
  else
    echo ""
  fi
}

github_latest_release_tag_uncached() {
  local repo="$1"

  http_fetch -fsSL "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null | jq -r '.tag_name // empty' | xargs || true
}

github_latest_release_tag() {
  local repo="$1"

  http_cached_output "github-release-tag" "${repo}" github_latest_release_tag_uncached "${repo}" || true
}

docker_hub_repo_tags_uncached() {
  local namespace="$1"
  local repository="$2"
  local next_url="https://hub.docker.com/v2/namespaces/${namespace}/repositories/${repository}/tags?page_size=100"
  local payload=""
  local tags=""

  while [ -n "${next_url}" ]; do
    payload="$(http_fetch -fsSL "${next_url}" 2>/dev/null)" || return 1
    tags="${tags}$(jq -r '.results[]?.name // empty' <<<"${payload}")"$'\n'
    next_url="$(jq -r '.next // empty' <<<"${payload}")"
  done

  printf "%s" "${tags}"
}

docker_hub_repo_tags() {
  local namespace="$1"
  local repository="$2"

  http_cached_output "docker-hub-tags" "${namespace}/${repository}" docker_hub_repo_tags_uncached "${namespace}" "${repository}"
}

parse_www_authenticate_bearer() {
  local header_file="$1"

  run_inline_python "${header_file}" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="ignore")
match = re.search(r'^[Ww][Ww][Ww]-[Aa]uthenticate:\s*Bearer\s+(.*)$', text, re.MULTILINE)
if not match:
    raise SystemExit(1)

params = {}
for key, value in re.findall(r'([A-Za-z]+)="([^"]*)"', match.group(1)):
    params[key.lower()] = value

print(f'{params.get("realm", "")}\t{params.get("service", "")}\t{params.get("scope", "")}')
PY
}

oci_registry_repo_tags_uncached() {
  local registry="$1"
  local repository="$2"
  local url="https://${registry}/v2/${repository}/tags/list?n=1000"
  local headers_file body_file realm service scope token_url token_payload token

  headers_file="$(mktemp)"
  body_file="$(mktemp)"

  if http_fetch -fsSL -D "${headers_file}" "${url}" -o "${body_file}" 2>/dev/null; then
    jq -r '.tags[]? // empty' "${body_file}" 2>/dev/null || true
    rm -f "${headers_file}" "${body_file}"
    return 0
  fi

  if ! IFS=$'\t' read -r realm service scope < <(parse_www_authenticate_bearer "${headers_file}" 2>/dev/null || true); then
    rm -f "${headers_file}" "${body_file}"
    return 1
  fi

  rm -f "${body_file}"
  if [ -z "${realm}" ]; then
    rm -f "${headers_file}"
    return 1
  fi

  if [ -z "${scope}" ]; then
    scope="repository:${repository}:pull"
  fi

  token_url="${realm}?service=$(uri_encode "${service}")&scope=$(uri_encode "${scope}")"
  token_payload="$(http_fetch -fsSL "${token_url}" 2>/dev/null || true)"
  token="$(jq -r '.token // .access_token // empty' <<<"${token_payload}" 2>/dev/null | xargs || true)"
  if [ -z "${token}" ]; then
    rm -f "${headers_file}"
    return 1
  fi

  body_file="$(mktemp)"
  if ! http_fetch -fsSL -H "Authorization: Bearer ${token}" "${url}" -o "${body_file}" 2>/dev/null; then
    rm -f "${headers_file}" "${body_file}"
    return 1
  fi

  jq -r '.tags[]? // empty' "${body_file}" 2>/dev/null || true
  rm -f "${headers_file}" "${body_file}"
}

oci_registry_repo_tags() {
  local registry="$1"
  local repository="$2"

  http_cached_output "oci-registry-tags" "${registry}/${repository}" oci_registry_repo_tags_uncached "${registry}" "${repository}"
}

kindest_node_latest_tag() {
  docker_hub_repo_tags "kindest" "node" 2>/dev/null | \
    grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | \
    sort -V | tail -n 1
}

kind_installed_version() {
  local version=""

  if ! command -v kind >/dev/null 2>&1; then
    echo ""
    return 0
  fi

  version="$(kind version -q 2>/dev/null | xargs || true)"
  if [ -n "${version}" ]; then
    echo "${version}"
    return 0
  fi

  version="$(kind --version 2>/dev/null | sed -E 's/^kind version[[:space:]]+//; s/[[:space:]].*$//' | xargs || true)"
  echo "${version}"
}

normalize_semver_like_tag() {
  local version="$1"

  if [ -z "${version}" ]; then
    echo ""
  elif [[ "${version}" == v* ]]; then
    echo "${version}"
  else
    echo "v${version}"
  fi
}

tag_version_prefix() {
  local tag="$1"

  if [[ "${tag}" =~ ^([vV]?[0-9]+(\.[0-9]+){1,2}) ]]; then
    printf "%s\n" "${BASH_REMATCH[1]}"
    return 0
  fi

  printf "\n"
}

tag_version_core() {
  local prefix

  prefix="$(tag_version_prefix "$1")"
  prefix="${prefix#v}"
  prefix="${prefix#V}"
  printf "%s\n" "${prefix}"
}

tag_version_segment_count() {
  local core

  core="$(tag_version_core "$1")"
  if [ -z "${core}" ]; then
    printf '0\n'
    return 0
  fi

  awk -F '.' '{ print NF }' <<<"${core}"
}

tag_release_series_key() {
  local core

  core="$(tag_version_core "$1")"
  if [ -z "${core}" ]; then
    printf '\n'
    return 0
  fi

  awk -F '.' '
    NF >= 2 { print $1 "." $2; next }
    NF == 1 { print $1; next }
  ' <<<"${core}"
}

tag_suffix_after_version_prefix() {
  local tag="$1"
  local prefix

  prefix="$(tag_version_prefix "${tag}")"
  if [ -z "${prefix}" ]; then
    printf "\n"
    return 0
  fi

  printf "%s\n" "${tag#"${prefix}"}"
}

derive_tag_with_existing_suffix() {
  local desired_version="$1"
  local existing_tag="$2"
  local existing_prefix
  local normalized_version
  local suffix

  if [ -z "${desired_version}" ]; then
    printf "\n"
    return 0
  fi

  existing_prefix="$(tag_version_prefix "${existing_tag}")"
  normalized_version="${desired_version#v}"
  normalized_version="${normalized_version#V}"
  if [[ "${existing_prefix}" == [vV]* ]]; then
    normalized_version="v${normalized_version}"
  fi

  suffix="$(tag_suffix_after_version_prefix "${existing_tag}")"
  printf "%s%s\n" "${normalized_version}" "${suffix}"
}

image_ref_availability() {
  local image_ref="$1"
  local stderr=""
  local rc=0
  local registry=""

  if [ -z "${image_ref}" ]; then
    printf "unknown\n"
    return 0
  fi

  registry="$(image_ref_registry "${image_ref}")"
  if [ "${registry}" = "dhi.io" ] && [ "${CHECK_VERSION_PROBE_PRIVATE_IMAGES:-0}" != "1" ]; then
    printf "unknown\n"
    return 0
  fi

  if ! command -v docker >/dev/null 2>&1; then
    printf "unknown\n"
    return 0
  fi

  stderr="$(docker_manifest_inspect_safe "${image_ref}")" || rc=$?
  if [ "${rc}" -eq 0 ]; then
    printf "available\n"
    return 0
  fi

  if [ "${rc}" -eq 124 ]; then
    printf "unknown\n"
    return 0
  fi

  if echo "${stderr}" | grep -Eqi 'unauthorized|authentication required|access denied|denied:'; then
    printf "auth-required\n"
    return 0
  fi

  printf "missing\n"
}

docker_manifest_inspect_safe() {
  local image_ref="$1"
  local timeout="${CHECK_VERSION_DOCKER_MANIFEST_TIMEOUT_SECONDS:-10}"
  local tmp pid start elapsed rc

  tmp="$(mktemp)"
  docker manifest inspect "${image_ref}" >/dev/null 2>"${tmp}" &
  pid=$!
  start="$(date +%s)"

  while kill -0 "${pid}" >/dev/null 2>&1; do
    elapsed=$(( $(date +%s) - start ))
    if [ "${elapsed}" -ge "${timeout}" ]; then
      kill "${pid}" >/dev/null 2>&1 || true
      sleep 1
      if kill -0 "${pid}" >/dev/null 2>&1; then
        kill -9 "${pid}" >/dev/null 2>&1 || true
      fi
      while wait "${pid}" >/dev/null 2>&1; do
        :
      done
      rm -f "${tmp}"
      return 124
    fi
    sleep 1
  done

  wait "${pid}"
  rc=$?
  cat "${tmp}"
  rm -f "${tmp}"
  return "${rc}"
}

preferred_image_status() {
  local configured_ref="$1"
  local configured_state="$2"
  local candidate_ref="$3"
  local candidate_state="$4"

  if [ -z "${configured_ref}" ]; then
    printf "not configured\n"
    return 0
  fi

  case "${configured_state}" in
    available)
      if [ -z "${candidate_ref}" ] || [ "${candidate_ref}" = "${configured_ref}" ]; then
        printf "configured image exists\n"
        return 0
      fi

      case "${candidate_state}" in
        available) printf "latest preferred image exists\n" ;;
        missing) printf "latest preferred image missing; hold configured image\n" ;;
        auth-required) printf "latest preferred image requires registry auth\n" ;;
        *) printf "latest preferred image unverified\n" ;;
      esac
      ;;
    missing)
      printf "configured image missing from registry\n"
      ;;
    auth-required)
      printf "configured image requires registry auth\n"
      ;;
    *)
      printf "configured image unverified\n"
      ;;
  esac
}

print_preferred_image_row() {
  local name="$1"
  local configured_ref="$2"
  local configured_state="$3"
  local candidate_ref="$4"
  local candidate_state="$5"
  local status_text
  local color="${GREEN}"

  status_text="$(preferred_image_status "${configured_ref}" "${configured_state}" "${candidate_ref}" "${candidate_state}")"

  case "${configured_state}" in
    missing) color="${RED}" ;;
    auth-required|unknown) color="${YELLOW}" ;;
    available)
      case "${candidate_state}" in
        missing|auth-required|unknown) color="${YELLOW}" ;;
      esac
      ;;
  esac

  printf "%s\t%s\t%s\t%s%s%s\n" \
    "${name}" \
    "${configured_ref:-}" \
    "${candidate_ref:-}" \
    "${color}" \
    "${status_text}" \
    "${NC}"
}

print_observed_latest_row() {
  local item="$1"
  local observed="$2"
  local latest="$3"
  local observed_label="$4"
  local latest_label="$5"
  local status=""
  local normalized_observed=""
  local normalized_latest=""

  normalized_observed="$(normalize_semver_like_tag "${observed}")"
  normalized_latest="$(normalize_semver_like_tag "${latest}")"

  if [ -z "${observed}" ] && [ -z "${latest}" ]; then
    status="${YELLOW}${observed_label} ?; latest ${latest_label} ?${NC}"
  elif [ -z "${observed}" ]; then
    status="${YELLOW}${observed_label} ?; latest ${latest_label} == ${latest}${NC}"
  elif [ -z "${latest}" ]; then
    status="${YELLOW}${observed_label} == ${observed}; latest ${latest_label} ?${NC}"
  elif [ "${normalized_observed}" = "${normalized_latest}" ]; then
    status="${GREEN}${observed_label} == latest ${latest_label} (${normalized_latest})${NC}"
  else
    status="${YELLOW}${observed_label} != latest ${latest_label} (${observed} vs ${latest})${NC}"
  fi

  printf "%s\t%s\t%s\t%s\n" "${item}" "${observed:-}" "${latest:-}" "${status}"
}

render_tsv_table() {
  awk -F $'\t' '
    function strip_ansi(text, cleaned) {
      cleaned = text
      gsub(/\033\[[0-9;]*m/, "", cleaned)
      return cleaned
    }

    {
      row_count++
      field_count[row_count] = NF
      for (i = 1; i <= NF; i++) {
        rows[row_count, i] = $i
        visible = strip_ansi($i)
        if (length(visible) > width[i]) {
          width[i] = length(visible)
        }
      }
    }

    END {
      for (row = 1; row <= row_count; row++) {
        line = ""
        for (col = 1; col <= field_count[row]; col++) {
          cell = rows[row, col]
          if (col < field_count[row]) {
            line = line sprintf("%-*s  ", width[col], cell)
          } else {
            line = line cell
          }
        }
        print line
      }
    }
  '
}

tsv_rows_to_json_array() {
  local headers_json="$1"

  jq -Rcs --argjson headers "${headers_json}" '
    split("\n")
    | map(select(length > 0) | split("\t"))
    | map(
        . as $row
        | reduce range(0; $headers | length) as $i ({};
            . + {
              ($headers[$i]): (($row[$i] // "") | gsub("\u001b\\[[0-9;]*m"; ""))
            }
          )
      )
  '
}

k8s_deployment_container_image() {
  local namespace="$1"
  local deployment="$2"
  local container="$3"

  if ! command -v kubectl >/dev/null 2>&1; then
    echo ""
    return 0
  fi

  kubectl -n "${namespace}" get deployment "${deployment}" -o json 2>/dev/null | \
    jq -r --arg c "${container}" '.spec.template.spec.containers[]? | select(.name==$c) | .image // empty' | \
    head -n1 | xargs || true
}

print_row() {
  local name="$1"
  local deployed="$2"
  local codebase="$3"
  local latest="$4"
  local deployed_tag="$5"
  local codebase_tag="$6"
  local dhi_tag="$7"
  local latest_tag="$8"
  local prefer_hardened="${9:-0}"
  local preferred_tag_status="${10:-}"
  local status
  local deploy_state
  local codebase_latest_state
  local update_available=0
  local all_match=0
  local codebase_matches_latest=0
  local not_deployed_current=0

  if [ -n "$codebase" ] && [ -n "$latest" ] && [ "$codebase" != "$latest" ]; then
    if [ "${prefer_hardened}" = "1" ]; then
      if [ "${preferred_tag_status}" = "available" ]; then
        update_available=1
      fi
    else
      update_available=1
    fi
  fi

  if [ -n "$codebase" ] && [ -n "$latest" ] && [ "$codebase" = "$latest" ]; then
    codebase_matches_latest=1
  fi

  if [ "${CLUSTER_OK}" -ne 1 ]; then
    deploy_state="deployed ? (cluster unreachable)"
  elif [ -z "$deployed" ]; then
    deploy_state="not deployed"
  elif [ -n "$codebase" ] && [ "$deployed" = "$codebase" ]; then
    deploy_state="deployed == codebase (${codebase})"
  else
    if [ -n "$codebase" ]; then
      deploy_state="deployed != codebase (${deployed} vs ${codebase})"
    else
      deploy_state="deployed == ${deployed}"
    fi
  fi

  if [ -z "$codebase" ] && [ -z "$latest" ]; then
    codebase_latest_state="codebase ?; latest ?"
  elif [ -z "$codebase" ]; then
    codebase_latest_state="codebase ?; latest == ${latest}"
  elif [ -z "$latest" ]; then
    codebase_latest_state="codebase == ${codebase}; latest ?"
  elif [ "${codebase_matches_latest}" -eq 1 ]; then
    codebase_latest_state="codebase == latest (${codebase})"
  elif [ "${prefer_hardened}" = "1" ] && [ -n "${dhi_tag}" ]; then
    case "${preferred_tag_status}" in
      available) codebase_latest_state="codebase != latest (${codebase} vs ${latest}); preferred image available (${dhi_tag})" ;;
      missing) codebase_latest_state="codebase != latest (${codebase} vs ${latest}); preferred image missing (${dhi_tag})" ;;
      auth-required) codebase_latest_state="codebase != latest (${codebase} vs ${latest}); preferred image requires auth (${dhi_tag})" ;;
      unknown) codebase_latest_state="codebase != latest (${codebase} vs ${latest}); preferred image unverified (${dhi_tag})" ;;
      *) codebase_latest_state="codebase != latest (${codebase} vs ${latest}); preferred image candidate ${dhi_tag}" ;;
    esac
  else
    codebase_latest_state="codebase != latest (${codebase} vs ${latest})"
  fi

  if [ -n "$codebase" ] && [ -n "$deployed" ] && [ -n "$latest" ] && \
    [ "$codebase" = "$deployed" ] && [ "$codebase" = "$latest" ]; then
    all_match=1
    status="deployed == codebase == latest (${codebase})"
  elif [ -z "$deployed" ] && [ "${codebase_matches_latest}" -eq 1 ]; then
    not_deployed_current=1
    status="not deployed; ${codebase_latest_state}"
  else
    status="${deploy_state}; ${codebase_latest_state}"
  fi

  if [[ "$deploy_state" == deployed\ !=* ]]; then
    status="${RED}${status}${NC}"
  elif [ "${all_match}" -eq 1 ] || [ "${not_deployed_current}" -eq 1 ]; then
    status="${GREEN}${status}${NC}"
  elif [ "${update_available}" -eq 1 ] || [[ "$deploy_state" == not* ]] || [[ "$deploy_state" == deployed\ ?* ]] || [[ "$codebase_latest_state" == *"latest ?"* ]] || [[ "$codebase_latest_state" == codebase\ ?* ]]; then
    status="${YELLOW}${status}${NC}"
  else
    status="${GREEN}${status}${NC}"
  fi

  # Emit a sortable TSV row; rendering happens after sorting by component name.
  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$name" "${deployed:-}" "$codebase" "$latest" "${deployed_tag:-}" "${codebase_tag:-}" "${dhi_tag:-}" "${latest_tag:-}" "$status"
}

check_preload_image_version_alignment() {
  local preload_file="${PRELOAD_IMAGES_FILE}"
  local expected_argocd_image_ref="$1"
  local expected_prometheus_tag="$2"
  local expected_grafana_tag="$3"
  local expected_loki_tag="$4"
  local expected_tempo_tag="$5"
  local expected_victoria_logs_tag="$6"

  if [ ! -f "${preload_file}" ]; then
    warn "preload image list not found at ${preload_file}"
    return 0
  fi

  check_preload_image_ref_alignment "${preload_file}" "ArgoCD" '^[[:space:]]*((dhi\.io/argocd)|(quay\.io/argoproj/argocd)):' "${expected_argocd_image_ref}"
  check_preload_repo_tag_alignment "${preload_file}" "Prometheus" '^[[:space:]]*quay\.io/prometheus/prometheus:' 's|^[[:space:]]*quay\.io/prometheus/prometheus:([^[:space:]]+).*|\1|' "${expected_prometheus_tag}"
  check_preload_repo_tag_alignment "${preload_file}" "Grafana" '^[[:space:]]*(docker\.io/)?grafana/grafana:' 's|^[[:space:]]*(docker\.io/)?grafana/grafana:([^[:space:]]+).*|\2|' "${expected_grafana_tag}"
  check_preload_repo_tag_alignment "${preload_file}" "Loki" '^[[:space:]]*(docker\.io/)?grafana/loki:' 's|^[[:space:]]*(docker\.io/)?grafana/loki:([^[:space:]]+).*|\2|' "${expected_loki_tag}"
  check_preload_repo_tag_alignment "${preload_file}" "Tempo" '^[[:space:]]*(docker\.io/)?grafana/tempo:' 's|^[[:space:]]*(docker\.io/)?grafana/tempo:([^[:space:]]+).*|\2|' "${expected_tempo_tag}"
  check_preload_repo_tag_alignment "${preload_file}" "VictoriaLogs" '^[[:space:]]*(docker\.io/)?victoriametrics/victoria-logs:' 's|^[[:space:]]*(docker\.io/)?victoriametrics/victoria-logs:([^[:space:]]+).*|\2|' "${expected_victoria_logs_tag}"
  echo ""
}

check_preload_image_ref_alignment() {
  local preload_file="$1"
  local component="$2"
  local line_regex="$3"
  local expected_ref="$4"
  local matches has_exact mismatch_count

  if [ -z "${expected_ref}" ]; then
    warn "preload image check skipped for ${component}: expected image ref is unknown"
    return 0
  fi

  matches=$(grep -nE "${line_regex}" "${preload_file}" 2>/dev/null || true)
  if [ -z "${matches}" ]; then
    warn "preload image missing for ${component}: expected ${expected_ref}"
    return 0
  fi

  has_exact=0
  mismatch_count=0

  while IFS= read -r entry; do
    [ -z "${entry}" ] && continue

    local lineno image_ref found_ref
    lineno="${entry%%:*}"
    image_ref="${entry#*:}"
    found_ref=$(echo "${image_ref}" | sed -E 's/[[:space:]]+$//' | xargs || true)

    if [ "${found_ref}" = "${expected_ref}" ]; then
      has_exact=1
      continue
    fi

    mismatch_count=$((mismatch_count + 1))
    warn "stale preload candidate (line ${lineno}): ${image_ref} (expected ${component} image ${expected_ref})"
  done <<< "${matches}"

  if [ "${has_exact}" -eq 1 ]; then
    if [ "${mismatch_count}" -eq 0 ]; then
      ok "${component} preload image matches configured image (${expected_ref})"
    else
      warn "${component} preload includes ${mismatch_count} non-matching line(s); expected image is ${expected_ref}"
    fi
  else
    warn "preload image missing exact ${component} image: ${expected_ref}"
  fi
}

check_preload_repo_tag_alignment() {
  local preload_file="$1"
  local component="$2"
  local line_regex="$3"
  local tag_extract_sed="$4"
  local expected_tag="$5"
  local matches has_expected mismatch_count

  if [ -z "${expected_tag}" ]; then
    warn "preload image check skipped for ${component}: expected chart appVersion is unknown"
    return 0
  fi

  matches=$(grep -nE "${line_regex}" "${preload_file}" 2>/dev/null || true)
  if [ -z "${matches}" ]; then
    warn "preload image missing for ${component}: expected tag ${expected_tag}"
    return 0
  fi

  has_expected=0
  mismatch_count=0

  while IFS= read -r entry; do
    [ -z "${entry}" ] && continue

    local lineno image_ref found_tag
    lineno="${entry%%:*}"
    image_ref="${entry#*:}"
    found_tag=$(echo "${image_ref}" | sed -E "${tag_extract_sed}" | xargs || true)

    if [ "${found_tag}" = "${expected_tag}" ]; then
      has_expected=1
      continue
    fi

    mismatch_count=$((mismatch_count + 1))
    warn "stale preload candidate (line ${lineno}): ${image_ref} (expected ${component} tag ${expected_tag})"
  done <<< "${matches}"

  if [ "${has_expected}" -eq 1 ]; then
    if [ "${mismatch_count}" -eq 0 ]; then
      ok "${component} preload image tag matches chart appVersion (${expected_tag})"
    else
      warn "${component} preload includes ${mismatch_count} non-matching tag line(s); expected tag is ${expected_tag}"
    fi
  else
    warn "preload image missing exact ${component} tag: ${expected_tag}"
  fi
}

preload_expected_chart_version_for_section() {
  local section="$1"

  case "${section}" in
    Cilium) echo "${CODE_CILIUM}" ;;
    ArgoCD) echo "${CODE_ARGOCD}" ;;
    Gitea) echo "${CODE_GITEA}" ;;
    Kyverno) echo "${CODE_KYVERNO}" ;;
    cert-manager) echo "${CODE_CERT_MANAGER}" ;;
    SigNoz) echo "${CODE_SIGNOZ}" ;;
    Prometheus) echo "${CODE_PROMETHEUS}" ;;
    Loki) echo "${CODE_LOKI}" ;;
    VictoriaLogs) echo "${CODE_VICTORIA_LOGS}" ;;
    Tempo) echo "${CODE_TEMPO}" ;;
    Grafana) echo "${CODE_GRAFANA}" ;;
    Headlamp) echo "${CODE_HEADLAMP}" ;;
    Dex) echo "${CODE_DEX}" ;;
    oauth2-proxy) echo "${CODE_OAUTH2_PROXY}" ;;
    "OpenTelemetry Collector") echo "${CODE_OTEL_COLLECTOR}" ;;
    "NGINX Gateway Fabric") echo "main" ;;
    *) echo "" ;;
  esac
}

check_preload_chart_section_version_alignment() {
  local preload_file="${PRELOAD_IMAGES_FILE}"

  if [ ! -f "${preload_file}" ]; then
    warn "preload image list not found at ${preload_file}"
    return 0
  fi

  local line lineno section section_chart expected section_drift
  local drift_sections=0
  local stale_lines=0
  lineno=0
  section_drift=0
  section=""

  while IFS= read -r line || [ -n "${line}" ]; do
    lineno=$((lineno + 1))

    if echo "${line}" | grep -Eq '^[[:space:]]*#[[:space:]]*---[[:space:]]*.+[[:space:]]+\(chart[[:space:]]+[^)]*\)[[:space:]]*---[[:space:]]*$'; then
      section=$(echo "${line}" | sed -E 's/^[[:space:]]*#[[:space:]]*---[[:space:]]*(.+)[[:space:]]+\(chart[[:space:]]+([^)]*)\)[[:space:]]*---[[:space:]]*$/\1/' | xargs)
      section_chart=$(echo "${line}" | sed -E 's/^[[:space:]]*#[[:space:]]*---[[:space:]]*(.+)[[:space:]]+\(chart[[:space:]]+([^)]*)\)[[:space:]]*---[[:space:]]*$/\2/' | xargs)
      expected=$(preload_expected_chart_version_for_section "${section}")
      section_drift=0

      if [ -n "${expected}" ] && [ "${section_chart}" != "${expected}" ]; then
        warn "preload section drift (line ${lineno}): ${section} chart ${section_chart} but codebase expects ${expected}"
        section_drift=1
        drift_sections=$((drift_sections + 1))
      fi
      continue
    fi

    if [ "${section_drift}" -eq 1 ] && ! echo "${line}" | grep -Eq '^[[:space:]]*(#|$)'; then
      stale_lines=$((stale_lines + 1))
      warn "stale preload candidate (line ${lineno}): ${line} (section ${section} is on the wrong chart version)"
    fi
  done < "${preload_file}"

  if [ "${drift_sections}" -eq 0 ]; then
    ok "preload-images section chart versions match chart versions in codebase"
  else
    warn "preload-images chart section drift found in ${drift_sections} section(s), with ${stale_lines} stale image line candidate(s)"
  fi

  echo ""
}

helm_deployed_chart_version() {
  local namespace="$1"
  local release="$2"

  local json chart
  json=$(helm -n "$namespace" list -o json 2>/dev/null || true)
  chart=$(echo "$json" | jq -r ".[] | select(.name==\"${release}\") | .chart" 2>/dev/null || true)
  if [ -z "$chart" ]; then
    echo ""
    return 0
  fi

  # chart looks like "cilium-1.18.6" or "argo-cd-9.3.7".
  echo "$chart" | sed -E 's/^.*-([0-9][0-9A-Za-z.+-]+)$/\1/'
}

chart_version_from_label() {
  local label="$1"

  if [ -z "$label" ]; then
    echo ""
    return 0
  fi

  # label looks like "prometheus-28.13.0", "opentelemetry-collector-0.128.0", or "cert-manager-v1.19.4".
  echo "$label" | sed -E 's/^.*-([vV]?[0-9][0-9A-Za-z.+-]+)$/\1/'
}

argocd_app_release_name() {
  local app="$1"
  local ns="${2:-argocd}"

  if ! command -v kubectl >/dev/null 2>&1; then
    echo ""
    return 0
  fi

  kubectl -n "$ns" get application "$app" -o jsonpath='{.spec.source.helm.releaseName}' 2>/dev/null || true
}

argocd_app_destination_namespace() {
  local app="$1"
  local ns="${2:-argocd}"

  if ! command -v kubectl >/dev/null 2>&1; then
    echo ""
    return 0
  fi

  kubectl -n "$ns" get application "$app" -o jsonpath='{.spec.destination.namespace}' 2>/dev/null || true
}

argocd_app_deployed_chart_version() {
  local app="$1"
  local chart="$2"
  local app_ns="${3:-argocd}"
  local release namespace label

  if ! command -v kubectl >/dev/null 2>&1; then
    echo ""
    return 0
  fi

  namespace=$(argocd_app_destination_namespace "$app" "$app_ns")
  if [ -z "${namespace}" ]; then
    echo ""
    return 0
  fi

  release=$(argocd_app_release_name "$app" "$app_ns")
  if [ -z "${release}" ]; then
    release="$app"
  fi

  label=$(
    kubectl -n "${namespace}" get deploy,statefulset,daemonset,job,cronjob,svc,sa,cm,ingress,networkpolicy,role,rolebinding,pdb \
      -l "app.kubernetes.io/instance=${release}" -o json 2>/dev/null | \
      jq -r --arg chart "${chart}" '
        [
          .items[]?.metadata.labels["helm.sh/chart"]
          | select(. != null and startswith($chart + "-"))
        ] | first // empty
      ' 2>/dev/null || true
  )

  chart_version_from_label "${label}"
}

argocd_app_deployed_target_revision() {
  local app="$1"
  local ns="${2:-argocd}"

  if ! command -v kubectl >/dev/null 2>&1; then
    echo ""
    return 0
  fi

  # Prefer the live synced revision when present; fall back to desired targetRevision.
  local rev
  rev=$(kubectl -n "$ns" get application "$app" -o jsonpath='{.status.sync.revision}' 2>/dev/null || true)
  if [ -n "$rev" ]; then
    echo "$rev"
    return 0
  fi

  kubectl -n "$ns" get application "$app" -o jsonpath='{.spec.source.targetRevision}' 2>/dev/null || true
}

check_consistent_tfvars() {
  local key="$1"
  local uniq

  uniq=$(grep -hE "^[[:space:]]*${key}[[:space:]]*=[[:space:]]*" "${STAGES_DIR}"/*.tfvars 2>/dev/null | \
    sed -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"?([^\"#]+)\"?.*$/\1/" | xargs -n1 | sort -u || true)

  if [ -z "$uniq" ]; then
    return 0
  fi

  local count
  count=$(echo "$uniq" | wc -l | tr -d ' ')
  if [ "$count" -gt 1 ]; then
    warn "Inconsistent ${key} across stages:"
    while IFS= read -r line; do
      echo "  - ${line}"
    done <<<"${uniq}"
    echo ""
  fi
}

check_app_yaml_tfvar_drift() {
  if [ ! -d "${ARGOCD_APPS_DIR}" ]; then
    return 0
  fi

  local warned=0
  local file app revision tfvar_key expected
  for file in "${ARGOCD_APPS_DIR}"/*.yaml; do
    [ -f "$file" ] || continue

    revision=$(awk '/^[[:space:]]*targetRevision:[[:space:]]*/ { print $2; exit }' "$file" | tr -d '"' | xargs)
    if [ -z "$revision" ]; then
      continue
    fi

    case "$revision" in
      main|master|HEAD)
        continue
        ;;
    esac

    app=$(awk '
      /^metadata:[[:space:]]*$/ { in_meta=1; next }
      in_meta && /^[[:space:]]*name:[[:space:]]*/ { print $2; exit }
      in_meta && /^[^[:space:]]/ { in_meta=0 }
    ' "$file" | tr -d '"' | xargs)

    tfvar_key=""
    case "$app" in
      cert-manager) tfvar_key="cert_manager_chart_version" ;;
      kyverno) tfvar_key="kyverno_chart_version" ;;
      policy-reporter) tfvar_key="policy_reporter_chart_version" ;;
      prometheus) tfvar_key="prometheus_chart_version" ;;
      grafana) tfvar_key="grafana_chart_version" ;;
      loki) tfvar_key="loki_chart_version" ;;
      victoria-logs) tfvar_key="victoria_logs_chart_version" ;;
      tempo) tfvar_key="tempo_chart_version" ;;
      signoz) tfvar_key="signoz_chart_version" ;;
      otel-collector-agent|otel-collector-prometheus) tfvar_key="opentelemetry_collector_chart_version" ;;
      *) continue ;;
    esac

    expected=$(tfvar_get_any_stage "$tfvar_key")
    if [ -z "$expected" ]; then
      expected=$(tf_default_from_variables "$tfvar_key")
    fi
    if [ -z "$expected" ]; then
      warn "YAML↔tfvar drift: $(basename "$file") targetRevision=${revision} but ${tfvar_key} is missing from stages/*.tfvars"
      warned=1
      continue
    fi

    if [ "$revision" != "$expected" ]; then
      warn "YAML↔tfvar drift: $(basename "$file") targetRevision=${revision} but ${tfvar_key}=${expected}"
      warned=1
    fi
  done

  if [ "$warned" -eq 0 ]; then
    ok "No app-of-apps targetRevision drift detected"
  fi
  echo ""
}

emit_app_dependency_rows() {
  local package_json app_dir app_label cooldown_seconds dep spec current latest_overall latest_eligible status
  local pyproject cutoff_iso requirement dep_name uv_lock requirement_status spec_status

  while IFS= read -r package_json; do
    app_dir="$(dirname "${package_json}")"
    app_label="${app_dir#"${REPO_ROOT}/"}"
    cooldown_seconds="$(js_dependency_cooldown_seconds "${app_dir}")"

    while IFS=$'\t' read -r dep spec; do
      [ -n "${dep}" ] || continue
      spec_status="$(js_dependency_spec_status "${spec}")"
      if [ -n "${spec_status}" ]; then
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
          "${app_label}" \
          "${dep}" \
          "${spec:-}" \
          "" \
          "" \
          "${spec_status}"
        continue
      fi
      current="$(bun_lock_resolved_version "${app_dir}/bun.lock" "${dep}")"
      latest_overall="$(npm_latest_overall_version "${dep}")"
      latest_eligible="$(npm_latest_eligible_version "${dep}" "${cooldown_seconds}")"
      status="$(dependency_update_status "${current}" "${latest_eligible}" "${latest_overall}")"
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "${app_label}" \
        "${dep}" \
        "${current:-}" \
        "${latest_eligible:-}" \
        "${latest_overall:-}" \
        "${status}"
    done < <(package_json_direct_dependencies "${package_json}")
  done < <(
    find "${REPO_ROOT}/apps" \
      \( \
        -path '*/.git' -o \
        -path '*/.terraform' -o \
        -path '*/.venv' -o \
        -path '*/venv' -o \
        -path '*/node_modules' -o \
        -path '*/dist' -o \
        -path '*/build' -o \
        -path "${APIM_SIMULATOR_VENDOR_DIR}" -o \
        -path "${APIM_SIMULATOR_VENDOR_DIR}/*" \
      \) -prune \
      -o -type f -name package.json -print \
      | LC_ALL=C sort
  )

  while IFS= read -r pyproject; do
    app_dir="$(dirname "${pyproject}")"
    app_label="${app_dir#"${REPO_ROOT}/"}"
    cutoff_iso="$(python_dependency_cooldown_cutoff "${app_dir}")"
    uv_lock="${app_dir}/uv.lock"

    while IFS= read -r requirement; do
      [ -n "${requirement}" ] || continue
      requirement_status="$(python_requirement_status "${requirement}")"
      if [ "${requirement_status}" = "skip" ]; then
        continue
      fi
      dep_name="$(python_requirement_name "${requirement}")"
      [ -n "${dep_name}" ] || continue
      if [ -n "${requirement_status}" ]; then
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
          "${app_label}" \
          "${dep_name}" \
          "${requirement}" \
          "" \
          "" \
          "${requirement_status}"
        continue
      fi
      current="$(uv_lock_resolved_version "${uv_lock}" "${dep_name}")"
      latest_overall="$(pypi_latest_overall_version "${dep_name}")"
      latest_eligible="$(pypi_latest_eligible_version "${dep_name}" "${cutoff_iso}")"
      status="$(dependency_update_status "${current}" "${latest_eligible}" "${latest_overall}")"
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "${app_label}" \
        "${dep_name}" \
        "${current:-}" \
        "${latest_eligible:-}" \
        "${latest_overall:-}" \
        "${status}"
    done < <(pyproject_project_dependencies "${pyproject}")
  done < <(
    find "${REPO_ROOT}/apps" \
      \( \
        -path '*/.git' -o \
        -path '*/.terraform' -o \
        -path '*/.venv' -o \
        -path '*/venv' -o \
        -path '*/node_modules' -o \
        -path '*/dist' -o \
        -path '*/build' -o \
        -path "${APIM_SIMULATOR_VENDOR_DIR}" -o \
        -path "${APIM_SIMULATOR_VENDOR_DIR}/*" \
      \) -prune \
      -o -type f -name pyproject.toml -print \
      | LC_ALL=C sort
  )
}

collect_js_dependency_names() {
  local package_json dep spec spec_status

  while IFS= read -r package_json; do
    while IFS=$'\t' read -r dep spec; do
      [ -n "${dep}" ] || continue
      spec_status="$(js_dependency_spec_status "${spec}")"
      if [ -n "${spec_status}" ]; then
        continue
      fi
      printf '%s\n' "${dep}"
    done < <(package_json_direct_dependencies "${package_json}")
  done < <(
    find "${REPO_ROOT}/apps" \
      \( \
        -path '*/.git' -o \
        -path '*/.terraform' -o \
        -path '*/.venv' -o \
        -path '*/venv' -o \
        -path '*/node_modules' -o \
        -path '*/dist' -o \
        -path '*/build' -o \
        -path "${APIM_SIMULATOR_VENDOR_DIR}" -o \
        -path "${APIM_SIMULATOR_VENDOR_DIR}/*" \
      \) -prune \
      -o -type f -name package.json -print \
      | LC_ALL=C sort
  )
}

collect_python_dependency_names() {
  local pyproject requirement requirement_status dep_name

  while IFS= read -r pyproject; do
    while IFS= read -r requirement; do
      [ -n "${requirement}" ] || continue
      requirement_status="$(python_requirement_status "${requirement}")"
      if [ "${requirement_status}" = "skip" ]; then
        continue
      fi
      dep_name="$(python_requirement_name "${requirement}")"
      [ -n "${dep_name}" ] || continue
      if [ -n "${requirement_status}" ]; then
        continue
      fi
      printf '%s\n' "${dep_name}"
    done < <(pyproject_project_dependencies "${pyproject}")
  done < <(
    find "${REPO_ROOT}/apps" \
      \( \
        -path '*/.git' -o \
        -path '*/.terraform' -o \
        -path '*/.venv' -o \
        -path '*/venv' -o \
        -path '*/node_modules' -o \
        -path '*/dist' -o \
        -path '*/build' -o \
        -path "${APIM_SIMULATOR_VENDOR_DIR}" -o \
        -path "${APIM_SIMULATOR_VENDOR_DIR}/*" \
      \) -prune \
      -o -type f -name pyproject.toml -print \
      | LC_ALL=C sort
  )
}

warm_dependency_metadata_caches() {
  local max_jobs="${CHECK_VERSION_HTTP_CONCURRENCY:-4}"
  local js_input py_input output_dir

  js_input="$(mktemp)"
  py_input="$(mktemp)"
  output_dir="$(mktemp -d)"

  collect_js_dependency_names | LC_ALL=C sort -u >"${js_input}"
  collect_python_dependency_names | LC_ALL=C sort -u >"${py_input}"

  if [ -s "${js_input}" ]; then
    parallel_map_lines "${max_jobs}" warm_npm_registry_payload "${js_input}" "${output_dir}/npm" >/dev/null
  fi

  if [ -s "${py_input}" ]; then
    parallel_map_lines "${max_jobs}" warm_pypi_package_payload "${py_input}" "${output_dir}/pypi" >/dev/null
  fi

  rm -f "${js_input}" "${py_input}"
  rm -rf "${output_dir}"
}

emit_external_image_rows() {
  local input_file output_dir max_jobs

  input_file="$(mktemp)"
  output_dir="$(mktemp -d)"
  max_jobs="${CHECK_VERSION_HTTP_CONCURRENCY:-4}"

  collect_declared_image_refs | awk -F'\t' '!seen[$2]++' >"${input_file}"
  parallel_map_lines "${max_jobs}" emit_external_image_row "${input_file}" "${output_dir}"

  rm -f "${input_file}"
  rm -rf "${output_dir}"
}

emit_external_image_row() {
  local input="$1"
  local source_ref image_ref current_tag latest_tag registry status

  IFS=$'\t' read -r source_ref image_ref <<<"${input}"

  [ -n "${image_ref}" ] || return 0
  if image_ref_is_internal "${image_ref}"; then
    return 0
  fi

  current_tag="$(image_tag_from_ref "${image_ref}")"
  registry="$(image_ref_registry "${image_ref}")"
  latest_tag=""
  case "${registry}" in
    docker.io)
      latest_tag="$(docker_hub_latest_tag_for_ref "${image_ref}")"
      ;;
    ghcr.io|quay.io|mcr.microsoft.com)
      latest_tag="$(oci_registry_latest_tag_for_ref "${image_ref}")"
      ;;
  esac

  if [ -z "${current_tag}" ]; then
    status="$(image_status_when_latest_unknown "${image_ref}" "${registry}")"
  elif [ -z "${latest_tag}" ]; then
    status="$(image_status_when_latest_unknown "${image_ref}" "${registry}")"
  else
    status="$(external_image_update_status "${current_tag}" "${latest_tag}")"
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${source_ref#"${REPO_ROOT}/"}" \
    "${image_ref}" \
    "${current_tag:-}" \
    "${latest_tag:-}" \
    "${registry}" \
    "${status}"
}

render_dependency_audit_text() {
  local rows="$1"

  awk -F $'\t' '
    function print_summary(app) {
      if (app == "") {
        return
      }

      if ((updates[app] + cooldown[app] + localdep[app] + directurl[app] + unresolved[app]) == 0) {
        hidden_current_only++
        hidden_current_deps += current[app]
        return
      }

      printf "%s\n", app
      printf "  updates: %d, cooldown: %d, local: %d, direct-url: %d, unresolved: %d, current: %d\n",
        updates[app] + 0,
        cooldown[app] + 0,
        localdep[app] + 0,
        directurl[app] + 0,
        unresolved[app] + 0,
        current[app] + 0

      for (i = 1; i <= detail_count[app]; i++) {
        print "  - " detail[app, i]
      }
      print ""
    }

    {
      app = $1
      dep = $2
      current_value = $3
      eligible = $4
      latest = $5
      status = $6

      if (!(app in seen)) {
        order[++app_count] = app
        seen[app] = 1
      }

      if (status == "current") {
        current[app]++
        next
      }

      if (status == "update available") {
        updates[app]++
        detail[app, ++detail_count[app]] = dep ": " current_value " -> " eligible " (latest " latest ")"
        next
      }

      if (status == "cooldown active") {
        cooldown[app]++
        detail[app, ++detail_count[app]] = dep ": " current_value " held by cooldown; latest " latest
        next
      }

      if (status == "local/path dependency") {
        localdep[app]++
        detail[app, ++detail_count[app]] = dep ": " current_value " (" status ")"
        next
      }

      if (status == "direct-url dependency") {
        directurl[app]++
        detail[app, ++detail_count[app]] = dep ": " current_value " (" status ")"
        next
      }

      unresolved[app]++
      detail[app, ++detail_count[app]] = dep ": " status
    }

    END {
      for (i = 1; i <= app_count; i++) {
        print_summary(order[i])
      }

      if (hidden_current_only > 0) {
        printf "hidden current-only apps: %d (dependencies hidden: %d)\n\n", hidden_current_only + 0, hidden_current_deps + 0
      }
    }
  ' <<<"${rows}"
}

render_external_image_audit_text() {
  local rows="$1"

  awk -F $'\t' '
    {
      source = $1
      image = $2
      current = $3
      latest = $4
      registry = $5
      status = $6

      if (status == "current") {
        current_count++
        next
      }

      if (status == "update available") {
        update_count++
        update_details[++update_detail_count] = "  - " source ": " image " (" current " -> " latest ", " registry ")"
        next
      }

      other_count++
      other_details[++other_detail_count] = "  - " source ": " image " [" status ", " registry "]"
    }

    END {
      if (update_count > 0) {
        printf "updates available: %d\n", update_count
      } else {
        print "updates available: 0"
      }
      if (other_count > 0) {
        printf "non-updatable references: %d\n", other_count
      } else {
        print "non-updatable references: 0"
      }
      printf "current hidden: %d\n\n", current_count + 0

      if (update_detail_count > 0) {
        print "Updates:"
        for (i = 1; i <= update_detail_count; i++) {
          print update_details[i]
        }
        print ""
      }

      if (other_detail_count > 0) {
        print "Skipped / non-updatable:"
        for (i = 1; i <= other_detail_count; i++) {
          print other_details[i]
        }
        print ""
      }
    }
  ' <<<"${rows}"
}

emit_json_report() {
  local component_rows="$1"
  local preferred_image_rows="$2"
  local kind_rows="$3"
  local dependency_rows="$4"
  local external_image_rows="$5"
  local components_json preferred_images_json kind_versions_json dependencies_json external_images_json
  local cluster_ok_json expect_kind_provisioning_json argo_cd_image_override_active_json

  components_json="$(
    printf '%s\n' "${component_rows}" | \
      tsv_rows_to_json_array '["component","deployed","codebase","latest","deploy_tag","code_tag","preferred_tag","latest_tag","status"]' | \
      jq '
        map(
          . + {
            status_text: .status,
            update_available: (.codebase != "" and .latest != "" and .codebase != .latest),
            deployed_available: (.deployed != "" and .deployed != "Unavailable")
          }
          | del(.status)
        )
      '
  )"

  preferred_images_json="$(
    printf '%s\n' "${preferred_image_rows}" | \
      tsv_rows_to_json_array '["component","configured","candidate","status"]' | \
      jq 'map(. + {status_text: .status} | del(.status))'
  )"

  kind_versions_json="$(
    printf '%s\n' "${kind_rows}" | \
      tsv_rows_to_json_array '["item","observed","latest","status"]' | \
      jq 'map(. + {status_text: .status} | del(.status))'
  )"

  dependencies_json="$(
    printf '%s\n' "${dependency_rows}" | \
      tsv_rows_to_json_array '["app","dependency","current","latest_eligible","latest_overall","status"]' | \
      jq 'map(. + {status_text: .status} | del(.status))'
  )"

  external_images_json="$(
    printf '%s\n' "${external_image_rows}" | \
      tsv_rows_to_json_array '["source","image","current","latest","registry","status"]' | \
      jq 'map(. + {status_text: .status} | del(.status))'
  )"

  if [ "${CLUSTER_OK}" -eq 1 ]; then
    cluster_ok_json=true
  else
    cluster_ok_json=false
  fi

  if [ "${EXPECT_KIND_PROVISIONING}" = "true" ]; then
    expect_kind_provisioning_json=true
  else
    expect_kind_provisioning_json=false
  fi

  if [ -n "${CODE_ARGOCD_IMAGE_REF}" ] && [ "${CODE_ARGOCD_IMAGE_REPO}" != "quay.io/argoproj/argocd" ]; then
    argo_cd_image_override_active_json=true
  else
    argo_cd_image_override_active_json=false
  fi

  jq -n \
    --arg format "check-version/v1" \
    --arg expected_cluster_name "${EXPECTED_CLUSTER_NAME}" \
    --argjson cluster_ok "${cluster_ok_json}" \
    --argjson expect_kind_provisioning "${expect_kind_provisioning_json}" \
    --argjson components "${components_json}" \
    --argjson preferred_images "${preferred_images_json}" \
    --argjson kind_versions "${kind_versions_json}" \
    --argjson app_dependencies "${dependencies_json}" \
    --argjson external_images "${external_images_json}" \
    --arg configured_argocd_image "${CODE_ARGOCD_IMAGE_REF}" \
    --arg configured_argocd_image_status "${CONFIGURED_ARGOCD_IMAGE_STATUS}" \
    --arg latest_preferred_argocd_image "${LATEST_PREFERRED_ARGOCD_IMAGE_REF}" \
    --arg latest_preferred_argocd_image_status "${LATEST_PREFERRED_ARGOCD_IMAGE_STATUS}" \
    --argjson argo_cd_image_override_active "${argo_cd_image_override_active_json}" \
    '
      {
        format: $format,
        cluster: {
          expected_cluster_name: $expected_cluster_name,
          reachable: $cluster_ok,
          expect_kind_provisioning: $expect_kind_provisioning
        },
        components: $components,
        preferred_images: $preferred_images,
        kind_versions: $kind_versions,
        app_dependencies: $app_dependencies,
        external_images: $external_images,
        argo_cd_image_override: {
          active: $argo_cd_image_override_active,
          configured_image: $configured_argocd_image,
          configured_image_status: $configured_argocd_image_status,
          latest_preferred_image: $latest_preferred_argocd_image,
          latest_preferred_image_status: $latest_preferred_argocd_image_status
        },
        summary: {
          component_count: ($components | length),
          component_update_count: ($components | map(select(.update_available == true)) | length),
          dependency_count: ($app_dependencies | length),
          dependency_update_count: ($app_dependencies | map(select(.status_text == "update available")) | length),
          dependency_cooldown_count: ($app_dependencies | map(select(.status_text == "cooldown active")) | length),
          external_image_count: ($external_images | length),
          external_image_update_count: ($external_images | map(select(.status_text == "update available")) | length)
        }
      }
    '
}

main() {
  require curl
  require helm
  require jq

  echo ""
  ok "Version check (Deployed vs Codebase vs Latest)"
  echo ""

  CODE_ARGOCD=$(tf_default_from_variables "argocd_chart_version")
  CODE_ARGOCD_IMAGE_REPO=$(tf_default_from_variables "argocd_image_repository")
  CODE_ARGOCD_IMAGE_TAG=$(tf_default_from_variables "argocd_image_tag")
  CODE_GITEA=$(tf_default_from_variables "gitea_chart_version")
  CODE_CILIUM=$(tf_default_from_variables "cilium_version")
  CODE_PROMETHEUS=$(tf_default_from_variables "prometheus_chart_version")
  CODE_GRAFANA=$(tf_default_from_variables "grafana_chart_version")
  CODE_GRAFANA_IMAGE_TAG=$(tf_default_from_variables "grafana_image_tag")
  CODE_LOKI=$(tf_default_from_variables "loki_chart_version")
  CODE_VICTORIA_LOGS=$(tf_default_from_variables "victoria_logs_chart_version")
  CODE_TEMPO=$(tf_default_from_variables "tempo_chart_version")
  CODE_SIGNOZ=$(tf_default_from_variables "signoz_chart_version")
  CODE_OTEL_COLLECTOR=$(tf_default_from_variables "opentelemetry_collector_chart_version")
  CODE_HEADLAMP=$(tf_default_from_variables "headlamp_chart_version")
  CODE_KYVERNO=$(tf_default_from_variables "kyverno_chart_version")
  CODE_POLICY_REPORTER=$(tf_default_from_variables "policy_reporter_chart_version")
  CODE_CERT_MANAGER=$(tf_default_from_variables "cert_manager_chart_version")
  CODE_DEX=$(tf_default_from_variables "dex_chart_version")
  CODE_OAUTH2_PROXY=$(tf_default_from_variables "oauth2_proxy_chart_version")
  CODE_KIND_NODE_IMAGE="$(tfvar_get_any_stage_or_default "node_image" "$(tf_default_from_variables "node_image")")"
  CODE_KIND_NODE_TAG="$(image_tag_from_ref "${CODE_KIND_NODE_IMAGE}")"
  if [ -z "${CODE_ARGOCD_IMAGE_REPO}" ]; then
    CODE_ARGOCD_IMAGE_REPO="quay.io/argoproj/argocd"
  fi

  CODE_ARGOCD_IMAGE_REF=""
  if [ -n "${CODE_ARGOCD_IMAGE_REPO}" ] && [ -n "${CODE_ARGOCD_IMAGE_TAG}" ]; then
    CODE_ARGOCD_IMAGE_REF="${CODE_ARGOCD_IMAGE_REPO}:${CODE_ARGOCD_IMAGE_TAG}"
  fi

  EXPECT_KIND_PROVISIONING="$(tfvar_get_any_stage_bool_or_default "provision_kind_cluster" "true")"
  EXPECTED_CLUSTER_NAME="$(tfvar_get_any_stage_or_default "cluster_name" "kind-local")"
  if [ -z "${EXPECTED_CLUSTER_NAME}" ]; then EXPECTED_CLUSTER_NAME="kind-local"; fi

  progress "Resolving latest upstream chart versions"
  start_heartbeat "Still resolving latest upstream chart versions"
  LATEST_ARGOCD=$(helm_latest_chart_version "argo" "https://argoproj.github.io/argo-helm" "argo-cd")
  LATEST_GITEA=$(helm_latest_chart_version "gitea" "https://dl.gitea.io/charts/" "gitea")
  LATEST_CILIUM=$(helm_latest_chart_version "cilium" "https://helm.cilium.io" "cilium")
  LATEST_PROMETHEUS=$(helm_latest_chart_version "prometheus-community" "https://prometheus-community.github.io/helm-charts" "prometheus")
  LATEST_GRAFANA=$(helm_latest_chart_version "grafana" "https://grafana.github.io/helm-charts" "grafana")
  LATEST_LOKI=$(helm_latest_chart_version "grafana" "https://grafana.github.io/helm-charts" "loki")
  LATEST_VICTORIA_LOGS=$(helm_latest_chart_version "vm" "https://victoriametrics.github.io/helm-charts/" "victoria-logs-single")
  LATEST_TEMPO=$(helm_latest_chart_version "grafana" "https://grafana.github.io/helm-charts" "tempo")
  LATEST_SIGNOZ=$(helm_latest_chart_version "signoz" "https://charts.signoz.io" "signoz")
  LATEST_OTEL_COLLECTOR=$(helm_latest_chart_version "open-telemetry" "https://open-telemetry.github.io/opentelemetry-helm-charts" "opentelemetry-collector")
  LATEST_HEADLAMP=$(helm_latest_chart_version "headlamp" "https://kubernetes-sigs.github.io/headlamp/" "headlamp")
  LATEST_KYVERNO=$(helm_latest_chart_version "kyverno" "https://kyverno.github.io/kyverno/" "kyverno")
  LATEST_POLICY_REPORTER=$(helm_latest_chart_version "kyverno" "https://kyverno.github.io/policy-reporter" "policy-reporter")
  LATEST_CERT_MANAGER=$(helm_latest_chart_version "jetstack" "https://charts.jetstack.io" "cert-manager")
  LATEST_DEX=$(helm_latest_chart_version "dex" "https://charts.dexidp.io" "dex")
  LATEST_OAUTH2_PROXY=$(helm_latest_chart_version "oauth2-proxy" "https://oauth2-proxy.github.io/manifests" "oauth2-proxy")
  stop_heartbeat

  progress "Resolving appVersion metadata for configured chart versions"
  start_heartbeat "Still resolving configured chart appVersion metadata"
  CODETAG_ARGOCD_CHART=$(helm_chart_app_version "argo" "https://argoproj.github.io/argo-helm" "argo-cd" "${CODE_ARGOCD}")
  CODETAG_ARGOCD="${CODETAG_ARGOCD_CHART}"
  CODETAG_GITEA=$(helm_chart_app_version "gitea" "https://dl.gitea.io/charts/" "gitea" "${CODE_GITEA}")
  CODETAG_CILIUM=$(helm_chart_app_version "cilium" "https://helm.cilium.io" "cilium" "${CODE_CILIUM}")
  CODETAG_PROMETHEUS=$(helm_chart_app_version "prometheus-community" "https://prometheus-community.github.io/helm-charts" "prometheus" "${CODE_PROMETHEUS}")
  CODETAG_GRAFANA=$(helm_chart_app_version "grafana" "https://grafana.github.io/helm-charts" "grafana" "${CODE_GRAFANA}")
  if [ -n "${CODE_GRAFANA_IMAGE_TAG}" ]; then
    CODETAG_GRAFANA="${CODE_GRAFANA_IMAGE_TAG}"
  fi
  CODETAG_LOKI=$(helm_chart_app_version "grafana" "https://grafana.github.io/helm-charts" "loki" "${CODE_LOKI}")
  CODETAG_VICTORIA_LOGS=$(helm_chart_app_version "vm" "https://victoriametrics.github.io/helm-charts/" "victoria-logs-single" "${CODE_VICTORIA_LOGS}")
  CODETAG_TEMPO=$(helm_chart_app_version "grafana" "https://grafana.github.io/helm-charts" "tempo" "${CODE_TEMPO}")
  CODETAG_SIGNOZ=$(helm_chart_app_version "signoz" "https://charts.signoz.io" "signoz" "${CODE_SIGNOZ}")
  CODETAG_OTEL_COLLECTOR=$(helm_chart_app_version "open-telemetry" "https://open-telemetry.github.io/opentelemetry-helm-charts" "opentelemetry-collector" "${CODE_OTEL_COLLECTOR}")
  CODETAG_HEADLAMP=$(helm_chart_app_version "headlamp" "https://kubernetes-sigs.github.io/headlamp/" "headlamp" "${CODE_HEADLAMP}")
  CODETAG_KYVERNO=$(helm_chart_app_version "kyverno" "https://kyverno.github.io/kyverno/" "kyverno" "${CODE_KYVERNO}")
  CODETAG_POLICY_REPORTER=$(helm_chart_app_version "kyverno" "https://kyverno.github.io/policy-reporter" "policy-reporter" "${CODE_POLICY_REPORTER}")
  CODETAG_CERT_MANAGER=$(helm_chart_app_version "jetstack" "https://charts.jetstack.io" "cert-manager" "${CODE_CERT_MANAGER}")
  CODETAG_DEX=$(helm_chart_app_version "dex" "https://charts.dexidp.io" "dex" "${CODE_DEX}")
  CODETAG_OAUTH2_PROXY=$(helm_chart_app_version "oauth2-proxy" "https://oauth2-proxy.github.io/manifests" "oauth2-proxy" "${CODE_OAUTH2_PROXY}")
  stop_heartbeat

  progress "Resolving appVersion metadata for latest upstream chart versions"
  start_heartbeat "Still resolving latest chart appVersion metadata"
  LATESTTAG_ARGOCD_CHART=$(helm_chart_app_version "argo" "https://argoproj.github.io/argo-helm" "argo-cd" "${LATEST_ARGOCD}")
  LATESTTAG_ARGOCD="${LATESTTAG_ARGOCD_CHART}"
  LATESTTAG_GITEA=$(helm_chart_app_version "gitea" "https://dl.gitea.io/charts/" "gitea" "${LATEST_GITEA}")
  LATESTTAG_CILIUM=$(helm_chart_app_version "cilium" "https://helm.cilium.io" "cilium" "${LATEST_CILIUM}")
  LATESTTAG_PROMETHEUS=$(helm_chart_app_version "prometheus-community" "https://prometheus-community.github.io/helm-charts" "prometheus" "${LATEST_PROMETHEUS}")
  LATESTTAG_GRAFANA=$(helm_chart_app_version "grafana" "https://grafana.github.io/helm-charts" "grafana" "${LATEST_GRAFANA}")
  LATESTTAG_LOKI=$(helm_chart_app_version "grafana" "https://grafana.github.io/helm-charts" "loki" "${LATEST_LOKI}")
  LATESTTAG_VICTORIA_LOGS=$(helm_chart_app_version "vm" "https://victoriametrics.github.io/helm-charts/" "victoria-logs-single" "${LATEST_VICTORIA_LOGS}")
  LATESTTAG_TEMPO=$(helm_chart_app_version "grafana" "https://grafana.github.io/helm-charts" "tempo" "${LATEST_TEMPO}")
  LATESTTAG_SIGNOZ=$(helm_chart_app_version "signoz" "https://charts.signoz.io" "signoz" "${LATEST_SIGNOZ}")
  LATESTTAG_OTEL_COLLECTOR=$(helm_chart_app_version "open-telemetry" "https://open-telemetry.github.io/opentelemetry-helm-charts" "opentelemetry-collector" "${LATEST_OTEL_COLLECTOR}")
  LATESTTAG_HEADLAMP=$(helm_chart_app_version "headlamp" "https://kubernetes-sigs.github.io/headlamp/" "headlamp" "${LATEST_HEADLAMP}")
  LATESTTAG_KYVERNO=$(helm_chart_app_version "kyverno" "https://kyverno.github.io/kyverno/" "kyverno" "${LATEST_KYVERNO}")
  LATESTTAG_POLICY_REPORTER=$(helm_chart_app_version "kyverno" "https://kyverno.github.io/policy-reporter" "policy-reporter" "${LATEST_POLICY_REPORTER}")
  LATESTTAG_CERT_MANAGER=$(helm_chart_app_version "jetstack" "https://charts.jetstack.io" "cert-manager" "${LATEST_CERT_MANAGER}")
  LATESTTAG_DEX=$(helm_chart_app_version "dex" "https://charts.dexidp.io" "dex" "${LATEST_DEX}")
  LATESTTAG_OAUTH2_PROXY=$(helm_chart_app_version "oauth2-proxy" "https://oauth2-proxy.github.io/manifests" "oauth2-proxy" "${LATEST_OAUTH2_PROXY}")
  stop_heartbeat

  progress "Checking preferred image availability and cluster reachability"
  progress "Checking configured Argo CD image availability"
  CONFIGURED_ARGOCD_IMAGE_STATUS="$(image_ref_availability "${CODE_ARGOCD_IMAGE_REF}")"
  LATEST_PREFERRED_ARGOCD_TAG=""
  LATEST_PREFERRED_ARGOCD_IMAGE_REF=""
  LATEST_PREFERRED_ARGOCD_IMAGE_STATUS=""
  if [ "${CODE_ARGOCD_IMAGE_REPO}" = "dhi.io/argocd" ] && [ -n "${CODE_ARGOCD_IMAGE_TAG}" ] && [ -n "${LATESTTAG_ARGOCD_CHART}" ]; then
    LATEST_PREFERRED_ARGOCD_TAG="$(derive_tag_with_existing_suffix "${LATESTTAG_ARGOCD_CHART}" "${CODE_ARGOCD_IMAGE_TAG}")"
    if [ -n "${LATEST_PREFERRED_ARGOCD_TAG}" ]; then
      LATEST_PREFERRED_ARGOCD_IMAGE_REF="${CODE_ARGOCD_IMAGE_REPO}:${LATEST_PREFERRED_ARGOCD_TAG}"
      progress "Checking latest preferred Argo CD image availability"
      LATEST_PREFERRED_ARGOCD_IMAGE_STATUS="$(image_ref_availability "${LATEST_PREFERRED_ARGOCD_IMAGE_REF}")"
    fi
  fi

  CLUSTER_OK=0
  if [ "${EXPECT_KIND_PROVISIONING}" = "true" ] && command -v kind >/dev/null 2>&1; then
    progress "Checking kind cluster presence"
    if ! kind_get_clusters_safe | grep -qx "${EXPECTED_CLUSTER_NAME}"; then
      warn "Cluster '${EXPECTED_CLUSTER_NAME}' not found; Deployed=Unavailable"
      progress "Checking Kubernetes API reachability"
    elif cluster_reachable; then
      CLUSTER_OK=1
    else
      warn "Cluster '${EXPECTED_CLUSTER_NAME}' exists but API is unreachable; Deployed=Unavailable"
    fi
  else
    progress "Checking Kubernetes API reachability"
    if cluster_reachable; then
      CLUSTER_OK=1
    else
      if [ "${EXPECT_KIND_PROVISIONING}" = "true" ]; then
        warn "Cluster API unreachable (and 'kind' not found); Deployed=Unavailable"
      else
        warn "Cluster API unreachable for existing-cluster target; Deployed=Unavailable"
      fi
    fi
  fi

  DEPLOYED_CILIUM=""
  DEPLOYED_ARGOCD=""
  DEPLOYED_GITEA=""
  DEPLOYED_SIGNOZ=""
  DEPLOYED_PROMETHEUS=""
  DEPLOYED_GRAFANA=""
  DEPLOYED_LOKI=""
  DEPLOYED_VICTORIA_LOGS=""
  DEPLOYED_TEMPO=""
  DEPLOYED_OTEL_COLLECTOR=""
  DEPLOYED_HEADLAMP=""
  DEPLOYED_KYVERNO=""
  DEPLOYED_POLICY_REPORTER=""
  DEPLOYED_CERT_MANAGER=""
  DEPLOYED_DEX=""
  DEPLOYED_OAUTH2_PROXY=""
  DEPLOYEDTAG_CILIUM=""
  DEPLOYEDTAG_ARGOCD=""
  DEPLOYED_ARGOCD_IMAGE_REF=""
  DEPLOYEDTAG_GITEA=""
  DEPLOYEDTAG_PROMETHEUS=""
  DEPLOYEDTAG_GRAFANA=""
  DEPLOYEDTAG_LOKI=""
  DEPLOYEDTAG_VICTORIA_LOGS=""
  DEPLOYEDTAG_TEMPO=""
  DEPLOYEDTAG_SIGNOZ=""
  DEPLOYEDTAG_OTEL_COLLECTOR=""
  DEPLOYEDTAG_HEADLAMP=""
  DEPLOYEDTAG_KYVERNO=""
  DEPLOYEDTAG_POLICY_REPORTER=""
  DEPLOYEDTAG_CERT_MANAGER=""
  DEPLOYEDTAG_DEX=""
  DEPLOYEDTAG_OAUTH2_PROXY=""

  if [ "${CLUSTER_OK}" -eq 1 ]; then
    progress "Inspecting deployed chart and image versions from cluster resources"
    start_heartbeat "Still inspecting deployed chart and image versions"
    DEPLOYED_CILIUM=$(helm_deployed_chart_version "kube-system" "cilium")
    DEPLOYED_ARGOCD=$(helm_deployed_chart_version "argocd" "argocd")
    DEPLOYED_ARGOCD_IMAGE_REF=$(k8s_deployment_container_image "argocd" "argocd-server" "server")

    DEPLOYED_GITEA=$(argocd_app_deployed_chart_version "gitea" "gitea")
    DEPLOYED_PROMETHEUS=$(argocd_app_deployed_chart_version "prometheus" "prometheus")
    DEPLOYED_GRAFANA=$(argocd_app_deployed_chart_version "grafana" "grafana")
    DEPLOYED_LOKI=$(argocd_app_deployed_chart_version "loki" "loki")
    DEPLOYED_VICTORIA_LOGS=$(argocd_app_deployed_chart_version "victoria-logs" "victoria-logs-single")
    DEPLOYED_TEMPO=$(argocd_app_deployed_chart_version "tempo" "tempo")
    DEPLOYED_SIGNOZ=$(argocd_app_deployed_chart_version "signoz" "signoz")
    DEPLOYED_OTEL_COLLECTOR=$(argocd_app_deployed_chart_version "otel-collector-agent" "opentelemetry-collector")
    if [ -z "${DEPLOYED_OTEL_COLLECTOR}" ]; then
      DEPLOYED_OTEL_COLLECTOR=$(argocd_app_deployed_chart_version "otel-collector-prometheus" "opentelemetry-collector")
    fi
    DEPLOYED_HEADLAMP=$(argocd_app_deployed_chart_version "headlamp" "headlamp")

    DEPLOYED_KYVERNO=$(argocd_app_deployed_chart_version "kyverno" "kyverno")
    DEPLOYED_POLICY_REPORTER=$(argocd_app_deployed_chart_version "policy-reporter" "policy-reporter")
    DEPLOYED_CERT_MANAGER=$(argocd_app_deployed_chart_version "cert-manager" "cert-manager")

    DEPLOYED_DEX=$(argocd_app_deployed_chart_version "dex" "dex")
    DEPLOYED_OAUTH2_PROXY=$(argocd_app_deployed_chart_version "oauth2-proxy-argocd" "oauth2-proxy")

    DEPLOYEDTAG_CILIUM=$(helm_chart_app_version "cilium" "https://helm.cilium.io" "cilium" "${DEPLOYED_CILIUM}")
    DEPLOYEDTAG_ARGOCD=$(image_tag_from_ref "${DEPLOYED_ARGOCD_IMAGE_REF}")
    if [ -z "${DEPLOYEDTAG_ARGOCD}" ]; then
      DEPLOYEDTAG_ARGOCD=$(helm_chart_app_version "argo" "https://argoproj.github.io/argo-helm" "argo-cd" "${DEPLOYED_ARGOCD}")
    fi
    DEPLOYEDTAG_GITEA=$(helm_chart_app_version "gitea" "https://dl.gitea.io/charts/" "gitea" "${DEPLOYED_GITEA}")
    DEPLOYEDTAG_PROMETHEUS=$(helm_chart_app_version "prometheus-community" "https://prometheus-community.github.io/helm-charts" "prometheus" "${DEPLOYED_PROMETHEUS}")
    DEPLOYEDTAG_GRAFANA=$(helm_chart_app_version "grafana" "https://grafana.github.io/helm-charts" "grafana" "${DEPLOYED_GRAFANA}")
    DEPLOYEDTAG_LOKI=$(helm_chart_app_version "grafana" "https://grafana.github.io/helm-charts" "loki" "${DEPLOYED_LOKI}")
    DEPLOYEDTAG_VICTORIA_LOGS=$(helm_chart_app_version "vm" "https://victoriametrics.github.io/helm-charts/" "victoria-logs-single" "${DEPLOYED_VICTORIA_LOGS}")
    DEPLOYEDTAG_TEMPO=$(helm_chart_app_version "grafana" "https://grafana.github.io/helm-charts" "tempo" "${DEPLOYED_TEMPO}")
    DEPLOYEDTAG_SIGNOZ=$(helm_chart_app_version "signoz" "https://charts.signoz.io" "signoz" "${DEPLOYED_SIGNOZ}")
    DEPLOYEDTAG_OTEL_COLLECTOR=$(helm_chart_app_version "open-telemetry" "https://open-telemetry.github.io/opentelemetry-helm-charts" "opentelemetry-collector" "${DEPLOYED_OTEL_COLLECTOR}")
    DEPLOYEDTAG_HEADLAMP=$(helm_chart_app_version "headlamp" "https://kubernetes-sigs.github.io/headlamp/" "headlamp" "${DEPLOYED_HEADLAMP}")
    DEPLOYEDTAG_KYVERNO=$(helm_chart_app_version "kyverno" "https://kyverno.github.io/kyverno/" "kyverno" "${DEPLOYED_KYVERNO}")
    DEPLOYEDTAG_POLICY_REPORTER=$(helm_chart_app_version "kyverno" "https://kyverno.github.io/policy-reporter" "policy-reporter" "${DEPLOYED_POLICY_REPORTER}")
    DEPLOYEDTAG_CERT_MANAGER=$(helm_chart_app_version "jetstack" "https://charts.jetstack.io" "cert-manager" "${DEPLOYED_CERT_MANAGER}")
    DEPLOYEDTAG_DEX=$(helm_chart_app_version "dex" "https://charts.dexidp.io" "dex" "${DEPLOYED_DEX}")
    DEPLOYEDTAG_OAUTH2_PROXY=$(helm_chart_app_version "oauth2-proxy" "https://oauth2-proxy.github.io/manifests" "oauth2-proxy" "${DEPLOYED_OAUTH2_PROXY}")
    stop_heartbeat
  else
    DEPLOYED_CILIUM="Unavailable"
    DEPLOYED_ARGOCD="Unavailable"
    DEPLOYED_GITEA="Unavailable"
    DEPLOYED_PROMETHEUS="Unavailable"
    DEPLOYED_GRAFANA="Unavailable"
    DEPLOYED_LOKI="Unavailable"
    DEPLOYED_VICTORIA_LOGS="Unavailable"
    DEPLOYED_TEMPO="Unavailable"
    DEPLOYED_SIGNOZ="Unavailable"
    DEPLOYED_OTEL_COLLECTOR="Unavailable"
    DEPLOYED_HEADLAMP="Unavailable"
    DEPLOYED_KYVERNO="Unavailable"
    DEPLOYED_POLICY_REPORTER="Unavailable"
    DEPLOYED_CERT_MANAGER="Unavailable"
    DEPLOYED_DEX="Unavailable"
    DEPLOYED_OAUTH2_PROXY="Unavailable"
    DEPLOYEDTAG_CILIUM="Unavailable"
    DEPLOYEDTAG_ARGOCD="Unavailable"
    DEPLOYEDTAG_GITEA="Unavailable"
    DEPLOYEDTAG_PROMETHEUS="Unavailable"
    DEPLOYEDTAG_GRAFANA="Unavailable"
    DEPLOYEDTAG_LOKI="Unavailable"
    DEPLOYEDTAG_VICTORIA_LOGS="Unavailable"
    DEPLOYEDTAG_TEMPO="Unavailable"
    DEPLOYEDTAG_SIGNOZ="Unavailable"
    DEPLOYEDTAG_OTEL_COLLECTOR="Unavailable"
    DEPLOYEDTAG_HEADLAMP="Unavailable"
    DEPLOYEDTAG_KYVERNO="Unavailable"
    DEPLOYEDTAG_POLICY_REPORTER="Unavailable"
    DEPLOYEDTAG_CERT_MANAGER="Unavailable"
    DEPLOYEDTAG_DEX="Unavailable"
    DEPLOYEDTAG_OAUTH2_PROXY="Unavailable"
  fi

  rows=()
  rows+=("$(print_row "argo-cd chart" "${DEPLOYED_ARGOCD}" "${CODE_ARGOCD}" "${LATEST_ARGOCD}" "${DEPLOYEDTAG_ARGOCD}" "${CODETAG_ARGOCD}" "${LATEST_PREFERRED_ARGOCD_TAG}" "${LATESTTAG_ARGOCD}" "1" "${LATEST_PREFERRED_ARGOCD_IMAGE_STATUS}")")
  rows+=("$(print_row "gitea chart" "${DEPLOYED_GITEA}" "${CODE_GITEA}" "${LATEST_GITEA}" "${DEPLOYEDTAG_GITEA}" "${CODETAG_GITEA}" "" "${LATESTTAG_GITEA}" "0")")
  rows+=("$(print_row "cilium chart" "${DEPLOYED_CILIUM}" "${CODE_CILIUM}" "${LATEST_CILIUM}" "${DEPLOYEDTAG_CILIUM}" "${CODETAG_CILIUM}" "" "${LATESTTAG_CILIUM}" "0")")
  rows+=("$(print_row "prometheus chart" "${DEPLOYED_PROMETHEUS}" "${CODE_PROMETHEUS}" "${LATEST_PROMETHEUS}" "${DEPLOYEDTAG_PROMETHEUS}" "${CODETAG_PROMETHEUS}" "" "${LATESTTAG_PROMETHEUS}" "0")")
  rows+=("$(print_row "grafana chart" "${DEPLOYED_GRAFANA}" "${CODE_GRAFANA}" "${LATEST_GRAFANA}" "${DEPLOYEDTAG_GRAFANA}" "${CODETAG_GRAFANA}" "" "${LATESTTAG_GRAFANA}" "0")")
  rows+=("$(print_row "loki chart" "${DEPLOYED_LOKI}" "${CODE_LOKI}" "${LATEST_LOKI}" "${DEPLOYEDTAG_LOKI}" "${CODETAG_LOKI}" "" "${LATESTTAG_LOKI}" "0")")
  rows+=("$(print_row "victoria-logs" "${DEPLOYED_VICTORIA_LOGS}" "${CODE_VICTORIA_LOGS}" "${LATEST_VICTORIA_LOGS}" "${DEPLOYEDTAG_VICTORIA_LOGS}" "${CODETAG_VICTORIA_LOGS}" "" "${LATESTTAG_VICTORIA_LOGS}" "0")")
  rows+=("$(print_row "tempo chart" "${DEPLOYED_TEMPO}" "${CODE_TEMPO}" "${LATEST_TEMPO}" "${DEPLOYEDTAG_TEMPO}" "${CODETAG_TEMPO}" "" "${LATESTTAG_TEMPO}" "0")")
  rows+=("$(print_row "signoz chart" "${DEPLOYED_SIGNOZ}" "${CODE_SIGNOZ}" "${LATEST_SIGNOZ}" "${DEPLOYEDTAG_SIGNOZ}" "${CODETAG_SIGNOZ}" "" "${LATESTTAG_SIGNOZ}" "0")")
  rows+=("$(print_row "otel-collector" "${DEPLOYED_OTEL_COLLECTOR}" "${CODE_OTEL_COLLECTOR}" "${LATEST_OTEL_COLLECTOR}" "${DEPLOYEDTAG_OTEL_COLLECTOR}" "${CODETAG_OTEL_COLLECTOR}" "" "${LATESTTAG_OTEL_COLLECTOR}" "0")")
  rows+=("$(print_row "headlamp chart" "${DEPLOYED_HEADLAMP}" "${CODE_HEADLAMP}" "${LATEST_HEADLAMP}" "${DEPLOYEDTAG_HEADLAMP}" "${CODETAG_HEADLAMP}" "" "${LATESTTAG_HEADLAMP}" "0")")
  rows+=("$(print_row "kyverno chart" "${DEPLOYED_KYVERNO}" "${CODE_KYVERNO}" "${LATEST_KYVERNO}" "${DEPLOYEDTAG_KYVERNO}" "${CODETAG_KYVERNO}" "" "${LATESTTAG_KYVERNO}" "0")")
  rows+=("$(print_row "policy-reporter" "${DEPLOYED_POLICY_REPORTER}" "${CODE_POLICY_REPORTER}" "${LATEST_POLICY_REPORTER}" "${DEPLOYEDTAG_POLICY_REPORTER}" "${CODETAG_POLICY_REPORTER}" "" "${LATESTTAG_POLICY_REPORTER}" "0")")
  rows+=("$(print_row "cert-manager" "${DEPLOYED_CERT_MANAGER}" "${CODE_CERT_MANAGER}" "${LATEST_CERT_MANAGER}" "${DEPLOYEDTAG_CERT_MANAGER}" "${CODETAG_CERT_MANAGER}" "" "${LATESTTAG_CERT_MANAGER}" "0")")
  rows+=("$(print_row "dex chart" "${DEPLOYED_DEX}" "${CODE_DEX}" "${LATEST_DEX}" "${DEPLOYEDTAG_DEX}" "${CODETAG_DEX}" "" "${LATESTTAG_DEX}" "0")")
  rows+=("$(print_row "oauth2-proxy" "${DEPLOYED_OAUTH2_PROXY}" "${CODE_OAUTH2_PROXY}" "${LATEST_OAUTH2_PROXY}" "${DEPLOYEDTAG_OAUTH2_PROXY}" "${CODETAG_OAUTH2_PROXY}" "" "${LATESTTAG_OAUTH2_PROXY}" "0")")
  component_rows_sorted="$(printf "%s\n" "${rows[@]}" | sort -t $'\t' -k1,1)"

  image_rows=()
  if [ -n "${CODE_ARGOCD_IMAGE_REF}" ] && [ "${CODE_ARGOCD_IMAGE_REPO}" = "dhi.io/argocd" ]; then
    image_rows+=("$(print_preferred_image_row "argo-cd image" "${CODE_ARGOCD_IMAGE_REF}" "${CONFIGURED_ARGOCD_IMAGE_STATUS}" "${LATEST_PREFERRED_ARGOCD_IMAGE_REF}" "${LATEST_PREFERRED_ARGOCD_IMAGE_STATUS}")")
  fi
  preferred_image_rows_sorted="$(printf "%s\n" "${image_rows[@]}" | sort -t $'\t' -k1,1 || true)"

  INSTALLED_KIND="$(kind_installed_version)"
  progress "Checking latest kind release tag"
  LATEST_KIND_RELEASE_TAG="$(github_latest_release_tag "kubernetes-sigs/kind")"
  progress "Checking latest kindest/node tag"
  LATEST_KIND_NODE_TAG="$(kindest_node_latest_tag)"

  kind_rows=()
  kind_rows+=("$(print_observed_latest_row "kind release tag" "$(normalize_semver_like_tag "${INSTALLED_KIND}")" "${LATEST_KIND_RELEASE_TAG}" "installed cli" "release tag")")
  kind_rows+=("$(print_observed_latest_row "kind node tag" "${CODE_KIND_NODE_TAG}" "${LATEST_KIND_NODE_TAG}" "codebase" "node tag")")
  kind_rows_sorted="$(printf "%s\n" "${kind_rows[@]}" | sort -t $'\t' -k1,1)"

  check_consistent_tfvars "argocd_chart_version"
  check_consistent_tfvars "argocd_image_repository"
  check_consistent_tfvars "argocd_image_tag"
  check_consistent_tfvars "gitea_chart_version"
  check_consistent_tfvars "cilium_version"
  check_consistent_tfvars "prometheus_chart_version"
  check_consistent_tfvars "grafana_chart_version"
  check_consistent_tfvars "loki_chart_version"
  check_consistent_tfvars "victoria_logs_chart_version"
  check_consistent_tfvars "tempo_chart_version"
  check_consistent_tfvars "signoz_chart_version"
  check_consistent_tfvars "opentelemetry_collector_chart_version"
  check_consistent_tfvars "headlamp_chart_version"
  check_consistent_tfvars "kyverno_chart_version"
  check_consistent_tfvars "policy_reporter_chart_version"
  check_consistent_tfvars "cert_manager_chart_version"
  check_consistent_tfvars "dex_chart_version"
  check_consistent_tfvars "oauth2_proxy_chart_version"

  progress "Checking app-of-apps revisions and preload image alignment"
  check_app_yaml_tfvar_drift
  check_preload_chart_section_version_alignment
  check_preload_image_version_alignment "${CODE_ARGOCD_IMAGE_REF}" "${CODETAG_PROMETHEUS}" "${CODETAG_GRAFANA}" "${CODETAG_LOKI}" "${CODETAG_TEMPO}" "${CODETAG_VICTORIA_LOGS}"

  progress "Warming npm and PyPI metadata cache"
  warm_dependency_metadata_caches

  progress "Auditing app dependency freshness"
  dependency_rows="$(emit_app_dependency_rows | sort -t $'\t' -k1,1 -k2,2 || true)"

  progress "Auditing external workload images"
  image_audit_rows="$(emit_external_image_rows | sort -t $'\t' -k2,2 || true)"

  if json_mode; then
    emit_json_report \
      "${component_rows_sorted}" \
      "${preferred_image_rows_sorted}" \
      "${kind_rows_sorted}" \
      "${dependency_rows}" \
      "${image_audit_rows}"
    return 0
  fi

  section "Component versions"
  printf "%s\n" \
    $'Component\tDeployed\tCodebase\tLatest\tDeployTag\tCodeTag\tPrefTag\tLatestTag\tStatus' \
    $'---------\t--------\t--------\t------\t---------\t-------\t-------\t---------\t------' \
    "${component_rows_sorted}" | render_tsv_table
  echo ""

  section "Preferred image availability"
  if [ "${#image_rows[@]}" -eq 0 ]; then
    warn "No preferred image overrides configured"
    echo ""
  else
    printf "%s\n" \
      $'Component\tConfigured\tCandidate\tStatus' \
      $'---------\t----------\t---------\t------' \
      "${preferred_image_rows_sorted}" | render_tsv_table
    echo ""
  fi

  section "Kind versions"
  printf "%s\n" \
    $'Item\tObserved\tLatest\tStatus' \
    $'----\t--------\t------\t------' \
    "${kind_rows_sorted}" | render_tsv_table
  echo ""

  section "App dependency cooldown audit"
  if [ -z "${dependency_rows}" ]; then
    warn "No app dependency roots discovered"
    echo ""
  else
    render_dependency_audit_text "${dependency_rows}"
  fi

  section "External workload image audit"
  if [ -z "${image_audit_rows}" ]; then
    warn "No external workload images discovered"
    echo ""
  else
    render_external_image_audit_text "${image_audit_rows}"
  fi

  if [ -n "${CODE_ARGOCD_IMAGE_REF}" ] && [ "${CODE_ARGOCD_IMAGE_REPO}" != "quay.io/argoproj/argocd" ]; then
    ok "Argo CD image override active: ${CODE_ARGOCD_IMAGE_REF} (chart appVersion ${CODETAG_ARGOCD_CHART}, latest upstream appVersion ${LATESTTAG_ARGOCD_CHART})"
    echo ""
  fi

  ok "Done"
}

if [ "${CHECK_VERSION_LIB_ONLY:-0}" = "1" ]; then
  if ! return 0 2>/dev/null; then
    # shellcheck disable=SC2317
    exit 0
  fi
fi

main "$@"
