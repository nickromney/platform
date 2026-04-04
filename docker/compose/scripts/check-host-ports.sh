#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

fail() {
  echo "FAIL $*" >&2
  exit 1
}

ok() {
  echo "OK   $*"
}

usage() {
  cat <<EOF
Usage: check-host-ports.sh [--mode MODE] [--dry-run] [--execute]

Checks whether the published docker/compose host ports are available.

Modes:
  current    Check the default compose port bindings.
  https-443  Check whether host port 443 is free for direct HTTPS binding.

$(shell_cli_standard_options)
EOF
}

MODE="current"
shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --mode)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--mode"
        exit 1
      }
      MODE="$2"
      shift 2
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

shell_cli_maybe_execute_or_preview_summary usage \
  "would check docker/compose host port availability in ${MODE} mode"

COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-compose}"
COMPOSE_EDGE_HTTP_PORT="${COMPOSE_EDGE_HTTP_PORT:-8088}"
COMPOSE_EDGE_HTTPS_PORT="${COMPOSE_EDGE_HTTPS_PORT:-8443}"
COMPOSE_DEX_DEBUG_PORT="${COMPOSE_DEX_DEBUG_PORT:-8300}"
COMPOSE_APIM_HEALTH_PORT="${COMPOSE_APIM_HEALTH_PORT:-8302}"

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

listeners_for_port_lsof() {
  local bind_ip="$1"
  local port="$2"
  local raw
  local header
  local body

  raw="$(lsof -nP -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null || true)"
  [[ -n "${raw}" ]] || return 1

  if [[ "${bind_ip}" == "0.0.0.0" ]]; then
    printf '%s\n' "${raw}"
    return 0
  fi

  header="$(printf '%s\n' "${raw}" | sed -n '1p')"
  body="$(
    printf '%s\n' "${raw}" | tail -n +2 | \
      grep -E "(^|[[:space:]])(\\*:${port}|127\\.0\\.0\\.1:${port}|localhost:${port}|\\[::1\\]:${port}|::1:${port})([[:space:]]|$)" || true
  )"
  [[ -n "${body}" ]] || return 1
  printf '%s\n%s\n' "${header}" "${body}"
}

listeners_for_port_ss() {
  local bind_ip="$1"
  local port="$2"
  local body

  body="$(ss -H -ltn "sport = :${port}" 2>/dev/null || true)"
  [[ -n "${body}" ]] || return 1

  if [[ "${bind_ip}" == "127.0.0.1" ]]; then
    body="$(
      printf '%s\n' "${body}" | awk -v port="${port}" '
        {
          local_addr = $4
          if (
            local_addr == "*:" port ||
            local_addr == "127.0.0.1:" port ||
            local_addr == "[::1]:" port ||
            local_addr == "::1:" port
          ) {
            print
          }
        }
      '
    )"
    [[ -n "${body}" ]] || return 1
  fi

  printf 'State Recv-Q Send-Q Local Address:Port Peer Address:Port\n%s\n' "${body}"
}

listeners_for_port() {
  local bind_ip="$1"
  local port="$2"

  if have_cmd lsof; then
    listeners_for_port_lsof "${bind_ip}" "${port}"
    return $?
  fi

  if have_cmd ss; then
    listeners_for_port_ss "${bind_ip}" "${port}"
    return $?
  fi

  fail "neither lsof nor ss found in PATH; cannot verify host port availability"
}

