#!/usr/bin/env bash
# shellcheck disable=SC2329
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

MODE="report"
APPLY=0
ONLY="tools,devcontainer,charts,packages,providers,images"

TOOLCHAIN_VERSIONS_FILE="${TOOLCHAIN_VERSIONS_FILE:-${REPO_ROOT}/.devcontainer/toolchain-versions.sh}"
TOOLCHAIN_SOURCES_FILE="${TOOLCHAIN_SOURCES_FILE:-${REPO_ROOT}/.devcontainer/toolchain-sources.tsv}"
DEVCONTAINER_DOCKERFILE="${DEVCONTAINER_DOCKERFILE:-${REPO_ROOT}/.devcontainer/Dockerfile}"
DEVCONTAINER_CONFIG="${DEVCONTAINER_CONFIG:-${REPO_ROOT}/.devcontainer/devcontainer.json}"
UPDATE_VERSIONS_GITHUB_API_BASE="${UPDATE_VERSIONS_GITHUB_API_BASE:-https://api.github.com}"
UPDATE_VERSIONS_MCR_API_BASE="${UPDATE_VERSIONS_MCR_API_BASE:-https://mcr.microsoft.com}"
UPDATE_VERSIONS_MIN_RELEASE_AGE_SECONDS="${UPDATE_VERSIONS_MIN_RELEASE_AGE_SECONDS:-604800}"
UPDATE_VERSIONS_ALLOW_UNKNOWN_COOLDOWN="${UPDATE_VERSIONS_ALLOW_UNKNOWN_COOLDOWN:-0}"

COMPONENT_REPORT_FILE=""
PROVIDER_REPORT_FILE=""
ERRORS=0

usage() {
  cat <<EOF
$(shell_cli_usage_line " [--dry-run] [--execute] [--apply] [--only tools,devcontainer,charts,packages,providers,images]")

Reports and optionally applies eligible dependency updates across the platform
version domains.

Options:
  --apply      With --execute, apply eligible updates per domain, then rerun
               the existing version audits.
  --only LIST  Comma-separated domain filter. Domains: tools, devcontainer,
               charts, packages, providers, images.

Environment:
  GITHUB_TOKEN / GH_TOKEN  Optional GitHub API token for release lookups;
                           falls back to 'gh auth token', then anonymous
                           requests (60/hour rate limit).

$(shell_cli_standard_options)
EOF
}

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --apply)
      APPLY=1
      shift
      ;;
    --only)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--only"
        exit 1
      }
      ONLY="$2"
      shift 2
      ;;
    --)
      shift
      break
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

if [[ $# -gt 0 ]]; then
  shell_cli_unexpected_arg "$(shell_cli_script_name)" "$1"
  exit 1
fi

if [[ "${SHELL_CLI_DRY_RUN}" -eq 1 ]]; then
  usage
  shell_cli_print_dry_run_summary "would report available version updates across domains (${ONLY})"
  exit 0
fi

shell_cli_maybe_execute_or_preview_summary usage \
  "would report available version updates across domains (${ONLY})"

if [[ "${APPLY}" -eq 1 ]]; then
  MODE="apply"
fi

contains_domain() {
  local needle="$1"
  case ",${ONLY}," in
    *",${needle},"*) return 0 ;;
    *) return 1 ;;
  esac
}

validate_domains() {
  local item rest="${ONLY}"
  while [[ -n "${rest}" ]]; do
    item="${rest%%,*}"
    if [[ "${rest}" == "${item}" ]]; then
      rest=""
    else
      rest="${rest#*,}"
    fi
    case "${item}" in
      tools|devcontainer|charts|packages|providers|images) ;;
      *)
        printf 'update-versions.sh: unknown domain in --only: %s\n' "${item}" >&2
        exit 1
        ;;
    esac
  done
}

require() {
  local bin="$1"
  command -v "${bin}" >/dev/null 2>&1 || {
    printf '%s not found in PATH\n' "${bin}" >&2
    return 1
  }
}

run_shell_command() {
  local command_text="$1"
  /bin/bash -lc "${command_text}"
}

