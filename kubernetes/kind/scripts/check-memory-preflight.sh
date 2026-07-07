#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

KIND_PREFLIGHT_MIN_HOST_AVAILABLE_GB="${KIND_PREFLIGHT_MIN_HOST_AVAILABLE_GB:-4}"
KIND_PREFLIGHT_FAIL_HOST_AVAILABLE_GB="${KIND_PREFLIGHT_FAIL_HOST_AVAILABLE_GB:-2}"
KIND_PREFLIGHT_MIN_DOCKER_MEM_GB="${KIND_PREFLIGHT_MIN_DOCKER_MEM_GB:-8}"
KIND_PREFLIGHT_COMPETING_VM_RSS_GB="${KIND_PREFLIGHT_COMPETING_VM_RSS_GB:-2}"
KIND_PREFLIGHT_LSOF_TIMEOUT_SECONDS="${KIND_PREFLIGHT_LSOF_TIMEOUT_SECONDS:-10}"

usage() {
  cat <<EOF >&2
Usage: ${0##*/} [--dry-run] [--execute]

Fails early when the host and Docker daemon do not have enough memory for kind.

$(shell_cli_standard_options)
EOF
}

warn() {
  echo "WARN $*" >&2
}

ok() {
  echo "OK   $*"
}

fail() {
  echo "FAIL $*" >&2
}

bytes_to_gib() {
  awk -v bytes="$1" 'BEGIN { if (bytes > 0) printf "%.1fGiB", bytes / 1024 / 1024 / 1024; else printf "unknown" }'
}

gb_to_bytes() {
  local value="$1"

  awk -v gb="${value}" 'BEGIN {
    if (gb !~ /^[0-9]+([.][0-9]+)?$/) exit 1
    printf "%.0f", gb * 1024 * 1024 * 1024
  }'
}

bytes_less_than_threshold() {
  local bytes="$1"
  local threshold_bytes="$2"

  awk -v bytes="${bytes}" -v threshold="${threshold_bytes}" 'BEGIN { exit !(bytes < threshold) }'
}

bytes_greater_than_threshold() {
  local bytes="$1"
  local threshold_bytes="$2"

  awk -v bytes="${bytes}" -v threshold="${threshold_bytes}" 'BEGIN { exit !(bytes > threshold) }'
}

rss_kib_to_bytes() {
  awk -v kib="$1" 'BEGIN { if (kib ~ /^[0-9]+$/) printf "%.0f", kib * 1024; else print "0" }'
}

validate_threshold() {
  local env_name="$1"
  local value="$2"

  if ! gb_to_bytes "${value}" >/dev/null; then
    fail "${env_name}=${value} is invalid; use a numeric GiB value (for example 4 or 4.5). Override with ${env_name}; remediation: unset ${env_name}"
    exit 1
  fi
}

darwin_memory_bytes() {
  local page_size total_bytes free_pages inactive_pages purgeable_pages available_bytes

  total_bytes="$(sysctl -n hw.memsize 2>/dev/null || true)"
  if [[ -z "${total_bytes}" || "${total_bytes}" == *[!0-9]* ]]; then
    return 1
  fi

  page_size="$(vm_stat 2>/dev/null | awk '/page size of/ { print $8; exit }' || true)"
  if [[ -z "${page_size}" || "${page_size}" == *[!0-9]* ]]; then
    return 1
  fi

  free_pages="$(vm_stat 2>/dev/null | awk '/Pages free:/ { gsub("\\.", "", $3); print $3; exit }' || true)"
  inactive_pages="$(vm_stat 2>/dev/null | awk '/Pages inactive:/ { gsub("\\.", "", $3); print $3; exit }' || true)"
  purgeable_pages="$(vm_stat 2>/dev/null | awk '/Pages purgeable:/ { gsub("\\.", "", $3); print $3; exit }' || true)"

  free_pages="${free_pages:-0}"
  inactive_pages="${inactive_pages:-0}"
  purgeable_pages="${purgeable_pages:-0}"
  available_bytes="$(( (free_pages + inactive_pages + purgeable_pages) * page_size ))"

  printf '%s %s\n' "${total_bytes}" "${available_bytes}"
}

linux_memory_bytes() {
  local total_kib available_kib

  if [[ ! -r /proc/meminfo ]]; then
    return 1
  fi

  total_kib="$(awk '/^MemTotal:/ { print $2; exit }' /proc/meminfo)"
  available_kib="$(awk '/^MemAvailable:/ { print $2; exit }' /proc/meminfo)"
  if [[ -z "${total_kib}" || -z "${available_kib}" ]]; then
    return 1
  fi

  printf '%s %s\n' "$((total_kib * 1024))" "$((available_kib * 1024))"
}

