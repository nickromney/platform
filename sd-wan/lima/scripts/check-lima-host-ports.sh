#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=/dev/null
source "${MODULE_DIR}/../../scripts/lib/shell-cli.sh"

fail() { echo "FAIL $*" >&2; exit 1; }
ok() { echo "OK   $*"; }

usage() {
  cat <<EOF
Usage: check-lima-host-ports.sh [--cloud-file PATH]... [--dry-run] [--execute]

Checks the host ports claimed by the SD-WAN Lima cloud definitions and fails on
planned overlaps or existing conflicting listeners.

Positional cloud definition paths are still accepted for compatibility.

$(shell_cli_standard_options)
EOF
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

parse_port_forwards_file() {
  local file="$1"
  local cloud
  local in_port_forwards=0
  local guest_port=""
  local host_ip=""
  local host_port=""
  local proto=""
  local emitted=0
  cloud="$(basename "${file}" .yaml)"

  emit_forward() {
    if [[ -z "${host_port}" ]]; then
      guest_port=""
      host_ip=""
      host_port=""
      proto=""
      emitted=0
      return
    fi

    if [[ -z "${host_ip}" ]]; then
      host_ip="0.0.0.0"
    fi
    if [[ -z "${proto}" ]]; then
      proto="tcp"
    fi
    if [[ -z "${guest_port}" ]]; then
      guest_port="?"
    fi

    printf '%s|%s|%s|%s|%s|%s\n' "${cloud}" "${host_ip}" "${host_port}" "${proto}" "${guest_port}" "${file}"
    guest_port=""
    host_ip=""
    host_port=""
    proto=""
    emitted=0
  }

  while IFS= read -r line || [[ -n "${line}" ]]; do
    case "${line}" in
      portForwards:)
        in_port_forwards=1
        continue
        ;;
    esac

    if [[ "${in_port_forwards}" -eq 0 ]]; then
      continue
    fi

    if [[ "${line}" != [[:space:]]* ]]; then
      emit_forward
      in_port_forwards=0
      continue
    fi

    if [[ "${line}" =~ ^[[:space:]]*-[[:space:]]+ ]]; then
      if [[ "${emitted}" -eq 1 ]]; then
        emit_forward
      fi
      emitted=1
    fi

    if [[ "${line}" =~ guestPort:[[:space:]]*([0-9]+) ]]; then
      guest_port="${BASH_REMATCH[1]}"
      emitted=1
    elif [[ "${line}" =~ hostIP:[[:space:]]*([^[:space:]]+) ]]; then
      host_ip="${BASH_REMATCH[1]//\"/}"
      host_ip="${host_ip//\'/}"
      emitted=1
    elif [[ "${line}" =~ hostPort:[[:space:]]*([0-9]+) ]]; then
      host_port="${BASH_REMATCH[1]}"
      emitted=1
    elif [[ "${line}" =~ proto:[[:space:]]*([^[:space:]]+) ]]; then
      proto="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')"
      proto="${proto//\"/}"
      proto="${proto//\'/}"
      emitted=1
    fi
  done < "${file}"

  emit_forward
}

listeners_for_port_lsof() {
  local bind_ip="$1"
  local port="$2"
  local proto="$3"
  local raw
  local header
  local body

  if [[ "${proto}" == "tcp" ]]; then
    raw="$(lsof -nP -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null || true)"
  else
    raw="$(lsof -nP -iUDP:"${port}" 2>/dev/null || true)"
  fi

  [[ -n "${raw}" ]] || return 1

  if [[ "${bind_ip}" == "0.0.0.0" ]]; then
    printf '%s\n' "${raw}"
    return 0
  fi

  header="$(printf '%s\n' "${raw}" | sed -n '1p')"
  body="$(
    printf '%s\n' "${raw}" | tail -n +2 | \
      grep -E "(^|[[:space:]])(\\*:${port}|${bind_ip//./\\.}:${port}|127\\.0\\.0\\.1:${port}|localhost:${port}|\\[::1\\]:${port}|::1:${port})([[:space:]]|$)" || true
  )"
  [[ -n "${body}" ]] || return 1
  printf '%s\n%s\n' "${header}" "${body}"
}

