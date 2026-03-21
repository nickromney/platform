#!/usr/bin/env bash

if [[ -n "${GITEA_LOCAL_ACCESS_HELPER_LOADED:-}" ]]; then
  # shellcheck disable=SC2317
  return 0 2>/dev/null || exit 0
fi
GITEA_LOCAL_ACCESS_HELPER_LOADED=1

GITEA_LOCAL_ACCESS_MODE="${GITEA_LOCAL_ACCESS_MODE:-nodeport}"
GITEA_LOCAL_ACCESS_HOST="${GITEA_LOCAL_ACCESS_HOST:-127.0.0.1}"
GITEA_NAMESPACE="${GITEA_NAMESPACE:-gitea}"
GITEA_HTTP_SERVICE="${GITEA_HTTP_SERVICE:-gitea-http}"
GITEA_SSH_SERVICE="${GITEA_SSH_SERVICE:-gitea-ssh}"
GITEA_HTTP_SERVICE_PORT="${GITEA_HTTP_SERVICE_PORT:-3000}"
GITEA_SSH_SERVICE_PORT="${GITEA_SSH_SERVICE_PORT:-22}"
GITEA_LOCAL_ACCESS_WAIT_SECONDS="${GITEA_LOCAL_ACCESS_WAIT_SECONDS:-${GITEA_WAIT_MAX_SECONDS:-180}}"
GITEA_LOCAL_ACCESS_HTTP_READY="${GITEA_LOCAL_ACCESS_HTTP_READY:-0}"
GITEA_LOCAL_ACCESS_SSH_READY="${GITEA_LOCAL_ACCESS_SSH_READY:-0}"
GITEA_LOCAL_ACCESS_PIDS=()
GITEA_LOCAL_ACCESS_LOGS=()

gitea_local_access_is_devcontainer() {
  [[ "${PLATFORM_DEVCONTAINER:-0}" == "1" ]]
}

gitea_local_access_rewrite_loopback_host() {
  local host="${1:-}"

  if gitea_local_access_is_devcontainer && [[ "${host}" == "127.0.0.1" || "${host}" == "localhost" ]]; then
    printf '%s\n' "host.docker.internal"
    return 0
  fi

  printf '%s\n' "${host}"
}

