#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

CHECK_DOCKER_REGISTRY_AUTH_SCRIPT="${PLATFORM_STATUS_CHECK_DOCKER_REGISTRY_AUTH_SCRIPT:-${REPO_ROOT}/kubernetes/kind/scripts/check-docker-registry-auth.sh}"
KIND_KUBECONFIG_PATH="${PLATFORM_STATUS_KIND_KUBECONFIG_PATH:-${HOME}/.kube/kind-kind-local.yaml}"
LIMA_KUBECONFIG_PATH="${PLATFORM_STATUS_LIMA_KUBECONFIG_PATH:-${HOME}/.kube/limavm-k3s.yaml}"
SLICER_KUBECONFIG_PATH="${PLATFORM_STATUS_SLICER_KUBECONFIG_PATH:-${HOME}/.kube/slicer-k3s.yaml}"
SLICER_VM_NAME="${SLICER_VM_NAME:-slicer-1}"
output_format="human"
PLATFORM_SHARED_PORTS="${PLATFORM_STATUS_SHARED_PORTS:-443 30022 30080 30090 31235 3301 3302}"
PLATFORM_PROVIDER_PORTS="${PLATFORM_STATUS_PROVIDER_PORTS:-6443 ${PLATFORM_SHARED_PORTS}}"
PLATFORM_SDWAN_PORTS="${PLATFORM_STATUS_SDWAN_PORTS:-58081}"
PLATFORM_PROBE_PORTS="${PLATFORM_STATUS_PROBE_PORTS:-${PLATFORM_PROVIDER_PORTS} ${PLATFORM_SDWAN_PORTS}}"
PLATFORM_STATUS_PORTS_WRAP_WIDTH="${PLATFORM_STATUS_PORTS_WRAP_WIDTH:-20}"
PLATFORM_STATUS_CELL_WRAP_SENTINEL="__PLATFORM_CELL_WRAP__"

usage() {
  cat <<'EOF'
Usage: platform-status.sh [--output human|text|json] [--dry-run] [--execute]

Summarises local variant runtime status across:
  - kubernetes/kind
  - kubernetes/lima
  - kubernetes/slicer
  - sd-wan/lima
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

bool_json() {
  if [ "${1:-0}" -eq 1 ]; then
    printf 'true'
  else
    printf 'false'
  fi
}

append_line() {
  local var_name="$1"
  local value="${2:-}"
  local current=""

  [ -n "${value}" ] || return 0

  current="${!var_name-}"
  if [ -n "${current}" ]; then
    printf -v "${var_name}" '%s\n%s' "${current}" "${value}"
  else
    printf -v "${var_name}" '%s' "${value}"
  fi
}

first_non_empty_line() {
  local input="${1-}"

  [ -n "${input}" ] || return 0
  printf '%s\n' "${input}" | awk 'NF { print; exit }'
}

strip_status_prefix() {
  local input="${1-}"

  [ -n "${input}" ] || return 0
  printf '%s\n' "${input}" | sed -E 's/^(OK|WARN)[[:space:]]+//'
}

shared_host_ports_claimed_by() {
  printf 'shared host ports claimed by %s\n' "$1"
}

lima_vms_claimed_by() {
  printf 'Lima VMs claimed by %s\n' "$1"
}

registry_source_from_probe() {
  local probe_output="${1-}"

  case "${probe_output}" in
    *" via "*)
      printf '%s\n' "${probe_output}" | sed -nE 's/^.* via ([^[:space:]]+).*$/\1/p' | head -n 1
      ;;
    *" in "*config.json*)
      printf 'config.json\n'
      ;;
    *"Docker config not found"*)
      printf 'config.json missing\n'
      ;;
    *"uses "*", but it is not available on PATH"*)
      printf '%s\n' "${probe_output}" | sed -nE 's/^.* uses ([^[:space:]]+), but it is not available on PATH.*$/\1/p' | head -n 1
      ;;
    *)
      printf ''
      ;;
  esac
}

json_array_from_newline() {
  local input="${1-}"

  if [ -z "${input}" ]; then
    printf '[]'
    return 0
  fi

  printf '%s\n' "${input}" | jq -Rsc 'split("\n") | map(select(length > 0))'
}

docker_host_ports_for_pattern() {
  local docker_lines="${1-}"
  local name_pattern="${2-}"

  [ -n "${docker_lines}" ] || return 0
  printf '%s\n' "${docker_lines}" \
    | awk -F '|' -v pat="${name_pattern}" '$1 ~ pat { print $2 }' \
    | tr ',' '\n' \
    | sed -nE 's/^[[:space:]]*([^[:space:],]+:[0-9]+)->.*$/\1/p' \
    | LC_ALL=C sort -u
}

docker_running_name_ports() {
  local docker_lines="${1-}"

  [ -n "${docker_lines}" ] || return 0
  printf '%s\n' "${docker_lines}" | awk -F '|' '$2 ~ /^Up/ { print $1 "|" $3 }'
}

docker_name_exists() {
  local docker_lines="${1-}"
  local name_pattern="${2-}"

  [ -n "${docker_lines}" ] || return 1
  printf '%s\n' "${docker_lines}" | awk -F '|' -v pat="${name_pattern}" '$1 ~ pat { found=1 } END { exit found ? 0 : 1 }'
}

ports_include_number() {
  local ports_text="${1-}"
  local port_number="$2"

  [ -n "${ports_text}" ] || return 1
  printf '%s\n' "${ports_text}" | awk -F ':' -v port="${port_number}" '$NF == port { found=1 } END { exit found ? 0 : 1 }'
}

port_listener_output() {
  local port="$1"

  if have_cmd lsof; then
    lsof -nP -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null || true
    return 0
  fi

  if have_cmd ss; then
    ss -H -ltn "sport = :${port}" 2>/dev/null || true
    return 0
  fi

  printf ''
}

append_lines() {
  local var_name="$1"
  local value_lines="${2-}"
  local line=""

  [ -n "${value_lines}" ] || return 0

  while IFS= read -r line; do
    [ -n "${line}" ] || continue
    append_line "${var_name}" "${line}"
  done <<<"${value_lines}"
}

unique_sorted_lines() {
  local input="${1-}"

  [ -n "${input}" ] || return 0
  printf '%s\n' "${input}" | awk 'NF && !seen[$0]++ { print }' | LC_ALL=C sort
}

listener_addresses_from_lsof() {
  local input="${1-}"

  [ -n "${input}" ] || return 0
  printf '%s\n' "${input}" | awk '
    NR == 1 { next }
    {
      addr = ($NF == "(LISTEN)" && NF > 1) ? $(NF - 1) : $NF
      if (addr ~ /^\*:/) {
        sub(/^\*:/, "0.0.0.0:", addr)
      } else if (addr ~ /^localhost:/) {
        sub(/^localhost:/, "127.0.0.1:", addr)
      }
      if (addr ~ /:[0-9]+$/ || addr ~ /^\[[^]]+\]:[0-9]+$/) {
        print addr
      }
    }
  '
}

listener_addresses_from_ss() {
  local input="${1-}"

  [ -n "${input}" ] || return 0
  printf '%s\n' "${input}" | awk '
    {
      addr = ($4 != "" ? $4 : $5)
      if (addr ~ /^\*:/) {
        sub(/^\*:/, "0.0.0.0:", addr)
      } else if (addr ~ /^localhost:/) {
        sub(/^localhost:/, "127.0.0.1:", addr)
      }
      if (addr ~ /:[0-9]+$/ || addr ~ /^\[[^]]+\]:[0-9]+$/) {
        print addr
      }
    }
  '
}

listener_addresses_for_port() {
  local port="$1"
  local raw_output=""

  raw_output="$(port_listener_output "${port}")"
  [ -n "${raw_output}" ] || return 0

  if have_cmd lsof; then
    listener_addresses_from_lsof "${raw_output}"
    return 0
  fi

  if have_cmd ss; then
    listener_addresses_from_ss "${raw_output}"
    return 0
  fi
}

