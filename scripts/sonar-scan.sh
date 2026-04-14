#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/shell-cli.sh"

SONAR_SCAN_REPO="${SONAR_SCAN_REPO:-${PWD}}"
SONAR_PROJECT_KEY="${SONAR_PROJECT_KEY:-}"
SONAR_PROJECT_NAME="${SONAR_PROJECT_NAME:-}"
SONAR_HOST_URL="${SONAR_HOST_URL:-http://127.0.0.1:9000}"
SONAR_DOCKER_HOST_URL="${SONAR_DOCKER_HOST_URL:-http://host.docker.internal:9000}"
SONAR_SCANNER_IMAGE="${SONAR_SCANNER_IMAGE:-sonarsource/sonar-scanner-cli:latest}"
SONAR_SCAN_CACHE_DIR="${SONAR_SCAN_CACHE_DIR:-}"
SONAR_TOKEN="${SONAR_TOKEN:-}"
SONAR_TOKEN_FILE="${SONAR_TOKEN_FILE:-}"
SONAR_USERNAME="${SONAR_USERNAME:-}"
SONAR_PASSWORD="${SONAR_PASSWORD:-}"
SONAR_TOKEN_NAME="${SONAR_TOKEN_NAME:-}"
SONAR_NO_DEFAULT_EXCLUSIONS="${SONAR_NO_DEFAULT_EXCLUSIONS:-0}"
SONAR_EXCLUSIONS="${SONAR_EXCLUSIONS:-}"

DEFAULT_EXCLUSIONS=(
  "**/.git/**"
  "**/.scannerwork/**"
  "**/.run/**"
  "**/node_modules/**"
  "**/.venv/**"
  "**/dist/**"
  "**/build/**"
  "**/coverage/**"
  "**/target/**"
  "**/.next/**"
  "**/.turbo/**"
)

usage() {
  cat <<EOF
Usage: sonar-scan.sh [options]

Run a SonarQube analysis for a local repository using the bundled scanner
container. If the target repository already has a sonar-project.properties file,
this helper uses it. Otherwise, it falls back to sensible defaults.

Options:
  --repo PATH            Repository or project root to scan (default: current directory)
  --project-key KEY      Override the SonarQube project key
  --project-name NAME    Override the SonarQube project name
  --host-url URL        SonarQube API URL for token management and status checks
  --docker-host-url URL SonarQube URL visible from the scanner container
  --scanner-image IMAGE  Scanner container image (default: ${SONAR_SCANNER_IMAGE})
  --token TOKEN          Use an existing SonarQube token
  --token-file PATH      Read an existing token from a file
  --exclude PATTERN      Add a Sonar exclusion pattern; may be repeated
  --no-default-exclusions
                        Do not add the helper's built-in exclusion list
$(shell_cli_standard_options)

Environment variables:
  SONAR_TOKEN, SONAR_TOKEN_FILE, SONAR_USERNAME, SONAR_PASSWORD
  SONAR_PROJECT_KEY, SONAR_PROJECT_NAME
  SONAR_HOST_URL, SONAR_DOCKER_HOST_URL, SONAR_SCANNER_IMAGE
  SONAR_EXCLUSIONS, SONAR_NO_DEFAULT_EXCLUSIONS
EOF
}

fail() {
  printf 'sonar-scan: %s\n' "$*" >&2
  exit 1
}

is_true() {
  case "$1" in
    1|true|TRUE|yes|YES|y|Y)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

sanitize_slug() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/[^a-z0-9._:-]/-/g' -e 's/--*/-/g' -e 's/^-//' -e 's/-$//'
}

expand_home_path() {
  case "$1" in
    "~")
      printf '%s\n' "${HOME}"
      ;;
    "~/"*)
      printf '%s\n' "${HOME}/${1#\~/}"
      ;;
    *)
      printf '%s\n' "$1"
      ;;
  esac
}

join_by_comma() {
  local IFS=,

  printf '%s\n' "$*"
}

repo_root_from_path() {
  local repo_path="$1"

  [[ -d "${repo_path}" ]] || fail "repository path does not exist: ${repo_path}"
  (cd "${repo_path}" && pwd)
}

