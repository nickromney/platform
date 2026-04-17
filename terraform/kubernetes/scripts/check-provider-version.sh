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
HTTP_FETCH_MAX_TIME_SECONDS="${HTTP_FETCH_MAX_TIME_SECONDS:-${CHECK_PROVIDER_VERSION_CURL_MAX_TIME_SECONDS:-15}}"
HTTP_FETCH_CONNECT_TIMEOUT_SECONDS="${HTTP_FETCH_CONNECT_TIMEOUT_SECONDS:-${CHECK_PROVIDER_VERSION_CURL_CONNECT_TIMEOUT_SECONDS:-5}}"
CHECK_PROVIDER_VERSION_CACHE_DIR="${CHECK_PROVIDER_VERSION_CACHE_DIR:-}"
HTTP_FETCH_CACHE_DIR="${HTTP_FETCH_CACHE_DIR:-${CHECK_PROVIDER_VERSION_CACHE_DIR:-}}"

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

usage() {
  cat <<EOF
Usage: check-provider-version.sh [--dry-run] [--execute]

Checks the locked Terraform provider versions against the latest upstream
registry releases.

$(shell_cli_standard_options)
EOF
}

if [ "${CHECK_PROVIDER_VERSION_LIB_ONLY:-0}" != "1" ]; then
  shell_cli_handle_standard_no_args usage "would compare locked Terraform providers against the latest upstream releases" "$@"
fi

require() {
  local bin="$1"
  command -v "$bin" >/dev/null 2>&1 || fail "$bin not found in PATH"
}

cleanup_temp_paths() {
  local first="${1:-}"
  local second="${2:-}"
  local directory="${3:-}"

  [ -n "${first}" ] && rm -f "${first}"
  [ -n "${second}" ] && rm -f "${second}"
  [ -n "${directory}" ] && rm -rf "${directory}"
}

version_lt() {
  local left="$1"
  local right="$2"
  [ "$(printf '%s\n%s\n' "${left}" "${right}" | sort -V | head -n 1)" = "${left}" ] && [ "${left}" != "${right}" ]
}

version_lte() {
  local left="$1"
  local right="$2"
  [ "${left}" = "${right}" ] || version_lt "${left}" "${right}"
}

version_gt() {
  version_lt "$2" "$1"
}

version_gte() {
  [ "$1" = "$2" ] || version_gt "$1" "$2"
}

constraint_clause_allows_version() {
  local clause="$1"
  local version="$2"

  clause="$(echo "${clause}" | xargs)"
  if [ -z "${clause}" ]; then
    return 0
  fi

  case "${clause}" in
    "~> "*)
      local base="${clause#~> }"
      local base_major="" base_minor="" base_patch=""
      local version_major="" version_minor=""

      IFS='.' read -r base_major base_minor base_patch <<<"${base}"
      IFS='.' read -r version_major version_minor _ <<<"${version}"

      if [ -n "${base_patch:-}" ]; then
        [ "${version_major}" = "${base_major}" ] && [ "${version_minor}" = "${base_minor}" ] && version_gte "${version}" "${base}"
      else
        [ "${version_major}" = "${base_major}" ] && version_gte "${version}" "${base}"
      fi
      ;;
    ">= "*)
      version_gte "${version}" "${clause#>= }"
      ;;
    "<= "*)
      version_lte "${version}" "${clause#<= }"
      ;;
    "> "*)
      version_gt "${version}" "${clause#> }"
      ;;
    "< "*)
      version_lt "${version}" "${clause#< }"
      ;;
    "= "*)
      [ "${version}" = "${clause#= }" ]
      ;;
    *)
      [ "${version}" = "${clause}" ]
      ;;
  esac
}

constraint_allows_version() {
  local constraint="$1"
  local version="$2"
  local clause

  if [ -z "${constraint}" ]; then
    return 0
  fi

  IFS=',' read -ra clauses <<<"${constraint}"
  for clause in "${clauses[@]}"; do
    constraint_clause_allows_version "${clause}" "${version}" || return 1
  done
}