component_report_cmd() {
  if [[ -n "${UPDATE_VERSIONS_COMPONENT_REPORT_CMD:-}" ]]; then
    printf '%s\n' "${UPDATE_VERSIONS_COMPONENT_REPORT_CMD}"
    return 0
  fi

  printf '%s\n' \
    "CHECK_VERSION_FORMAT=json CHECK_VERSION_CI_MODE=1 '${REPO_ROOT}/terraform/kubernetes/scripts/check-component-version.sh' --execute --ci"
}

provider_report_cmd() {
  if [[ -n "${UPDATE_VERSIONS_PROVIDER_REPORT_CMD:-}" ]]; then
    printf '%s\n' "${UPDATE_VERSIONS_PROVIDER_REPORT_CMD}"
    return 0
  fi

  printf '%s\n' \
    "CHECK_VERSION_FORMAT=json '${REPO_ROOT}/terraform/kubernetes/scripts/check-provider-version.sh' --execute"
}

ensure_component_report() {
  if [[ -n "${COMPONENT_REPORT_FILE}" ]]; then
    return 0
  fi

  COMPONENT_REPORT_FILE="$(mktemp "${TMPDIR:-/tmp}/update-versions-components.XXXXXX")"
  if ! run_shell_command "$(component_report_cmd)" >"${COMPONENT_REPORT_FILE}"; then
    printf 'ERROR components: failed to collect check-component-version JSON report\n' >&2
    return 1
  fi
}

ensure_provider_report() {
  if [[ -n "${PROVIDER_REPORT_FILE}" ]]; then
    return 0
  fi

  PROVIDER_REPORT_FILE="$(mktemp "${TMPDIR:-/tmp}/update-versions-providers.XXXXXX")"
  if ! run_shell_command "$(provider_report_cmd)" >"${PROVIDER_REPORT_FILE}"; then
    printf 'ERROR providers: failed to collect check-provider-version JSON report\n' >&2
    return 1
  fi
}

print_section() {
  printf '\n== %s ==\n' "$1"
}

GITHUB_API_TOKEN_RESOLVED=0
GITHUB_API_TOKEN_VALUE=""

github_api_token() {
  if [[ "${GITHUB_API_TOKEN_RESOLVED}" -eq 0 ]]; then
    GITHUB_API_TOKEN_VALUE="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
    if [[ -z "${GITHUB_API_TOKEN_VALUE}" ]] && command -v gh >/dev/null 2>&1; then
      GITHUB_API_TOKEN_VALUE="$(gh auth token 2>/dev/null || true)"
    fi
    GITHUB_API_TOKEN_RESOLVED=1
  fi
  printf '%s' "${GITHUB_API_TOKEN_VALUE}"
}

