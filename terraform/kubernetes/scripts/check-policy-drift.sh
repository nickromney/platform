#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

POLICY_DIR="${POLICY_DIR:-${REPO_ROOT}/terraform/kubernetes/cluster-policies/cilium}"

usage() {
  cat <<EOF
Usage: ${0##*/} [--policy-dir <dir>] [--dry-run] [--execute]

Compare live CiliumClusterwideNetworkPolicies against the rendered source and
fail on divergence.

These policies are GitOps-managed with selfHeal enabled, so a hand-applied
change reverts within seconds and a source change does not reach the cluster
until a tofu apply re-renders the policies repo. Both states look fine from the
Argo Application list.

The failure this exists to catch is worse than a plain mismatch: after a
successful fetch the repo-server caches the Helm index, so an Application can
read sync=Synced, health=Healthy while running on an allowlist that no longer
permits the fetch. The green row is a cached success on top of an unfixed
policy, and it reverts the moment the cache is evicted. The live policy spec is
the only reliable signal, which is what this compares.

$(shell_cli_standard_options)
EOF
}

warn() { echo "WARN check-policy-drift: $*" >&2; }
fail() { echo "FAIL check-policy-drift: $*" >&2; }

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --policy-dir)
      [[ $# -ge 2 ]] || { shell_cli_missing_value "$(shell_cli_script_name)" "--policy-dir"; exit 1; }
      POLICY_DIR="$2"
      shift 2
      ;;
    *)
      shell_cli_unknown_flag "$(shell_cli_script_name)" "$1"
      exit 1
      ;;
  esac
done

shell_cli_maybe_execute_or_preview_summary usage \
  "would compare live Cilium policies in ${POLICY_DIR} against the rendered source"

for tool in kubectl jq yq; do
  command -v "${tool}" >/dev/null 2>&1 || { warn "${tool} not found in PATH; skipping policy drift check"; exit 0; }
done

if ! kubectl cluster-info >/dev/null 2>&1; then
  warn "cluster unreachable; skipping policy drift check"
  exit 0
fi

rendered="$(kubectl kustomize "${POLICY_DIR}" 2>/dev/null || true)"
if [[ -z "${rendered}" ]]; then
  warn "rendered no policies from ${POLICY_DIR}; skipping policy drift check"
  exit 0
fi

# One compact JSON document per line, so each policy can be handled without a
# temp file per policy.
policies="$(printf '%s\n' "${rendered}" |
  yq eval -o=json -I=0 'select(.kind == "CiliumClusterwideNetworkPolicy")' - 2>/dev/null || true)"

if [[ -z "${policies}" ]]; then
  warn "no CiliumClusterwideNetworkPolicy documents in ${POLICY_DIR}; skipping"
  exit 0
fi

# The cilium-gateway-ingress-* policies describe Cilium's own Envoy. They used to
# be skipped here when the operator facts said the NGINX gateway was in use,
# because the renderer pruned them on that path and the source tree always
# declares them. Cilium is the only gateway now, they are always rendered, and
# the operator facts no longer carry cilium_gateway_api -- which made the skip
# unconditional and quietly took eight policies out of drift detection.
checked=0
drifted=0

while IFS= read -r doc; do
  [[ -n "${doc}" ]] || continue
  name="$(printf '%s' "${doc}" | jq -r '.metadata.name')"
  [[ -n "${name}" && "${name}" != "null" ]] || continue

  checked=$((checked + 1))

  want="$(printf '%s' "${doc}" | jq -S '.spec')"

  live_json="$(kubectl get ciliumclusterwidenetworkpolicies "${name}" -o json 2>/dev/null || true)"
  if [[ -z "${live_json}" ]]; then
    drifted=$((drifted + 1))
    fail "${name}: not present in the cluster"
    continue
  fi

  got="$(printf '%s' "${live_json}" | jq -S '.spec')"

  if [[ "${want}" == "${got}" ]]; then
    continue
  fi

  drifted=$((drifted + 1))
  fail "${name}: live policy differs from the rendered source"
  diff <(printf '%s\n' "${want}") <(printf '%s\n' "${got}") |
    sed 's/^/       /' >&2 || true
done <<EOF
${policies}
EOF

if [[ "${drifted}" -gt 0 ]]; then
  echo "" >&2
  echo "FAIL ${drifted} of ${checked} Cilium policies drifted from source" >&2
  echo "     Run tofu apply to re-render the policies repo; kubectl apply alone reverts via selfHeal." >&2
  exit 1
fi

echo "OK   all ${checked} Cilium policies match the rendered source"