listener_addresses_for_ports() {
  local ports_text="${1-}"
  local port=""
  local combined=""
  local addresses=""

  [ -n "${ports_text}" ] || return 0

  for port in ${ports_text}; do
    addresses="$(listener_addresses_for_port "${port}")"
    append_lines combined "${addresses}"
  done

  unique_sorted_lines "${combined}"
}

filter_ports_by_numbers() {
  local ports_text="${1-}"
  local port_numbers="${2-}"

  [ -n "${ports_text}" ] || return 0
  [ -n "${port_numbers}" ] || return 0

  printf '%s\n' "${ports_text}" | awk -F ':' -v numbers="${port_numbers}" '
    BEGIN {
      split(numbers, wanted_numbers, /[[:space:]]+/)
      for (i in wanted_numbers) {
        if (wanted_numbers[i] != "") {
          wanted[wanted_numbers[i]] = 1
        }
      }
    }
    NF && wanted[$NF] {
      print $0
    }
  ' | LC_ALL=C sort -u
}

line_set_difference() {
  local input_text="${1-}"
  local exclude_text="${2-}"

  [ -n "${input_text}" ] || return 0

  if [ -z "${exclude_text}" ]; then
    unique_sorted_lines "${input_text}"
    return 0
  fi

  awk '
    NR == FNR {
      if (NF) {
        excluded[$0] = 1
      }
      next
    }
    NF && !excluded[$0] {
      print $0
    }
  ' <(printf '%s\n' "${exclude_text}") <(printf '%s\n' "${input_text}") | LC_ALL=C sort -u
}

append_foreign_port_blockers() {
  local var_name="$1"
  local ports_text="${2-}"
  local port=""

  [ -n "${ports_text}" ] || return 0

  while IFS= read -r port; do
    [ -n "${port}" ] || continue
    append_line "${var_name}" "${port} is already in use by a non-platform process"
  done <<<"${ports_text}"
}

limactl_state_for() {
  local limactl_list_output="${1-}"
  local target_name="$2"

  [ -n "${limactl_list_output}" ] || return 0
  printf '%s\n' "${limactl_list_output}" | awk -v target="${target_name}" 'NR > 1 && $1 == target { print $2; exit }'
}

limactl_has_prefix() {
  local limactl_list_output="${1-}"
  local prefix="$2"

  [ -n "${limactl_list_output}" ] || return 1
  printf '%s\n' "${limactl_list_output}" | awk -v prefix="${prefix}" 'NR > 1 && index($1, prefix) == 1 { found=1 } END { exit found ? 0 : 1 }'
}

limactl_running_prefix() {
  local limactl_list_output="${1-}"
  local prefix="$2"

  [ -n "${limactl_list_output}" ] || return 1
  printf '%s\n' "${limactl_list_output}" | awk -v prefix="${prefix}" 'NR > 1 && index($1, prefix) == 1 && $2 == "Running" { found=1 } END { exit found ? 0 : 1 }'
}

build_bootstrap_readiness_json() {
  local bootstrap_available="$1"
  local bootstrap_name="${2-}"

  jq -cn \
    --argjson bootstrap_client "$(bool_json "${bootstrap_available}")" \
    --arg bootstrap_client_name "${bootstrap_name}" \
    '{
      bootstrap_client: $bootstrap_client,
      bootstrap_client_name: (if $bootstrap_client_name == "" then null else $bootstrap_client_name end)
    }'
}

build_project_json() {
  local key="$1"
  local path="$2"
  local label="$3"
  local runtime_family="$4"
  local state="$5"
  local serving="$6"
  local runtime_present="$7"
  local kubeconfig_path="$8"
  local version="${9-}"
  local shared_ports_text="${10-}"
  local blockers_text="${11-}"
  local readiness_json="${12-}"

  jq -cn \
    --arg key "${key}" \
    --arg path "${path}" \
    --arg label "${label}" \
    --arg runtime_family "${runtime_family}" \
    --arg state "${state}" \
    --arg kubeconfig_path "${kubeconfig_path}" \
    --arg version "${version}" \
    --argjson serving "$(bool_json "${serving}")" \
    --argjson runtime_present "$(bool_json "${runtime_present}")" \
    --argjson shared_ports "$(json_array_from_newline "${shared_ports_text}")" \
    --argjson blockers "$(json_array_from_newline "${blockers_text}")" \
    --argjson readiness "${readiness_json}" \
    '{
      key: $key,
      path: $path,
      label: $label,
      runtime_family: $runtime_family,
      state: $state,
      serving: $serving,
      runtime_present: $runtime_present,
      kubeconfig_path: $kubeconfig_path,
      version: (if $version == "" then null else $version end),
      shared_ports: $shared_ports,
      blockers: $blockers,
      readiness: $readiness
    }'
}

build_runtime_json() {
  local name="$1"
  local available="$2"
  local running="$3"
  local detail="${4-}"

  jq -cn \
    --arg name "${name}" \
    --arg detail "${detail}" \
    --argjson available "$(bool_json "${available}")" \
    --argjson running "$(bool_json "${running}")" \
    '{
      name: $name,
      available: $available,
      running: $running,
      detail: (if $detail == "" then null else $detail end)
    }'
}

build_registry_auth_json() {
  local registry="$1"
  local authenticated="$2"
  local source="${3-}"
  local detail="${4-}"

  jq -cn \
    --arg registry "${registry}" \
    --arg source "${source}" \
    --arg detail "${detail}" \
    --argjson authenticated "$(bool_json "${authenticated}")" \
    '{
      registry: $registry,
      authenticated: $authenticated,
      source: (if $source == "" then null else $source end),
      detail: (if $detail == "" then null else $detail end)
    }'
}

kube_version_for() {
  local kubeconfig_path="$1"
  local kubeconfig_context="${2-}"

  [ -n "${kubeconfig_path}" ] || return 0
  [ -f "${kubeconfig_path}" ] || return 0
  have_cmd kubectl || return 0

  if [ -n "${kubeconfig_context}" ]; then
    KUBECONFIG="${kubeconfig_path}" kubectl --context "${kubeconfig_context}" get nodes -o jsonpath='{.items[0].status.nodeInfo.kubeletVersion}' --request-timeout=2s 2>/dev/null || true
  else
    KUBECONFIG="${kubeconfig_path}" kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.kubeletVersion}' --request-timeout=2s 2>/dev/null || true
  fi
}