check_host_memory() {
  local uname_s total_bytes available_bytes warn_threshold_bytes fail_threshold_bytes memory_pair

  uname_s="$(uname -s)"
  case "${uname_s}" in
    Darwin)
      memory_pair="$(darwin_memory_bytes || true)"
      ;;
    Linux)
      memory_pair="$(linux_memory_bytes || true)"
      ;;
    *)
      warn "host memory: unsupported OS ${uname_s}; skipping host available memory check"
      return 0
      ;;
  esac

  if [[ -z "${memory_pair}" ]]; then
    warn "host memory: unable to determine available memory on ${uname_s}; skipping host available memory check"
    return 0
  fi

  total_bytes="${memory_pair%% *}"
  available_bytes="${memory_pair##* }"
  warn_threshold_bytes="$(gb_to_bytes "${KIND_PREFLIGHT_MIN_HOST_AVAILABLE_GB}")"
  fail_threshold_bytes="$(gb_to_bytes "${KIND_PREFLIGHT_FAIL_HOST_AVAILABLE_GB}")"

  if bytes_less_than_threshold "${available_bytes}" "${fail_threshold_bytes}"; then
    fail "host memory: $(bytes_to_gib "${available_bytes}") available out of $(bytes_to_gib "${total_bytes}") total; fail threshold is ${KIND_PREFLIGHT_FAIL_HOST_AVAILABLE_GB}GiB (${KIND_PREFLIGHT_FAIL_HOST_AVAILABLE_GB} via KIND_PREFLIGHT_FAIL_HOST_AVAILABLE_GB); warn threshold is ${KIND_PREFLIGHT_MIN_HOST_AVAILABLE_GB}GiB (${KIND_PREFLIGHT_MIN_HOST_AVAILABLE_GB} via KIND_PREFLIGHT_MIN_HOST_AVAILABLE_GB); remediation: close memory-hungry applications or stop other local VMs (for example: make -C kubernetes/slicer stop)"
    return 1
  fi

  if bytes_less_than_threshold "${available_bytes}" "${warn_threshold_bytes}"; then
    warn "host memory: $(bytes_to_gib "${total_bytes}") total, $(bytes_to_gib "${available_bytes}") available; warn threshold is ${KIND_PREFLIGHT_MIN_HOST_AVAILABLE_GB}GiB (${KIND_PREFLIGHT_MIN_HOST_AVAILABLE_GB} via KIND_PREFLIGHT_MIN_HOST_AVAILABLE_GB); fail threshold is ${KIND_PREFLIGHT_FAIL_HOST_AVAILABLE_GB}GiB (${KIND_PREFLIGHT_FAIL_HOST_AVAILABLE_GB} via KIND_PREFLIGHT_FAIL_HOST_AVAILABLE_GB); remediation: close memory-hungry applications or stop other local VMs (for example: make -C kubernetes/slicer stop)"
    return 0
  fi

  ok "host memory: $(bytes_to_gib "${total_bytes}") total, $(bytes_to_gib "${available_bytes}") available"
}

