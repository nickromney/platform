#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

fail() { echo "review-environment-dispatch: $*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute]

Dispatch or inspect a Gitea Actions workflow for an app repository.

$(shell_cli_standard_options)
EOF
}

review_dispatch_payload() {
  local ref="$1"
  printf '{"ref":"%s"}' "${ref}"
}

review_dispatch_workflow() {
  local repo="${1:-${APP_REPO_NAME:?APP_REPO_NAME is required}}"
  local workflow_id="${2:-${APP_WORKFLOW_ID:?APP_WORKFLOW_ID is required}}"
  local ref="${3:-${APP_WORKFLOW_REF:-main}}"
  local resp code body

  : "${GITEA_HTTP_BASE:?GITEA_HTTP_BASE is required}"
  : "${GITEA_ADMIN_USERNAME:?GITEA_ADMIN_USERNAME is required}"
  : "${GITEA_ADMIN_PWD:?GITEA_ADMIN_PWD is required}"
  : "${GITEA_REPO_OWNER:?GITEA_REPO_OWNER is required}"

  resp="$(curl -sS -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "$(review_dispatch_payload "${ref}")" \
    "${GITEA_HTTP_BASE}/api/v1/repos/${GITEA_REPO_OWNER}/${repo}/actions/workflows/${workflow_id}/dispatches" \
    -w '\n%{http_code}' || true)"
  code="$(printf '%s' "${resp}" | tail -n 1)"
  body="$(printf '%s' "${resp}" | sed '$d')"

  if [[ "${code}" == "204" || "${code}" == "201" ]]; then
    return 0
  fi

  echo "Failed to dispatch ${repo} workflow (${workflow_id}), HTTP ${code}" >&2
  if [[ -n "${body}" ]]; then
    echo "${body}" >&2
  fi
  return 1
}

review_actions_runs_json() {
  local repo="${1:-${APP_REPO_NAME:?APP_REPO_NAME is required}}"
  local limit="${2:-5}"

  curl -fsS -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
    "${GITEA_HTTP_BASE}/api/v1/repos/${GITEA_REPO_OWNER}/${repo}/actions/runs?limit=${limit}" || true
}