render_status_table() {
  local json_payload="$1"

  jq -r \
    --arg wrap_sentinel "${PLATFORM_STATUS_CELL_WRAP_SENTINEL}" \
    --argjson ports_wrap_width "${PLATFORM_STATUS_PORTS_WRAP_WIDTH}" '
    def wrap_items($width; $sentinel):
      reduce .[] as $item (
        {lines: [], current: ""};
        if .current == "" then
          .current = $item
        elif ((.current | length) + 1 + ($item | length)) <= $width then
          .current += "," + $item
        else
          .lines += [.current] | .current = $item
        end
      )
      | (.lines + (if .current == "" then [] else [.current] end))
      | join($sentinel);

    def truncate_note($text):
      if ($text | length) > 56 then $text[0:53] + "..." else $text end;

    (["VARIANT", "STATE", "SERVE", "PRESENT", "VERSION", "PORTS", "CLAIMED BY", "NOTE"] | @tsv),
    (
      (.variants_order // .projects_order)[] as $key
      | ((.variants // .projects)[$key]) as $project
      | ($project.blockers[0] // "") as $blocker
      | (
          if ($blocker | test("^(?<claim>.+) claimed by (?<owner>.+)$")) then
            ($blocker | capture("^(?<claim>.+) claimed by (?<owner>.+)$"))
          else
            null
          end
        ) as $claim_match
      | [
          $project.path,
          $project.state,
          (if $project.serving then "Y" else "N" end),
          (if $project.runtime_present then "Y" else "N" end),
          ($project.version // "-"),
          (
            if ($project.shared_ports | length) > 0 then
              (
                $project.shared_ports
                | map(split(":") | last)
                | unique
                | wrap_items($ports_wrap_width; $wrap_sentinel)
              )
            else
              "-"
            end
          ),
          (
            if $claim_match then
              $claim_match.owner
            else
              "-"
            end
          ),
          (
            if $blocker == "" then
              "-"
            elif $claim_match then
              truncate_note($claim_match.claim)
            else
              truncate_note($blocker)
            end
          )
        ]
      | @tsv
    )
  ' <<<"${json_payload}" | render_tsv_table
}

render_runtime_table() {
  local json_payload="$1"

  jq -r '
    (["PLATFORM", "AVAIL", "RUNNING", "DETAIL"] | @tsv),
    (
      .platforms
      | to_entries
      | map(select(.value.available))
      | sort_by(.key)
      | .[] as $entry
      | $entry.value as $runtime
      | [
          $runtime.name,
          (if $runtime.available then "Y" else "N" end),
          (if $runtime.running then "Y" else "N" end),
          ($runtime.detail // "-")
        ]
      | @tsv
    )
  ' <<<"${json_payload}" | render_tsv_table
}

render_registry_auth_table() {
  local json_payload="$1"

  jq -r '
    (["REGISTRY", "AUTH", "SOURCE", "DETAIL"] | @tsv),
    (
      .registry_auth_order[] as $key
      | .registry_auth[$key] as $entry
      | [
          $entry.registry,
          (if $entry.authenticated then "Y" else "N" end),
          ($entry.source // "-"),
          ($entry.detail // "-")
        ]
      | @tsv
    )
  ' <<<"${json_payload}" | render_tsv_table
}

render_tsv_table() {
  awk -F $'\t' -v wrap_sentinel="${PLATFORM_STATUS_CELL_WRAP_SENTINEL}" '
    function repeat(char, count,    result, i) {
      result = ""
      for (i = 0; i < count; i++) {
        result = result char
      }
      return result
    }
    function split_cell(cell, lines,    count) {
      if (cell == "") {
        lines[1] = ""
        return 1
      }
      return split(cell, lines, wrap_sentinel)
    }
    {
      if (NF > max_nf) {
        max_nf = NF
      }
      for (i = 1; i <= NF; i++) {
        cells[NR, i] = $i
        line_count = split_cell($i, cell_lines)
        if (line_count > row_heights[NR]) {
          row_heights[NR] = line_count
        }
        for (line = 1; line <= line_count; line++) {
          if (length(cell_lines[line]) > widths[i]) {
            widths[i] = length(cell_lines[line])
          }
        }
      }
    }
    END {
      for (row = 1; row <= NR; row++) {
        row_height = row_heights[row]
        if (row_height < 1) {
          row_height = 1
        }
        for (line = 1; line <= row_height; line++) {
          for (i = 1; i <= max_nf; i++) {
            cell = cells[row, i]
            line_count = split_cell(cell, cell_lines)
            value = (line <= line_count ? cell_lines[line] : "")
            printf "%-*s", widths[i], value
            if (i < max_nf) {
              printf "  "
            } else {
              printf "\n"
            }
          }
        }
        if (row == 1) {
          for (i = 1; i <= max_nf; i++) {
            printf "%-*s", widths[i], repeat("-", widths[i])
            if (i < max_nf) {
              printf "  "
            } else {
              printf "\n"
            }
          }
        }
      }
    }
  '
}

build_action_json() {
  local id="$1"
  local label="$2"
  local variant="$3"
  local variant_path="$4"
  local enabled="$5"
  local reason="$6"
  local command="$7"
  local dangerous="$8"

  jq -cn \
    --arg id "${id}" \
    --arg label "${label}" \
    --arg variant "${variant}" \
    --arg variant_path "${variant_path}" \
    --arg reason "${reason}" \
    --arg command "${command}" \
    --argjson enabled "$(bool_json "${enabled}")" \
    --argjson dangerous "$(bool_json "${dangerous}")" \
    '{
      id: $id,
      label: $label,
      variant: $variant,
      variant_path: $variant_path,
      provider: $variant,
      project: $variant_path,
      enabled: $enabled,
      reason: (if $reason == "" then null else $reason end),
      command: $command,
      dangerous: $dangerous
    }'
}

render_human_output() {
  local json_payload="$1"
  local table_output=""
  local runtime_table=""
  local registry_auth_table=""

  table_output="$(render_status_table "${json_payload}")"
  runtime_table="$(render_runtime_table "${json_payload}")"
  registry_auth_table="$(render_registry_auth_table "${json_payload}")"

  jq -r '
    "Platform local runtime status",
    "",
    "Overall state: \(.overall_state)",
    "Active cluster variant: \((.active_cluster_variant_path // .active_provider_path // "none"))",
    "Active variant surface: \((.active_variant_path // .active_project_path // "none"))",
    (
      if (.foreign_ports | length) > 0 then
        "Foreign shared ports:\n" + ((.foreign_ports | map("  - " + .)) | join("\n"))
      else
        "Foreign shared ports: none"
      end
    )
  ' <<<"${json_payload}"
  printf '\nPlatforms:\n%s\n' "${runtime_table}"
  printf '\nRegistry auth (Docker config + credential helper probe):\n%s\n' "${registry_auth_table}"
  printf '\nTracked variants:\n%s\n' "${table_output}"
  jq -r '
    "",
    "Recommended actions:",
    (
      .actions
      | map(select(.enabled))
      | map("  - " + .command)
      | unique
      | .[:8]
      | if length > 0 then .[] else "  - make status" end
    )
  ' <<<"${json_payload}"
}

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --output)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--output"
        exit 1
      }
      output_format="${2:-}"
      shift 2
      ;;
    *)
      shell_cli_unknown_flag "$(shell_cli_script_name)" "$1"
      exit 1
      ;;
  esac
done

shell_cli_maybe_execute_or_preview_summary usage "would inspect local platform variant status"

case "${output_format}" in
  text)
    output_format="human"
    ;;
  human|json)
    ;;
  *)
    shell_cli_unexpected_arg "$(shell_cli_script_name)" "--output ${output_format}"
    exit 1
    ;;
esac

have_cmd jq || {
  echo "platform-status.sh: jq not found in PATH" >&2
  exit 1
}

docker_available=0
docker_daemon=0
docker_context=""
docker_ps_output=""
docker_ps_all_output=""
docker_runtime_detail=""
docker_ps_all_ok=0
if have_cmd docker; then
  docker_available=1
  docker_context="$(docker context show 2>/dev/null || true)"
  if docker_ps_all_output="$(docker ps -a --format '{{.Names}}|{{.Status}}|{{.Ports}}' 2>/dev/null)"; then
    docker_ps_all_ok=1
    docker_ps_output="$(docker_running_name_ports "${docker_ps_all_output}")"
  else
    docker_ps_all_output=""
    docker_ps_output=""
  fi
  if docker info >/dev/null 2>&1 || [ "${docker_ps_all_ok}" -eq 1 ]; then
    docker_daemon=1
    if [ -n "${docker_context}" ]; then
      docker_runtime_detail="context=${docker_context}"
    else
      docker_runtime_detail="daemon reachable"
    fi
  else
    docker_runtime_detail="daemon unreachable"
  fi
else
  docker_runtime_detail="docker not found"
fi

colima_available=0
colima_running=0
colima_runtime_detail=""
if have_cmd colima; then
  colima_available=1
  if colima_status_output="$(colima status 2>&1)"; then
    colima_running=1
    colima_runtime_detail="$(first_non_empty_line "${colima_status_output}")"
    if [ -z "${colima_runtime_detail}" ]; then
      colima_runtime_detail="colima status ok"
    fi
  else
    colima_runtime_detail="$(first_non_empty_line "${colima_status_output:-}")"
    if [ -z "${colima_runtime_detail}" ]; then
      colima_runtime_detail="colima not running"
    fi
  fi
else
  colima_runtime_detail="colima not found"
fi

podman_available=0
podman_running=0
podman_runtime_detail=""
if have_cmd podman; then
  podman_available=1
  if podman_info_output="$(podman info 2>&1)"; then
    podman_running=1
    podman_runtime_detail="$(first_non_empty_line "${podman_info_output}")"
    if [ -z "${podman_runtime_detail}" ]; then
      podman_runtime_detail="podman info ok"
    fi
  else
    podman_runtime_detail="$(first_non_empty_line "${podman_info_output:-}")"
    if [ -z "${podman_runtime_detail}" ]; then
      podman_runtime_detail="podman not running"
    fi
  fi
else
  podman_runtime_detail="podman not found"
fi

kind_available=0
kind_clusters=""
if have_cmd kind; then
  kind_available=1
  kind_clusters="$(kind get clusters 2>/dev/null || true)"
fi

limactl_available=0
limactl_list_output=""
if have_cmd limactl; then
  limactl_available=1
  limactl_list_output="$(limactl list 2>/dev/null || true)"
fi

slicer_available=0
slicer_endpoint_reachable=0
slicer_vm_list_json='[]'
if have_cmd slicer; then
  slicer_available=1
  if slicer_vm_list_json="$(slicer vm list --json 2>/dev/null)"; then
    slicer_endpoint_reachable=1
  else
    slicer_vm_list_json='[]'
  fi
fi

bootstrap_client_available=0
bootstrap_client_name=""
for candidate in "${K3SUP_PRO_BIN:-}" "$(command -v k3sup-pro 2>/dev/null || true)" "${K3SUP_BIN:-}" "$(command -v k3sup 2>/dev/null || true)" "${HOME}/.arkade/bin/k3sup"; do
  [ -n "${candidate}" ] || continue
  [ -x "${candidate}" ] || continue
  bootstrap_client_available=1
  bootstrap_client_name="$(basename "${candidate}")"
  break
done

kind_ports="$(docker_host_ports_for_pattern "${docker_ps_output}" '^kind-local-(control-plane|worker([0-9]+)?)$' || true)"
kind_ports="$(unique_sorted_lines "${kind_ports}")"
kind_runtime_present=0
kind_running=0
if [ -n "${kind_clusters}" ] || [ -n "${kind_ports}" ] || docker_name_exists "${docker_ps_all_output}" '^kind-local-(control-plane|worker([0-9]+)?)$'; then
  kind_runtime_present=1
fi
if docker_name_exists "${docker_ps_output}" '^kind-local-control-plane$'; then
  kind_running=1
fi

lima_runtime_present=0
lima_running=0
if limactl_has_prefix "${limactl_list_output}" 'k3s-node-'; then
  lima_runtime_present=1
fi
if limactl_running_prefix "${limactl_list_output}" 'k3s-node-'; then
  lima_running=1
fi

slicer_runtime_present=0
slicer_running=0
slicer_paused=0
slicer_vm_state=""
if [ "${slicer_endpoint_reachable}" -eq 1 ]; then
  slicer_vm_state="$(jq -r --arg vm "${SLICER_VM_NAME}" '.[] | select(.hostname == $vm) | .status // empty' <<<"${slicer_vm_list_json}" | head -n 1 || true)"
  if [ -n "${slicer_vm_state}" ]; then
    slicer_runtime_present=1
  fi
  if [ "${slicer_vm_state}" = "Running" ]; then
    slicer_running=1
  fi
  if [ "${slicer_vm_state}" = "Paused" ]; then
    slicer_paused=1
  fi
fi

sdwan_present_count=0
sdwan_running_count=0
for cloud in cloud1 cloud2 cloud3; do
  cloud_state="$(limactl_state_for "${limactl_list_output}" "${cloud}")"
  if [ -n "${cloud_state}" ]; then
    sdwan_present_count=$((sdwan_present_count + 1))
  fi
  if [ "${cloud_state}" = "Running" ]; then
    sdwan_running_count=$((sdwan_running_count + 1))
  fi
done
sdwan_runtime_present=0
if [ "${sdwan_present_count}" -gt 0 ]; then
  sdwan_runtime_present=1
fi

lima_ports=""
if [ "${lima_running}" -eq 1 ]; then
  lima_ports="$(listener_addresses_for_ports "${PLATFORM_PROVIDER_PORTS}" || true)"
fi
lima_ports="$(unique_sorted_lines "${lima_ports}")"

slicer_ports=""
if [ "${slicer_running}" -eq 1 ]; then
  slicer_ports="$(listener_addresses_for_ports "${PLATFORM_PROVIDER_PORTS}" || true)"
fi
slicer_ports="$(unique_sorted_lines "${slicer_ports}")"

sdwan_ports=""
if [ "${sdwan_runtime_present}" -eq 1 ] || [ -n "$(listener_addresses_for_ports "${PLATFORM_SDWAN_PORTS}" || true)" ]; then
  sdwan_ports="$(listener_addresses_for_ports "${PLATFORM_SDWAN_PORTS}" || true)"
fi
sdwan_ports="$(unique_sorted_lines "${sdwan_ports}")"

kind_serving=0
if ports_include_number "${kind_ports}" 443; then
  kind_serving=1
fi

lima_serving=0
if ports_include_number "${lima_ports}" 443; then
  lima_serving=1
fi

slicer_serving=0
if ports_include_number "${slicer_ports}" 443; then
  slicer_serving=1
fi

sdwan_serving=0
if [ "${sdwan_running_count}" -eq 3 ] && ports_include_number "${sdwan_ports}" 58081; then
  sdwan_serving=1
fi

kind_version="$(kube_version_for "${KIND_KUBECONFIG_PATH}" 'kind-kind-local')"
lima_version="$(kube_version_for "${LIMA_KUBECONFIG_PATH}" 'limavm-k3s')"
slicer_version="$(kube_version_for "${SLICER_KUBECONFIG_PATH}" 'slicer-k3s')"
sdwan_version=""

kind_state="absent"
if [ "${kind_runtime_present}" -eq 1 ]; then
  if [ "${kind_running}" -eq 1 ] && [ "${kind_serving}" -eq 1 ]; then
    kind_state="running"
  elif [ "${kind_running}" -eq 1 ]; then
    kind_state="degraded"
  else
    kind_state="stopped"
  fi
fi

lima_state="absent"
if [ "${lima_runtime_present}" -eq 1 ]; then
  if [ "${lima_running}" -eq 1 ] && [ "${lima_serving}" -eq 1 ]; then
    lima_state="running"
  elif [ "${lima_running}" -eq 1 ]; then
    lima_state="degraded"
  else
    lima_state="stopped"
  fi
fi

slicer_state="absent"
if [ "${slicer_runtime_present}" -eq 1 ]; then
  if [ "${slicer_paused}" -eq 1 ]; then
    slicer_state="paused"
  elif [ "${slicer_running}" -eq 1 ] && [ "${slicer_serving}" -eq 1 ]; then
    slicer_state="running"
  elif [ "${slicer_running}" -eq 1 ]; then
    slicer_state="degraded"
  else
    slicer_state="stopped"
  fi
fi

sdwan_state="absent"
if [ "${sdwan_runtime_present}" -eq 1 ]; then
  if [ "${sdwan_running_count}" -eq 0 ]; then
    sdwan_state="stopped"
  elif [ "${sdwan_running_count}" -lt 3 ]; then
    sdwan_state="degraded"
  elif [ "${sdwan_serving}" -eq 1 ]; then
    sdwan_state="running"
  else
    sdwan_state="degraded"
  fi
fi

all_project_ports=""
append_lines all_project_ports "${kind_ports}"
append_lines all_project_ports "${lima_ports}"
append_lines all_project_ports "${slicer_ports}"
append_lines all_project_ports "${sdwan_ports}"
all_project_ports="$(unique_sorted_lines "${all_project_ports}")"

probe_listener_ports="$(listener_addresses_for_ports "${PLATFORM_PROBE_PORTS}" || true)"
foreign_ports="$(line_set_difference "${probe_listener_ports}" "${all_project_ports}")"

lima_platform_running=0
if [ "${lima_running}" -eq 1 ] || [ "${sdwan_running_count}" -gt 0 ]; then
  lima_platform_running=1
fi
lima_platform_detail=""
if [ "${limactl_available}" -eq 1 ]; then
  lima_instances="$(printf '%s\n' "${limactl_list_output}" | awk 'NR > 1 { printf("%s%s:%s", (count++ ? "," : ""), $1, $2) }')"
  if [ -n "${lima_instances}" ]; then
    lima_platform_detail="instances=${lima_instances}"
  else
    lima_platform_detail="no Lima instances"
  fi
else
  lima_platform_detail="limactl not found"
fi

slicer_platform_detail=""
if [ "${slicer_available}" -ne 1 ]; then
  slicer_platform_detail="slicer not found"
elif [ "${slicer_endpoint_reachable}" -ne 1 ]; then
  slicer_platform_detail="endpoint unreachable"
elif [ -n "${slicer_vm_state}" ]; then
  slicer_platform_detail="vm=${SLICER_VM_NAME}:${slicer_vm_state}"
else
  slicer_platform_detail="endpoint reachable"
fi

kind_dhi_auth=0
kind_dhi_auth_source=""
kind_dhi_auth_detail=""
kind_docker_hub_auth=0
kind_docker_hub_auth_source=""
kind_docker_hub_auth_detail=""
if [ -x "${CHECK_DOCKER_REGISTRY_AUTH_SCRIPT}" ]; then
  if dhi_auth_probe_output="$("${CHECK_DOCKER_REGISTRY_AUTH_SCRIPT}" --execute dhi.io "Docker Hardened Images (dhi.io)" 2>&1)"; then
    kind_dhi_auth=1
  fi
  if docker_hub_auth_probe_output="$("${CHECK_DOCKER_REGISTRY_AUTH_SCRIPT}" --execute index.docker.io "Docker Hub" 2>&1)"; then
    kind_docker_hub_auth=1
  fi
else
  dhi_auth_probe_output="Docker auth probe helper is unavailable"
  docker_hub_auth_probe_output="Docker auth probe helper is unavailable"
fi
kind_dhi_auth_source="$(registry_source_from_probe "${dhi_auth_probe_output}")"
kind_dhi_auth_detail="$(strip_status_prefix "$(first_non_empty_line "${dhi_auth_probe_output}")")"
kind_docker_hub_auth_source="$(registry_source_from_probe "${docker_hub_auth_probe_output}")"
kind_docker_hub_auth_detail="$(strip_status_prefix "$(first_non_empty_line "${docker_hub_auth_probe_output}")")"

kind_foreign_ports="$(filter_ports_by_numbers "${foreign_ports}" "${PLATFORM_PROVIDER_PORTS}")"
lima_foreign_ports="$(filter_ports_by_numbers "${foreign_ports}" "${PLATFORM_PROVIDER_PORTS}")"
slicer_foreign_ports="$(filter_ports_by_numbers "${foreign_ports}" "${PLATFORM_PROVIDER_PORTS}")"
sdwan_foreign_ports="$(filter_ports_by_numbers "${foreign_ports}" "${PLATFORM_SDWAN_PORTS}")"

kind_blockers=""
if [ "${docker_available}" -ne 1 ]; then
  append_line kind_blockers 'docker not found in PATH'
elif [ "${docker_daemon}" -ne 1 ]; then
  append_line kind_blockers 'Docker daemon not reachable'
fi
if [ "${kind_available}" -ne 1 ]; then
  append_line kind_blockers 'kind not found in PATH'
fi
if [ "${kind_dhi_auth}" -ne 1 ]; then
  append_line kind_blockers 'Docker Hardened Images (dhi.io) auth missing'
fi
if [ "${kind_docker_hub_auth}" -ne 1 ]; then
  append_line kind_blockers 'Docker Hub auth missing'
fi
if [ "${lima_state}" = "running" ] || [ "${lima_state}" = "degraded" ]; then
  append_line kind_blockers "$(shared_host_ports_claimed_by 'kubernetes/lima')"
fi
if [ "${slicer_state}" = "running" ] || [ "${slicer_state}" = "degraded" ]; then
  append_line kind_blockers "$(shared_host_ports_claimed_by 'kubernetes/slicer')"
fi
append_foreign_port_blockers kind_blockers "${kind_foreign_ports}"

lima_blockers=""
if [ "${docker_available}" -ne 1 ]; then
  append_line lima_blockers 'docker not found in PATH'
elif [ "${docker_daemon}" -ne 1 ]; then
  append_line lima_blockers 'Docker daemon not reachable'
fi
if [ "${limactl_available}" -ne 1 ]; then
  append_line lima_blockers 'limactl not found in PATH'
fi
if [ "${bootstrap_client_available}" -ne 1 ]; then
  append_line lima_blockers 'bootstrap client not found (k3sup-pro or k3sup)'
fi
if [ "${kind_state}" = "running" ] || [ "${kind_state}" = "degraded" ]; then
  append_line lima_blockers "$(shared_host_ports_claimed_by 'kubernetes/kind')"
fi
if [ "${slicer_state}" = "running" ] || [ "${slicer_state}" = "degraded" ]; then
  append_line lima_blockers "$(shared_host_ports_claimed_by 'kubernetes/slicer')"
fi
if [ "${sdwan_state}" = "running" ] || [ "${sdwan_state}" = "degraded" ]; then
  append_line lima_blockers "$(lima_vms_claimed_by 'sd-wan/lima')"
fi
append_foreign_port_blockers lima_blockers "${lima_foreign_ports}"

slicer_blockers=""
if [ "${docker_available}" -ne 1 ]; then
  append_line slicer_blockers 'docker not found in PATH'
elif [ "${docker_daemon}" -ne 1 ]; then
  append_line slicer_blockers 'Docker daemon not reachable'
fi
if [ "${slicer_available}" -ne 1 ]; then
  append_line slicer_blockers 'slicer not found in PATH'
fi
if [ "${slicer_available}" -eq 1 ] && [ "${slicer_endpoint_reachable}" -ne 1 ]; then
  append_line slicer_blockers 'Slicer endpoint is not reachable'
fi
if [ "${bootstrap_client_available}" -ne 1 ]; then
  append_line slicer_blockers 'bootstrap client not found (k3sup-pro or k3sup)'
fi
if [ "${kind_state}" = "running" ] || [ "${kind_state}" = "degraded" ]; then
  append_line slicer_blockers "$(shared_host_ports_claimed_by 'kubernetes/kind')"
fi
if [ "${lima_state}" = "running" ] || [ "${lima_state}" = "degraded" ]; then
  append_line slicer_blockers "$(shared_host_ports_claimed_by 'kubernetes/lima')"
fi
append_foreign_port_blockers slicer_blockers "${slicer_foreign_ports}"

sdwan_blockers=""
if [ "${limactl_available}" -ne 1 ]; then
  append_line sdwan_blockers 'limactl not found in PATH'
fi
if [ "${lima_state}" = "running" ] || [ "${lima_state}" = "degraded" ]; then
  append_line sdwan_blockers "$(lima_vms_claimed_by 'kubernetes/lima')"
fi
append_foreign_port_blockers sdwan_blockers "${sdwan_foreign_ports}"

docker_runtime_json="$(build_runtime_json docker "${docker_available}" "${docker_daemon}" "${docker_runtime_detail}")"
colima_runtime_json="$(build_runtime_json colima "${colima_available}" "${colima_running}" "${colima_runtime_detail}")"
podman_runtime_json="$(build_runtime_json podman "${podman_available}" "${podman_running}" "${podman_runtime_detail}")"
lima_platform_json="$(build_runtime_json lima "${limactl_available}" "${lima_platform_running}" "${lima_platform_detail}")"
slicer_platform_json="$(build_runtime_json slicer "${slicer_available}" "${slicer_running}" "${slicer_platform_detail}")"

dhi_registry_auth_json="$(build_registry_auth_json dhi.io "${kind_dhi_auth}" "${kind_dhi_auth_source}" "${kind_dhi_auth_detail}")"
docker_io_registry_auth_json="$(build_registry_auth_json docker.io "${kind_docker_hub_auth}" "${kind_docker_hub_auth_source}" "${kind_docker_hub_auth_detail}")"

kind_readiness_json="$(jq -cn \
  --argjson docker_available "$(bool_json "${docker_available}")" \
  --argjson docker_daemon "$(bool_json "${docker_daemon}")" \
  --arg docker_context "${docker_context}" \
  --argjson kind_available "$(bool_json "${kind_available}")" \
  --argjson dhi_auth "$(bool_json "${kind_dhi_auth}")" \
  --argjson docker_hub_auth "$(bool_json "${kind_docker_hub_auth}")" \
  '{
    docker_available: $docker_available,
    docker_daemon: $docker_daemon,
    docker_context: (if $docker_context == "" then null else $docker_context end),
    kind_available: $kind_available,
    dhi_auth: $dhi_auth,
    docker_hub_auth: $docker_hub_auth
  }')"

