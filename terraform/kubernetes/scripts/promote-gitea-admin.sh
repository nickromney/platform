#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../../scripts/lib/shell-cli.sh"

fail() { echo "promote-gitea-admin: $*" >&2; exit 1; }
warn() { echo "promote-gitea-admin: $*" >&2; }
ok() { echo "promote-gitea-admin: $*"; }

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute]

Promote a Gitea user to an administrator account.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage \
  "would promote the configured user to a Gitea administrator if needed" \
  "$@"

: "${GITEA_ADMIN_USERNAME:?GITEA_ADMIN_USERNAME is required}"
: "${GITEA_ADMIN_PWD:?GITEA_ADMIN_PWD is required}"
: "${GITEA_PROMOTE_USER:?GITEA_PROMOTE_USER is required}"
command -v jq >/dev/null 2>&1 || fail "jq is required to parse Gitea API responses"

GITEA_WAIT_MAX_SECONDS="${GITEA_WAIT_MAX_SECONDS:-600}"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/gitea-local-access.sh"

body_file=""
trap 'rm -f "${body_file:-}"; gitea_local_access_cleanup || true' EXIT

gitea_http_code() {
  local url="$1"
  curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 2 --max-time 5 "$url" 2>/dev/null || echo 000
}

gitea_is_reachable() {
  local code
  code="$(gitea_http_code "${GITEA_HTTP_BASE}/api/v1/version")"
  if [[ "$code" =~ ^[234][0-9][0-9]$ ]]; then
    return 0
  fi

  code="$(gitea_http_code "${GITEA_HTTP_BASE}/")"
  [[ "$code" =~ ^[234][0-9][0-9]$ ]]
}

wait_for_gitea() {
  local i
  for ((i = 1; i <= GITEA_WAIT_MAX_SECONDS; i++)); do
    if gitea_is_reachable; then
      return 0
    fi
    sleep 1
  done
  fail "Gitea API not reachable at ${GITEA_HTTP_BASE} after ${GITEA_WAIT_MAX_SECONDS}s"
}

urlencode_basic() {
  local s="$1"
  s=${s//@/%40}
  printf '%s' "$s"
}

gitea_local_access_setup http
: "${GITEA_HTTP_BASE:?GITEA_HTTP_BASE is required after local access setup}"

wait_for_gitea

user_enc=$(urlencode_basic "${GITEA_PROMOTE_USER}")
user_url="${GITEA_HTTP_BASE}/api/v1/users/${user_enc}"

body_file=$(mktemp)

code=$(curl -sS -o "${body_file}" -w "%{http_code}" \
  -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
  "${user_url}" || true)

if [[ "${code}" == "404" ]]; then
  warn "user '${GITEA_PROMOTE_USER}' not found yet; log in via SSO first to auto-create it"
  exit 0
fi

if [[ "${code}" != "200" ]]; then
  fail "failed to look up user '${GITEA_PROMOTE_USER}' (HTTP ${code})"
fi

if grep -Eq '"is_admin"[[:space:]]*:[[:space:]]*true' "${body_file}"; then
  ok "user '${GITEA_PROMOTE_USER}' is already admin"
  exit 0
fi

patch_url="${GITEA_HTTP_BASE}/api/v1/admin/users/${user_enc}"

login_name=$(jq -r '.login_name // ""' "${body_file}")
email=$(jq -r '.email // ""' "${body_file}")
source_id=$(jq -r '.source_id // 0' "${body_file}")
full_name=$(jq -r '.full_name // ""' "${body_file}")

if [[ -z "${login_name}" ]]; then
  if [[ -n "${email}" ]]; then
    login_name="${email}"
  else
    login_name="${GITEA_PROMOTE_USER}"
  fi
fi

if [[ -z "${full_name}" || "${full_name}" == "${GITEA_PROMOTE_USER}" ]]; then
  if [[ -n "${email}" ]]; then
    full_name="${email}"
  fi
fi

patch_body=$(jq -cn \
  --arg login_name "${login_name}" \
  --argjson source_id "${source_id}" \
  --arg full_name "${full_name}" \
  '{
    login_name: $login_name,
    source_id: $source_id,
    admin: true
  } + (if $full_name != "" then {full_name: $full_name} else {} end)')

code=$(curl -sS -o "${body_file}" -w "%{http_code}" \
  -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
  -X PATCH -H 'Content-Type: application/json' \
  -d "${patch_body}" \
  "${patch_url}" || true)

if [[ "${code}" =~ ^2 ]]; then
  ok "promoted '${GITEA_PROMOTE_USER}' to admin"
  exit 0
fi

if [[ "${code}" == "422" ]]; then
  warn "promotion for '${GITEA_PROMOTE_USER}' rejected (HTTP 422); user may already be admin or not ready yet"
  exit 0
fi

if [[ "${code}" == "401" || "${code}" == "403" ]]; then
  fail "authorization failed promoting '${GITEA_PROMOTE_USER}' (HTTP ${code})"
fi

fail "failed to promote '${GITEA_PROMOTE_USER}' (HTTP ${code})"