http_get() {
  local url="$1"
  local token
  local -a auth_args=()
  # Only ever send the GitHub token to the GitHub API host, not MCR or
  # other registries this function may be pointed at.
  if [[ "${url}" == "${UPDATE_VERSIONS_GITHUB_API_BASE%/}"/* ]]; then
    token="$(github_api_token)"
    if [[ -n "${token}" ]]; then
      auth_args=(-H "Authorization: Bearer ${token}")
    fi
  fi
  curl -fsSL \
    -H "Accept: application/vnd.github+json" \
    -H "User-Agent: platform-check-version" \
    ${auth_args[@]+"${auth_args[@]}"} \
    "${url}" </dev/null
}

epoch_from_iso() {
  local value="$1"
  value="${value%%.*}Z"
  date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "${value}" '+%s' 2>/dev/null ||
    date -u -d "${value}" '+%s' 2>/dev/null ||
    return 1
}

date_from_epoch() {
  local epoch="$1"
  date -u -r "${epoch}" '+%Y-%m-%d' 2>/dev/null ||
    date -u -d "@${epoch}" '+%Y-%m-%d' 2>/dev/null ||
    return 1
}

github_latest_release() {
  local repo="$1"
  http_get "${UPDATE_VERSIONS_GITHUB_API_BASE%/}/repos/${repo}/releases/latest" |
    jq -r '[.tag_name // "", .published_at // ""] | @tsv'
}

status_for_latest() {
  local current="$1"
  local latest="$2"
  local published_at="$3"
  local published_epoch eligible_epoch eligible_date now_epoch

  if [[ -z "${latest}" ]]; then
    printf 'unknown\t\n'
    return 0
  fi

  if [[ "${current}" == "${latest}" ]]; then
    printf 'current\t\n'
    return 0
  fi

  if [[ -z "${published_at}" ]]; then
    printf 'cooldown_unknown\tunknown\n'
    return 0
  fi

  published_epoch="$(epoch_from_iso "${published_at}" 2>/dev/null || true)"
  if [[ -z "${published_epoch}" ]]; then
    printf 'cooldown_unknown\tunknown\n'
    return 0
  fi

  eligible_epoch="$((published_epoch + UPDATE_VERSIONS_MIN_RELEASE_AGE_SECONDS))"
  eligible_date="$(date_from_epoch "${eligible_epoch}" 2>/dev/null || printf 'unknown')"
  now_epoch="$(date -u '+%s')"

  if [[ "${eligible_epoch}" -gt "${now_epoch}" ]]; then
    printf 'cooldown_active\t%s\n' "${eligible_date}"
  else
    printf 'update_available\t%s\n' "${eligible_date}"
  fi
}

tool_current_pin() {
  local pin="$1"
  local tool_name

  case "${pin}" in
    ARKADE:*)
      tool_name="${pin#ARKADE:}"
      awk -v tool="${tool_name}" '
        $0 ~ "^[[:space:]]+\"" tool "=" {
          value=$0
          gsub(/^[[:space:]]*"|"$/, "", value)
          sub(/^[^=]+=/, "", value)
          print value
          exit
        }
      ' "${TOOLCHAIN_VERSIONS_FILE}"
      ;;
    *)
      sed -nE "s/^${pin}=\"\\\$\\{${pin}:-([^\"]+)\\}\".*/\\1/p" "${TOOLCHAIN_VERSIONS_FILE}" | head -n 1
      ;;
  esac
}

tool_resolved_row() {
  local tool="$1"
  local source="$2"
  local pin="$3"
  local current latest published_at status eligible_date repo release_row

  current="$(tool_current_pin "${pin}")"
  if [[ -z "${current}" ]]; then
    printf '%s\t%s\t%s\t%s\t%s\n' "${tool}" "unknown" "" "pin_not_found" ""
    return 0
  fi

  case "${source}" in
    github:*)
      repo="${source#github:}"
      release_row="$(github_latest_release "${repo}" 2>/dev/null || true)"
      IFS=$'\t' read -r latest published_at <<< "${release_row}"
      IFS=$'\t' read -r status eligible_date <<< "$(status_for_latest "${current}" "${latest}" "${published_at}")"
      printf '%s\t%s\t%s\t%s\t%s\n' "${tool}" "${current}" "${latest}" "${status}" "${eligible_date}"
      ;;
    audit-only)
      printf '%s\t%s\t%s\t%s\t%s\n' "${tool}" "${current}" "" "audit-only" ""
      ;;
    *)
      printf '%s\t%s\t%s\t%s\t%s\n' "${tool}" "${current}" "" "unknown_source" ""
      ;;
  esac
}

tool_rows() {
  if [[ -n "${UPDATE_VERSIONS_TOOL_REPORT_TSV:-}" ]]; then
    printf '%s\n' "${UPDATE_VERSIONS_TOOL_REPORT_TSV}"
    return 0
  fi

  require curl || return 1
  require jq || return 1
  require awk || return 1

  while IFS=$'\t' read -r tool source pin; do
    [[ -n "${tool}" && "${tool}" != \#* ]] || continue
    tool_resolved_row "${tool}" "${source}" "${pin}"
  done < "${TOOLCHAIN_SOURCES_FILE}"
}

update_toolchain_pin() {
  local pin="$1"
  local latest="$2"
  local tool_name

  case "${pin}" in
    ARKADE:*)
      tool_name="${pin#ARKADE:}"
      TOOL_NAME="${tool_name}" LATEST_VERSION="${latest}" perl -0pi -e \
        's/^(\s*"\Q$ENV{TOOL_NAME}\E=)[^"]+(")/$1$ENV{LATEST_VERSION}$2/m' \
        "${TOOLCHAIN_VERSIONS_FILE}"
      ;;
    *)
      PIN_NAME="${pin}" LATEST_VERSION="${latest}" perl -0pi -e \
        's/^(\Q$ENV{PIN_NAME}\E="\$\{\Q$ENV{PIN_NAME}\E:-)[^"]+(\}")/$1$ENV{LATEST_VERSION}$2/m' \
        "${TOOLCHAIN_VERSIONS_FILE}"
      ;;
  esac
}

