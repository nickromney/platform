#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SSO_DIR="${SSO_PLAYWRIGHT_PROJECT_DIR:-${REPO_ROOT}/tests/kubernetes/sso}"
BROWSERS_JSON="${SSO_DIR}/node_modules/playwright-core/browsers.json"
INSTALL_HINTS="${REPO_ROOT}/scripts/install-tool-hints.sh"

# PLATFORM_PLAYWRIGHT_CHANNEL=chrome tells the SSO Playwright config to use a
# system Chrome channel instead of the pinned Playwright Chromium build. That is
# useful as an operator fallback, but it trades deterministic browser revisions
# for whatever Chrome version is installed on the host.
PLATFORM_PLAYWRIGHT_CHANNEL="${PLATFORM_PLAYWRIGHT_CHANNEL:-}"
PLATFORM_PLAYWRIGHT_MODE="${PLATFORM_PLAYWRIGHT_MODE:-native}"
PLAYWRIGHT_BROWSER_INSTALL_TIMEOUT_SECONDS="${PLAYWRIGHT_BROWSER_INSTALL_TIMEOUT_SECONDS:-600}"
PLAYWRIGHT_BROWSER_INSTALL_RETRIES="${PLAYWRIGHT_BROWSER_INSTALL_RETRIES:-2}"
PLAYWRIGHT_SKIP_CDN_PREFLIGHT="${PLAYWRIGHT_SKIP_CDN_PREFLIGHT:-0}"
PLAYWRIGHT_ENSURE_CHECK_ONLY="${PLAYWRIGHT_ENSURE_CHECK_ONLY:-0}"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
  cat <<EOF
Usage: ${0##*/} [--check] [--dry-run] [--execute]

Ensures the Kubernetes SSO Playwright browser cache contains the pinned
chromium and chromium_headless_shell revisions before any E2E test starts.

Environment:
  PLATFORM_PLAYWRIGHT_MODE=native|docker       Browser execution mode, default native
  PLAYWRIGHT_BROWSER_INSTALL_TIMEOUT_SECONDS  Per-install timeout, default 600
  PLAYWRIGHT_BROWSER_INSTALL_RETRIES          Attempts after cleanup, default 2
  PLAYWRIGHT_ENSURE_CHECK_ONLY=1              Validate only; warn and exit 0
  PLAYWRIGHT_BROWSERS_PATH                    Override Playwright browser cache
  PLAYWRIGHT_SKIP_CDN_PREFLIGHT=1             Skip browser archive CDN probe
  PLATFORM_PLAYWRIGHT_CHANNEL=chrome          Use system Chrome, skip downloads

$(shell_cli_standard_options)
EOF
}

script_name="$(shell_cli_script_name)"
shell_cli_init_standard_flags
while [ "$#" -gt 0 ]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --check)
      PLAYWRIGHT_ENSURE_CHECK_ONLY=1
      shift
      ;;
    *)
      if [[ "$1" == -* ]]; then
        shell_cli_unknown_flag "${script_name}" "$1"
      else
        shell_cli_unexpected_arg "${script_name}" "$1"
      fi
      exit 1
      ;;
  esac
done

shell_cli_maybe_execute_or_preview_summary usage "would ensure pinned Playwright browser revisions are cached"

fail() {
  printf 'ensure-playwright-browsers.sh: %s\n' "$*" >&2
  exit 1
}

require_tool() {
  local tool="$1"

  if command -v "${tool}" >/dev/null 2>&1; then
    return 0
  fi

  printf '%s not found in PATH\n' "${tool}" >&2
  if [ -x "${INSTALL_HINTS}" ]; then
    printf 'Install hints:\n' >&2
    "${INSTALL_HINTS}" --execute --plain "${tool}" | sed 's/^/  /' >&2
  fi
  exit 1
}

require_positive_integer() {
  local name="$1"
  local value="$2"

  case "${value}" in
    ''|*[!0-9]*) fail "${name} must be a positive integer, got: ${value}" ;;
  esac
  [ "${value}" -gt 0 ] || fail "${name} must be greater than 0"
}

playwright_cache_dir() {
  if [ -n "${PLAYWRIGHT_BROWSERS_PATH:-}" ]; then
    printf '%s\n' "${PLAYWRIGHT_BROWSERS_PATH}"
    return 0
  fi

  case "$(uname -s)" in
    Darwin) printf '%s\n' "${HOME}/Library/Caches/ms-playwright" ;;
    *) printf '%s\n' "${HOME}/.cache/ms-playwright" ;;
  esac
}