lima_readiness_json="$(jq -cn \
  --argjson docker_available "$(bool_json "${docker_available}")" \
  --argjson docker_daemon "$(bool_json "${docker_daemon}")" \
  --arg docker_context "${docker_context}" \
  --argjson limactl_available "$(bool_json "${limactl_available}")" \
  --argjson bootstrap_client "$(bool_json "${bootstrap_client_available}")" \
  --arg bootstrap_client_name "${bootstrap_client_name}" \
  '{
    docker_available: $docker_available,
    docker_daemon: $docker_daemon,
    docker_context: (if $docker_context == "" then null else $docker_context end),
    limactl_available: $limactl_available,
    bootstrap_client: $bootstrap_client,
    bootstrap_client_name: (if $bootstrap_client_name == "" then null else $bootstrap_client_name end)
  }')"

slicer_readiness_json="$(jq -cn \
  --argjson docker_available "$(bool_json "${docker_available}")" \
  --argjson docker_daemon "$(bool_json "${docker_daemon}")" \
  --arg docker_context "${docker_context}" \
  --argjson slicer_available "$(bool_json "${slicer_available}")" \
  --argjson slicer_endpoint_reachable "$(bool_json "${slicer_endpoint_reachable}")" \
  --argjson bootstrap_client "$(bool_json "${bootstrap_client_available}")" \
  --arg bootstrap_client_name "${bootstrap_client_name}" \
  '{
    docker_available: $docker_available,
    docker_daemon: $docker_daemon,
    docker_context: (if $docker_context == "" then null else $docker_context end),
    slicer_available: $slicer_available,
    slicer_endpoint_reachable: $slicer_endpoint_reachable,
    bootstrap_client: $bootstrap_client,
    bootstrap_client_name: (if $bootstrap_client_name == "" then null else $bootstrap_client_name end)
  }')"

