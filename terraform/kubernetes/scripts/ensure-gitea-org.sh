#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${REPO_ROOT:-}" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
fi

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/platform-env.sh"

fail() { echo "ensure-gitea-org: $*" >&2; exit 1; }
warn() { echo "ensure-gitea-org: $*" >&2; }
ok() { echo "ensure-gitea-org: $*"; }

usage() {
  cat <<EOF
Usage: ensure-gitea-org.sh [--dry-run] [--execute]

Ensures the configured Gitea organization and member accounts exist.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage "would ensure the configured Gitea organization and members exist" "$@"

platform_load_env

: "${GITEA_ADMIN_USERNAME:?GITEA_ADMIN_USERNAME is required}"
: "${GITEA_ADMIN_PWD:?GITEA_ADMIN_PWD is required}"
: "${GITEA_ORG_NAME:?GITEA_ORG_NAME is required}"
: "${GITEA_MEMBERS_DEFAULT_PWD:=${PLATFORM_DEMO_PASSWORD:-}}"
if [[ -z "${GITEA_MEMBERS_DEFAULT_PWD}" ]]; then
  platform_require_vars PLATFORM_DEMO_PASSWORD || exit 1
  GITEA_MEMBERS_DEFAULT_PWD="${PLATFORM_DEMO_PASSWORD}"
fi

GITEA_ORG_FULL_NAME="${GITEA_ORG_FULL_NAME:-}"
GITEA_ORG_EMAIL="${GITEA_ORG_EMAIL:-}"
GITEA_ORG_VISIBILITY="${GITEA_ORG_VISIBILITY:-private}"
GITEA_ORG_MEMBERS="${GITEA_ORG_MEMBERS:-}"
GITEA_ORG_MEMBER_EMAILS="${GITEA_ORG_MEMBER_EMAILS:-}"

command -v curl >/dev/null 2>&1 || fail "curl not found"
command -v jq >/dev/null 2>&1 || fail "jq not found"

GITEA_WAIT_MAX_SECONDS="${GITEA_WAIT_MAX_SECONDS:-600}"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/gitea-local-access.sh"
trap 'gitea_local_access_cleanup || true' EXIT

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

gitea_local_access_setup http
: "${GITEA_HTTP_BASE:?GITEA_HTTP_BASE is required after local access setup}"

org_exists() {
  local code
  code=$(curl -sS -o /dev/null -w "%{http_code}" \
    -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
    "${GITEA_HTTP_BASE}/api/v1/orgs/${GITEA_ORG_NAME}" || echo 000)
  [[ "${code}" == "200" ]]
}

create_org() {
  local payload code
  payload=$(jq -cn \
    --arg username "${GITEA_ORG_NAME}" \
    --arg full_name "${GITEA_ORG_FULL_NAME}" \
    --arg email "${GITEA_ORG_EMAIL}" \
    --arg visibility "${GITEA_ORG_VISIBILITY}" \
    '{
      username: $username
    } + (if $full_name != "" then {full_name: $full_name} else {} end)
      + (if $email != "" then {email: $email} else {} end)
      + (if $visibility != "" then {visibility: $visibility} else {} end)')

  code=$(curl -sS -o /dev/null -w "%{http_code}" \
    -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
    -H "Content-Type: application/json" \
    -d "${payload}" \
    "${GITEA_HTTP_BASE}/api/v1/orgs" || echo 000)

  if [[ "${code}" == "201" || "${code}" == "409" || "${code}" == "422" ]]; then
    return 0
  fi

  fail "Create org returned HTTP ${code}"
}

urlencode_basic() {
  local s="$1"
  s=${s// /%20}
  s=${s//@/%40}
  s=${s//+/%2B}
  printf '%s' "$s"
}

get_owners_team_id() {
  local teams team_id
  teams=$(curl -sS \
    -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
    "${GITEA_HTTP_BASE}/api/v1/orgs/${GITEA_ORG_NAME}/teams")

  team_id=$(echo "${teams}" | jq -r '.[] | select(.name=="Owners") | .id' | head -n 1)
  if [[ -n "${team_id}" && "${team_id}" != "null" ]]; then
    echo "${team_id}"
    return 0
  fi

  team_id=$(echo "${teams}" | jq -r '.[] | select(.permission=="admin") | .id' | head -n 1)
  if [[ -n "${team_id}" && "${team_id}" != "null" ]]; then
    echo "${team_id}"
    return 0
  fi

  local payload code tmp_file
  payload=$(jq -cn \
    --arg name "owners" \
    '{
      name: $name,
      permission: "admin",
      includes_all_repositories: true
    }')

  tmp_file=$(mktemp)
  code=$(curl -sS -o "${tmp_file}" -w "%{http_code}" \
    -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
    -H "Content-Type: application/json" \
    -d "${payload}" \
    "${GITEA_HTTP_BASE}/api/v1/orgs/${GITEA_ORG_NAME}/teams" || echo 000)

  if [[ "${code}" != "201" ]]; then
    rm -f "${tmp_file}"
    fail "Create team returned HTTP ${code}"
  fi

  jq -r '.id' "${tmp_file}"
  rm -f "${tmp_file}"
}

sanitize_login() {
  local input="$1"
  # NOTE: use printf (not echo) to avoid introducing a trailing '\n' which would
  # get normalized into a trailing '-' by `tr -c ...`.
  input=$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]')
  input=$(printf '%s' "$input" | tr -c '[:alnum:]' '-')
  # BSD sed: '$' is only special at end-of-regex. Use '-$' (not '-$$').
  input=$(printf '%s' "$input" | sed 's/-\+/-/g; s/^-//; s/-$//')
  input="${input:-user}"
  echo "$input"
}

login_exists() {
  local login="$1"
  local code
  code=$(curl -sS -o /dev/null -w "%{http_code}" \
    -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
    "${GITEA_HTTP_BASE}/api/v1/users/${login}" || echo 000)
  [[ "${code}" == "200" ]]
}

user_exists() {
  local username="$1"
  local code
  code=$(curl -sS -o /dev/null -w "%{http_code}" \
    -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
    "${GITEA_HTTP_BASE}/api/v1/users/${username}" || echo 000)
  [[ "${code}" == "200" ]]
}

update_user_email() {
  local login="$1"
  local email="$2"
  local payload code source_id user_json

  # Gitea's admin PATCH endpoint requires `login_name` + `source_id` even if you're
  # only changing the email. Fetch current values and include them.
  user_json="$(curl -sS \
    -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
    "${GITEA_HTTP_BASE}/api/v1/users/${login}" || true)"
  source_id="$(echo "${user_json:-{}}" | jq -r '.source_id // 0' 2>/dev/null || echo 0)"

  payload=$(jq -cn \
    --arg email "${email}" \
    --arg login_name "${email}" \
    --argjson source_id "${source_id}" \
    '{
      email: $email,
      login_name: $login_name,
      source_id: $source_id,
      must_change_password: false
    }')

  code=$(curl -sS -o /dev/null -w "%{http_code}" \
    -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
    -H "Content-Type: application/json" \
    -X PATCH \
    -d "${payload}" \
    "${GITEA_HTTP_BASE}/api/v1/admin/users/${login}" || echo 000)

  [[ "${code}" == "200" ]]
}

create_user() {
  local login="$1"
  local email="$2"
  local full_name="$3"
  local payload code tmp_file body

  payload=$(jq -cn \
    --arg login "${login}" \
    --arg email "${email}" \
    --arg full_name "${full_name:-}" \
    --arg password "${GITEA_MEMBERS_DEFAULT_PWD}" \
    '{
      username: $login,
      email: $email,
      password: $password,
      send_notify: false,
      # Avoid "Change Password" prompt on first login for bootstrap-created users.
      must_change_password: false
    } + (if $full_name != "" then {full_name: $full_name} else {} end)')

  tmp_file=$(mktemp)
  code=$(curl -sS -o "${tmp_file}" -w "%{http_code}" \
    -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
    -H "Content-Type: application/json" \
    -d "${payload}" \
    "${GITEA_HTTP_BASE}/api/v1/admin/users" || echo 000)

  if [[ "${code}" == "201" ]]; then
    rm -f "${tmp_file}"
    return 0
  fi

  body="$(cat "${tmp_file}" 2>/dev/null || true)"
  rm -f "${tmp_file}"

  # 409 is typically "already exists". 422 can be "already exists" OR "invalid username" OR "email taken".
  if [[ "${code}" == "409" ]]; then
    warn "user ${login} already exists (HTTP ${code})"
    if update_user_email "${login}" "${email}"; then return 0; fi
    return 2
  fi

  if [[ "${code}" == "422" ]]; then
    if login_exists "${login}"; then
      warn "user ${login} already exists (HTTP ${code})"
      if update_user_email "${login}" "${email}"; then return 0; fi
      return 2
    fi

    # If the email is already in use, return 2 so the caller can resolve by email.
    if [[ "${body}" == *"email"* ]] || [[ "${body}" == *"Email"* ]]; then
      return 2
    fi

    warn "failed to create user ${login} (HTTP ${code}): ${body}"
    return 1
  fi

  warn "failed to create user ${login} (HTTP ${code}): ${body}"
  return 1
}

ensure_user_by_email() {
  local email="$1"
  local full_name="$2"
  local login candidate suffix create_status

  email="${email//$'\r'/}"
  email="${email//$'\n'/}"

  login=$(resolve_username_by_email "${email}")
  if [[ -n "${login}" && "${login}" != "null" ]]; then
    echo "${login}"
    return 0
  fi

  login=$(sanitize_login "${email}")
  candidate="${login}"
  suffix=1
  while login_exists "${candidate}"; do
    candidate="${login}-${suffix}"
    suffix=$((suffix + 1))
  done

  create_user "${candidate}" "${email}" "${full_name:-}" || create_status=$?
  create_status=${create_status:-0}
  if [[ "${create_status}" -eq 0 ]]; then
    echo "${candidate}"
    return 0
  fi

  if login_exists "${candidate}"; then
    echo "${candidate}"
    return 0
  fi

  if [[ "${create_status}" -eq 2 ]]; then
    login=$(resolve_username_by_email "${email}")
    if [[ -n "${login}" && "${login}" != "null" ]]; then
      echo "${login}"
      return 0
    fi
    if login_exists "${candidate}"; then
      echo "${candidate}"
      return 0
    fi
  fi

  warn "could not ensure user exists for email ${email}"
  return 1
}

add_member_to_team() {
  local team_id="$1"
  local username="$2"

  if ! user_exists "${username}"; then
    warn "user '${username}' not found; skipping org membership"
    return 0
  fi

  local code
  code=$(curl -sS -o /dev/null -w "%{http_code}" \
    -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
    -X PUT \
    "${GITEA_HTTP_BASE}/api/v1/teams/${team_id}/members/${username}" || echo 000)

  if [[ "${code}" == "204" || "${code}" == "409" || "${code}" == "422" ]]; then
    return 0
  fi

  warn "failed to add '${username}' to org team (HTTP ${code})"
}

resolve_username_by_email() {
  local email="$1"
  local q
  q=$(urlencode_basic "${email}")
  curl -sS -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
    "${GITEA_HTTP_BASE}/api/v1/users/search?q=${q}&limit=20" | \
    jq -r --arg email "${email}" '.data[] | select(.email == $email) | .login' | head -n 1
}

wait_for_gitea

if ! org_exists; then
  create_org
  ok "created org ${GITEA_ORG_NAME}"
else
  ok "org ${GITEA_ORG_NAME} already exists"
fi

members=()
if [[ -n "${GITEA_ORG_MEMBERS}" ]]; then
  IFS=',' read -r -a members <<< "${GITEA_ORG_MEMBERS}"
fi

if [[ -n "${GITEA_ORG_MEMBER_EMAILS}" ]]; then
    IFS=',' read -r -a email_members <<< "${GITEA_ORG_MEMBER_EMAILS}"
    for email in "${email_members[@]}"; do
      email=$(echo "${email}" | xargs)
      email="${email//$'\r'/}"
      [[ -z "${email}" ]] && continue
      username=$(ensure_user_by_email "${email}" "")
    if [[ -n "${username}" ]]; then
      members+=("${username}")
    else
      warn "no user found for email '${email}' yet; ensure login exists before syncing org"
    fi
  done
fi

if [[ "${#members[@]}" -eq 0 ]]; then
  exit 0
fi

team_id=$(get_owners_team_id)
if [[ -z "${team_id}" || "${team_id}" == "null" ]]; then
  fail "failed to resolve Owners team id for org ${GITEA_ORG_NAME}"
fi

for username in "${members[@]}"; do
  username=$(echo "${username}" | xargs)
  [[ -z "${username}" ]] && continue
  add_member_to_team "${team_id}" "${username}"
done

ok "ensured org members for ${GITEA_ORG_NAME}"
