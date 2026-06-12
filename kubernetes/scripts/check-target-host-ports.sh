#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../scripts/lib/shell-cli.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../scripts/lib/host-port-listeners.sh"

fail() { echo "FAIL $*" >&2; exit 1; }
ok() { echo "OK   $*"; }

TARGET_LABEL="${TARGET_LABEL:-target}"
PORT_CHECKS="${PORT_CHECKS:-}"
VARIANT_JSON=""

usage() {
  shell_cli_usage_line " [--variant-json PATH] [--var-file PATH]... [--dry-run] [--execute]"
  cat <<EOF
Checks whether the host ports required for a target are free.

Pass --variant-json to derive the preflight rows from the variant manifest.
For compatibility, callers may still set TARGET_LABEL and PORT_CHECKS in the
environment. PORT_CHECKS must be a newline-separated list of:

  name|bind_ip|host_var|host_default|target_var|target_default

Use an empty host_var or target_var to treat the corresponding default as a
literal, non-tfvars-backed port.

Options:
  --variant-json PATH  Kubernetes variant.json file to read for host-access facts

$(shell_cli_standard_options)
EOF
}

tfvar_value_and_source() {
  local key="$1"
  local fallback="$2"
  local file
  local value=""
  local source="<default>"

  if [[ -z "${key}" ]]; then
    printf '%s|%s\n' "${fallback}" "<literal>"
    return 0
  fi

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

variant_json_value() {
  local query="$1"

  jq -r "${query} // empty" "${VARIANT_JSON}"
}

variant_shared_host_ports_contains() {
  local port="$1"

  jq -e --argjson port "${port}" '(.host_access_path.shared_host_ports // []) | index($port)' "${VARIANT_JSON}" >/dev/null
}

append_port_check() {
  local row="$1"

  if [[ -z "${PORT_CHECKS}" ]]; then
    PORT_CHECKS="${row}"
    return 0
  fi

  PORT_CHECKS+=$'\n'"${row}"
}

append_admin_port_check_if_shared() {
  local name="$1"
  local bind_ip="$2"
  local host_var="$3"
  local host_default="$4"
  local target_var="$5"
  local target_default="$6"

  variant_shared_host_ports_contains "${host_default}" || return 0
  append_port_check "${name}|${bind_ip}|${host_var}|${host_default}|${target_var}|${target_default}"
}

populate_port_checks_from_variant_json() {
  [[ -f "${VARIANT_JSON}" ]] || fail "Missing variant manifest: ${VARIANT_JSON}"
  command -v jq >/dev/null 2>&1 || fail "Missing required tool: jq"

  local variant_id
  local variant_label
  local mode
  local gateway_bind_ip="127.0.0.1"
  local gateway_host_port
  local gateway_target_port
  local expose_admin_nodeports

  variant_id="$(variant_json_value '.id')"
  variant_label="$(variant_json_value '.label')"
  mode="$(variant_json_value '.host_access_path.mode')"
  gateway_host_port="$(variant_json_value '.host_access_path.gateway_host_port')"
  gateway_target_port="$(variant_json_value '.host_access_path.gateway_target_port')"

  [[ -n "${variant_id}" ]] || fail "Missing variant id in ${VARIANT_JSON}"
  [[ -n "${mode}" ]] || fail "Missing host_access_path.mode in ${VARIANT_JSON}"
  [[ -n "${gateway_host_port}" ]] || fail "Missing host_access_path.gateway_host_port in ${VARIANT_JSON}"
  [[ -n "${gateway_target_port}" ]] || gateway_target_port="${gateway_host_port}"

  if [[ "${TARGET_LABEL}" == "target" ]]; then
    TARGET_LABEL="${variant_label:-${variant_id}}"
  fi

  if [[ "${mode}" == "kind-nodeports" ]]; then
    gateway_bind_ip="$(tfvar_or_default "gateway_https_listen_address" "127.0.0.1")"
  fi

  append_port_check "gateway-https|${gateway_bind_ip}|gateway_https_host_port|${gateway_host_port}|gateway_https_node_port|${gateway_target_port}"

  if [[ "${variant_id}" == "kind" ]]; then
    append_port_check "api-server|127.0.0.1|kind_api_server_port|6443|kind_api_server_port|6443"
  fi

  expose_admin_nodeports="$(tfvar_or_default "expose_admin_nodeports" "true")"
  [[ "${expose_admin_nodeports}" == "true" ]] || return 0

  append_admin_port_check_if_shared "argocd" "127.0.0.1" "argocd_server_node_port" "30080" "argocd_server_node_port" "30080"
  append_admin_port_check_if_shared "hubble-ui" "127.0.0.1" "hubble_ui_node_port" "31235" "hubble_ui_node_port" "31235"
  append_admin_port_check_if_shared "gitea-http" "127.0.0.1" "gitea_http_node_port" "30090" "gitea_http_node_port" "30090"
  append_admin_port_check_if_shared "gitea-ssh" "127.0.0.1" "gitea_ssh_node_port" "30022" "gitea_ssh_node_port" "30022"
  if [[ "${variant_id}" != "kind" ]]; then
    append_admin_port_check_if_shared "signoz-ui" "127.0.0.1" "signoz_ui_host_port" "3301" "signoz_ui_node_port" "30301"
  fi
  append_admin_port_check_if_shared "grafana-ui" "127.0.0.1" "grafana_ui_host_port" "3302" "grafana_ui_node_port" "30302"
}

docker_publishers_for_port() {
  local bind_ip="$1"
  local port="$2"

  host_port_have_cmd docker || return 0

  docker ps --format '{{.Names}}	{{.Ports}}' 2>/dev/null | while IFS=$'\t' read -r name ports; do
    [[ -n "${ports}" ]] || continue

    if [[ "${bind_ip}" == "0.0.0.0" ]]; then
      if [[ "${ports}" == *"0.0.0.0:${port}->"* || "${ports}" == *"[::]:${port}->"* ]]; then
        printf '%s\t%s\n' "${name}" "${ports}"
      fi
      continue
    fi

    if [[ "${ports}" == *"0.0.0.0:${port}->"* || "${ports}" == *"[::]:${port}->"* || "${ports}" == *"127.0.0.1:${port}->"* || "${ports}" == *"[::1]:${port}->"* ]]; then
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
shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --var-file)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--var-file"
        exit 1
      }
      TFVARS_FILES+=("$2")
      shift 2
      ;;
    --variant-json)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--variant-json"
        exit 1
      }
      VARIANT_JSON="$2"
      shift 2
      ;;
    --)
      shift
      break
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
  "would check ${TARGET_LABEL} host ports using ${#TFVARS_FILES[@]} tfvars file(s)"

