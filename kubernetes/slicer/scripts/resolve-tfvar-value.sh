#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 KEY DEFAULT [TFVARS_FILE...]" >&2
  exit 1
fi

key="$1"
default_value="$2"
shift 2

value=""
for file in "$@"; do
  [[ -n "${file}" && -f "${file}" ]] || continue
  current="$(
    grep -E "^[[:space:]]*${key}[[:space:]]*=" "${file}" 2>/dev/null | tail -n 1 | \
      sed -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"?([^\"#]+)\"?.*$/\1/" | xargs || true
  )"
  if [[ -n "${current}" ]]; then
    value="${current}"
  fi
done

if [[ -n "${value}" ]]; then
  printf '%s\n' "${value}"
else
  printf '%s\n' "${default_value}"
fi
