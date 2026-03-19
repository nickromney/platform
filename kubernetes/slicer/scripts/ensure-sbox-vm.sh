#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL $*" >&2; exit 1; }
ok() { echo "OK   $*"; }
warn() { echo "WARN $*" >&2; }

slicer_url="${SLICER_URL:-${SLICER_SOCKET:-}}"
vm_name="${SLICER_VM_NAME:-slicer-1}"
vm_group="${SLICER_VM_GROUP:-slicer}"
ready_timeout="${SLICER_VM_READY_TIMEOUT:-300s}"
min_disk_gb="${SLICER_VM_MIN_DISK_GB:-25}"
use_local_mac="${SLICER_USE_LOCAL_MAC:-0}"
slicer_config="${SLICER_CONFIG:-${HOME}/slicer-mac/slicer-mac.yaml}"
tag_target="${SLICER_TARGET_TAG:-target=slicer}"
tag_workspace="${SLICER_WORKSPACE_TAG:-workspace=platform}"

[ -n "${slicer_url}" ] || fail "SLICER_URL or SLICER_SOCKET must be set"
command -v slicer >/dev/null 2>&1 || fail "slicer not found in PATH"
command -v jq >/dev/null 2>&1 || fail "jq not found in PATH"
[[ "${min_disk_gb}" =~ ^[0-9]+$ ]] || fail "SLICER_VM_MIN_DISK_GB must be an integer number of GiB"

vm_root_disk_gb() {
  local disk_bytes
  disk_bytes="$(SLICER_URL="${slicer_url}" slicer vm exec "${vm_name}" -- "df -B1 --output=size / | awk 'NR==2 {print \$1}'" | tr -d '\r' | xargs)"
  [[ "${disk_bytes}" =~ ^[0-9]+$ ]] || fail "Could not determine root disk size for ${vm_name}"
  echo $(( (disk_bytes + 1073741824 - 1) / 1073741824 ))
}

local_mac_recreate_hint() {
  cat >&2 <<EOF
The local slicer-mac daemon manages ${vm_name} from ${slicer_config}.
Update the host group storage_size there, stop the daemon, delete the backing *.img for ${vm_name}, and start the daemon again so ${vm_name} is recreated with the new disk size.
EOF
}

group_line="$(SLICER_URL="${slicer_url}" slicer vm group 2>/dev/null | awk -v group="${vm_group}" '$1 == group { print $0 }')"
[[ -n "${group_line}" ]] || fail "Host group '${vm_group}' not found on the active slicer daemon"

group_cpus="$(printf '%s\n' "${group_line}" | awk '{print $3}')"
group_ram_raw="$(printf '%s\n' "${group_line}" | awk '{print $4}')"
group_ram_gb="$(printf '%s\n' "${group_ram_raw}" | tr -cd '0-9')"

vm_cpus="${SLICER_VM_CPUS:-${group_cpus}}"
vm_ram_gb="${SLICER_VM_RAM_GB:-${group_ram_gb}}"

[[ -n "${vm_cpus}" ]] || fail "Could not determine CPU count for host group '${vm_group}'"
[[ -n "${vm_ram_gb}" ]] || fail "Could not determine RAM for host group '${vm_group}'"

if (( vm_cpus > group_cpus )); then
  fail "Requested ${vm_cpus} CPUs for ${vm_name}, but host group '${vm_group}' only allows ${group_cpus}"
fi
if (( vm_ram_gb > group_ram_gb )); then
  fail "Requested ${vm_ram_gb}GiB RAM for ${vm_name}, but host group '${vm_group}' only allows ${group_ram_gb}GiB"
fi