sdwan_readiness_json="$(jq -cn \
  --argjson limactl_available "$(bool_json "${limactl_available}")" \
  --argjson listener_58081 "$(bool_json "$( ports_include_number "${sdwan_ports}" 58081 && printf 1 || printf 0 )")" \
  '{
    limactl_available: $limactl_available,
    listener_58081: $listener_58081
  }')"

kind_project_json="$(build_project_json kind kubernetes/kind 'Kind local cluster' docker "${kind_state}" "${kind_serving}" "${kind_runtime_present}" "${KIND_KUBECONFIG_PATH}" "${kind_version}" "${kind_ports}" "${kind_blockers}" "${kind_readiness_json}")"
lima_project_json="$(build_project_json lima kubernetes/lima 'Kubernetes Lima cluster' lima "${lima_state}" "${lima_serving}" "${lima_runtime_present}" "${LIMA_KUBECONFIG_PATH}" "${lima_version}" "${lima_ports}" "${lima_blockers}" "${lima_readiness_json}")"
slicer_project_json="$(build_project_json slicer kubernetes/slicer 'Slicer local cluster' slicer "${slicer_state}" "${slicer_serving}" "${slicer_runtime_present}" "${SLICER_KUBECONFIG_PATH}" "${slicer_version}" "${slicer_ports}" "${slicer_blockers}" "${slicer_readiness_json}")"
sdwan_project_json="$(build_project_json sdwan_lima sd-wan/lima 'SD-WAN Lima lab' lima "${sdwan_state}" "${sdwan_serving}" "${sdwan_runtime_present}" "" "${sdwan_version}" "${sdwan_ports}" "${sdwan_blockers}" "${sdwan_readiness_json}")"

