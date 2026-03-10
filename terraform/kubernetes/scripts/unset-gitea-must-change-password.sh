#!/usr/bin/env bash
set -euo pipefail

fail() { echo "unset-gitea-must-change-password: $*" >&2; exit 1; }
ok() { echo "unset-gitea-must-change-password: $*"; }

require() { command -v "$1" >/dev/null 2>&1 || fail "missing required binary: $1"; }

require kubectl

NAMESPACE="${GITEA_NAMESPACE:-gitea}"
DEPLOYMENT="${GITEA_DEPLOYMENT:-gitea}"
CONTAINER="${GITEA_CONTAINER:-gitea}"

wait_for_gitea_cli() {
  for _ in $(seq 1 120); do
    if kubectl -n "${NAMESPACE}" exec "deploy/${DEPLOYMENT}" -c "${CONTAINER}" -- \
      gitea admin user list >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  fail "timed out waiting for gitea admin CLI to become ready"
}

wait_for_gitea_cli

# For local dev, we don't want bootstrap-created users (or chart-created admin users)
# to be forced through /user/settings/change_password.
kubectl -n "${NAMESPACE}" exec "deploy/${DEPLOYMENT}" -c "${CONTAINER}" -- \
  gitea admin user must-change-password --all --unset >/dev/null

ok "unset must-change-password for all users"
