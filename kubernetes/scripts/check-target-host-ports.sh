#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../scripts/lib/shell-cli.sh"

fail() { echo "FAIL $*" >&2; exit 1; }
ok() { echo "OK   $*"; }

TARGET_LABEL="${TARGET_LABEL:-target}"
PORT_CHECKS="${PORT_CHECKS:-}"

usage() {
  cat <<EOF
Usage: check-target-host-ports.sh [--var-file PATH]... [--dry-run] [--execute]

Checks whether the host ports required for a target are free.

Set TARGET_LABEL and PORT_CHECKS in the environment. PORT_CHECKS must be a
newline-separated list of:

  name|bind_ip|host_var|host_default|target_var|target_default

Use an empty host_var or target_var to treat the corresponding default as a
literal, non-tfvars-backed port.

$(shell_cli_standard_options)
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

if [[ "${SHELL_CLI_DRY_RUN}" -eq 1 ]]; then
  shell_cli_print_dry_run_summary "would check ${TARGET_LABEL} host ports using ${#TFVARS_FILES[@]} tfvars file(s)"
  exit 0
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
    if binds_overlap "${left_ip}" "${left_port}" "${right_ip}" "${right_port}"; then
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
  listeners="$(listeners_for_port "${bind_ip}" "${port}" || true)"
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
