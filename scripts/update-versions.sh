#!/usr/bin/env bash
# shellcheck disable=SC2329
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

MODE="report"
APPLY=0
ONLY="tools,charts,packages,providers,images"

COMPONENT_REPORT_FILE=""
PROVIDER_REPORT_FILE=""
ERRORS=0

usage() {
  cat <<EOF
$(shell_cli_usage_line " [--dry-run] [--execute] [--apply] [--only tools,charts,packages,providers,images]")

Reports and optionally applies eligible dependency updates across the platform
version domains.

Options:
  --apply      With --execute, apply eligible updates per domain, then rerun
               the existing version audits.
  --only LIST  Comma-separated domain filter. Domains: tools, charts, packages,
               providers, images.

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
      tools|charts|packages|providers|images) ;;
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

tool_rows() {
  if [[ -n "${UPDATE_VERSIONS_TOOL_REPORT_TSV:-}" ]]; then
    printf '%s\n' "${UPDATE_VERSIONS_TOOL_REPORT_TSV}"
    return 0
  fi

  require awk || return 1
  awk '
    /^[A-Z0-9_]+_VERSION="\$\{[A-Z0-9_]+_VERSION:-/ {
      name=$1
      value=$0
      sub(/=.*/, "", name)
      sub(/.*:-/, "", value)
      sub(/\}".*/, "", value)
      printf "%s\t%s\t%s\t%s\t%s\n", name, value, "", "audit-only", ""
    }
    /^[[:space:]]*"[^"]+=[^"]+"/ {
      value=$0
      gsub(/^[[:space:]]*"|"$/, "", value)
      split(value, parts, "=")
      printf "ARKADE:%s\t%s\t%s\t%s\t%s\n", parts[1], parts[2], "", "audit-only", ""
    }
  ' "${REPO_ROOT}/.devcontainer/toolchain-versions.sh"
}

report_tools() {
  print_section "tools"
  printf 'source: .devcontainer/toolchain-versions.sh; audited by .devcontainer/check-devcontainer-version.sh\n'
  printf 'Name\tCurrent\tLatest eligible\tStatus\tEligible date\n'
  tool_rows | while IFS=$'\t' read -r name current latest status eligible_date; do
    [[ -n "${name}" ]] || continue
    printf '%s\t%s\t%s\t%s\t%s\n' "${name}" "${current:-unknown}" "${latest:-unknown}" "${status:-unknown}" "${eligible_date:-}"
  done
  if [[ "${MODE}" == "apply" ]]; then
    run_applier "tools" "${UPDATE_VERSIONS_TOOLS_APPLY_CMD:-}"
  else
    printf 'Apply action: update toolchain pins when an eligible resolver reports newer versions.\n'
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
printf 'cooldown semantics: reused from terraform/kubernetes/scripts/check-component-version.sh js_dependency_cooldown_seconds\n'

for domain in tools charts packages providers images; do
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