gitea_local_access_rewrite_loopback_base() {
  local base="${1:-}"
  local scheme host port path

  if ! gitea_local_access_is_devcontainer; then
    printf '%s\n' "${base}"
    return 0
  fi

  if [[ ! "${base}" =~ ^([a-zA-Z][a-zA-Z0-9+.-]*)://([^/:]+)(:([0-9]+))?(.*)$ ]]; then
    printf '%s\n' "${base}"
    return 0
  fi

  scheme="${BASH_REMATCH[1]}"
  host="${BASH_REMATCH[2]}"
  port="${BASH_REMATCH[4]:-}"
  path="${BASH_REMATCH[5]:-}"
  host="$(gitea_local_access_rewrite_loopback_host "${host}")"

  if [[ -n "${port}" ]]; then
    printf '%s\n' "${scheme}://${host}:${port}${path}"
  else
    printf '%s\n' "${scheme}://${host}${path}"
  fi
}

gitea_local_access_fail() {
  echo "gitea-local-access: $*" >&2
  return 1
}

gitea_local_access_require_cmd() {
  command -v "$1" >/dev/null 2>&1 || gitea_local_access_fail "$1 not found in PATH"
}

gitea_local_access_kubectl() {
  local args=()
  if [[ -n "${KUBECONFIG_CONTEXT:-}" ]]; then
    args+=(--context "${KUBECONFIG_CONTEXT}")
  fi
  kubectl "${args[@]}" "$@"
}

gitea_local_access_tcp_open() {
  local host="$1"
  local port="$2"

  if command -v nc >/dev/null 2>&1; then
    nc -z "${host}" "${port}" >/dev/null 2>&1
    return $?
  fi

  (exec 3<>"/dev/tcp/${host}/${port}") >/dev/null 2>&1
}

gitea_local_access_service_has_endpoints() {
  local service_name="$1"
  local addresses

  addresses="$(
    gitea_local_access_kubectl -n "${GITEA_NAMESPACE}" get endpoints "${service_name}" \
      -o jsonpath='{range .subsets[*].addresses[*]}x{end}' 2>/dev/null || true
  )"
  [[ -n "${addresses}" ]]
}

gitea_local_access_wait_for_service_endpoints() {
  local service_name="$1"
  local waited=0

  while [[ "${waited}" -lt "${GITEA_LOCAL_ACCESS_WAIT_SECONDS}" ]]; do
    if gitea_local_access_service_has_endpoints "${service_name}"; then
      return 0
    fi
    sleep 1
    waited=$((waited + 1))
  done

  gitea_local_access_fail "timed out waiting for ready endpoints for service/${service_name}"
}

gitea_local_access_forwarded_port() {
  local log_file="$1"

  sed -nE 's/.*:([0-9]+)[[:space:]]+->[[:space:]]*[0-9]+$/\1/p' "${log_file}" 2>/dev/null | head -n 1
}

gitea_local_access_wait_for_forward_port() {
  local label="$1"
  local pid="$2"
  local log_file="$3"
  local waited=0
  local port=""

  while [[ "${waited}" -lt "${GITEA_LOCAL_ACCESS_WAIT_SECONDS}" ]]; do
    port="$(gitea_local_access_forwarded_port "${log_file}")"
    if [[ -n "${port}" ]]; then
      printf '%s\n' "${port}"
      return 0
    fi
    if ! kill -0 "${pid}" >/dev/null 2>&1; then
      if [[ -f "${log_file}" ]]; then
        cat "${log_file}" >&2 || true
      fi
      gitea_local_access_fail "${label} port-forward exited before reporting a local port"
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done

  if [[ -f "${log_file}" ]]; then
    cat "${log_file}" >&2 || true
  fi
  gitea_local_access_fail "timed out waiting for ${label} port-forward to report a local port"
}

gitea_local_access_wait_for_tcp() {
  local label="$1"
  local host="$2"
  local port="$3"
  local pid="$4"
  local log_file="$5"
  local waited=0

  while [[ "${waited}" -lt "${GITEA_LOCAL_ACCESS_WAIT_SECONDS}" ]]; do
    if gitea_local_access_tcp_open "${host}" "${port}"; then
      return 0
    fi
    if ! kill -0 "${pid}" >/dev/null 2>&1; then
      if [[ -f "${log_file}" ]]; then
        cat "${log_file}" >&2 || true
      fi
      gitea_local_access_fail "${label} port-forward exited before becoming ready"
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done

  if [[ -f "${log_file}" ]]; then
    cat "${log_file}" >&2 || true
  fi
  gitea_local_access_fail "timed out waiting for ${label} port-forward on ${host}:${port}"
}

gitea_local_access_start_forward() {
  local label="$1"
  local service_name="$2"
  local remote_port="$3"
  local host="$4"
  local port_var="$5"
  local port log_file pid

  log_file="$(mktemp "${TMPDIR:-/tmp}/gitea-local-access-${label}.XXXXXX")"

  gitea_local_access_require_cmd kubectl || return 1
  gitea_local_access_wait_for_service_endpoints "${service_name}" || return 1

  gitea_local_access_kubectl -n "${GITEA_NAMESPACE}" port-forward \
    --address "${host}" \
    "svc/${service_name}" \
    ":${remote_port}" >"${log_file}" 2>&1 &
  pid=$!

  if ! port="$(gitea_local_access_wait_for_forward_port "${label}" "${pid}" "${log_file}")"; then
    kill "${pid}" >/dev/null 2>&1 || true
    wait "${pid}" >/dev/null 2>&1 || true
    return 1
  fi

  if ! gitea_local_access_wait_for_tcp "${label}" "${host}" "${port}" "${pid}" "${log_file}"; then
    kill "${pid}" >/dev/null 2>&1 || true
    wait "${pid}" >/dev/null 2>&1 || true
    return 1
  fi

  GITEA_LOCAL_ACCESS_PIDS+=("${pid}")
  GITEA_LOCAL_ACCESS_LOGS+=("${log_file}")
  printf -v "${port_var}" '%s' "${port}"
  return 0
}

gitea_local_access_setup_nodeport() {
  local require="${1:-both}"
  local nodeport_host

  nodeport_host="$(gitea_local_access_rewrite_loopback_host "${GITEA_LOCAL_ACCESS_HOST}")"

  if [[ "${require}" == "http" || "${require}" == "both" ]]; then
    if [[ "${GITEA_LOCAL_ACCESS_HTTP_READY}" != "1" ]]; then
      : "${GITEA_HTTP_NODE_PORT:=30090}"
      export GITEA_HTTP_BASE="$(gitea_local_access_rewrite_loopback_base "${GITEA_HTTP_BASE:-http://${nodeport_host}:${GITEA_HTTP_NODE_PORT}}")"
      GITEA_LOCAL_ACCESS_HTTP_READY=1
    fi
  fi

  if [[ "${require}" == "ssh" || "${require}" == "both" ]]; then
    if [[ "${GITEA_LOCAL_ACCESS_SSH_READY}" != "1" ]]; then
      : "${GITEA_SSH_NODE_PORT:=30022}"
      export GITEA_SSH_HOST="$(gitea_local_access_rewrite_loopback_host "${GITEA_SSH_HOST:-${nodeport_host}}")"
      export GITEA_SSH_PORT="${GITEA_SSH_PORT:-${GITEA_SSH_NODE_PORT}}"
      GITEA_LOCAL_ACCESS_SSH_READY=1
    fi
  fi
}

gitea_local_access_setup_port_forward() {
  local require="${1:-both}"
  local http_port ssh_port

  if [[ "${require}" == "http" || "${require}" == "both" ]]; then
    if [[ "${GITEA_LOCAL_ACCESS_HTTP_READY}" != "1" ]]; then
      gitea_local_access_start_forward "http" "${GITEA_HTTP_SERVICE}" "${GITEA_HTTP_SERVICE_PORT}" "127.0.0.1" http_port || return 1
      export GITEA_HTTP_BASE="http://127.0.0.1:${http_port}"
      GITEA_LOCAL_ACCESS_HTTP_READY=1
    fi
  fi

  if [[ "${require}" == "ssh" || "${require}" == "both" ]]; then
    if [[ "${GITEA_LOCAL_ACCESS_SSH_READY}" != "1" ]]; then
      gitea_local_access_start_forward "ssh" "${GITEA_SSH_SERVICE}" "${GITEA_SSH_SERVICE_PORT}" "127.0.0.1" ssh_port || return 1
      export GITEA_SSH_HOST="127.0.0.1"
      export GITEA_SSH_PORT="${ssh_port}"
      GITEA_LOCAL_ACCESS_SSH_READY=1
    fi
  fi
}

gitea_local_access_setup() {
  local require="${1:-both}"

  case "${require}" in
    http|ssh|both) ;;
    *)
      gitea_local_access_fail "unsupported access requirement: ${require}"
      return 1
      ;;
  esac

  case "${GITEA_LOCAL_ACCESS_MODE}" in
    nodeport)
      gitea_local_access_setup_nodeport "${require}"
      ;;
    port-forward)
      gitea_local_access_setup_port_forward "${require}"
      ;;
    *)
      gitea_local_access_fail "unsupported GITEA_LOCAL_ACCESS_MODE=${GITEA_LOCAL_ACCESS_MODE}"
      return 1
      ;;
  esac
}

gitea_local_access_reset() {
  local require="${1:-both}"

  if [[ "${GITEA_LOCAL_ACCESS_MODE}" == "port-forward" ]]; then
    gitea_local_access_cleanup || true
  fi

  gitea_local_access_setup "${require}"
}

gitea_local_access_cleanup() {
  local pid log_file

  for pid in "${GITEA_LOCAL_ACCESS_PIDS[@]:-}"; do
    if [[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1; then
      kill "${pid}" >/dev/null 2>&1 || true
    fi
  done

  for pid in "${GITEA_LOCAL_ACCESS_PIDS[@]:-}"; do
    if [[ -n "${pid}" ]]; then
      wait "${pid}" >/dev/null 2>&1 || true
    fi
  done

  for log_file in "${GITEA_LOCAL_ACCESS_LOGS[@]:-}"; do
    if [[ -n "${log_file}" && -f "${log_file}" ]]; then
      rm -f "${log_file}"
    fi
  done

  GITEA_LOCAL_ACCESS_PIDS=()
  GITEA_LOCAL_ACCESS_LOGS=()
  GITEA_LOCAL_ACCESS_HTTP_READY=0
  GITEA_LOCAL_ACCESS_SSH_READY=0
}
