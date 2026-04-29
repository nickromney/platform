#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute]

Estimate how much space the standard Docker builder/system prune sequence would reclaim.
$(shell_cli_standard_options)
EOF
}

fail() {
  echo "docker-prune-estimate: $*" >&2
  exit 1
}

shell_cli_handle_standard_no_args usage \
  "would estimate reclaimable Docker builder and system prune space" \
  "$@"

command -v docker >/dev/null 2>&1 || fail "docker not found in PATH"
command -v jq >/dev/null 2>&1 || fail "jq not found in PATH"

clean_reclaimable_text() {
  local value="${1:-0B}"
  value="${value%% *}"
  if [[ -z "${value}" || "${value}" == "null" ]]; then
    value="0B"
  fi
  printf '%s\n' "${value}"
}

human_to_bytes() {
  local input="${1:-0B}"
  local number unit multiplier

  input="${input//[[:space:]]/}"
  if [[ -z "${input}" || "${input}" == "0" || "${input}" == "0B" ]]; then
    printf '0\n'
    return 0
  fi

  if [[ ! "${input}" =~ ^([0-9]+([.][0-9]+)?)([A-Za-z]+)$ ]]; then
    fail "could not parse size '${input}'"
  fi

  number="${BASH_REMATCH[1]}"
  unit="${BASH_REMATCH[3]}"

  case "${unit}" in
    B) multiplier=1 ;;
    kB|KB) multiplier=1000 ;;
    MB) multiplier=1000000 ;;
    GB) multiplier=1000000000 ;;
    TB) multiplier=1000000000000 ;;
    PB) multiplier=1000000000000000 ;;
    KiB) multiplier=1024 ;;
    MiB) multiplier=1048576 ;;
    GiB) multiplier=1073741824 ;;
    TiB) multiplier=1099511627776 ;;
    PiB) multiplier=1125899906842624 ;;
    *) fail "unsupported size unit '${unit}' in '${input}'" ;;
  esac

  awk -v number="${number}" -v multiplier="${multiplier}" 'BEGIN { printf "%.0f\n", number * multiplier }'
}

bytes_to_human() {
  local bytes="${1:-0}"
  awk -v bytes="${bytes}" '
    BEGIN {
      split("B kB MB GB TB PB", units, " ")
      value = bytes + 0
      idx = 1
      while (value >= 1000 && idx < 6) {
        value /= 1000
        idx++
      }
      if (idx == 1) {
        printf "%.0f %s\n", value, units[idx]
      } else {
        printf "%.2f %s\n", value, units[idx]
      }
    }
  '
}

lookup_reclaimable() {
  local rows="$1"
  local type="$2"
  local value
  value="$(printf '%s\n' "${rows}" | jq -r --arg type "${type}" 'select(.Type == $type) | .Reclaimable' | head -n 1)"
  clean_reclaimable_text "${value}"
}

df_rows="$(docker system df --format '{{json .}}' 2>/dev/null || true)"
[[ -n "${df_rows}" ]] || fail "docker system df returned no data"

images_text="$(lookup_reclaimable "${df_rows}" "Images")"
containers_text="$(lookup_reclaimable "${df_rows}" "Containers")"
volumes_text="$(lookup_reclaimable "${df_rows}" "Local Volumes")"
build_cache_text="$(lookup_reclaimable "${df_rows}" "Build Cache")"

images_bytes="$(human_to_bytes "${images_text}")"
containers_bytes="$(human_to_bytes "${containers_text}")"
volumes_bytes="$(human_to_bytes "${volumes_text}")"
build_cache_bytes="$(human_to_bytes "${build_cache_text}")"

system_prune_bytes=$((images_bytes + containers_bytes))
combined_bytes=$((build_cache_bytes + system_prune_bytes))

cat <<EOF
Docker prune estimate

Exact sequence estimate:
  docker builder prune -af : $(bytes_to_human "${build_cache_bytes}")
  docker system prune -af  : $(bytes_to_human "${system_prune_bytes}")
    images                 : ${images_text}
    containers             : ${containers_text}
  combined sequence        : $(bytes_to_human "${combined_bytes}") plus any unused networks

Not included in those commands:
  local volumes            : ${volumes_text}
  networks                 : docker system df does not expose reclaimable network bytes ahead of time

Notes:
  - The combined estimate matches this exact two-command sequence, so build cache is counted only once.
  - To reclaim local volumes as well, you would need docker system prune --volumes or docker volume prune.
EOF

if [[ "${volumes_bytes}" -gt 0 ]]; then
  echo "  - Reclaiming local volumes is a separate decision because it can remove persistent app and database state."
fi
