#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${REPO_ROOT:-}" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
fi

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

RUNNER_NAMESPACE="${RUNNER_NAMESPACE:-gitea-runner}"
RUNNER_DEPLOYMENT="${RUNNER_DEPLOYMENT:-act-runner}"
RUNNER_WAIT_SECONDS="${RUNNER_WAIT_SECONDS:-600}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
ARGOCD_APP="${ARGOCD_APP:-gitea-actions-runner}"

# shellcheck disable=SC2329 # invoked by name through the shell_cli_* helpers
usage() {
  cat <<'EOF' | sed "s|@SCRIPT_NAME@|${0##*/}|g"
Usage: @SCRIPT_NAME@ [--dry-run] [--execute]

Wait for the Gitea Actions runner namespace, deployment, and rollout so
app-repo sync cannot fire workflows before a runner exists.
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

shell_cli_handle_standard_no_args usage "would wait for ${RUNNER_NAMESPACE}/${RUNNER_DEPLOYMENT}" "$@"

: "${KUBECONFIG:?KUBECONFIG is required}"
command -v kubectl >/dev/null 2>&1 || { echo "kubectl not found in PATH" >&2; exit 1; }

echo "Waiting for Gitea Actions runner deployment to be ready..."

waited=0
while [ "${waited}" -lt "${RUNNER_WAIT_SECONDS}" ]; do
  if kubectl get ns "${RUNNER_NAMESPACE}" >/dev/null 2>&1; then
    echo "Namespace ${RUNNER_NAMESPACE} exists"
    break
  fi
  sleep 2
  waited=$((waited + 2))
done

if ! kubectl get ns "${RUNNER_NAMESPACE}" >/dev/null 2>&1; then
  echo "Timed out waiting for namespace ${RUNNER_NAMESPACE}" >&2
  echo "ArgoCD app status:" >&2
  kubectl -n "${ARGOCD_NAMESPACE}" get applications.argoproj.io "${ARGOCD_APP}" -o yaml 2>/dev/null || true
  exit 1
fi

waited=0
while [ "${waited}" -lt "${RUNNER_WAIT_SECONDS}" ]; do
  if kubectl -n "${RUNNER_NAMESPACE}" get deploy "${RUNNER_DEPLOYMENT}" >/dev/null 2>&1; then
    echo "Deployment ${RUNNER_NAMESPACE}/${RUNNER_DEPLOYMENT} exists"
    break
  fi
  sleep 2
  waited=$((waited + 2))
done

if ! kubectl -n "${RUNNER_NAMESPACE}" get deploy "${RUNNER_DEPLOYMENT}" >/dev/null 2>&1; then
  echo "Timed out waiting for deployment ${RUNNER_NAMESPACE}/${RUNNER_DEPLOYMENT}" >&2
  echo "ArgoCD app status:" >&2
  kubectl -n "${ARGOCD_NAMESPACE}" get applications.argoproj.io "${ARGOCD_APP}" -o yaml 2>/dev/null || true
  exit 1
fi

if ! kubectl -n "${RUNNER_NAMESPACE}" rollout status "deploy/${RUNNER_DEPLOYMENT}" --timeout="${RUNNER_WAIT_SECONDS}s"; then
  echo "Runner deployment rollout failed" >&2
  kubectl -n "${RUNNER_NAMESPACE}" get pods -o wide || true
  kubectl -n "${RUNNER_NAMESPACE}" describe pods -l app.kubernetes.io/name="${RUNNER_DEPLOYMENT}" || true
  exit 1
fi

echo "Gitea Actions runner is ready"
