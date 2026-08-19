#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${REPO_ROOT:-}" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
fi

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/wait-for-gitea-ssh.sh"

# shellcheck disable=SC2329 # invoked by name through the shell_cli_* helpers
usage() {
  cat <<'EOF' | sed "s|@SCRIPT_NAME@|${0##*/}|g"
Usage: @SCRIPT_NAME@ [--dry-run] [--execute]

Patch argocd-ssh-known-hosts-cm from the generated Gitea host key, then
restart argocd-repo-server so it re-reads SSH trust and repo credentials.
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

shell_cli_handle_standard_no_args usage "would patch Argo CD known hosts and restart repo-server" "$@"

: "${KUBECONFIG:?KUBECONFIG is required}"
: "${KNOWN_HOSTS_CONTENT:?KNOWN_HOSTS_CONTENT is required}"
: "${ARGOCD_NAMESPACE:?ARGOCD_NAMESPACE is required}"
: "${ROLLOUT_TIMEOUT_SECONDS:?ROLLOUT_TIMEOUT_SECONDS is required}"
: "${GITEA_SSH_TIMEOUT_SECONDS:?GITEA_SSH_TIMEOUT_SECONDS is required}"
command -v kubectl >/dev/null 2>&1 || { echo "kubectl not found in PATH" >&2; exit 1; }

WAIT_FOR_GITEA_SSH_MODE="${WAIT_FOR_GITEA_SSH_MODE:-strict}"
KNOWN_HOSTS_FILE="${KNOWN_HOSTS_FILE:-$(mktemp)}"
mkdir -p "$(dirname "${KNOWN_HOSTS_FILE}")"
printf '%s\n' "${KNOWN_HOSTS_CONTENT}" >"${KNOWN_HOSTS_FILE}"
trap 'rm -f "${KNOWN_HOSTS_FILE}"' EXIT

# The Kubernetes provider state can drift from the live, Helm-owned ConfigMap.
# Patch the live ConfigMap explicitly from the generated Gitea host key file, then
# restart argocd-repo-server so it re-reads both the mounted ssh_known_hosts
# content and the repository credentials secrets. On a clean cluster, skipping
# the restart because the ConfigMap is already current can leave repo-server
# serving stale SSH trust state for newly created repo secrets.
#
# (e.g. "failed calling webhook ... connect: connection refused"). Retry the restart in that case.

retry_webhook_fail() {
  local max=12
  local attempt=0
  local delay=2
  while true; do
    set +e
    out="$("$@" 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -eq 0 ]; then
      echo "$out"
      return 0
    fi
    if echo "$out" | grep -qE 'failed calling webhook|kyverno-svc|kyverno\.svc-fail|connect: connection refused|no endpoints available for service'; then
      attempt=$((attempt + 1))
      if [ "$attempt" -ge "$max" ]; then
        echo "$out" >&2
        return "$rc"
      fi
      echo "WARN webhook not ready; retrying ($attempt/$max) after ${delay}s..." >&2
      sleep "$delay"
      delay=$((delay * 2))
      if [ "$delay" -gt 30 ]; then delay=30; fi
      continue
    fi
    echo "$out" >&2
    return "$rc"
  done
}

patch_known_hosts() {
  local tmpdir
  tmpdir="$(mktemp -d)"

  local base_file="$tmpdir/base"
  local base_filtered="$tmpdir/base-filtered"
  local current_hosts="$tmpdir/current-hosts"
  local merged_file="$tmpdir/merged"
  local patch_file="$tmpdir/patch.yaml"
  local patch_out

  kubectl -n "${ARGOCD_NAMESPACE}" get configmap argocd-ssh-known-hosts-cm -o jsonpath='{.data.ssh_known_hosts}' > "$base_file"
  printf '\n' >> "$base_file"

  awk 'NF {print $1}' "$KNOWN_HOSTS_FILE" | LC_ALL=C sort -u > "$current_hosts"
  awk 'NR==FNR {replace[$1]=1; next} NF && !($1 in replace)' "$current_hosts" "$base_file" > "$base_filtered"
  awk 'NF && !seen[$0]++' "$base_filtered" "$KNOWN_HOSTS_FILE" | LC_ALL=C sort -u > "$merged_file"

  {
    echo "data:"
    echo "  ssh_known_hosts: |"
    sed 's/^/    /' "$merged_file"
  } > "$patch_file"

  patch_out="$(retry_webhook_fail kubectl patch configmap argocd-ssh-known-hosts-cm -n "${ARGOCD_NAMESPACE}" --type merge --patch-file "$patch_file")"
  echo "$patch_out"
  rm -rf "$tmpdir"
}

force_delete_stuck_repo_server_pods() {
  local stuck_pods
  stuck_pods="$(
    kubectl -n "${ARGOCD_NAMESPACE}" get pods \
      -l app.kubernetes.io/name=argocd-repo-server \
      -o jsonpath='{range .items[?(@.metadata.deletionTimestamp)]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true
  )"

  if [ -z "$stuck_pods" ]; then
    return 1
  fi

  while IFS= read -r pod; do
    [ -n "$pod" ] || continue
    echo "WARN force deleting stuck repo-server pod: $pod" >&2
    kubectl -n "${ARGOCD_NAMESPACE}" delete pod "$pod" --force --grace-period=0 >/dev/null 2>&1 || true
  done <<< "$stuck_pods"

  return 0
}

if kubectl -n "${ARGOCD_NAMESPACE}" get deployment argocd-repo-server >/dev/null 2>&1; then
  wait_for_gitea_ssh
  patch_known_hosts
  retry_webhook_fail kubectl rollout restart deployment argocd-repo-server -n "${ARGOCD_NAMESPACE}"
  if ! retry_webhook_fail kubectl rollout status deployment argocd-repo-server -n "${ARGOCD_NAMESPACE}" --timeout="${ROLLOUT_TIMEOUT_SECONDS}s"; then
    if force_delete_stuck_repo_server_pods; then
      retry_webhook_fail kubectl rollout status deployment argocd-repo-server -n "${ARGOCD_NAMESPACE}" --timeout="${ROLLOUT_TIMEOUT_SECONDS}s"
    else
      exit 1
    fi
  fi
else
  echo "WARN argocd-repo-server deployment not found in namespace ${ARGOCD_NAMESPACE}; skipping restart" >&2
fi
