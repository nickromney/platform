#!/usr/bin/env bash

# The portable timeout wrapper used to live here, reachable only by whatever
# sourced this file -- one script. It is shared now; this keeps the old name as
# a thin alias so callers and their assertions do not have to move at once.
K3S_BOOTSTRAP_LIB_DIR="${K3S_BOOTSTRAP_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib" && pwd)}"
# shellcheck source=scripts/lib/timeout.sh
source "${K3S_BOOTSTRAP_LIB_DIR}/timeout.sh"

k3s_bootstrap_find_client() {
  local candidate

  for candidate in \
    "${K3SUP_PRO_BIN:-}" \
    "$(command -v k3sup-pro 2>/dev/null || true)" \
    "${K3SUP_BIN:-}" \
    "$(command -v k3sup 2>/dev/null || true)" \
    "$HOME/.arkade/bin/k3sup"; do
    [ -n "${candidate}" ] || continue
    [ -x "${candidate}" ] || continue
    echo "${candidate}"
    return 0
  done

  return 1
}

k3s_bootstrap_channel_args() {
  local channel="$1"
  local version="$2"

  if [ -n "${version}" ]; then
    printf '%s\n' "--k3s-version ${version}"
  else
    printf '%s\n' "--k3s-channel ${channel}"
  fi
}

k3s_bootstrap_run_with_timeout() {
  run_with_timeout "$@"
}