apply_tools() {
  local tool source pin current latest status eligible_date applied=0 skipped=0

  while IFS=$'\t' read -r tool source pin; do
    [[ -n "${tool}" && "${tool}" != \#* ]] || continue
    current="$(tool_current_pin "${pin}")"
    [[ -n "${current}" ]] || continue
    IFS=$'\t' read -r _ _ latest status eligible_date <<< "$(tool_resolved_row "${tool}" "${source}" "${pin}")"
    case "${status}" in
      update_available)
        update_toolchain_pin "${pin}" "${latest}"
        printf 'Updated tools: %s %s -> %s\n' "${tool}" "${current}" "${latest}"
        applied=$((applied + 1))
        ;;
      cooldown_unknown)
        if [[ "${UPDATE_VERSIONS_ALLOW_UNKNOWN_COOLDOWN}" == "1" ]]; then
          update_toolchain_pin "${pin}" "${latest}"
          printf 'Updated tools: %s %s -> %s (cooldown unknown allowed)\n' "${tool}" "${current}" "${latest}"
          applied=$((applied + 1))
        else
          printf 'Skipped tools: %s latest %s has unknown cooldown; set UPDATE_VERSIONS_ALLOW_UNKNOWN_COOLDOWN=1 to apply\n' "${tool}" "${latest:-unknown}"
          skipped=$((skipped + 1))
        fi
        ;;
      cooldown_active)
        printf 'Skipped tools: %s latest %s is blocked by cooldown until %s\n' "${tool}" "${latest:-unknown}" "${eligible_date:-unknown}"
        skipped=$((skipped + 1))
        ;;
    esac
  done < "${TOOLCHAIN_SOURCES_FILE}"

  if [[ "${applied}" -eq 0 ]]; then
    printf 'No eligible toolchain pin updates applied.\n'
  fi
  if [[ "${skipped}" -gt 0 ]]; then
    printf 'Skipped %s toolchain update(s) because of cooldown policy.\n' "${skipped}"
  fi
}

report_tools() {
  print_section "tools"
  printf 'source: .devcontainer/toolchain-versions.sh; sources: .devcontainer/toolchain-sources.tsv\n'
  tool_rows | render_update_rows
  if [[ "${MODE}" == "apply" ]]; then
    if [[ -n "${UPDATE_VERSIONS_TOOLS_APPLY_CMD:-}" ]]; then
      run_applier "tools" "${UPDATE_VERSIONS_TOOLS_APPLY_CMD}"
    else
      apply_tools
    fi
  else
    printf 'Apply action: update eligible pins in .devcontainer/toolchain-versions.sh.\n'
  fi
}

parse_devcontainer_base_image() {
  sed -nE 's/^FROM[[:space:]]+([^[:space:]]+).*/\1/p' "${DEVCONTAINER_DOCKERFILE}" | head -n 1
}

latest_mcr_devcontainer_base_tag() {
  local current_tag="$1"
  local family_prefix="${current_tag%%[0-9]*}"

  http_get "${UPDATE_VERSIONS_MCR_API_BASE%/}/v2/devcontainers/base/tags/list" |
    jq -r --arg prefix "${family_prefix}" '
      .tags
      | map(select(startswith($prefix)))
      | map((capture("^(?<prefix>.*?)(?<major>[0-9]+)\\.(?<minor>[0-9]+)$")?) as $m | select($m != null) | {tag: ., major: ($m.major | tonumber), minor: ($m.minor | tonumber)})
      | sort_by(.major, .minor)
      | last.tag // ""
    '
}

