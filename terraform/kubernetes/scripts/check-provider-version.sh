#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../scripts/lib/shell-cli.sh"

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
NC=$'\033[0m'

ok() { echo "${GREEN}✔${NC} $*"; }
warn() { echo "${YELLOW}⚠${NC} $*"; }
fail() { echo "${RED}✖${NC} $*" >&2; exit 1; }
progress() { printf '... %s\n' "$*" >&2; }

usage() {
  cat <<EOF
Usage: check-provider-version.sh [--dry-run] [--execute]

Checks the locked Terraform provider versions against the latest upstream
registry releases.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage "would compare locked Terraform providers against the latest upstream releases" "$@"

require() {
  local bin="$1"
  command -v "$bin" >/dev/null 2>&1 || fail "$bin not found in PATH"
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

  versions_json="$(curl -fsSL "https://${host}/v1/providers/${namespace}/${name}/versions")"
  jq -r '.versions[].version' <<<"${versions_json}" | grep -v -- '-' | sort -V | tail -n 1
}

require curl
require jq

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STACK_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
LOCK_FILE="${STACK_DIR}/.terraform.lock.hcl"

[ -f "${LOCK_FILE}" ] || fail "missing ${LOCK_FILE}"

echo "Terraform provider versions"
rows_file="$(mktemp)"
trap 'rm -f "${rows_file}"' EXIT

printf '%s\n' $'Provider\tConstraint\tLocked\tLatest\tStatus' >"${rows_file}"
printf '%s\n' $'--------\t----------\t------\t------\t------' >>"${rows_file}"

outdated_count=0
error_count=0

while IFS=$'\t' read -r full_source short_source locked_version constraint; do
  [ -n "${full_source}" ] || continue

  progress "Checking latest Terraform provider release for ${short_source}"
  latest_version=""
  if ! latest_version="$(latest_registry_version "${full_source}" 2>/dev/null)"; then
    latest_version="unknown"
    status="${RED}registry lookup failed${NC}"
    error_count=$((error_count + 1))
  elif [ -z "${latest_version}" ]; then
    latest_version="unknown"
    status="${RED}no stable version found${NC}"
    error_count=$((error_count + 1))
  elif [ "${locked_version}" = "${latest_version}" ]; then
    status="${GREEN}up to date${NC}"
  elif constraint_allows_version "${constraint}" "${latest_version}"; then
    status="${YELLOW}update available${NC}"
    outdated_count=$((outdated_count + 1))
  else
    status="${YELLOW}update available; constraint blocks latest${NC}"
    outdated_count=$((outdated_count + 1))
  fi

  printf "%s\t%s\t%s\t%s\t%b\n" \
    "${short_source}" "${constraint:--}" "${locked_version}" "${latest_version}" "${status}" >>"${rows_file}"
done < <(extract_locked_providers)

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

if [ "${error_count}" -gt 0 ]; then
  warn "${error_count} provider registry lookup(s) failed"
fi

if [ "${outdated_count}" -gt 0 ]; then
  warn "${outdated_count} provider(s) are behind the latest upstream release"
else
  ok "all locked providers match the latest upstream release"
fi