check_docker_memory() {
  local mem_total threshold_bytes

  if ! command -v docker >/dev/null 2>&1; then
    fail "docker daemon not reachable (docker not found in PATH); threshold is ${KIND_PREFLIGHT_MIN_DOCKER_MEM_GB}GiB (${KIND_PREFLIGHT_MIN_DOCKER_MEM_GB} via KIND_PREFLIGHT_MIN_DOCKER_MEM_GB); remediation: start Docker Desktop"
    return 1
  fi

  if ! docker info >/dev/null 2>&1; then
    if [[ "$(uname -s)" == "Darwin" ]]; then
      fail "docker daemon not reachable (is Docker Desktop running?); threshold is ${KIND_PREFLIGHT_MIN_DOCKER_MEM_GB}GiB (${KIND_PREFLIGHT_MIN_DOCKER_MEM_GB} via KIND_PREFLIGHT_MIN_DOCKER_MEM_GB); remediation: open -a Docker"
    else
      fail "docker daemon not reachable; threshold is ${KIND_PREFLIGHT_MIN_DOCKER_MEM_GB}GiB (${KIND_PREFLIGHT_MIN_DOCKER_MEM_GB} via KIND_PREFLIGHT_MIN_DOCKER_MEM_GB); remediation: sudo systemctl start docker"
    fi
    return 1
  fi

  mem_total="$(docker info --format '{{.MemTotal}}' 2>/dev/null || true)"
  if [[ -z "${mem_total}" || "${mem_total}" == "<no value>" || "${mem_total}" == *[!0-9]* ]]; then
    fail "Docker VM budget: unknown; threshold is ${KIND_PREFLIGHT_MIN_DOCKER_MEM_GB}GiB (${KIND_PREFLIGHT_MIN_DOCKER_MEM_GB} via KIND_PREFLIGHT_MIN_DOCKER_MEM_GB); remediation: restart Docker Desktop"
    return 1
  fi

  threshold_bytes="$(gb_to_bytes "${KIND_PREFLIGHT_MIN_DOCKER_MEM_GB}")"
  if bytes_less_than_threshold "${mem_total}" "${threshold_bytes}"; then
    fail "Docker VM budget: $(bytes_to_gib "${mem_total}") found; threshold is ${KIND_PREFLIGHT_MIN_DOCKER_MEM_GB}GiB (${KIND_PREFLIGHT_MIN_DOCKER_MEM_GB} via KIND_PREFLIGHT_MIN_DOCKER_MEM_GB); remediation: increase Docker Desktop memory to at least ${KIND_PREFLIGHT_MIN_DOCKER_MEM_GB}GiB"
    return 1
  fi

  ok "Docker VM budget: $(bytes_to_gib "${mem_total}")"
}

is_vm_process_name() {
  local text="$1"

  case "${text}" in
    *com.apple.Virtualization.VirtualMachine*|*vfkit*|*krunkit*|*qemu-system*)
      return 0
      ;;
  esac
  return 1
}

lsof_for_pid() {
  local pid="$1"
  local output_file lsof_pid waited lsof_status

  if ! command -v lsof >/dev/null 2>&1; then
    return 127
  fi

  output_file="$(mktemp "${TMPDIR:-/tmp}/kind-memory-preflight-lsof.XXXXXX")"
  lsof -b -n -P -p "${pid}" >"${output_file}" 2>/dev/null &
  lsof_pid="$!"
  waited=0

  while kill -0 "${lsof_pid}" 2>/dev/null; do
    if [[ "${waited}" -ge "${KIND_PREFLIGHT_LSOF_TIMEOUT_SECONDS}" ]]; then
      kill "${lsof_pid}" 2>/dev/null || true
      wait "${lsof_pid}" 2>/dev/null || true
      rm -f "${output_file}"
      return 124
    fi

    sleep 1
    waited=$((waited + 1))
  done

  lsof_status=0
  wait "${lsof_pid}" || lsof_status=$?
  if [[ "${lsof_status}" -ne 0 || ! -s "${output_file}" ]]; then
    rm -f "${output_file}"
    return 1
  fi

  cat "${output_file}"
  rm -f "${output_file}"
}

classify_vm_owner() {
  local pid="$1"
  local lsof_output lsof_status

  lsof_status=0
  lsof_output="$(lsof_for_pid "${pid}")" || lsof_status=$?
  if [[ "${lsof_status}" -eq 124 ]]; then
    lsof_status=0
    lsof_output="$(lsof_for_pid "${pid}")" || lsof_status=$?
  fi
  if [[ "${lsof_status}" -eq 124 ]]; then
    printf '%s\n' "timeout|classification timed out|increase KIND_PREFLIGHT_LSOF_TIMEOUT_SECONDS or stop the owning VM application (inspect with: lsof -b -n -P -p ${pid})"
    return 0
  fi
  if [[ -z "${lsof_output}" ]]; then
    printf '%s\n' "unknown|unknown VM owner|stop the owning VM application (inspect with: lsof -b -n -P -p ${pid})"
    return 0
  fi

  # Here-strings, not pipes: under set -o pipefail, `printf big | grep -q`
  # reports failure when grep exits at the first match and printf takes
  # SIGPIPE on the unread remainder (lsof output here exceeds the 64KB pipe
  # buffer). This false-negatived Docker's own VM as "unknown owner".
  if grep -Eiq 'com[.]docker|Docker[.]app|docker[.]sock' <<<"${lsof_output}"; then
    printf '%s\n' "docker|Docker|"
    return 0
  fi

  if grep -Eiq 'slicer' <<<"${lsof_output}"; then
    printf '%s\n' "slicer|Slicer|make -C kubernetes/slicer stop"
    return 0
  fi

  if grep -Eiq 'lima' <<<"${lsof_output}"; then
    printf '%s\n' "lima|Lima|make -C kubernetes/lima stop"
    return 0
  fi

  printf '%s\n' "unknown|unknown VM owner|stop the owning VM application (inspect with: lsof -b -n -P -p ${pid})"
}

