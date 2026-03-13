#!/usr/bin/env bash
set -euo pipefail

if ! command -v docker >/dev/null 2>&1; then
  exit 0
fi

running_kind_nodes="$(
  docker ps --format '{{.Names}}' 2>/dev/null | \
    grep -E '^kind-local-(control-plane|worker([0-9]+)?)$' || true
)"

if [[ -z "${running_kind_nodes}" ]]; then
  exit 0
fi

echo "kind-local is still running." >&2
echo "Stop it before starting Lima on this host:" >&2
echo "  make -C kubernetes/kind stop-kind" >&2
echo "" >&2
echo "Running kind containers:" >&2
while IFS= read -r container; do
  [[ -z "${container}" ]] && continue
  printf '  %s\n' "${container}" >&2
done <<< "${running_kind_nodes}"
exit 1
