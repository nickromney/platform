#!/usr/bin/env bash
set -euo pipefail

fail() { echo "sync-gitea-repo: $*" >&2; exit 1; }

: "${STACK_DIR:?STACK_DIR is required}"
: "${SOURCE_DIR:?SOURCE_DIR is required (host path to the repo content)}"
: "${GITEA_ADMIN_USERNAME:?GITEA_ADMIN_USERNAME is required}"
: "${GITEA_ADMIN_PWD:?GITEA_ADMIN_PWD is required}"
: "${GITEA_SSH_USERNAME:?GITEA_SSH_USERNAME is required (typically git)}"
: "${GITEA_REPO_OWNER:?GITEA_REPO_OWNER is required}"
: "${GITEA_REPO_NAME:?GITEA_REPO_NAME is required}"
: "${DEPLOY_KEY_TITLE:?DEPLOY_KEY_TITLE is required}"
: "${DEPLOY_PUBLIC_KEY:?DEPLOY_PUBLIC_KEY is required}"
: "${SSH_PRIVATE_KEY_PATH:?SSH_PRIVATE_KEY_PATH is required}"

GITEA_REPO_OWNER_IS_ORG="${GITEA_REPO_OWNER_IS_ORG:-false}"
GITEA_REPO_OWNER_FALLBACK="${GITEA_REPO_OWNER_FALLBACK:-}"

command -v curl >/dev/null 2>&1 || fail "curl not found"
command -v git >/dev/null 2>&1 || fail "git not found"

# shellcheck source=/dev/null
source "${STACK_DIR}/scripts/gitea-local-access.sh"

tmp=""
cleanup() {
  local d="${tmp:-}"
  gitea_local_access_cleanup || true
  if [[ -n "$d" && -d "$d" ]]; then
    rm -rf "$d"
  fi
  return 0
}
trap cleanup EXIT

cleanup_tmp() {
  local d="${tmp:-}"
  if [[ -n "$d" && -d "$d" ]]; then
    rm -rf "$d"
  fi
  tmp=""
  return 0
}

wait_for_gitea() {
  local code
  for i in {1..120}; do
    code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 2 --max-time 5 \
      "${GITEA_HTTP_BASE}/api/v1/version" 2>/dev/null || echo 000)"
    if [[ "${code}" =~ ^[234][0-9][0-9]$ ]]; then
      return 0
    fi
    echo "Waiting for Gitea API... ($i/120)" >&2
    sleep 2
  done
  fail "Gitea API not reachable at ${GITEA_HTTP_BASE}"
}

refresh_gitea_git_access() {
  gitea_local_access_reset both
  : "${GITEA_HTTP_BASE:?GITEA_HTTP_BASE is required after local access setup}"
  : "${GITEA_SSH_HOST:?GITEA_SSH_HOST is required after local access setup}"
  : "${GITEA_SSH_PORT:?GITEA_SSH_PORT is required after local access setup}"
  wait_for_gitea
}

is_true() {
  case "${1}" in
    true|TRUE|1|yes|YES|y|Y) return 0 ;;
    *) return 1 ;;
  esac
}

repo_exists_for_owner() {
  local owner="$1"
  local code
  code=$(curl -sS -o /dev/null -w "%{http_code}" \
    -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
    "${GITEA_HTTP_BASE}/api/v1/repos/${owner}/${GITEA_REPO_NAME}" || echo 000)
  [[ "$code" == "200" ]]
}

ensure_org_exists() {
  if ! is_true "${GITEA_REPO_OWNER_IS_ORG}"; then
    return 0
  fi

  local code payload
  code=$(curl -sS -o /dev/null -w "%{http_code}" \
    -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
    "${GITEA_HTTP_BASE}/api/v1/orgs/${GITEA_REPO_OWNER}" || echo 000)

  if [[ "${code}" == "200" ]]; then
    return 0
  fi

  payload=$(cat <<EOF
{"username":"${GITEA_REPO_OWNER}"}
EOF
)

  echo "Gitea org '${GITEA_REPO_OWNER}' is missing; creating it before syncing repos" >&2
  code=$(curl -sS -o /dev/null -w "%{http_code}" \
    -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
    -H "Content-Type: application/json" \
    -d "${payload}" \
    "${GITEA_HTTP_BASE}/api/v1/orgs" || echo 000)

  if [[ "${code}" != "201" && "${code}" != "409" && "${code}" != "422" ]]; then
    fail "create org '${GITEA_REPO_OWNER}' returned HTTP ${code}"
  fi

  code=$(curl -sS -o /dev/null -w "%{http_code}" \
    -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
    "${GITEA_HTTP_BASE}/api/v1/orgs/${GITEA_REPO_OWNER}" || echo 000)
  [[ "${code}" == "200" ]] || fail "organization '${GITEA_REPO_OWNER}' is still unavailable after create attempt (HTTP ${code})"
}