ensure_sso_dependencies() {
  if [ -f "${BROWSERS_JSON}" ]; then
    return 0
  fi

  printf 'INFO installing SSO E2E dependencies so Playwright browsers.json is available\n'
  (cd "${SSO_DIR}" && bun install --frozen-lockfile)
}

required_browsers() {
  # shellcheck disable=SC2016
  node -e '
const fs = require("fs");
const path = process.argv[1];
const data = JSON.parse(fs.readFileSync(path, "utf8"));
const wanted = new Set(["chromium", "chromium-headless-shell"]);
for (const browser of data.browsers || []) {
  if (!wanted.has(browser.name)) continue;
  const directory = `${browser.name.replace(/-/g, "_")}-${browser.revision}`;
  console.log(`${browser.name}\t${browser.revision}\t${directory}`);
}
' "${BROWSERS_JSON}"
}

cleanup_incomplete_required_dirs() {
  local cache_dir="$1"
  local cleaned=0
  local name=""
  local revision=""
  local directory=""
  local browser_dir=""

  while IFS=$'\t' read -r name revision directory; do
    [ -n "${name}" ] || continue
    browser_dir="${cache_dir}/${directory}"
    if [ -d "${browser_dir}" ] && [ ! -f "${browser_dir}/INSTALLATION_COMPLETE" ]; then
      printf 'WARN removing incomplete Playwright browser cache directory: %s\n' "${browser_dir}" >&2
      rm -rf "${browser_dir}"
      cleaned=1
    fi
  done < <(required_browsers)

  if [ "${cleaned}" -eq 1 ] && [ -e "${cache_dir}/__dirlock" ]; then
    printf 'WARN removing stale Playwright browser cache lock: %s\n' "${cache_dir}/__dirlock" >&2
    rm -rf "${cache_dir}/__dirlock"
  fi
}

remove_playwright_lock() {
  local cache_dir="$1"

  if [ -e "${cache_dir}/__dirlock" ]; then
    printf 'WARN removing stale Playwright browser cache lock: %s\n' "${cache_dir}/__dirlock" >&2
    rm -rf "${cache_dir}/__dirlock"
  fi
}

chromium_revision() {
  local name=""
  local revision=""
  local directory=""

  while IFS=$'\t' read -r name revision directory; do
    if [ "${name}" = "chromium" ]; then
      printf '%s\n' "${revision}"
      return 0
    fi
  done < <(required_browsers)

  return 1
}

playwright_archive_platform_suffix() {
  local os_name=""
  local machine=""

  os_name="$(uname -s)"
  machine="$(uname -m)"

  case "${os_name}:${machine}" in
    Darwin:arm64|Darwin:aarch64) printf 'mac-arm64\n' ;;
    Darwin:*) printf 'mac\n' ;;
    Linux:arm64|Linux:aarch64) printf 'linux-arm64\n' ;;
    Linux:*) printf 'linux\n' ;;
    *) fail "unsupported platform for Playwright CDN preflight: ${os_name}/${machine}" ;;
  esac
}

playwright_chromium_archive_url() {
  local revision="$1"
  local suffix=""

  suffix="$(playwright_archive_platform_suffix)"
  printf 'https://cdn.playwright.dev/dbazure/download/playwright/builds/chromium/%s/chromium-%s.zip\n' "${revision}" "${suffix}"
}

preflight_playwright_cdn() {
  local revision="$1"
  local url=""
  local status=""

  if [ "${PLAYWRIGHT_SKIP_CDN_PREFLIGHT}" = "1" ]; then
    printf 'INFO skipping Playwright CDN preflight because PLAYWRIGHT_SKIP_CDN_PREFLIGHT=1\n'
    return 0
  fi

  require_tool curl
  url="$(playwright_chromium_archive_url "${revision}")"
  printf 'INFO checking Playwright browser archive CDN: %s\n' "${url}"
  status="$(curl -sIL --max-time 10 -o /dev/null -w '%{http_code}' "${url}" 2>/dev/null || true)"
  if [ "${status}" = "200" ]; then
    return 0
  fi

  [ -n "${status}" ] || status="curl-failed"
  printf 'ERROR Playwright CDN preflight failed for %s with final HTTP status %s.\n' "${url}" "${status}" >&2
  printf 'ERROR This network cannot fetch Playwright browsers from the required CDN chain.\n' >&2
  printf 'ERROR Remediation: set PLATFORM_PLAYWRIGHT_MODE=docker to run tests in the matching Playwright container image.\n' >&2
  printf 'ERROR Remediation: set PLATFORM_PLAYWRIGHT_CHANNEL=chrome to use system Chrome instead of downloading Playwright Chromium.\n' >&2
  printf 'ERROR Remediation: change networks and rerun this script.\n' >&2
  return 1
}