listeners_for_port_ss() {
  local bind_ip="$1"
  local port="$2"
  local proto="$3"
  local body
  local header

  if [[ "${proto}" == "tcp" ]]; then
    body="$(ss -H -ltn "sport = :${port}" 2>/dev/null || true)"
    header="State Recv-Q Send-Q Local Address:Port Peer Address:Port"
  else
    body="$(ss -H -lun "sport = :${port}" 2>/dev/null || true)"
    header="State Recv-Q Send-Q Local Address:Port Peer Address:Port"
  fi

  [[ -n "${body}" ]] || return 1

  if [[ "${bind_ip}" != "0.0.0.0" ]]; then
    body="$(
      printf '%s\n' "${body}" | awk -v port="${port}" -v bind_ip="${bind_ip}" '
        {
          local_addr = $5
          if (local_addr == "") {
            local_addr = $4
          }
          if (
            local_addr == "*:" port ||
            local_addr == bind_ip ":" port ||
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

  printf '%s\n%s\n' "${header}" "${body}"
}

listeners_for_port() {
  local bind_ip="$1"
  local port="$2"
  local proto="$3"

  if have_cmd lsof; then
    listeners_for_port_lsof "${bind_ip}" "${port}" "${proto}"
    return $?
  fi

  if have_cmd ss; then
    listeners_for_port_ss "${bind_ip}" "${port}" "${proto}"
    return $?
  fi

  fail "neither lsof nor ss found in PATH; cannot verify Lima host port availability"
}

cloud_is_running() {
  local cloud="$1"
  have_cmd limactl || return 1
  [[ "$(limactl list --format '{{.Name}} {{.Status}}' 2>/dev/null | awk -v target="${cloud}" '$1 == target { print $2; exit }')" == "Running" ]]
}

listeners_belong_to_running_cloud() {
  local cloud="$1"
  local listeners="$2"
  local commands

  cloud_is_running "${cloud}" || return 1

  commands="$(
    printf '%s\n' "${listeners}" | tail -n +2 | awk '{print $1}' | sort -u
  )"
  [[ -n "${commands}" ]] || return 1
  [[ "${commands}" == "limactl" ]]
}

binds_overlap() {
  local left_ip="$1"
  local left_port="$2"
  local left_proto="$3"
  local right_ip="$4"
  local right_port="$5"
  local right_proto="$6"

  [[ "${left_proto}" == "${right_proto}" ]] || return 1
  [[ "${left_port}" == "${right_port}" ]] || return 1
  [[ "${left_ip}" == "${right_ip}" || "${left_ip}" == "0.0.0.0" || "${right_ip}" == "0.0.0.0" ]]
}

docker_publishers_for_port() {
  local bind_ip="$1"
  local port="$2"
  local proto="$3"

  have_cmd docker || return 0

  docker ps --format '{{.Names}}	{{.Ports}}' 2>/dev/null | while IFS=$'\t' read -r name ports; do
    [[ -n "${ports}" ]] || continue

  if [[ "${bind_ip}" == "0.0.0.0" ]]; then
    if [[ "${ports}" == *"0.0.0.0:${port}->"*"/${proto}"* || "${ports}" == *"[::]:${port}->"*"/${proto}"* ]]; then
      printf '%s\t%s\n' "${name}" "${ports}"
    fi
    continue
  fi

    if [[ "${ports}" == *"${bind_ip}:${port}->"*"/${proto}"* || "${ports}" == *"0.0.0.0:${port}->"*"/${proto}"* || "${ports}" == *"[::]:${port}->"*"/${proto}"* || "${ports}" == *"127.0.0.1:${port}->"*"/${proto}"* || "${ports}" == *"[::1]:${port}->"*"/${proto}"* ]]; then
      printf '%s\t%s\n' "${name}" "${ports}"
    fi
  done
}

print_docker_publishers() {
  local bind_ip="$1"
  local port="$2"
  local proto="$3"
  local publishers

  publishers="$(docker_publishers_for_port "${bind_ip}" "${port}" "${proto}" || true)"
  [[ -n "${publishers}" ]] || return 0

  echo "Conflicting Docker publishers:" >&2
  while IFS=$'\t' read -r name ports; do
    [[ -n "${name}" ]] || continue
    echo "  - ${name}: ${ports}" >&2
  done <<<"${publishers}"
}

cloud_files=()
shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --cloud-file)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--cloud-file"
        exit 1
      }
      cloud_files+=("$2")
      shift 2
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        cloud_files+=("$1")
        shift
      done
      ;;
    -*)
      shell_cli_unknown_flag "$(shell_cli_script_name)" "$1"
      exit 1
      ;;
    *)
      cloud_files+=("$1")
      shift
      ;;
  esac