extract_locked_providers() {
  awk '
    /^provider "/ {
      source=$2
      gsub(/"/, "", source)
      in_block=1
      version=""
      constraints=""
      next
    }
    in_block && /^[[:space:]]*version[[:space:]]*=/ {
      version=$0
      sub(/^[^"]*"/, "", version)
      sub(/".*$/, "", version)
      next
    }
    in_block && /^[[:space:]]*constraints[[:space:]]*=/ {
      constraints=$0
      sub(/^[^"]*"/, "", constraints)
      sub(/".*$/, "", constraints)
      next
    }
    in_block && /^[[:space:]]*}/ {
      split(source, parts, "/")
      short_source=parts[2] "/" parts[3]
      printf "%s\t%s\t%s\t%s\n", source, short_source, version, constraints
      in_block=0
    }
  ' "${LOCK_FILE}"
}

latest_registry_version() {
  local source="$1"
  local host namespace name versions_json
  IFS='/' read -r host namespace name <<<"${source}"

  versions_json="$(http_cached_output "terraform-provider-versions" "${source}" latest_registry_version_uncached "${source}")"
  jq -r '.versions[].version' <<<"${versions_json}" | grep -v -- '-' | sort -V | tail -n 1
}

latest_registry_version_uncached() {
  local source="$1"
  local host namespace name

  IFS='/' read -r host namespace name <<<"${source}"
  http_fetch -fsSL "https://${host}/v1/providers/${namespace}/${name}/versions"
}

emit_provider_row() {
  local line="$1"
  local full_source="" short_source="" locked_version="" constraint=""
  local latest_version="" status_text="" status_rendered=""
  local outdated_flag="0" error_flag="0"

  IFS=$'\t' read -r full_source short_source locked_version constraint <<<"${line}"
  [ -n "${full_source}" ] || return 0

  latest_version="$(latest_registry_version "${full_source}" 2>/dev/null || true)"
  if [ -z "${latest_version}" ]; then
    latest_version="unknown"
    status_text="registry lookup failed"
    status_rendered="${RED}${status_text}${NC}"
    error_flag="1"
  elif [ "${locked_version}" = "${latest_version}" ]; then
    status_text="up to date"
    status_rendered="${GREEN}${status_text}${NC}"
  elif constraint_allows_version "${constraint}" "${latest_version}"; then
    status_text="update available"
    status_rendered="${YELLOW}${status_text}${NC}"
    outdated_flag="1"
  else
    status_text="update available; constraint blocks latest"
    status_rendered="${YELLOW}${status_text}${NC}"
    outdated_flag="1"
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${short_source}" \
    "${constraint:--}" \
    "${locked_version}" \
    "${latest_version}" \
    "${status_rendered}" \
    "${outdated_flag}" \
    "${error_flag}"
}

require curl
require jq

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
STACK_DIR="${STACK_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
LOCK_FILE="${STACK_DIR}/.terraform.lock.hcl"

main() {
  local providers_file rows_file output_dir max_jobs
  local outdated_count=0
  local error_count=0
  local short_source="" constraint="" locked_version="" latest_version="" status=""
  local outdated_flag="" error_flag=""

  [ -f "${LOCK_FILE}" ] || fail "missing ${LOCK_FILE}"
  HTTP_FETCH_CACHE_DIR="${HTTP_FETCH_CACHE_DIR:-${CHECK_PROVIDER_VERSION_CACHE_DIR:-}}"
  HTTP_FETCH_CACHE_DIR="$(http_cache_dir_ensure)"
  CHECK_PROVIDER_VERSION_CACHE_DIR="${HTTP_FETCH_CACHE_DIR}"

  providers_file="$(mktemp)"
  rows_file="$(mktemp)"
  output_dir="$(mktemp -d)"
  trap "cleanup_temp_paths '${providers_file}' '${rows_file}' '${output_dir}'" EXIT

  extract_locked_providers >"${providers_file}"
  printf '%s\n' $'Provider\tConstraint\tLocked\tLatest\tStatus' >"${rows_file}"
  printf '%s\n' $'--------\t----------\t------\t------\t------' >>"${rows_file}"

  max_jobs="$(parallel_default_jobs)"
  progress "Checking latest Terraform provider releases with concurrency ${max_jobs}"
  while IFS=$'\t' read -r short_source constraint locked_version latest_version status outdated_flag error_flag; do
    [ -n "${short_source}" ] || continue

    outdated_count=$((outdated_count + outdated_flag))
    error_count=$((error_count + error_flag))
    printf "%s\t%s\t%s\t%s\t%b\n" \
      "${short_source}" "${constraint}" "${locked_version}" "${latest_version}" "${status}" >>"${rows_file}"
  done < <(parallel_map_lines "${max_jobs}" emit_provider_row "${providers_file}" "${output_dir}")

  if json_mode; then
    jq -Rcs \
      --argjson outdated_count "${outdated_count}" \
      --argjson error_count "${error_count}" '
        split("\n")
        | .[2:-1]
        | map(select(length > 0) | split("\t"))
        | map({
            provider: .[0],
            constraint: .[1],
            locked: .[2],
            latest: .[3],
            status: ((.[4] // "") | gsub("\u001b\\[[0-9;]*m"; ""))
          })
        | {
            format: "check-provider-version/v1",
            providers: .,
            summary: {
              outdated_count: $outdated_count,
              error_count: $error_count
            }
          }
      ' "${rows_file}"
  else
    echo "Terraform provider versions"
    awk -F '\t' '
      {
        rows[NR] = $0
        row_count = NR
        for (i = 1; i < NF; i++) {
          if (length($i) > widths[i]) {
            widths[i] = length($i)
          }
        }
      }
      END {
        for (row = 1; row <= row_count; row++) {
          split(rows[row], fields, FS)
          for (i = 1; i < length(fields); i++) {
            printf "%-*s ", widths[i], fields[i]
          }
          printf "%s\n", fields[length(fields)]
        }
      }
    ' "${rows_file}"
  fi

  if [ "${error_count}" -gt 0 ]; then
    warn "${error_count} provider registry lookup(s) failed"
  fi

  if [ "${outdated_count}" -gt 0 ]; then
    warn "${outdated_count} provider(s) are behind the latest upstream release"
  else
    ok "all locked providers match the latest upstream release"
  fi
}

if [ "${CHECK_PROVIDER_VERSION_LIB_ONLY:-0}" != "1" ]; then
  main "$@"
fi