active_provider=""
active_provider_path=""
serving_provider_count=0
for provider_key in kind lima slicer; do
  provider_serving="$(jq -r --arg key "${provider_key}" '.[$key].serving' <<<"$(jq -cn \
    --argjson kind "${kind_project_json}" \
    --argjson lima "${lima_project_json}" \
    --argjson slicer "${slicer_project_json}" \
    '{kind: $kind, lima: $lima, slicer: $slicer}')")"
  if [ "${provider_serving}" = "true" ]; then
    serving_provider_count=$((serving_provider_count + 1))
    active_provider="${provider_key}"
  fi
done

overall_state="idle"
if [ "${serving_provider_count}" -gt 1 ]; then
  overall_state="conflict"
  active_provider=""
elif [ -n "${active_provider}" ]; then
  overall_state="running"
fi

if [ -n "${active_provider}" ]; then
  case "${active_provider}" in
    kind) active_provider_path="kubernetes/kind" ;;
    lima) active_provider_path="kubernetes/lima" ;;
    slicer) active_provider_path="kubernetes/slicer" ;;
  esac
elif [ "${sdwan_serving}" -eq 1 ]; then
  overall_state="running"
fi

if [ "${overall_state}" != "conflict" ] && [ "${overall_state}" != "running" ]; then
  if [ "${kind_runtime_present}" -eq 1 ] || [ "${lima_runtime_present}" -eq 1 ] || [ "${slicer_runtime_present}" -eq 1 ] || [ "${sdwan_runtime_present}" -eq 1 ]; then
    overall_state="running"
  fi
fi

active_project=""
active_project_path=""
if [ -n "${active_provider}" ]; then
  active_project="${active_provider}"
  active_project_path="${active_provider_path}"
elif [ "${sdwan_serving}" -eq 1 ]; then
  active_project="sdwan_lima"
  active_project_path="sd-wan/lima"
fi

active_cluster_variant="${active_provider}"
active_cluster_variant_path="${active_provider_path}"
active_variant="${active_project}"
active_variant_path="${active_project_path}"

kind_apply_100_enabled=1
kind_apply_100_reason=""
if [ "${docker_available}" -ne 1 ]; then
  kind_apply_100_enabled=0
  kind_apply_100_reason='docker not found in PATH'
elif [ "${docker_daemon}" -ne 1 ]; then
  kind_apply_100_enabled=0
  kind_apply_100_reason='Docker daemon not reachable'
elif [ "${kind_available}" -ne 1 ]; then
  kind_apply_100_enabled=0
  kind_apply_100_reason='kind not found in PATH'
elif [ "${lima_state}" = "running" ] || [ "${lima_state}" = "degraded" ]; then
  kind_apply_100_enabled=0
  kind_apply_100_reason="$(shared_host_ports_claimed_by 'kubernetes/lima')"
elif [ "${slicer_state}" = "running" ] || [ "${slicer_state}" = "degraded" ]; then
  kind_apply_100_enabled=0
  kind_apply_100_reason="$(shared_host_ports_claimed_by 'kubernetes/slicer')"
elif [ -n "${kind_foreign_ports}" ]; then
  kind_apply_100_enabled=0
  kind_apply_100_reason="$(first_non_empty_line "${kind_foreign_ports}") is already in use by another process"
fi

kind_apply_900_enabled="${kind_apply_100_enabled}"
kind_apply_900_reason="${kind_apply_100_reason}"
if [ "${kind_apply_900_enabled}" -eq 1 ] && [ "${kind_dhi_auth}" -ne 1 ]; then
  kind_apply_900_enabled=0
  kind_apply_900_reason='Docker Hardened Images (dhi.io) auth missing'
fi
if [ "${kind_apply_900_enabled}" -eq 1 ] && [ "${kind_docker_hub_auth}" -ne 1 ]; then
  kind_apply_900_enabled=0
  kind_apply_900_reason='Docker Hub auth missing'
fi

lima_apply_100_enabled=1
lima_apply_100_reason=""
if [ "${docker_available}" -ne 1 ]; then
  lima_apply_100_enabled=0
  lima_apply_100_reason='docker not found in PATH'
elif [ "${docker_daemon}" -ne 1 ]; then
  lima_apply_100_enabled=0
  lima_apply_100_reason='Docker daemon not reachable'