docker_publishers_for_port() {
  local bind_ip="$1"
  local port="$2"
  local label_filter="${3:-}"

  have_cmd docker || return 0

  local docker_args=(ps --format '{{.Names}}	{{.Ports}}')
  if [[ -n "${label_filter}" ]]; then
    docker_args+=(--filter "label=${label_filter}")
  fi

  docker "${docker_args[@]}" 2>/dev/null | while IFS=$'\t' read -r name ports; do
    [[ -n "${ports}" ]] || continue

    if [[ "${bind_ip}" == "0.0.0.0" ]]; then
      if [[ "${ports}" == *"0.0.0.0:${port}->"* || "${ports}" == *"[::]:${port}->"* || "${ports}" == *"127.0.0.1:${port}->"* || "${ports}" == *"[::1]:${port}->"* ]]; then
        printf '%s\t%s\n' "${name}" "${ports}"
      fi
      continue
    fi

    if [[ "${ports}" == *"0.0.0.0:${port}->"* || "${ports}" == *"[::]:${port}->"* || "${ports}" == *"127.0.0.1:${port}->"* || "${ports}" == *"[::1]:${port}->"* ]]; then
      printf '%s\t%s\n' "${name}" "${ports}"
    fi
  done
}

port_owned_by_current_project() {
  local bind_ip="$1"
  local port="$2"
  local all_publishers
  local project_publishers
  local line

  all_publishers="$(docker_publishers_for_port "${bind_ip}" "${port}" || true)"
  [[ -n "${all_publishers}" ]] || return 1

  project_publishers="$(
    docker_publishers_for_port "${bind_ip}" "${port}" "com.docker.compose.project=${COMPOSE_PROJECT_NAME}" || true
  )"
  [[ -n "${project_publishers}" ]] || return 1

  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    grep -Fqx "${line}" <<<"${project_publishers}" || return 1
  done <<<"${all_publishers}"

  return 0
}

print_docker_publishers() {
  local bind_ip="$1"
  local port="$2"
  local publishers

  publishers="$(docker_publishers_for_port "${bind_ip}" "${port}" || true)"
  [[ -n "${publishers}" ]] || return 0

  echo "Conflicting Docker publishers:" >&2
  while IFS=$'\t' read -r name ports; do
    [[ -n "${name}" ]] || continue
    echo "  - ${name}: ${ports}" >&2
  done <<<"${publishers}"
}

case "${MODE}" in
  current)
    checks=(
      "edge-http|0.0.0.0|${COMPOSE_EDGE_HTTP_PORT}|80"
      "edge-https|0.0.0.0|${COMPOSE_EDGE_HTTPS_PORT}|443"
      "dex-debug|0.0.0.0|${COMPOSE_DEX_DEBUG_PORT}|5556"
      "apim-health|0.0.0.0|${COMPOSE_APIM_HEALTH_PORT}|8000"
    )
    ;;
  https-443)
    checks=(
      "edge-https|0.0.0.0|443|443"
    )
    ;;
  *)
    fail "unsupported mode: ${MODE}"
    ;;
esac

conflicts=0
success_ports=()

for check in "${checks[@]}"; do
  IFS='|' read -r name bind_ip host_port container_port <<<"${check}"
  listeners="$(listeners_for_port "${bind_ip}" "${host_port}" || true)"

  if [[ -z "${listeners}" ]]; then
    success_ports+=("${bind_ip}:${host_port}")
    continue
  fi

  if [[ "${MODE}" == "current" ]] && port_owned_by_current_project "${bind_ip}" "${host_port}"; then
    success_ports+=("${bind_ip}:${host_port} (already owned by compose project ${COMPOSE_PROJECT_NAME})")
    continue
  fi

  echo "FAIL ${name} host port ${bind_ip}:${host_port} is already in use" >&2
  echo "Planned mapping: host ${bind_ip}:${host_port} -> compose container port ${container_port}" >&2
  print_docker_publishers "${bind_ip}" "${host_port}"
  echo "${listeners}" >&2
  conflicts=1
done

if [[ "${conflicts}" -ne 0 ]]; then
  if [[ "${MODE}" == "https-443" ]]; then
    echo "Resolve the conflicting listener before switching the Compose edge to direct HTTPS on :443." >&2
  else
    echo "Resolve the conflicting listeners before starting the Compose stack." >&2
  fi
  exit 1
fi

if [[ "${MODE}" == "https-443" ]]; then
  ok "compose direct HTTPS port available: $(IFS=', '; printf '%s' "${success_ports[*]}")"
else
  ok "compose host ports available: $(IFS=', '; printf '%s' "${success_ports[*]}")"
fi