validate_required_browsers() {
  local cache_dir="$1"
  local missing=0
  local seen=0
  local name=""
  local revision=""
  local directory=""
  local browser_dir=""

  while IFS=$'\t' read -r name revision directory; do
    [ -n "${name}" ] || continue
    seen=$((seen + 1))
    browser_dir="${cache_dir}/${directory}"
    if [ ! -d "${browser_dir}" ]; then
      printf 'MISSING Playwright browser %s revision %s: %s does not exist\n' "${name}" "${revision}" "${browser_dir}" >&2
      missing=1
      continue
    fi
    if [ ! -f "${browser_dir}/INSTALLATION_COMPLETE" ]; then
      printf 'MISSING Playwright browser %s revision %s: %s/INSTALLATION_COMPLETE does not exist\n' "${name}" "${revision}" "${browser_dir}" >&2
      missing=1
    fi
  done < <(required_browsers)

  [ "${seen}" -eq 2 ] || fail "browsers.json did not contain both chromium and chromium-headless-shell: ${BROWSERS_JSON}"
  [ "${missing}" -eq 0 ]
}

kill_process_group() {
  local pid="$1"

  kill -TERM "-${pid}" 2>/dev/null || true
  sleep 2
  kill -KILL "-${pid}" 2>/dev/null || true
}

run_install_with_timeout() {
  local timeout_seconds="$1"
  local pid=""
  local start_seconds=""
  local now_seconds=""
  local status=0

  printf 'INFO running bun x playwright install chromium with %ss timeout\n' "${timeout_seconds}"
  (
    cd "${SSO_DIR}" && exec perl -MPOSIX=setsid -e 'setsid() or die "setsid: $!"; exec @ARGV or die "exec: $!"' \
      bun x playwright install chromium
  ) &
  pid="$!"
  start_seconds="$(date +%s)"

  while kill -0 "${pid}" 2>/dev/null; do
    now_seconds="$(date +%s)"
    if [ "$((now_seconds - start_seconds))" -ge "${timeout_seconds}" ]; then
      printf 'ERROR Playwright browser install timed out after %ss; killing process group %s\n' "${timeout_seconds}" "${pid}" >&2
      kill_process_group "${pid}"
      wait "${pid}" 2>/dev/null || true
      return 124
    fi
    sleep 1
  done

  wait "${pid}" || status=$?
  return "${status}"
}

install_and_validate() {
  local cache_dir="$1"
  local max_attempts="$2"
  local timeout_seconds="$3"
  local attempt=1
  local status=0

  while [ "${attempt}" -le "${max_attempts}" ]; do
    cleanup_incomplete_required_dirs "${cache_dir}"
    if run_install_with_timeout "${timeout_seconds}"; then
      if validate_required_browsers "${cache_dir}"; then
        printf 'INFO Playwright browser cache is complete at %s\n' "${cache_dir}"
        return 0
      fi
      status=1
    else
      status=$?
    fi

    cleanup_incomplete_required_dirs "${cache_dir}"
    remove_playwright_lock "${cache_dir}"
    if [ "${attempt}" -lt "${max_attempts}" ]; then
      printf 'WARN Playwright browser install attempt %s/%s failed; retrying after cleanup\n' "${attempt}" "${max_attempts}" >&2
    fi
    attempt=$((attempt + 1))
  done

  printf 'ERROR Playwright browser provisioning failed after %s attempt(s).\n' "${max_attempts}" >&2
  printf 'ERROR Required pinned chromium revisions are still missing or incomplete in %s.\n' "${cache_dir}" >&2
  printf 'ERROR Remediation: remove the incomplete ms-playwright cache directory or rerun this script before check-sso-e2e.\n' >&2
  return "${status}"
}

