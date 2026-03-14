#!/usr/bin/env bash

if [[ -n "${GITEA_LOCAL_ACCESS_HELPER_LOADED:-}" ]]; then
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

gitea_local_access_random_port() {
  local python_bin=""
  if command -v python3 >/dev/null 2>&1; then
    python_bin="python3"
  elif command -v python >/dev/null 2>&1; then
    python_bin="python"
  else
    gitea_local_access_fail "python3 or python is required to allocate a free localhost port"
    return 1
  fi
  "${python_bin}" - <<'PY'
import socket

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
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

  port="$(gitea_local_access_random_port)" || return 1
  log_file="$(mktemp "${TMPDIR:-/tmp}/gitea-local-access-${label}.XXXXXX")"

  gitea_local_access_require_cmd kubectl || return 1
  gitea_local_access_wait_for_service_endpoints "${service_name}" || return 1

  gitea_local_access_kubectl -n "${GITEA_NAMESPACE}" port-forward \
    --address "${host}" \
    "svc/${service_name}" \
    "${port}:${remote_port}" >"${log_file}" 2>&1 &
  pid=$!

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

  if [[ "${require}" == "http" || "${require}" == "both" ]]; then
    if [[ "${GITEA_LOCAL_ACCESS_HTTP_READY}" != "1" ]]; then
      : "${GITEA_HTTP_NODE_PORT:=30090}"
      export GITEA_HTTP_BASE="${GITEA_HTTP_BASE:-http://${GITEA_LOCAL_ACCESS_HOST}:${GITEA_HTTP_NODE_PORT}}"
      GITEA_LOCAL_ACCESS_HTTP_READY=1
    fi
  fi

  if [[ "${require}" == "ssh" || "${require}" == "both" ]]; then
    if [[ "${GITEA_LOCAL_ACCESS_SSH_READY}" != "1" ]]; then
      : "${GITEA_SSH_NODE_PORT:=30022}"
      export GITEA_SSH_HOST="${GITEA_SSH_HOST:-${GITEA_LOCAL_ACCESS_HOST}}"
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