elif [ "${limactl_available}" -ne 1 ]; then
  lima_apply_100_enabled=0
  lima_apply_100_reason='limactl not found in PATH'
elif [ "${bootstrap_client_available}" -ne 1 ]; then
  lima_apply_100_enabled=0
  lima_apply_100_reason='bootstrap client not found (k3sup-pro or k3sup)'
elif [ "${kind_state}" = "running" ] || [ "${kind_state}" = "degraded" ]; then
  lima_apply_100_enabled=0
  lima_apply_100_reason="$(shared_host_ports_claimed_by 'kubernetes/kind')"
elif [ "${slicer_state}" = "running" ] || [ "${slicer_state}" = "degraded" ]; then
  lima_apply_100_enabled=0
  lima_apply_100_reason="$(shared_host_ports_claimed_by 'kubernetes/slicer')"
elif [ "${sdwan_state}" = "running" ] || [ "${sdwan_state}" = "degraded" ]; then
  lima_apply_100_enabled=0
  lima_apply_100_reason="$(lima_vms_claimed_by 'sd-wan/lima')"
elif [ -n "${lima_foreign_ports}" ]; then
  lima_apply_100_enabled=0
  lima_apply_100_reason="$(first_non_empty_line "${lima_foreign_ports}") is already in use by another process"
fi
lima_apply_900_enabled="${lima_apply_100_enabled}"
lima_apply_900_reason="${lima_apply_100_reason}"

slicer_apply_100_enabled=1
slicer_apply_100_reason=""
if [ "${docker_available}" -ne 1 ]; then
  slicer_apply_100_enabled=0
  slicer_apply_100_reason='docker not found in PATH'
elif [ "${docker_daemon}" -ne 1 ]; then
  slicer_apply_100_enabled=0
  slicer_apply_100_reason='Docker daemon not reachable'
elif [ "${slicer_available}" -ne 1 ]; then
  slicer_apply_100_enabled=0
  slicer_apply_100_reason='slicer not found in PATH'
elif [ "${bootstrap_client_available}" -ne 1 ]; then
  slicer_apply_100_enabled=0
  slicer_apply_100_reason='bootstrap client not found (k3sup-pro or k3sup)'
elif [ "${kind_state}" = "running" ] || [ "${kind_state}" = "degraded" ]; then
  slicer_apply_100_enabled=0
  slicer_apply_100_reason="$(shared_host_ports_claimed_by 'kubernetes/kind')"
elif [ "${lima_state}" = "running" ] || [ "${lima_state}" = "degraded" ]; then
  slicer_apply_100_enabled=0
  slicer_apply_100_reason="$(shared_host_ports_claimed_by 'kubernetes/lima')"
elif [ -n "${slicer_foreign_ports}" ]; then
  slicer_apply_100_enabled=0
  slicer_apply_100_reason="$(first_non_empty_line "${slicer_foreign_ports}") is already in use by another process"
fi
slicer_apply_900_enabled="${slicer_apply_100_enabled}"
slicer_apply_900_reason="${slicer_apply_100_reason}"

actions_json="$(
  {
    build_action_json kind-status 'Kind status' kind kubernetes/kind 1 '' 'make -C kubernetes/kind status' 0
    build_action_json kind-prereqs 'Kind prereqs' kind kubernetes/kind 1 '' 'make -C kubernetes/kind prereqs' 0
    build_action_json kind-check-health 'Kind health' kind kubernetes/kind "$( [ "${kind_runtime_present}" -eq 1 ] && printf 1 || printf 0 )" "$( [ "${kind_runtime_present}" -eq 1 ] && printf '' || printf 'kubernetes/kind is not running' )" 'make -C kubernetes/kind check-health' 0
    build_action_json kind-show-urls 'Kind URLs' kind kubernetes/kind "$( [ "${kind_runtime_present}" -eq 1 ] && printf 1 || printf 0 )" "$( [ "${kind_runtime_present}" -eq 1 ] && printf '' || printf 'kubernetes/kind is not running' )" 'make -C kubernetes/kind show-urls' 0
    build_action_json kind-stop 'Stop kind' kind kubernetes/kind "$( [ "${kind_runtime_present}" -eq 1 ] && printf 1 || printf 0 )" "$( [ "${kind_runtime_present}" -eq 1 ] && printf '' || printf 'kubernetes/kind is not present' )" 'make -C kubernetes/kind stop-kind' 0
    build_action_json kind-reset 'Reset kind' kind kubernetes/kind "$( [ "${kind_runtime_present}" -eq 1 ] && printf 1 || printf 0 )" "$( [ "${kind_runtime_present}" -eq 1 ] && printf '' || printf 'kubernetes/kind is not present' )" 'make -C kubernetes/kind reset AUTO_APPROVE=1' 1
    build_action_json kind-apply-100 'Kind stage 100 apply' kind kubernetes/kind "${kind_apply_100_enabled}" "${kind_apply_100_reason}" 'make -C kubernetes/kind 100 apply AUTO_APPROVE=1' 1
    build_action_json kind-apply-900 'Kind stage 900 apply' kind kubernetes/kind "${kind_apply_900_enabled}" "${kind_apply_900_reason}" 'make -C kubernetes/kind 900 apply AUTO_APPROVE=1' 1
    build_action_json kind-switch 'Switch to kind' kind kubernetes/kind "${kind_apply_900_enabled}" "$( [ "${kind_apply_900_enabled}" -eq 1 ] && printf '' || printf '%s' "${kind_apply_900_reason}" )" 'AUTO_APPROVE=1 make -C kubernetes/kind reset && make -C kubernetes/kind 100 apply && make -C kubernetes/kind 900 apply' 1

    build_action_json lima-status 'Kubernetes Lima status' lima kubernetes/lima 1 '' 'make -C kubernetes/lima status' 0
    build_action_json lima-prereqs 'Kubernetes Lima prereqs' lima kubernetes/lima 1 '' 'make -C kubernetes/lima prereqs' 0
    build_action_json lima-check-health 'Kubernetes Lima health' lima kubernetes/lima "$( [ "${lima_runtime_present}" -eq 1 ] && printf 1 || printf 0 )" "$( [ "${lima_runtime_present}" -eq 1 ] && printf '' || printf 'kubernetes/lima is not running' )" 'make -C kubernetes/lima check-health' 0
    build_action_json lima-show-urls 'Kubernetes Lima URLs' lima kubernetes/lima "$( [ "${lima_runtime_present}" -eq 1 ] && printf 1 || printf 0 )" "$( [ "${lima_runtime_present}" -eq 1 ] && printf '' || printf 'kubernetes/lima is not running' )" 'make -C kubernetes/lima show-urls' 0
    build_action_json lima-stop 'Stop Kubernetes Lima' lima kubernetes/lima "$( [ "${lima_runtime_present}" -eq 1 ] && printf 1 || printf 0 )" "$( [ "${lima_runtime_present}" -eq 1 ] && printf '' || printf 'kubernetes/lima is not present' )" 'make -C kubernetes/lima stop-lima' 0
    build_action_json lima-reset 'Reset Kubernetes Lima' lima kubernetes/lima "$( [ "${lima_runtime_present}" -eq 1 ] && printf 1 || printf 0 )" "$( [ "${lima_runtime_present}" -eq 1 ] && printf '' || printf 'kubernetes/lima is not present' )" 'make -C kubernetes/lima reset AUTO_APPROVE=1' 1
    build_action_json lima-apply-100 'Kubernetes Lima stage 100 apply' lima kubernetes/lima "${lima_apply_100_enabled}" "${lima_apply_100_reason}" 'make -C kubernetes/lima 100 apply AUTO_APPROVE=1' 1
    build_action_json lima-apply-900 'Kubernetes Lima stage 900 apply' lima kubernetes/lima "${lima_apply_900_enabled}" "${lima_apply_900_reason}" 'make -C kubernetes/lima 900 apply AUTO_APPROVE=1' 1
    build_action_json lima-switch 'Switch to Kubernetes Lima' lima kubernetes/lima "${lima_apply_900_enabled}" "$( [ "${lima_apply_900_enabled}" -eq 1 ] && printf '' || printf '%s' "${lima_apply_900_reason}" )" 'AUTO_APPROVE=1 make -C kubernetes/lima reset && make -C kubernetes/lima 100 apply && make -C kubernetes/lima 900 apply' 1

    build_action_json slicer-status 'Slicer status' slicer kubernetes/slicer 1 '' 'make -C kubernetes/slicer status' 0
    build_action_json slicer-prereqs 'Slicer prereqs' slicer kubernetes/slicer 1 '' 'make -C kubernetes/slicer prereqs' 0
    build_action_json slicer-check-health 'Slicer health' slicer kubernetes/slicer "$( [ "${slicer_runtime_present}" -eq 1 ] && printf 1 || printf 0 )" "$( [ "${slicer_runtime_present}" -eq 1 ] && printf '' || printf 'kubernetes/slicer is not running' )" 'make -C kubernetes/slicer check-health' 0
    build_action_json slicer-show-urls 'Slicer URLs' slicer kubernetes/slicer "$( [ "${slicer_runtime_present}" -eq 1 ] && printf 1 || printf 0 )" "$( [ "${slicer_runtime_present}" -eq 1 ] && printf '' || printf 'kubernetes/slicer is not running' )" 'make -C kubernetes/slicer show-urls' 0
    build_action_json slicer-stop 'Stop Slicer' slicer kubernetes/slicer "$( [ "${slicer_runtime_present}" -eq 1 ] && printf 1 || printf 0 )" "$( [ "${slicer_runtime_present}" -eq 1 ] && printf '' || printf 'kubernetes/slicer is not present' )" 'make -C kubernetes/slicer stop-slicer' 0
    build_action_json slicer-reset 'Reset Slicer' slicer kubernetes/slicer "$( [ "${slicer_runtime_present}" -eq 1 ] && printf 1 || printf 0 )" "$( [ "${slicer_runtime_present}" -eq 1 ] && printf '' || printf 'kubernetes/slicer is not present' )" 'make -C kubernetes/slicer reset AUTO_APPROVE=1' 1
    build_action_json slicer-apply-100 'Slicer stage 100 apply' slicer kubernetes/slicer "${slicer_apply_100_enabled}" "${slicer_apply_100_reason}" 'make -C kubernetes/slicer 100 apply AUTO_APPROVE=1' 1
    build_action_json slicer-apply-900 'Slicer stage 900 apply' slicer kubernetes/slicer "${slicer_apply_900_enabled}" "${slicer_apply_900_reason}" 'make -C kubernetes/slicer 900 apply AUTO_APPROVE=1' 1
    build_action_json slicer-switch 'Switch to Slicer' slicer kubernetes/slicer "${slicer_apply_900_enabled}" "$( [ "${slicer_apply_900_enabled}" -eq 1 ] && printf '' || printf '%s' "${slicer_apply_900_reason}" )" 'AUTO_APPROVE=1 make -C kubernetes/slicer reset && make -C kubernetes/slicer 100 apply && make -C kubernetes/slicer 900 apply' 1

    build_action_json sdwan-status 'SD-WAN Lima status' sdwan_lima sd-wan/lima 1 '' 'make -C sd-wan/lima status' 0
    build_action_json sdwan-show-urls 'SD-WAN Lima URLs' sdwan_lima sd-wan/lima "$( [ "${sdwan_runtime_present}" -eq 1 ] && printf 1 || printf 0 )" "$( [ "${sdwan_runtime_present}" -eq 1 ] && printf '' || printf 'sd-wan/lima is not present' )" 'make -C sd-wan/lima show-urls' 0
    build_action_json sdwan-prereqs 'SD-WAN Lima prereqs' sdwan_lima sd-wan/lima 1 '' 'make -C sd-wan/lima prereqs' 0
    build_action_json sdwan-up 'Bring up SD-WAN Lima' sdwan_lima sd-wan/lima "$( [ "${limactl_available}" -eq 1 ] && printf 1 || printf 0 )" "$( [ "${limactl_available}" -eq 1 ] && printf '' || printf 'limactl not found in PATH' )" 'make -C sd-wan/lima up' 1
    build_action_json sdwan-down 'Stop SD-WAN Lima' sdwan_lima sd-wan/lima "$( [ "${sdwan_runtime_present}" -eq 1 ] && printf 1 || printf 0 )" "$( [ "${sdwan_runtime_present}" -eq 1 ] && printf '' || printf 'sd-wan/lima is not present' )" 'make -C sd-wan/lima down' 0
  } | jq -s '.'
)"