resolve_scan_token() {
  local token=""

  if [[ -n "${SONAR_TOKEN}" ]]; then
    token="${SONAR_TOKEN}"
  elif [[ -n "${SONAR_TOKEN_FILE}" ]]; then
    local token_file
    token_file="$(expand_home_path "${SONAR_TOKEN_FILE}")"
    [[ -r "${token_file}" ]] || fail "SONAR_TOKEN_FILE is not readable: ${token_file}"
    token="$(< "${token_file}")"
    token="${token%$'\n'}"
  elif [[ -n "${SONAR_USERNAME}" || -n "${SONAR_PASSWORD}" ]]; then
    [[ -n "${SONAR_USERNAME}" && -n "${SONAR_PASSWORD}" ]] || \
      fail "set both SONAR_USERNAME and SONAR_PASSWORD if you want the helper to mint a temporary token"

    local token_name response
    token_name="${SONAR_TOKEN_NAME:-codex-sonar-scan-$(sanitize_slug "${SONAR_PROJECT_KEY:-${scan_repo_name}}")-$(date +%Y%m%d%H%M%S)-$$}"
    response="$(curl -fsS -u "${SONAR_USERNAME}:${SONAR_PASSWORD}" \
      -X POST "${SONAR_HOST_URL%/}/api/user_tokens/generate" \
      --data-urlencode "name=${token_name}")"
    token="$(jq -r '.token' <<<"${response}")"
    [[ "${token}" != "null" && -n "${token}" ]] || fail "SonarQube did not return a token"
    created_token_name="${token_name}"
    created_token=1
    printf 'Created temporary Sonar token: %s\n' "${created_token_name}" >&2
  else
    fail "set SONAR_TOKEN, SONAR_TOKEN_FILE, or SONAR_USERNAME+SONAR_PASSWORD"
  fi

  scan_token="${token}"
}

check_sonar_status() {
  local status

  status="$(
    curl -fsS "${SONAR_HOST_URL%/}/api/system/status" | jq -r '.status'
  )" || fail "unable to reach SonarQube at ${SONAR_HOST_URL}"

  [[ "${status}" == "UP" ]] || fail "SonarQube at ${SONAR_HOST_URL} is not UP (status: ${status})"
}

revoke_temp_token() {
  if [[ "${created_token}" -ne 1 || -z "${created_token_name}" ]]; then
    return 0
  fi

  curl -fsS -u "${SONAR_USERNAME}:${SONAR_PASSWORD}" \
    -X POST "${SONAR_HOST_URL%/}/api/user_tokens/revoke" \
    --data-urlencode "name=${created_token_name}" >/dev/null
}

cleanup() {
  if [[ "${scannerwork_preexisting}" -ne 1 && -n "${scannerwork_dir}" && -d "${scannerwork_dir}" ]]; then
    rm -rf "${scannerwork_dir}"
  fi

  revoke_temp_token || true
}

shell_cli_init_standard_flags
scan_repo_path="${SONAR_SCAN_REPO}"
scanner_exclusions=()
include_default_exclusions="${SONAR_NO_DEFAULT_EXCLUSIONS:-0}"
scannerwork_dir=""
scannerwork_preexisting=0
created_token=0
created_token_name=""
scan_repo_name=""
scan_token=""

