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

usage() {
  cat <<'EOF'
Usage: platform-status.sh [--output human|text|json] [--dry-run] [--execute]

Summarises local project runtime status across:
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

  jq -r '
    (["PROJECT", "STATE", "SERVE", "PRESENT", "VERSION", "PORTS", "NOTE"] | @tsv),
    (
      .projects_order[] as $key
      | .projects[$key] as $project
      | [
          $project.path,
          $project.state,
          (if $project.serving then "Y" else "N" end),
          (if $project.runtime_present then "Y" else "N" end),
          ($project.version // "-"),
          (
            if ($project.shared_ports | length) > 0 then
              (($project.shared_ports | join(",")) | if length > 28 then .[0:25] + "..." else . end)
            else
              "-"
            end
          ),
          (
            if ($project.blockers | length) > 0 then
              (($project.blockers[0]) | if length > 56 then .[0:53] + "..." else . end)
            else
              "-"
            end
          )
        ]
      | @tsv
    )
  ' <<<"${json_payload}" | awk -F $'\t' '
    function repeat(char, count,    result, i) {
      result = ""
      for (i = 0; i < count; i++) {
        result = result char
      }
      return result
    }
    {
      rows[NR] = $0
      if (NF > max_nf) {
        max_nf = NF
      }
      for (i = 1; i <= NF; i++) {
        if (length($i) > widths[i]) {
          widths[i] = length($i)
        }
      }
    }
    END {
      for (row = 1; row <= NR; row++) {
        split(rows[row], cols, FS)
        for (i = 1; i <= max_nf; i++) {
          printf "%-*s", widths[i], cols[i]
          if (i < max_nf) {
            printf "  "
          } else {
            printf "\n"
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
  local provider="$3"
  local project="$4"
  local enabled="$5"
  local reason="$6"
  local command="$7"
  local dangerous="$8"

  jq -cn \
    --arg id "${id}" \
    --arg label "${label}" \
    --arg provider "${provider}" \
    --arg project "${project}" \
    --arg reason "${reason}" \
    --arg command "${command}" \
    --argjson enabled "$(bool_json "${enabled}")" \
    --argjson dangerous "$(bool_json "${dangerous}")" \
    '{
      id: $id,
      label: $label,
      provider: $provider,
      project: $project,
      enabled: $enabled,
      reason: (if $reason == "" then null else $reason end),
      command: $command,
      dangerous: $dangerous
    }'
}

render_human_output() {
  local json_payload="$1"
  local table_output=""

  table_output="$(render_status_table "${json_payload}")"

  jq -r '
    "Platform local runtime status",
    "",
    "Overall state: \(.overall_state)",
    "Active cluster provider: \((.active_provider_path // "none"))",
    "Active project surface: \((.active_project_path // "none"))",
    (
      if (.foreign_ports | length) > 0 then
        "Foreign shared ports:\n" + ((.foreign_ports | map("  - " + .)) | join("\n"))
      else
        "Foreign shared ports: none"
      end
    )
  ' <<<"${json_payload}"
  printf '\n%s\n' "${table_output}"
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

shell_cli_maybe_execute_or_preview_summary usage "would inspect local platform project status"

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
if have_cmd docker; then
  docker_available=1
  if docker info >/dev/null 2>&1; then
    docker_daemon=1
    docker_context="$(docker context show 2>/dev/null || true)"
    docker_ps_output="$(docker ps --format '{{.Names}}|{{.Ports}}' 2>/dev/null || true)"
    docker_ps_all_output="$(docker ps -a --format '{{.Names}}|{{.Status}}|{{.Ports}}' 2>/dev/null || true)"
  fi
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

listener_443="$(port_listener_output 443)"
listener_58081="$(port_listener_output 58081)"

kind_ports="$(docker_host_ports_for_pattern "${docker_ps_output}" '^kind-local-(control-plane|worker([0-9]+)?)$' || true)"
kind_runtime_present=0
kind_running=0
kind_serving=0
if [ -n "${kind_clusters}" ] || [ -n "${kind_ports}" ] || docker_name_exists "${docker_ps_all_output}" '^kind-local-(control-plane|worker([0-9]+)?)$'; then
  kind_runtime_present=1
fi
if docker_name_exists "${docker_ps_output}" '^kind-local-control-plane$'; then
  kind_running=1
fi
if ports_include_number "${kind_ports}" 443; then
  kind_serving=1
fi

lima_ports="$(docker_host_ports_for_pattern "${docker_ps_output}" '^limavm-platform-gateway-443$' || true)"
lima_runtime_present=0
lima_running=0
lima_serving=0
if limactl_has_prefix "${limactl_list_output}" 'k3s-node-'; then
  lima_runtime_present=1
fi
if limactl_running_prefix "${limactl_list_output}" 'k3s-node-'; then
  lima_running=1
fi
if ports_include_number "${lima_ports}" 443; then
  lima_serving=1
fi

slicer_ports="$(docker_host_ports_for_pattern "${docker_ps_output}" '^slicer-platform-gateway-443$' || true)"
slicer_runtime_present=0
slicer_running=0
slicer_paused=0
slicer_serving=0
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
if ports_include_number "${slicer_ports}" 443; then
  slicer_serving=1
fi

sdwan_present_count=0
sdwan_running_count=0
sdwan_serving=0
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
if [ "${sdwan_running_count}" -eq 3 ] && [ -n "${listener_58081}" ]; then
  sdwan_serving=1
fi
sdwan_ports=""
if [ "${sdwan_runtime_present}" -eq 1 ] || [ -n "${listener_58081}" ]; then
  sdwan_ports='127.0.0.1:58081'
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

foreign_ports=""
if [ -n "${listener_443}" ] && [ "${kind_serving}" -eq 0 ] && [ "${lima_serving}" -eq 0 ] && [ "${slicer_serving}" -eq 0 ]; then
  append_line foreign_ports '127.0.0.1:443'
fi
if [ -n "${listener_58081}" ] && [ "${sdwan_serving}" -eq 0 ]; then
  append_line foreign_ports '127.0.0.1:58081'
fi

kind_dhi_auth=1
kind_docker_hub_auth=1
if [ -x "${CHECK_DOCKER_REGISTRY_AUTH_SCRIPT}" ]; then
  if ! "${CHECK_DOCKER_REGISTRY_AUTH_SCRIPT}" --execute dhi.io "Docker Hardened Images (dhi.io)" >/dev/null 2>&1; then
    kind_dhi_auth=0
  fi
  if ! "${CHECK_DOCKER_REGISTRY_AUTH_SCRIPT}" --execute index.docker.io "Docker Hub" >/dev/null 2>&1; then
    kind_docker_hub_auth=0
  fi
fi

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
  append_line kind_blockers 'kubernetes/lima is already using shared localhost ports'
fi
if [ "${slicer_state}" = "running" ] || [ "${slicer_state}" = "degraded" ]; then
  append_line kind_blockers 'kubernetes/slicer is already using shared localhost ports'
fi
if printf '%s\n' "${foreign_ports}" | grep -qx '127.0.0.1:443'; then
  append_line kind_blockers '127.0.0.1:443 is already in use by a non-platform process'
fi

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
  append_line lima_blockers 'kubernetes/kind is already using shared localhost ports'
fi
if [ "${slicer_state}" = "running" ] || [ "${slicer_state}" = "degraded" ]; then
  append_line lima_blockers 'kubernetes/slicer is already using shared localhost ports'
fi
if [ "${sdwan_state}" = "running" ] || [ "${sdwan_state}" = "degraded" ]; then
  append_line lima_blockers 'sd-wan/lima is already using Lima VMs'
fi
if printf '%s\n' "${foreign_ports}" | grep -qx '127.0.0.1:443'; then
  append_line lima_blockers '127.0.0.1:443 is already in use by a non-platform process'
fi

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
  append_line slicer_blockers 'kubernetes/kind is already using shared localhost ports'
fi
if [ "${lima_state}" = "running" ] || [ "${lima_state}" = "degraded" ]; then
  append_line slicer_blockers 'kubernetes/lima is already using shared localhost ports'
fi
if printf '%s\n' "${foreign_ports}" | grep -qx '127.0.0.1:443'; then
  append_line slicer_blockers '127.0.0.1:443 is already in use by a non-platform process'
fi

sdwan_blockers=""
if [ "${limactl_available}" -ne 1 ]; then
  append_line sdwan_blockers 'limactl not found in PATH'
fi
if [ "${lima_state}" = "running" ] || [ "${lima_state}" = "degraded" ]; then
  append_line sdwan_blockers 'kubernetes/lima is also using Lima VMs'
fi
if printf '%s\n' "${foreign_ports}" | grep -qx '127.0.0.1:58081'; then
  append_line sdwan_blockers '127.0.0.1:58081 is already in use by a non-platform process'
fi

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
  --argjson listener_58081 "$(bool_json "$( [ -n "${listener_58081}" ] && printf 1 || printf 0 )")" \
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
  kind_apply_100_reason='kubernetes/lima must be cleared first'
elif [ "${slicer_state}" = "running" ] || [ "${slicer_state}" = "degraded" ]; then
  kind_apply_100_enabled=0
  kind_apply_100_reason='kubernetes/slicer must be cleared first'
elif printf '%s\n' "${foreign_ports}" | grep -qx '127.0.0.1:443'; then
  kind_apply_100_enabled=0
  kind_apply_100_reason='127.0.0.1:443 is already in use by another process'
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
  lima_apply_100_reason='kubernetes/kind must be cleared first'
elif [ "${slicer_state}" = "running" ] || [ "${slicer_state}" = "degraded" ]; then
  lima_apply_100_enabled=0
  lima_apply_100_reason='kubernetes/slicer must be cleared first'
elif [ "${sdwan_state}" = "running" ] || [ "${sdwan_state}" = "degraded" ]; then
  lima_apply_100_enabled=0
  lima_apply_100_reason='sd-wan/lima is already using Lima VMs'
elif printf '%s\n' "${foreign_ports}" | grep -qx '127.0.0.1:443'; then
  lima_apply_100_enabled=0
  lima_apply_100_reason='127.0.0.1:443 is already in use by another process'
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
  slicer_apply_100_reason='kubernetes/kind must be cleared first'
elif [ "${lima_state}" = "running" ] || [ "${lima_state}" = "degraded" ]; then
  slicer_apply_100_enabled=0
  slicer_apply_100_reason='kubernetes/lima must be cleared first'
elif printf '%s\n' "${foreign_ports}" | grep -qx '127.0.0.1:443'; then
  slicer_apply_100_enabled=0
  slicer_apply_100_reason='127.0.0.1:443 is already in use by another process'
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
    build_action_json kind-switch 'Switch to kind' kind kubernetes/kind "${kind_apply_900_enabled}" "$( [ "${kind_apply_900_enabled}" -eq 1 ] && printf '' || printf '%s' "${kind_apply_900_reason}" )" 'make -C kubernetes/kind reset AUTO_APPROVE=1 && make -C kubernetes/kind 100 apply AUTO_APPROVE=1 && make -C kubernetes/kind 900 apply AUTO_APPROVE=1' 1

    build_action_json lima-status 'Kubernetes Lima status' lima kubernetes/lima 1 '' 'make -C kubernetes/lima status' 0
    build_action_json lima-prereqs 'Kubernetes Lima prereqs' lima kubernetes/lima 1 '' 'make -C kubernetes/lima prereqs' 0
    build_action_json lima-check-health 'Kubernetes Lima health' lima kubernetes/lima "$( [ "${lima_runtime_present}" -eq 1 ] && printf 1 || printf 0 )" "$( [ "${lima_runtime_present}" -eq 1 ] && printf '' || printf 'kubernetes/lima is not running' )" 'make -C kubernetes/lima check-health' 0
    build_action_json lima-show-urls 'Kubernetes Lima URLs' lima kubernetes/lima "$( [ "${lima_runtime_present}" -eq 1 ] && printf 1 || printf 0 )" "$( [ "${lima_runtime_present}" -eq 1 ] && printf '' || printf 'kubernetes/lima is not running' )" 'make -C kubernetes/lima show-urls' 0
    build_action_json lima-stop 'Stop Kubernetes Lima' lima kubernetes/lima "$( [ "${lima_runtime_present}" -eq 1 ] && printf 1 || printf 0 )" "$( [ "${lima_runtime_present}" -eq 1 ] && printf '' || printf 'kubernetes/lima is not present' )" 'make -C kubernetes/lima stop-lima' 0
    build_action_json lima-reset 'Reset Kubernetes Lima' lima kubernetes/lima "$( [ "${lima_runtime_present}" -eq 1 ] && printf 1 || printf 0 )" "$( [ "${lima_runtime_present}" -eq 1 ] && printf '' || printf 'kubernetes/lima is not present' )" 'make -C kubernetes/lima reset AUTO_APPROVE=1' 1
    build_action_json lima-apply-100 'Kubernetes Lima stage 100 apply' lima kubernetes/lima "${lima_apply_100_enabled}" "${lima_apply_100_reason}" 'make -C kubernetes/lima 100 apply AUTO_APPROVE=1' 1
    build_action_json lima-apply-900 'Kubernetes Lima stage 900 apply' lima kubernetes/lima "${lima_apply_900_enabled}" "${lima_apply_900_reason}" 'make -C kubernetes/lima 900 apply AUTO_APPROVE=1' 1
    build_action_json lima-switch 'Switch to Kubernetes Lima' lima kubernetes/lima "${lima_apply_900_enabled}" "$( [ "${lima_apply_900_enabled}" -eq 1 ] && printf '' || printf '%s' "${lima_apply_900_reason}" )" 'make -C kubernetes/lima reset AUTO_APPROVE=1 && make -C kubernetes/lima 100 apply AUTO_APPROVE=1 && make -C kubernetes/lima 900 apply AUTO_APPROVE=1' 1

    build_action_json slicer-status 'Slicer status' slicer kubernetes/slicer 1 '' 'make -C kubernetes/slicer status' 0
    build_action_json slicer-prereqs 'Slicer prereqs' slicer kubernetes/slicer 1 '' 'make -C kubernetes/slicer prereqs' 0
    build_action_json slicer-check-health 'Slicer health' slicer kubernetes/slicer "$( [ "${slicer_runtime_present}" -eq 1 ] && printf 1 || printf 0 )" "$( [ "${slicer_runtime_present}" -eq 1 ] && printf '' || printf 'kubernetes/slicer is not running' )" 'make -C kubernetes/slicer check-health' 0
    build_action_json slicer-show-urls 'Slicer URLs' slicer kubernetes/slicer "$( [ "${slicer_runtime_present}" -eq 1 ] && printf 1 || printf 0 )" "$( [ "${slicer_runtime_present}" -eq 1 ] && printf '' || printf 'kubernetes/slicer is not running' )" 'make -C kubernetes/slicer show-urls' 0
    build_action_json slicer-stop 'Stop Slicer' slicer kubernetes/slicer "$( [ "${slicer_runtime_present}" -eq 1 ] && printf 1 || printf 0 )" "$( [ "${slicer_runtime_present}" -eq 1 ] && printf '' || printf 'kubernetes/slicer is not present' )" 'make -C kubernetes/slicer stop-slicer' 0
    build_action_json slicer-reset 'Reset Slicer' slicer kubernetes/slicer "$( [ "${slicer_runtime_present}" -eq 1 ] && printf 1 || printf 0 )" "$( [ "${slicer_runtime_present}" -eq 1 ] && printf '' || printf 'kubernetes/slicer is not present' )" 'make -C kubernetes/slicer reset AUTO_APPROVE=1' 1
    build_action_json slicer-apply-100 'Slicer stage 100 apply' slicer kubernetes/slicer "${slicer_apply_100_enabled}" "${slicer_apply_100_reason}" 'make -C kubernetes/slicer 100 apply AUTO_APPROVE=1' 1
    build_action_json slicer-apply-900 'Slicer stage 900 apply' slicer kubernetes/slicer "${slicer_apply_900_enabled}" "${slicer_apply_900_reason}" 'make -C kubernetes/slicer 900 apply AUTO_APPROVE=1' 1
    build_action_json slicer-switch 'Switch to Slicer' slicer kubernetes/slicer "${slicer_apply_900_enabled}" "$( [ "${slicer_apply_900_enabled}" -eq 1 ] && printf '' || printf '%s' "${slicer_apply_900_reason}" )" 'make -C kubernetes/slicer reset AUTO_APPROVE=1 && make -C kubernetes/slicer 100 apply AUTO_APPROVE=1 && make -C kubernetes/slicer 900 apply AUTO_APPROVE=1' 1

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
  --arg active_provider "${active_provider}" \
  --arg active_provider_path "${active_provider_path}" \
  --arg active_project "${active_project}" \
  --arg active_project_path "${active_project_path}" \
  --argjson foreign_ports "$(json_array_from_newline "${foreign_ports}")" \
  --argjson kind "${kind_project_json}" \
  --argjson lima "${lima_project_json}" \
  --argjson slicer "${slicer_project_json}" \
  --argjson sdwan_lima "${sdwan_project_json}" \
  --argjson actions "${actions_json}" \
  '{
    generated_at: $generated_at,
    overall_state: $overall_state,
    active_provider: (if $active_provider == "" then null else $active_provider end),
    active_provider_path: (if $active_provider_path == "" then null else $active_provider_path end),
    active_project: (if $active_project == "" then null else $active_project end),
    active_project_path: (if $active_project_path == "" then null else $active_project_path end),
    foreign_ports: $foreign_ports,
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