status_json="$(jq -cn \
  --arg generated_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  --arg overall_state "${overall_state}" \
  --arg active_cluster_variant "${active_cluster_variant}" \
  --arg active_cluster_variant_path "${active_cluster_variant_path}" \
  --arg active_variant "${active_variant}" \
  --arg active_variant_path "${active_variant_path}" \
  --arg active_provider "${active_provider}" \
  --arg active_provider_path "${active_provider_path}" \
  --arg active_project "${active_project}" \
  --arg active_project_path "${active_project_path}" \
  --argjson foreign_ports "$(json_array_from_newline "${foreign_ports}")" \
  --argjson docker_runtime "${docker_runtime_json}" \
  --argjson colima_runtime "${colima_runtime_json}" \
  --argjson podman_runtime "${podman_runtime_json}" \
  --argjson lima_platform "${lima_platform_json}" \
  --argjson slicer_platform "${slicer_platform_json}" \
  --argjson dhi_registry_auth "${dhi_registry_auth_json}" \
  --argjson docker_io_registry_auth "${docker_io_registry_auth_json}" \
  --argjson kind "${kind_project_json}" \
  --argjson lima "${lima_project_json}" \
  --argjson slicer "${slicer_project_json}" \
  --argjson sdwan_lima "${sdwan_project_json}" \
  --argjson actions "${actions_json}" \
  '{
    generated_at: $generated_at,
    overall_state: $overall_state,
    active_cluster_variant: (if $active_cluster_variant == "" then null else $active_cluster_variant end),
    active_cluster_variant_path: (if $active_cluster_variant_path == "" then null else $active_cluster_variant_path end),
    active_variant: (if $active_variant == "" then null else $active_variant end),
    active_variant_path: (if $active_variant_path == "" then null else $active_variant_path end),
    active_provider: (if $active_provider == "" then null else $active_provider end),
    active_provider_path: (if $active_provider_path == "" then null else $active_provider_path end),
    active_project: (if $active_project == "" then null else $active_project end),
    active_project_path: (if $active_project_path == "" then null else $active_project_path end),
    foreign_ports: $foreign_ports,
    platforms: {
      docker: $docker_runtime,
      colima: $colima_runtime,
      podman: $podman_runtime,
      lima: $lima_platform,
      slicer: $slicer_platform
    },
    platforms_order: ["docker", "colima", "podman", "lima", "slicer"],
    host_runtimes: {
      docker: $docker_runtime,
      colima: $colima_runtime,
      podman: $podman_runtime
    },
    host_runtimes_order: ["docker", "colima", "podman"],
    registry_auth: {
      dhi_io: $dhi_registry_auth,
      docker_io: $docker_io_registry_auth
    },
    registry_auth_order: ["dhi_io", "docker_io"],
    cluster_variants: {
      kind: $kind,
      lima: $lima,
      slicer: $slicer
    },
    cluster_variants_order: ["kind", "lima", "slicer"],
    variants: {
      kind: $kind,
      lima: $lima,
      slicer: $slicer,
      sdwan_lima: $sdwan_lima
    },
    variants_order: ["kind", "lima", "slicer", "sdwan_lima"],
    providers: {
      kind: $kind,
      lima: $lima,
      slicer: $slicer
    },
    projects: {
      kind: $kind,
      lima: $lima,
      slicer: $slicer,
      sdwan_lima: $sdwan_lima
    },
    projects_order: ["kind", "lima", "slicer", "sdwan_lima"],
    actions: $actions
  }')"

if [ "${output_format}" = "json" ]; then
  printf '%s\n' "${status_json}"
else
  render_human_output "${status_json}"
fi