if [[ -n "${VARIANT_JSON}" ]]; then
  populate_port_checks_from_variant_json
fi

[[ -n "${PORT_CHECKS}" ]] || fail "PORT_CHECKS is required"

checks=()
while IFS= read -r raw; do
  [[ -n "${raw}" ]] || continue
  [[ "${raw}" =~ ^# ]] && continue
  IFS='|' read -r name bind_ip host_var host_default target_var target_default <<<"${raw}"
  [[ -n "${name}" && -n "${bind_ip}" ]] || fail "Invalid PORT_CHECKS row: ${raw}"

  resolved_host="$(tfvar_value_and_source "${host_var}" "${host_default}")"
  host_port="${resolved_host%%|*}"
  host_source="${resolved_host#*|}"
  resolved_target="$(tfvar_value_and_source "${target_var}" "${target_default}")"
  target_port="${resolved_target%%|*}"
  target_source="${resolved_target#*|}"

  [[ -n "${host_port}" ]] || fail "Missing host port for ${name}"
  [[ -n "${target_port}" ]] || target_port="${host_port}"

  checks+=("${name}|${bind_ip}|${host_port}|${host_var}|${host_source}|${target_port}|${target_var}|${target_source}")
done <<<"${PORT_CHECKS}"

conflicts=0

for ((i = 0; i < ${#checks[@]}; i += 1)); do
  IFS='|' read -r left_name left_ip left_port _left_host_var _left_host_source _left_target_port _left_target_var _left_target_source <<<"${checks[$i]}"
  for ((j = i + 1; j < ${#checks[@]}; j += 1)); do
    IFS='|' read -r right_name right_ip right_port _right_host_var _right_host_source _right_target_port _right_target_var _right_target_source <<<"${checks[$j]}"
    if host_port_binds_overlap "${left_ip}" "${left_port}" "${right_ip}" "${right_port}"; then
      echo "FAIL planned ${TARGET_LABEL} host port overlap: ${left_name} (${left_ip}:${left_port}) conflicts with ${right_name} (${right_ip}:${right_port})" >&2
      conflicts=1
    fi
  done
done

success_ports=()
for check in "${checks[@]}"; do
  IFS='|' read -r name bind_ip port host_var host_source target_port target_var target_source <<<"${check}"
  host_label="${host_var:-literal_host_port}"
  target_label="${target_var:-literal_target_port}"
  if listeners="$(host_port_listeners_for_port "${bind_ip}" "${port}")"; then
    :
  else
    listener_status=$?
    [[ "${listener_status}" -eq 127 ]] && fail "neither lsof nor ss found in PATH; cannot verify host port availability"
    listeners=""
  fi
  if [[ -n "${listeners}" ]]; then
    echo "FAIL ${name} host port ${bind_ip}:${port} is already in use" >&2
    echo "Planned mapping: ${host_label}=${port} (${host_source}) -> ${TARGET_LABEL} node port ${target_label}=${target_port} (${target_source})" >&2
    print_docker_publishers "${bind_ip}" "${port}"
    echo "${listeners}" >&2
    conflicts=1
    continue
  fi
  success_ports+=("${bind_ip}:${port}")
done

if [[ "${conflicts}" -ne 0 ]]; then
  echo "Resolve the conflicting listeners or override the relevant ${TARGET_LABEL} host ports in a local tfvars file before running apply." >&2
  exit 1
fi

ok "${TARGET_LABEL} host ports available: $(IFS=', '; printf '%s' "${success_ports[*]}")"