review_actions_run_field_for_tag() {
  local json="$1"
  local tag="$2"
  local field="$3"

  command -v jq >/dev/null 2>&1 || fail "jq not found"
  printf '%s' "${json}" | jq -r --arg tag "${tag}" --arg field "${field}" '
    .workflow_runs[]?
    | select((.head_sha // "") | startswith($tag))
    | .[$field] // empty
  ' | head -n 1
}

review_actions_failure_excerpt() {
  local repo="$1"
  local run_id="$2"
  local job_json job_id

  [[ -n "${run_id}" ]] || return 0
  job_json="$(curl -fsS -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
    "${GITEA_HTTP_BASE}/api/v1/repos/${GITEA_REPO_OWNER}/${repo}/actions/runs/${run_id}/jobs" || true)"
  job_id="$(printf '%s' "${job_json}" | jq -r '.jobs[0].id // empty')"
  [[ -n "${job_id}" ]] || return 0

  curl -fsS -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
    "${GITEA_HTTP_BASE}/api/v1/repos/${GITEA_REPO_OWNER}/${repo}/actions/jobs/${job_id}/logs" 2>/dev/null \
    | tr -d '\r' \
    | grep -Ei "ERROR|failed to|\\bFailure\\b|exit status|timed out|timeout|denied|unauthorized|DeadlineExceeded" \
    | tail -n 30 || true
}

review_check_actions_failure() {
  local tag="$1"
  local repo="${APP_REPO_NAME:?APP_REPO_NAME is required}"
  local display="${APP_DISPLAY_NAME:-${repo}}"
  local consequence="${APP_FAILURE_CONSEQUENCE:-Workflow outputs will not be ready until it succeeds.}"
  local json status conclusion run_id run_url excerpt

  ACTIONS_RETRIGGERED_TAG="${ACTIONS_RETRIGGERED_TAG:-}"
  json="$(review_actions_runs_json "${repo}" 5)"
  if [[ -z "${json}" ]]; then
    return 0
  fi

  status="$(review_actions_run_field_for_tag "${json}" "${tag}" status)"
  conclusion="$(review_actions_run_field_for_tag "${json}" "${tag}" conclusion)"
  run_id="$(review_actions_run_field_for_tag "${json}" "${tag}" id)"
  run_url="$(review_actions_run_field_for_tag "${json}" "${tag}" html_url)"

  if [[ "${status}" == "completed" && -n "${conclusion}" && "${conclusion}" != "success" ]]; then
    if [[ "${ACTIONS_RETRIGGERED_TAG}" != "${tag}" ]]; then
      echo "${display} Actions run for ${tag} failed (${conclusion}). Triggering one workflow_dispatch retry..." >&2
      if review_dispatch_workflow "${repo}" "${APP_WORKFLOW_ID:?APP_WORKFLOW_ID is required}" "${APP_WORKFLOW_REF:-main}"; then
        ACTIONS_RETRIGGERED_TAG="${tag}"
        return 0
      fi
      echo "Automatic retry dispatch failed; surfacing workflow failure details." >&2
    fi

    echo "${display} Actions run for ${tag} failed (${conclusion}). ${consequence}" >&2
    if [[ -n "${run_url}" ]]; then
      echo "Run URL: ${run_url}" >&2
    fi
    excerpt="$(review_actions_failure_excerpt "${repo}" "${run_id}")"
    if [[ -n "${excerpt}" ]]; then
      echo "Failure excerpts (run ${run_id}):" >&2
      printf '%s\n' "${excerpt}" >&2
    fi
    exit 1
  fi
}

review_ensure_workflow_started() {
  local tag="$1"
  local repo="${APP_REPO_NAME:?APP_REPO_NAME is required}"
  local display="${APP_DISPLAY_NAME:-${repo}}"
  local json status conclusion

  ACTIONS_RETRIGGERED_TAG="${ACTIONS_RETRIGGERED_TAG:-}"
  json="$(review_actions_runs_json "${repo}" 10)"
  if [[ -n "${json}" ]]; then
    status="$(review_actions_run_field_for_tag "${json}" "${tag}" status)"
    conclusion="$(review_actions_run_field_for_tag "${json}" "${tag}" conclusion)"

    if [[ "${status}" == "queued" || "${status}" == "waiting" || "${status}" == "running" ]]; then
      echo "${display} workflow already in progress for ${tag}"
      return 0
    fi
    if [[ "${status}" == "completed" && "${conclusion}" == "success" ]]; then
      echo "${display} workflow already completed for ${tag}"
      return 0
    fi
    if [[ "${status}" == "completed" && -n "${conclusion}" && "${conclusion}" != "success" ]]; then
      echo "${display} workflow previously failed for ${tag}; dispatching retry"
      ACTIONS_RETRIGGERED_TAG="${tag}"
      review_dispatch_workflow "${repo}" "${APP_WORKFLOW_ID:?APP_WORKFLOW_ID is required}" "${APP_WORKFLOW_REF:-main}"
      return 0
    fi
  fi

  echo "No ${display} workflow run found for ${tag}; dispatching ${APP_WORKFLOW_ID:?APP_WORKFLOW_ID is required}"
  ACTIONS_RETRIGGERED_TAG="${tag}"
  review_dispatch_workflow "${repo}" "${APP_WORKFLOW_ID}" "${APP_WORKFLOW_REF:-main}"
}

check_actions_failure() {
  review_check_actions_failure "$@"
}

ensure_workflow_started() {
  review_ensure_workflow_started "$@"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  shell_cli_handle_standard_no_args usage \
    "would dispatch APP_WORKFLOW_ID for APP_REPO_NAME using APP_WORKFLOW_REF" \
    "$@"
  review_dispatch_workflow
fi