check_only() {
  local cache_dir=""
  local validation_output=""

  case "${PLATFORM_PLAYWRIGHT_MODE}" in
    native) ;;
    docker)
      printf 'OK   Playwright browser cache check skipped because PLATFORM_PLAYWRIGHT_MODE=docker uses the matching container image\n'
      return 0
      ;;
    *) fail "PLATFORM_PLAYWRIGHT_MODE must be native or docker, got: ${PLATFORM_PLAYWRIGHT_MODE}" ;;
  esac

  if [ -n "${PLATFORM_PLAYWRIGHT_CHANNEL}" ]; then
    if [ "${PLATFORM_PLAYWRIGHT_CHANNEL}" != "chrome" ]; then
      fail "PLATFORM_PLAYWRIGHT_CHANNEL only supports chrome, got: ${PLATFORM_PLAYWRIGHT_CHANNEL}"
    fi
    printf 'OK   Playwright browser cache check skipped because PLATFORM_PLAYWRIGHT_CHANNEL=chrome uses system Chrome\n'
    return 0
  fi

  if [ ! -f "${BROWSERS_JSON}" ]; then
    printf 'WARN Playwright browser cache check skipped because %s is absent; run make playwright-install before native check-sso-e2e, or use PLATFORM_PLAYWRIGHT_MODE=docker / PLATFORM_PLAYWRIGHT_CHANNEL=chrome\n' "${BROWSERS_JSON}"
    return 0
  fi

  require_tool node
  cache_dir="$(playwright_cache_dir)"
  validation_output="$(mktemp "${TMPDIR:-/tmp}/platform-playwright-browser-validation.XXXXXX")"
  if validate_required_browsers "${cache_dir}" 2>"${validation_output}"; then
    rm -f "${validation_output}"
    printf 'OK   Playwright browser cache is complete at %s\n' "${cache_dir}"
    return 0
  fi
  cat "${validation_output}" >&2
  rm -f "${validation_output}"
  printf 'WARN Playwright browsers are absent or incomplete; run make playwright-install before native check-sso-e2e, or use PLATFORM_PLAYWRIGHT_MODE=docker / PLATFORM_PLAYWRIGHT_CHANNEL=chrome\n'
  return 0
}

if [ "${PLAYWRIGHT_ENSURE_CHECK_ONLY}" = "1" ]; then
  check_only
  exit 0
fi

case "${PLATFORM_PLAYWRIGHT_MODE}" in
  native) ;;
  docker)
    printf 'INFO PLATFORM_PLAYWRIGHT_MODE=docker set; skipping host Playwright browser provisioning\n'
    exit 0
    ;;
  *) fail "PLATFORM_PLAYWRIGHT_MODE must be native or docker, got: ${PLATFORM_PLAYWRIGHT_MODE}" ;;
esac

if [ -n "${PLATFORM_PLAYWRIGHT_CHANNEL}" ]; then
  if [ "${PLATFORM_PLAYWRIGHT_CHANNEL}" != "chrome" ]; then
    fail "PLATFORM_PLAYWRIGHT_CHANNEL only supports chrome, got: ${PLATFORM_PLAYWRIGHT_CHANNEL}"
  fi
  printf 'INFO PLATFORM_PLAYWRIGHT_CHANNEL=chrome set; skipping pinned Playwright browser provisioning\n'
  exit 0
fi

require_positive_integer "PLAYWRIGHT_BROWSER_INSTALL_TIMEOUT_SECONDS" "${PLAYWRIGHT_BROWSER_INSTALL_TIMEOUT_SECONDS}"
require_positive_integer "PLAYWRIGHT_BROWSER_INSTALL_RETRIES" "${PLAYWRIGHT_BROWSER_INSTALL_RETRIES}"
require_tool node
require_tool bun
require_tool perl

ensure_sso_dependencies
[ -f "${BROWSERS_JSON}" ] || fail "Playwright browsers.json not found after dependency install: ${BROWSERS_JSON}"

cache_dir="$(playwright_cache_dir)"
mkdir -p "${cache_dir}"
cleanup_incomplete_required_dirs "${cache_dir}"

validation_output="$(mktemp "${TMPDIR:-/tmp}/platform-playwright-browser-validation.XXXXXX")"
if validate_required_browsers "${cache_dir}" 2>"${validation_output}"; then
  rm -f "${validation_output}"
  printf 'INFO Playwright browser cache is complete at %s\n' "${cache_dir}"
  exit 0
fi
cat "${validation_output}" >&2
rm -f "${validation_output}"

preflight_playwright_cdn "$(chromium_revision)"
install_and_validate "${cache_dir}" "${PLAYWRIGHT_BROWSER_INSTALL_RETRIES}" "${PLAYWRIGHT_BROWSER_INSTALL_TIMEOUT_SECONDS}"
