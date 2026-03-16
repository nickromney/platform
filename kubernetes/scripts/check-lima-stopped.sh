#!/usr/bin/env bash
set -euo pipefail

lima_instance_prefix="${LIMA_INSTANCE_PREFIX:-k3s-node}"
running_lima_vms=""
running_lima_proxies=""

if command -v limactl >/dev/null 2>&1; then
  running_lima_vms="$(
    limactl list 2>/dev/null | \
      awk -v prefix="^${lima_instance_prefix}-[0-9]+$" '$1 ~ prefix && $2 == "Running" { print $1 }' || true
  )"
fi

if command -v docker >/dev/null 2>&1; then
  running_lima_proxies="$(
    docker ps --format '{{.Names}}' 2>/dev/null | \
      grep -E '^(limavm-platform-gateway-443|limavm-platform-llm-12434)$' || true
  )"
fi

if [[ -z "${running_lima_vms}" && -z "${running_lima_proxies}" ]]; then
  exit 0
fi

echo "Lima is still running." >&2
echo "Stop it before assuming the shared localhost ports are free:" >&2
echo "  make -C kubernetes/lima stop-lima" >&2
echo "" >&2

if [[ -n "${running_lima_vms}" ]]; then
  echo "Running Lima VMs:" >&2
  while IFS= read -r vm; do
    [[ -z "${vm}" ]] && continue
    printf '  %s\n' "${vm}" >&2
  done <<< "${running_lima_vms}"
fi

if [[ -n "${running_lima_proxies}" ]]; then
  [[ -n "${running_lima_vms}" ]] && echo "" >&2
  echo "Running Lima proxy containers:" >&2
  while IFS= read -r container; do
    [[ -z "${container}" ]] && continue
    printf '  %s\n' "${container}" >&2
  done <<< "${running_lima_proxies}"
fi

exit 1