check_competing_vms() {
  local threshold_bytes found_competitor pid rss_kib rss_bytes comm command name owner_info owner_key owner_label remediation

  threshold_bytes="$(gb_to_bytes "${KIND_PREFLIGHT_COMPETING_VM_RSS_GB}")"
  found_competitor=0

  # RSS is cheap and portable, but can understate a VM's reservation early in
  # its life. This is still useful as a fast preflight signal.
  while read -r pid rss_kib; do
    [[ -n "${pid:-}" && -n "${rss_kib:-}" ]] || continue
    rss_bytes="$(rss_kib_to_bytes "${rss_kib}")"
    if bytes_less_than_threshold "${rss_bytes}" "${threshold_bytes}"; then
      continue
    fi

    # Fetch per-pid fields after the RSS filter so executable paths containing
    # spaces, such as /Library/Application Support/..., cannot corrupt parsing.
    comm="$(ps -p "${pid}" -o comm= 2>/dev/null || true)"
    command="$(ps -p "${pid}" -o command= 2>/dev/null || true)"
    if ! is_vm_process_name "${comm} ${command}"; then
      continue
    fi

    owner_info="$(classify_vm_owner "${pid}")"
    owner_key="${owner_info%%|*}"
    owner_info="${owner_info#*|}"
    owner_label="${owner_info%%|*}"
    remediation="${owner_info#*|}"
    if [[ "${owner_key}" == "docker" ]]; then
      continue
    fi

    name="$(basename "${comm}")"
    fail "competing hypervisor VM detected: ${name} owner=${owner_label} pid=${pid} RSS=$(bytes_to_gib "${rss_bytes}"); threshold is ${KIND_PREFLIGHT_COMPETING_VM_RSS_GB}GiB (${KIND_PREFLIGHT_COMPETING_VM_RSS_GB} via KIND_PREFLIGHT_COMPETING_VM_RSS_GB); remediation: ${remediation}"
    found_competitor=1
  done < <(ps -axo pid=,rss= 2>/dev/null || true)

  if [[ "${found_competitor}" -ne 0 ]]; then
    return 1
  fi

  ok "no competing hypervisor VMs detected"
}

main() {
  local status

  shell_cli_handle_standard_no_args usage "would check host memory, Docker VM budget, and competing hypervisor VMs" "$@"

  if [[ "${KIND_SKIP_MEMORY_PREFLIGHT:-0}" == "1" ]]; then
    warn "memory preflight skipped because KIND_SKIP_MEMORY_PREFLIGHT=1"
    exit 0
  fi

  validate_threshold KIND_PREFLIGHT_MIN_HOST_AVAILABLE_GB "${KIND_PREFLIGHT_MIN_HOST_AVAILABLE_GB}"
  validate_threshold KIND_PREFLIGHT_FAIL_HOST_AVAILABLE_GB "${KIND_PREFLIGHT_FAIL_HOST_AVAILABLE_GB}"
  validate_threshold KIND_PREFLIGHT_MIN_DOCKER_MEM_GB "${KIND_PREFLIGHT_MIN_DOCKER_MEM_GB}"
  validate_threshold KIND_PREFLIGHT_COMPETING_VM_RSS_GB "${KIND_PREFLIGHT_COMPETING_VM_RSS_GB}"
  if bytes_greater_than_threshold "$(gb_to_bytes "${KIND_PREFLIGHT_FAIL_HOST_AVAILABLE_GB}")" "$(gb_to_bytes "${KIND_PREFLIGHT_MIN_HOST_AVAILABLE_GB}")"; then
    fail "host memory threshold config error: KIND_PREFLIGHT_FAIL_HOST_AVAILABLE_GB=${KIND_PREFLIGHT_FAIL_HOST_AVAILABLE_GB}GiB is greater than KIND_PREFLIGHT_MIN_HOST_AVAILABLE_GB=${KIND_PREFLIGHT_MIN_HOST_AVAILABLE_GB}GiB; remediation: set KIND_PREFLIGHT_FAIL_HOST_AVAILABLE_GB less than or equal to KIND_PREFLIGHT_MIN_HOST_AVAILABLE_GB"
    exit 1
  fi

  status=0
  check_host_memory || status=1
  check_docker_memory || status=1
  check_competing_vms || status=1

  return "${status}"
}

main "$@"
