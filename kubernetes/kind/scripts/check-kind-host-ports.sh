#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL $*" >&2; exit 1; }
ok() { echo "OK   $*"; }

usage() {
  cat <<'EOF'
Usage: check-kind-host-ports.sh [--var-file PATH]...

Checks whether the host ports required for a new kind-local cluster are free.
Pass the same tfvars files that will be used for `make kind apply`.
EOF
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

tfvar_value_and_source() {
  local key="$1"
  local fallback="$2"
  local file
  local value=""
  local source="<default>"

  for file in "${TFVARS_FILES[@]}"; do
    [[ -f "${file}" ]] || continue
    local match_line
    match_line="$(grep -nE "^[[:space:]]*${key}[[:space:]]*=" "${file}" 2>/dev/null | tail -n 1 || true)"
    [[ -n "${match_line}" ]] || continue

    local line_no="${match_line%%:*}"
    local line_text="${match_line#*:}"
    local match
    match="$(
      printf '%s\n' "${line_text}" | \
        sed -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"?([^\"#]+)\"?.*$/\1/" | \
        xargs || true
    )"
    if [[ -n "${match}" ]]; then
      value="${match}"
      source="${file}:${line_no}"
    fi
  done

  if [[ -z "${value}" ]]; then
    value="${fallback}"
  fi

  printf '%s|%s\n' "${value}" "${source}"
}

tfvar_or_default() {
  local key="$1"
  local fallback="$2"
  local resolved
  local value

  resolved="$(tfvar_value_and_source "${key}" "${fallback}")"
  value="${resolved%%|*}"
  printf '%s\n' "${value}"
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
    printf '%s\n' "${raw}" | tail -n +2 | awk -v port="${port}" '
      {
        name = $NF
        if (
          name == "*:" port ||
          name == "127.0.0.1:" port ||
          name == "localhost:" port ||
          name == "[::1]:" port ||
          name == "::1:" port
        ) {
          print
        }
      }
    '
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

binds_overlap() {
  local left_ip="$1"
  local left_port="$2"
  local right_ip="$3"
  local right_port="$4"

  [[ "${left_port}" == "${right_port}" ]] || return 1
  [[ "${left_ip}" == "${right_ip}" || "${left_ip}" == "0.0.0.0" || "${right_ip}" == "0.0.0.0" ]]
}

docker_publishers_for_port() {
  local bind_ip="$1"
  local port="$2"

  have_cmd docker || return 0

  docker ps --format '{{.Names}}	{{.Ports}}' 2>/dev/null | while IFS=$'\t' read -r name ports; do
    [[ -n "${ports}" ]] || continue

    if [[ "${bind_ip}" == "0.0.0.0" ]]; then
      if [[ "${ports}" == *"0.0.0.0:${port}->"* || "${ports}" == *"[::]:${port}->"* ]]; then
        printf '%s\t%s\n' "${name}" "${ports}"
      fi
      continue
    fi

    if [[ "${ports}" == *"127.0.0.1:${port}->"* || "${ports}" == *"[::1]:${port}->"* ]]; then
      printf '%s\t%s\n' "${name}" "${ports}"
    fi
  done
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

TFVARS_FILES=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --var-file)
      [[ $# -ge 2 ]] || fail "--var-file requires a path"
      TFVARS_FILES+=("$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

checks=(
  "gateway-https|0.0.0.0|$(tfvar_or_default gateway_https_host_port 443)|gateway_https_host_port|$(tfvar_or_default gateway_https_node_port 30070)|gateway_https_node_port"
  "argocd|0.0.0.0|$(tfvar_or_default argocd_server_node_port 30080)|argocd_server_node_port|$(tfvar_or_default argocd_server_node_port 30080)|argocd_server_node_port"
  "hubble-ui|0.0.0.0|$(tfvar_or_default hubble_ui_node_port 31235)|hubble_ui_node_port|$(tfvar_or_default hubble_ui_node_port 31235)|hubble_ui_node_port"
  "gitea-http|0.0.0.0|$(tfvar_or_default gitea_http_node_port 30090)|gitea_http_node_port|$(tfvar_or_default gitea_http_node_port 30090)|gitea_http_node_port"
  "gitea-ssh|0.0.0.0|$(tfvar_or_default gitea_ssh_node_port 30022)|gitea_ssh_node_port|$(tfvar_or_default gitea_ssh_node_port 30022)|gitea_ssh_node_port"
  "grafana-ui|0.0.0.0|$(tfvar_or_default grafana_ui_host_port 3302)|grafana_ui_host_port|$(tfvar_or_default grafana_ui_node_port 30302)|grafana_ui_node_port"
  "api-server|127.0.0.1|$(tfvar_or_default kind_api_server_port 6443)|kind_api_server_port|$(tfvar_or_default kind_api_server_port 6443)|kind_api_server_port"
)

conflicts=0

for ((i = 0; i < ${#checks[@]}; i += 1)); do
  IFS='|' read -r left_name left_ip left_port _left_host_var _left_target_port _left_target_var <<<"${checks[$i]}"
  for ((j = i + 1; j < ${#checks[@]}; j += 1)); do
    IFS='|' read -r right_name right_ip right_port _right_host_var _right_target_port _right_target_var <<<"${checks[$j]}"
    if binds_overlap "${left_ip}" "${left_port}" "${right_ip}" "${right_port}"; then
      echo "FAIL planned kind host port overlap: ${left_name} (${left_ip}:${left_port}) conflicts with ${right_name} (${right_ip}:${right_port})" >&2
      conflicts=1
    fi
  done
done

for check in "${checks[@]}"; do
  IFS='|' read -r name bind_ip port host_var target_port target_var <<<"${check}"
  host_source="$(tfvar_value_and_source "${host_var}" "${port}")"
  host_source="${host_source#*|}"
  target_source="$(tfvar_value_and_source "${target_var}" "${target_port}")"
  target_source="${target_source#*|}"
  listeners="$(listeners_for_port "${bind_ip}" "${port}" || true)"
  if [[ -n "${listeners}" ]]; then
    echo "FAIL ${name} host port ${bind_ip}:${port} is already in use" >&2
    echo "Planned mapping: ${host_var}=${port} (${host_source}) -> kind node port ${target_var}=${target_port} (${target_source})" >&2
    print_docker_publishers "${bind_ip}" "${port}"
    echo "${listeners}" >&2
    conflicts=1
  fi
done

if [[ "${conflicts}" -ne 0 ]]; then
  echo "Resolve the conflicting listeners or override the relevant kind host ports in a local tfvars file before running apply." >&2
  exit 1
fi

ok "kind host ports available: 0.0.0.0:$(tfvar_or_default gateway_https_host_port 443), 0.0.0.0:$(tfvar_or_default argocd_server_node_port 30080), 0.0.0.0:$(tfvar_or_default hubble_ui_node_port 31235), 0.0.0.0:$(tfvar_or_default gitea_http_node_port 30090), 0.0.0.0:$(tfvar_or_default gitea_ssh_node_port 30022), 0.0.0.0:$(tfvar_or_default grafana_ui_host_port 3302), 127.0.0.1:$(tfvar_or_default kind_api_server_port 6443)"