devcontainer_digest_rows() {
  if [[ ! -f "${DEVCONTAINER_CONFIG}" ]]; then
    return 0
  fi

  jq -r '
    (.features // {})
    | keys[]
    | select(contains("@sha256:"))
    | [., "pinned digest", "", "audit-only", ""] | @tsv
  ' "${DEVCONTAINER_CONFIG}" 2>/dev/null || true
}

devcontainer_rows() {
  if [[ -n "${UPDATE_VERSIONS_DEVCONTAINER_REPORT_TSV:-}" ]]; then
    printf '%s\n' "${UPDATE_VERSIONS_DEVCONTAINER_REPORT_TSV}"
    return 0
  fi

  require curl || return 1
  require jq || return 1

  local image repo tag latest status
  image="$(parse_devcontainer_base_image)"
  repo="${image%:*}"
  tag="${image##*:}"
  latest="$(latest_mcr_devcontainer_base_tag "${tag}" 2>/dev/null || true)"

  if [[ -z "${image}" ]]; then
    printf 'devcontainer base\tunknown\t\tpin_not_found\t\n'
  elif [[ -z "${latest}" ]]; then
    printf 'devcontainer base\t%s\t\tunknown\t\n' "${image}"
  elif [[ "${tag}" == "${latest}" ]]; then
    printf 'devcontainer base\t%s\t%s:%s\tcurrent\t\n' "${image}" "${repo}" "${latest}"
  else
    printf 'devcontainer base\t%s\t%s:%s\tupdate_available\t\n' "${image}" "${repo}" "${latest}"
  fi

  devcontainer_digest_rows
}

apply_devcontainer() {
  local image repo tag latest
  image="$(parse_devcontainer_base_image)"
  repo="${image%:*}"
  tag="${image##*:}"
  latest="$(latest_mcr_devcontainer_base_tag "${tag}" 2>/dev/null || true)"

  if [[ -z "${image}" || -z "${latest}" || "${tag}" == "${latest}" ]]; then
    printf 'No eligible devcontainer base image update applied.\n'
    return 0
  fi

  CURRENT_IMAGE="${image}" LATEST_IMAGE="${repo}:${latest}" perl -0pi -e \
    's/^FROM\s+\Q$ENV{CURRENT_IMAGE}\E(\s*)$/FROM $ENV{LATEST_IMAGE}$1/m' \
    "${DEVCONTAINER_DOCKERFILE}"
  printf 'Updated devcontainer base image: %s -> %s:%s\n' "${image}" "${repo}" "${latest}"
}

report_devcontainer() {
  print_section "devcontainer"
  printf 'source: .devcontainer/Dockerfile FROM and devcontainer.json digest pins\n'
  devcontainer_rows | render_update_rows
  if [[ "${MODE}" == "apply" ]]; then
    if [[ -n "${UPDATE_VERSIONS_DEVCONTAINER_APPLY_CMD:-}" ]]; then
      run_applier "devcontainer" "${UPDATE_VERSIONS_DEVCONTAINER_APPLY_CMD}"
    else
      apply_devcontainer
    fi
  else
    printf 'Apply action: update the .devcontainer/Dockerfile base image tag when MCR reports a newer same-family tag.\n'
  fi
}

report_charts() {
  print_section "charts"
  printf 'source: terraform/kubernetes/scripts/check-component-version.sh JSON components\n'
  ensure_component_report || return 1
  jq -r '
    .components[]
    | select((.component | test("chart|otel-collector|policy-reporter|cert-manager|oauth2-proxy|victoria-logs")) or (.update_available == true))
    | [.component, .codebase, .latest, .status_code, ""] | @tsv
  ' "${COMPONENT_REPORT_FILE}" | render_update_rows
  if [[ "${MODE}" == "apply" ]]; then
    run_applier "charts" "${UPDATE_VERSIONS_CHARTS_APPLY_CMD:-}"
  else
    printf 'Apply action: update eligible Terraform chart pins, then refresh vendored charts through terraform/kubernetes/scripts/sync-gitea-policies.sh.\n'
  fi
}

package_cooldown_eligible_date() {
  local app="$1"
  local dep="$2"
  local version="$3"
  local helper="${REPO_ROOT}/terraform/kubernetes/scripts/check-component-version.sh"

  [[ -n "${version}" ]] || return 0
  # shellcheck source=terraform/kubernetes/scripts/check-component-version.sh disable=SC1091
  CHECK_VERSION_LIB_ONLY=1 REPO_ROOT="${REPO_ROOT}" source "${helper}" >/dev/null 2>&1 || return 0
  local cooldown published
  cooldown="$(js_dependency_cooldown_seconds "${REPO_ROOT}/${app}" 2>/dev/null || true)"
  [[ "${cooldown}" =~ ^[0-9]+$ ]] || return 0
  published="$(
    npm_registry_payload "${dep}" 2>/dev/null | jq -r --arg version "${version}" '.time[$version] // empty' 2>/dev/null || true
  )"
  [[ -n "${published}" ]] || return 0
  date -u -r "$(( $(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "${published%.*Z}Z" '+%s' 2>/dev/null || printf 0) + cooldown ))" '+%Y-%m-%d' 2>/dev/null || true
}