transfer_repo_if_needed() {
  if ! is_true "${GITEA_REPO_OWNER_IS_ORG}"; then
    return 0
  fi

  if [[ -z "${GITEA_REPO_OWNER_FALLBACK}" ]]; then
    return 0
  fi

  if repo_exists_for_owner "${GITEA_REPO_OWNER}"; then
    return 0
  fi

  if ! repo_exists_for_owner "${GITEA_REPO_OWNER_FALLBACK}"; then
    return 0
  fi

  local payload code
  payload=$(cat <<EOF
{"new_owner":"${GITEA_REPO_OWNER}"}
EOF
)

  code=$(curl -sS -o /dev/null -w "%{http_code}" \
    -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
    -H "Content-Type: application/json" \
    -d "${payload}" \
    "${GITEA_HTTP_BASE}/api/v1/repos/${GITEA_REPO_OWNER_FALLBACK}/${GITEA_REPO_NAME}/transfer" || echo 000)

  if [[ "${code}" != "202" && "${code}" != "201" && "${code}" != "409" ]]; then
    fail "Transfer repo returned HTTP $code"
  fi
}

create_repo_if_missing() {
  if repo_exists_for_owner "${GITEA_REPO_OWNER}"; then
    return 0
  fi

  ensure_org_exists

  transfer_repo_if_needed
  if repo_exists_for_owner "${GITEA_REPO_OWNER}"; then
    return 0
  fi

  local payload code
  payload=$(cat <<EOF
{"name":"${GITEA_REPO_NAME}","private":true,"auto_init":false,"default_branch":"main"}
EOF
)

  local create_url
  if is_true "${GITEA_REPO_OWNER_IS_ORG}"; then
    create_url="${GITEA_HTTP_BASE}/api/v1/orgs/${GITEA_REPO_OWNER}/repos"
  else
    create_url="${GITEA_HTTP_BASE}/api/v1/user/repos"
  fi

  code=$(curl -sS -o /dev/null -w "%{http_code}" \
    -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
    -H "Content-Type: application/json" \
    -d "${payload}" \
    "${create_url}" || echo 000)

  if [[ "$code" != "201" && "$code" != "409" ]]; then
    fail "Create repo returned HTTP $code"
  fi
}

ensure_deploy_key() {
  local payload code
  payload=$(cat <<EOF
{"title":"${DEPLOY_KEY_TITLE}","key":"${DEPLOY_PUBLIC_KEY}","read_only":false}
EOF
)

  code=$(curl -sS -o /dev/null -w "%{http_code}" \
    -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
    -H "Content-Type: application/json" \
    -d "${payload}" \
    "${GITEA_HTTP_BASE}/api/v1/repos/${GITEA_REPO_OWNER}/${GITEA_REPO_NAME}/keys" || echo 000)

  if [[ "$code" != "201" && "$code" != "422" && "$code" != "409" ]]; then
    fail "Add deploy key returned HTTP $code"
  fi
}

seed_repo() {
  cleanup_tmp || true
  tmp=$(mktemp -d)

  mkdir -p "${tmp}/repo"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a \
      --exclude '.git' \
      --exclude '.DS_Store' \
      --exclude 'node_modules' \
      --exclude '.venv' \
      --exclude '__pycache__' \
      "${SOURCE_DIR}/" "${tmp}/repo/"
  else
    cp -R "${SOURCE_DIR}/." "${tmp}/repo/"
  fi

  pushd "${tmp}/repo" >/dev/null
  git init -q
  git config user.email "kind-demo@local"
  git config user.name "kind-demo"
  git config commit.gpgsign false
  git add -A

  if git diff --cached --quiet; then
    git commit -q --allow-empty -m "sync ${GITEA_REPO_NAME}"
  else
    git commit -q -m "sync ${GITEA_REPO_NAME}"
  fi

  git branch -M main

  local pushed="false"
  for i in {1..20}; do
    local remote_url ssh_cmd
    refresh_gitea_git_access
    remote_url="ssh://${GITEA_SSH_USERNAME}@${GITEA_SSH_HOST}:${GITEA_SSH_PORT}/${GITEA_REPO_OWNER}/${GITEA_REPO_NAME}.git"
    ssh_cmd="ssh -i ${SSH_PRIVATE_KEY_PATH} -p ${GITEA_SSH_PORT} -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    if git remote get-url origin >/dev/null 2>&1; then
      git remote set-url origin "${remote_url}"
    else
      git remote add origin "${remote_url}"
    fi
    if GIT_SSH_COMMAND="$ssh_cmd" git push -q --force origin main; then
      pushed="true"
      break
    fi
    echo "git push failed, retrying... ($i/20)" >&2
    sleep 3
  done

  popd >/dev/null
  if [[ "$pushed" != "true" ]]; then
    echo "git push failed after retries" >&2
    return 1
  fi

  return 0
}

gitea_local_access_setup both
: "${GITEA_HTTP_BASE:?GITEA_HTTP_BASE is required after local access setup}"
: "${GITEA_SSH_HOST:?GITEA_SSH_HOST is required after local access setup}"
: "${GITEA_SSH_PORT:?GITEA_SSH_PORT is required after local access setup}"

wait_for_gitea
create_repo_if_missing
ensure_deploy_key

if ! seed_repo; then
  fail "git push failed"
fi

echo "Synced ${GITEA_REPO_OWNER}/${GITEA_REPO_NAME} from ${SOURCE_DIR}"