while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --repo)
      [[ $# -ge 2 ]] || { shell_cli_missing_value "$(shell_cli_script_name)" "$1"; exit 1; }
      scan_repo_path="$2"
      shift 2
      ;;
    --project-key)
      [[ $# -ge 2 ]] || { shell_cli_missing_value "$(shell_cli_script_name)" "$1"; exit 1; }
      SONAR_PROJECT_KEY="$2"
      shift 2
      ;;
    --project-name)
      [[ $# -ge 2 ]] || { shell_cli_missing_value "$(shell_cli_script_name)" "$1"; exit 1; }
      SONAR_PROJECT_NAME="$2"
      shift 2
      ;;
    --host-url)
      [[ $# -ge 2 ]] || { shell_cli_missing_value "$(shell_cli_script_name)" "$1"; exit 1; }
      SONAR_HOST_URL="$2"
      shift 2
      ;;
    --docker-host-url)
      [[ $# -ge 2 ]] || { shell_cli_missing_value "$(shell_cli_script_name)" "$1"; exit 1; }
      SONAR_DOCKER_HOST_URL="$2"
      shift 2
      ;;
    --scanner-image)
      [[ $# -ge 2 ]] || { shell_cli_missing_value "$(shell_cli_script_name)" "$1"; exit 1; }
      SONAR_SCANNER_IMAGE="$2"
      shift 2
      ;;
    --token)
      [[ $# -ge 2 ]] || { shell_cli_missing_value "$(shell_cli_script_name)" "$1"; exit 1; }
      SONAR_TOKEN="$2"
      shift 2
      ;;
    --token-file)
      [[ $# -ge 2 ]] || { shell_cli_missing_value "$(shell_cli_script_name)" "$1"; exit 1; }
      SONAR_TOKEN_FILE="$2"
      shift 2
      ;;
    --exclude)
      [[ $# -ge 2 ]] || { shell_cli_missing_value "$(shell_cli_script_name)" "$1"; exit 1; }
      scanner_exclusions+=("$2")
      shift 2
      ;;
    --no-default-exclusions)
      include_default_exclusions=0
      shift
      ;;
    -*)
      shell_cli_unknown_flag "$(shell_cli_script_name)" "$1"
      exit 1
      ;;
    *)
      shell_cli_unexpected_arg "$(shell_cli_script_name)" "$1"
      exit 1
      ;;
  esac
done

scan_repo_path="$(expand_home_path "${scan_repo_path}")"
scan_repo_root="$(repo_root_from_path "${scan_repo_path}")"
scan_repo_name="$(basename "${scan_repo_root}")"
scannerwork_dir="${scan_repo_root}/.scannerwork"
if [[ -z "${SONAR_SCAN_CACHE_DIR}" ]]; then
  SONAR_SCAN_CACHE_DIR="${TMPDIR:-/tmp}/codex-sonar-scan/$(sanitize_slug "${scan_repo_root}")"
fi
SONAR_SCAN_CACHE_DIR="$(expand_home_path "${SONAR_SCAN_CACHE_DIR}")"

if [[ -f "${scan_repo_root}/sonar-project.properties" ]]; then
  has_project_config=1
else
  has_project_config=0
fi

if [[ "${has_project_config}" -eq 0 ]]; then
  if [[ -z "${SONAR_PROJECT_KEY}" ]]; then
    SONAR_PROJECT_KEY="codex-$(sanitize_slug "${scan_repo_name}")"
  fi
  if [[ -z "${SONAR_PROJECT_NAME}" ]]; then
    SONAR_PROJECT_NAME="${scan_repo_name}"
  fi
fi

if [[ -z "${SONAR_PROJECT_KEY}" && "${has_project_config}" -eq 0 ]]; then
  fail "unable to determine a Sonar project key"
fi

if [[ -n "${SONAR_EXCLUSIONS}" ]]; then
  scanner_exclusions+=("${SONAR_EXCLUSIONS}")
fi

if [[ "${has_project_config}" -eq 0 && "$(is_true "${include_default_exclusions}")" ]]; then
  scanner_exclusions+=("${DEFAULT_EXCLUSIONS[@]}")
fi

scanner_exclusion_arg=""
if [[ "${#scanner_exclusions[@]}" -gt 0 ]]; then
  scanner_exclusion_arg="$(join_by_comma "${scanner_exclusions[@]}")"
fi

dry_run_summary="would scan ${scan_repo_root} with ${SONAR_SCANNER_IMAGE} against ${SONAR_HOST_URL} (docker URL: ${SONAR_DOCKER_HOST_URL})"
if [[ -n "${SONAR_PROJECT_KEY}" ]]; then
  dry_run_summary="${dry_run_summary} as ${SONAR_PROJECT_KEY}"
fi

shell_cli_maybe_execute_or_preview_summary usage "${dry_run_summary}"

check_sonar_status
resolve_scan_token
trap cleanup EXIT INT TERM HUP

mkdir -p "${SONAR_SCAN_CACHE_DIR}"
mkdir -p "${SONAR_SCAN_CACHE_DIR}/.scannerwork"

docker_args=(
  run
  --rm
  -u "$(id -u):$(id -g)"
  -e "SONAR_USER_HOME=/tmp/sonar"
  -v "${SONAR_SCAN_CACHE_DIR}:/tmp/sonar"
  -v "${scan_repo_root}:/usr/src"
  -w /usr/src
  -e "SONAR_HOST_URL=${SONAR_DOCKER_HOST_URL}"
)

if [[ "$(uname -s)" == "Linux" ]]; then
  docker_args+=(--add-host=host.docker.internal:host-gateway)
fi

scanner_args=()

if [[ -n "${SONAR_PROJECT_KEY}" ]]; then
  scanner_args+=(-Dsonar.projectKey="${SONAR_PROJECT_KEY}")
fi

if [[ -n "${SONAR_PROJECT_NAME}" ]]; then
  scanner_args+=(-Dsonar.projectName="${SONAR_PROJECT_NAME}")
fi

if [[ "${has_project_config}" -eq 0 ]]; then
  scanner_args+=(-Dsonar.sources=.)
  scanner_args+=(-Dsonar.sourceEncoding=UTF-8)
fi

if [[ -n "${scanner_exclusion_arg}" ]]; then
  scanner_args+=(-Dsonar.exclusions="${scanner_exclusion_arg}")
fi

docker_args+=("${SONAR_SCANNER_IMAGE}")
scanner_args+=(-Dsonar.working.directory=/tmp/sonar/.scannerwork)
scanner_args+=(-Dsonar.host.url="${SONAR_DOCKER_HOST_URL}")
scanner_args+=(-Dsonar.token="${scan_token}")
docker_args+=("${scanner_args[@]}")

printf 'Running SonarQube scan for %s\n' "${scan_repo_root}"
docker "${docker_args[@]}"