report_packages() {
  print_section "packages"
  printf 'source: terraform/kubernetes/scripts/check-component-version.sh JSON app_dependencies; cooldown from js_dependency_cooldown_seconds\n'
  if [[ -n "${UPDATE_VERSIONS_PACKAGE_REPORT_TSV:-}" ]]; then
    printf '%s\n' "${UPDATE_VERSIONS_PACKAGE_REPORT_TSV}" | render_update_rows
  else
    ensure_component_report || return 1
    jq -r '
      .app_dependencies[]
      | [.app + ":" + .dependency, .current, .latest_eligible, .status_code, (.eligible_date // "")] | @tsv
    ' "${COMPONENT_REPORT_FILE}" | while IFS=$'\t' read -r name current latest status eligible_date; do
      if [[ "${status}" == "cooldown_active" && -z "${eligible_date}" ]]; then
        app="${name%%:*}"
        dep="${name#*:}"
        eligible_date="$(package_cooldown_eligible_date "${app}" "${dep}" "${latest}")"
      fi
      printf '%s\t%s\t%s\t%s\t%s\n' "${name}" "${current}" "${latest}" "${status}" "${eligible_date}"
    done | render_update_rows
  fi
  if [[ "${MODE}" == "apply" ]]; then
    local default_packages_apply_cmd
    default_packages_apply_cmd="make -C '${REPO_ROOT}/apps' update"
    run_applier "packages" "${UPDATE_VERSIONS_PACKAGES_APPLY_CMD:-${default_packages_apply_cmd}}"
  else
    printf 'Apply action: run native Bun/npm update flows for eligible package roots.\n'
  fi
}

report_providers() {
  print_section "providers"
  printf 'source: terraform/kubernetes/scripts/check-provider-version.sh JSON providers\n'
  ensure_provider_report || return 1
  jq -r '.providers[] | [.provider, .locked, .latest, (.status | gsub(" "; "_")), ""] | @tsv' "${PROVIDER_REPORT_FILE}" | render_update_rows
  if [[ "${MODE}" == "apply" ]]; then
    local default_providers_apply_cmd
    default_providers_apply_cmd="tofu -chdir='${REPO_ROOT}/terraform/kubernetes' init -upgrade"
    run_applier "providers" "${UPDATE_VERSIONS_PROVIDERS_APPLY_CMD:-${default_providers_apply_cmd}}"
  else
    printf 'Apply action: run OpenTofu provider upgrade for eligible locked providers.\n'
  fi
}

report_images() {
  print_section "images"
  printf 'source: terraform/kubernetes/scripts/preload-images.sh --refresh-lock\n'
  if [[ -n "${UPDATE_VERSIONS_IMAGE_REPORT_TSV:-}" ]]; then
    printf '%s\n' "${UPDATE_VERSIONS_IMAGE_REPORT_TSV}" | render_update_rows
  else
    printf 'Image digest locks\tcurrent lock files\tregistry digests\tmanaged_by_preload_images\t\n' | render_update_rows
  fi
  if [[ "${MODE}" == "apply" ]]; then
    local default_images_apply_cmd
    default_images_apply_cmd="'${REPO_ROOT}/terraform/kubernetes/scripts/preload-images.sh' --execute --pull-only --refresh-lock"
    run_applier "images" "${UPDATE_VERSIONS_IMAGES_APPLY_CMD:-${default_images_apply_cmd}}"
  else
    printf 'Apply action: refresh digest lock files via terraform/kubernetes/scripts/preload-images.sh --refresh-lock.\n'
  fi
}

render_update_rows() {
  local name current latest status eligible_date
  printf 'Name\tCurrent\tLatest eligible\tStatus\tEligible date\n'
  while IFS=$'\t' read -r name current latest status eligible_date; do
    [[ -n "${name}" ]] || continue
    case "${status}" in
      cooldown_unknown)
        printf '%s\t%s\t%s\tBLOCKED by unknown cooldown\t%s\n' "${name}" "${current:-unknown}" "${latest:-unknown}" "${eligible_date:-unknown}"
        ;;
      cooldown_active|cooldown*)
        printf '%s\t%s\t%s\tBLOCKED by cooldown\t%s\n' "${name}" "${current:-unknown}" "${latest:-unknown}" "${eligible_date:-unknown}"
        ;;
      update_available)
        printf '%s\t%s\t%s\tupdate available\t%s\n' "${name}" "${current:-unknown}" "${latest:-unknown}" "${eligible_date:-}"
        ;;
      current|up_to_date)
        printf '%s\t%s\t%s\tcurrent\t%s\n' "${name}" "${current:-unknown}" "${latest:-unknown}" "${eligible_date:-}"
        ;;
      *)
        printf '%s\t%s\t%s\t%s\t%s\n' "${name}" "${current:-unknown}" "${latest:-unknown}" "${status:-unknown}" "${eligible_date:-}"
        ;;
    esac
  done
  return 0
}