done

if [[ "${#cloud_files[@]}" -gt 0 ]]; then
  :
elif [[ -n "${LIMA_CLOUD_FILES:-}" ]]; then
  read -r -a cloud_files <<<"${LIMA_CLOUD_FILES}"
else
  cloud_files=(
    "${MODULE_DIR}/cloud1.yaml"
    "${MODULE_DIR}/cloud2.yaml"
    "${MODULE_DIR}/cloud3.yaml"
  )
fi

if [[ "${SHELL_CLI_DRY_RUN}" -eq 1 ]]; then
  shell_cli_print_dry_run_summary "would check Lima host port availability for ${#cloud_files[@]} cloud definition file(s)"
  exit 0
fi

checks=()
for file in "${cloud_files[@]}"; do
  [[ -f "${file}" ]] || fail "missing cloud definition: ${file}"
  while IFS= read -r line; do
    [[ -n "${line}" ]] && checks+=("${line}")
  done < <(parse_port_forwards_file "${file}")
done

[[ "${#checks[@]}" -gt 0 ]] || fail "no Lima host port forwards found"

conflicts=0

for ((i = 0; i < ${#checks[@]}; i += 1)); do
  IFS='|' read -r left_cloud left_ip left_port left_proto left_guest _left_source <<<"${checks[$i]}"
  for ((j = i + 1; j < ${#checks[@]}; j += 1)); do
    IFS='|' read -r right_cloud right_ip right_port right_proto right_guest _right_source <<<"${checks[$j]}"
    if binds_overlap "${left_ip}" "${left_port}" "${left_proto}" "${right_ip}" "${right_port}" "${right_proto}"; then
      echo "FAIL planned Lima host port overlap: ${left_cloud} (${left_proto} ${left_ip}:${left_port}, guest ${left_guest}) conflicts with ${right_cloud} (${right_proto} ${right_ip}:${right_port}, guest ${right_guest})" >&2
      conflicts=1
    fi
  done
done

for check in "${checks[@]}"; do
  IFS='|' read -r cloud bind_ip port proto guest_port source <<<"${check}"
  listeners="$(listeners_for_port "${bind_ip}" "${port}" "${proto}" || true)"
  if [[ -n "${listeners}" ]]; then
    if listeners_belong_to_running_cloud "${cloud}" "${listeners}"; then
      ok "${cloud} host port ${proto} ${bind_ip}:${port} already owned by running ${cloud} instance"
      continue
    fi
    echo "FAIL ${cloud} host port ${proto} ${bind_ip}:${port} is already in use" >&2
    echo "Planned mapping: $(basename "${source}") guestPort=${guest_port} -> ${proto} ${bind_ip}:${port}" >&2
    print_docker_publishers "${bind_ip}" "${port}" "${proto}"
    echo "${listeners}" >&2
    conflicts=1
  fi
done

if [[ "${conflicts}" -ne 0 ]]; then
  exit 1
fi

summary=()
for check in "${checks[@]}"; do
  IFS='|' read -r cloud bind_ip port proto guest_port _source <<<"${check}"
  summary+=("${cloud}:${proto}:${bind_ip}:${port}->${guest_port}")
done

ok "lima host ports available: ${summary[*]}"