list_json="$(SLICER_URL="${slicer_url}" slicer vm list --json)"
if jq -e --arg vm "${vm_name}" '.[] | select(.hostname == $vm)' >/dev/null 2>&1 <<<"${list_json}"; then
  existing_cpus="$(jq -r --arg vm "${vm_name}" '.[] | select(.hostname == $vm) | .cpus' <<<"${list_json}")"
  existing_ram_bytes="$(jq -r --arg vm "${vm_name}" '.[] | select(.hostname == $vm) | .ram_bytes' <<<"${list_json}")"
  existing_status="$(jq -r --arg vm "${vm_name}" '.[] | select(.hostname == $vm) | .status // empty' <<<"${list_json}")"
  existing_ram_gb="$(( (existing_ram_bytes + 1073741824 - 1) / 1073741824 ))"

  if (( existing_cpus < vm_cpus || existing_ram_gb < vm_ram_gb )); then
    fail "Existing VM ${vm_name} is smaller than requested (${existing_cpus} CPU / ${existing_ram_gb}GiB < ${vm_cpus} CPU / ${vm_ram_gb}GiB). Reset or delete it before recreating."
  fi

  ok "using existing ${vm_name} (${existing_cpus} CPU / ${existing_ram_gb}GiB)"

  case "${existing_status}" in
    Running|"")
      ;;
    Paused)
      echo "Resuming paused VM ${vm_name}"
      SLICER_URL="${slicer_url}" slicer vm resume "${vm_name}" >/dev/null
      ;;
    Suspended)
      echo "Restoring suspended VM ${vm_name}"
      SLICER_URL="${slicer_url}" slicer vm restore "${vm_name}" >/dev/null
      ;;
    Stopped)
      fail "Existing VM ${vm_name} is stopped. Start the Slicer daemon that owns it, or recreate ${vm_name} before retrying."
      ;;
    *)
      fail "Existing VM ${vm_name} is in unexpected state '${existing_status}'."
      ;;
  esac
else
  other_vms="$(jq -r --arg group "${vm_group}-" '.[] | .hostname | select(startswith($group))' <<<"${list_json}" || true)"
  if [[ -n "${other_vms}" ]]; then
    fail "Expected ${vm_name}, but found other ${vm_group} VMs instead: ${other_vms}"
  fi

  if [[ "${use_local_mac}" == "1" ]]; then
    echo "FAIL ${vm_name} is missing from the active local slicer-mac daemon." >&2
    local_mac_recreate_hint
    exit 1
  fi

  echo "Creating ${vm_name} in host group '${vm_group}' (${vm_cpus} CPU / ${vm_ram_gb}GiB)"
  SLICER_URL="${slicer_url}" slicer vm add "${vm_group}" \
    --cpus "${vm_cpus}" \
    --ram-gb "${vm_ram_gb}" \
    --tag "${tag_target}" \
    --tag "${tag_workspace}" >/dev/null
fi

echo "Waiting for ${vm_name}..."
SLICER_URL="${slicer_url}" slicer vm ready "${vm_name}" --timeout "${ready_timeout}" >/dev/null

root_disk_gb="$(vm_root_disk_gb)"
if (( root_disk_gb < min_disk_gb )); then
  if [[ "${use_local_mac}" == "1" ]]; then
    echo "FAIL ${vm_name} has a ${root_disk_gb}GiB root disk, but at least ${min_disk_gb}GiB is required. The disk cannot be resized in place." >&2
    local_mac_recreate_hint
    exit 1
  fi
  fail "${vm_name} has a ${root_disk_gb}GiB root disk, but at least ${min_disk_gb}GiB is required. Recreate ${vm_name} with a larger disk before retrying."
fi
ok "${vm_name} root disk ${root_disk_gb}GiB (minimum ${min_disk_gb}GiB)"

vm_ip="$(SLICER_URL="${slicer_url}" slicer vm list --json | jq -r --arg vm "${vm_name}" '.[] | select(.hostname == $vm) | .ip')"
[[ -n "${vm_ip}" ]] || fail "Could not determine IP for ${vm_name}"

ok "${vm_name} ready (${vm_ip})"