run_applier() {
  local domain="$1"
  local command_text="$2"

  if [[ -z "${command_text}" ]]; then
    printf 'No automatic applier configured for %s; audit/report only.\n' "${domain}"
    return 0
  fi

  printf 'Applying %s: %s\n' "${domain}" "${command_text}"
  run_shell_command "${command_text}"
}

run_domain() {
  local domain="$1"
  if ! "report_${domain}"; then
    printf 'ERROR %s: domain failed; continuing\n' "${domain}" >&2
    ERRORS=$((ERRORS + 1))
  fi
}

run_audits() {
  print_section "audit verdicts"
  local audit_errors=0
  local command_text
  local audit_commands="${UPDATE_VERSIONS_AUDIT_COMMANDS:-}"

  if [[ -z "${audit_commands}" ]]; then
    audit_commands=$(
      printf '%s\n' \
        "'${REPO_ROOT}/scripts/check-repo-version.sh' --execute" \
        "'${REPO_ROOT}/.devcontainer/check-devcontainer-version.sh' --execute" \
        "CHECK_VERSION_FORMAT=json '${REPO_ROOT}/terraform/kubernetes/scripts/check-provider-version.sh' --execute >/dev/null" \
        "CHECK_VERSION_FORMAT=json CHECK_VERSION_CI_MODE=1 '${REPO_ROOT}/terraform/kubernetes/scripts/check-component-version.sh' --execute --ci >/dev/null"
    )
  fi

  while IFS= read -r command_text; do
    [[ -n "${command_text}" ]] || continue
    printf 'Running: %s\n' "${command_text}"
    if run_shell_command "${command_text}"; then
      printf 'PASS\n'
    else
      printf 'FAIL\n'
      audit_errors=$((audit_errors + 1))
    fi
  done <<< "${audit_commands}"
  return "${audit_errors}"
}

cleanup() {
  [[ -n "${COMPONENT_REPORT_FILE}" ]] && rm -f "${COMPONENT_REPORT_FILE}"
  [[ -n "${PROVIDER_REPORT_FILE}" ]] && rm -f "${PROVIDER_REPORT_FILE}"
  return 0
}
trap cleanup EXIT

validate_domains
printf 'update-versions mode: %s\n' "${MODE}"
printf 'domains: %s\n' "${ONLY}"
printf 'cooldown semantics: packages reuse js_dependency_cooldown_seconds; release resolvers use %s seconds\n' "${UPDATE_VERSIONS_MIN_RELEASE_AGE_SECONDS}"

for domain in tools devcontainer charts packages providers images; do
  if contains_domain "${domain}"; then
    run_domain "${domain}"
  fi
done

if [[ "${MODE}" == "apply" ]]; then
  if ! run_audits; then
    ERRORS=$((ERRORS + 1))
  fi
fi

if [[ "${ERRORS}" -gt 0 ]]; then
  exit 1
fi

exit 0
