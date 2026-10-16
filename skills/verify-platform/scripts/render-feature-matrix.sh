#!/usr/bin/env bash
# Render current production route/application pruning without vendoring or pushing.
set -euo pipefail
export LC_ALL=C
script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$script_dir/../../../scripts/lib/shell-cli.sh"
usage() {
  shell_cli_usage_line ' [--dry-run] [--execute] EVIDENCE_DIR'
  echo 'Render stage and optional-feature combinations into a fresh evidence directory.'
  shell_cli_standard_options
}
shell_cli_parse_standard_only usage "$@" || exit 2
shell_cli_maybe_execute_or_preview_summary usage 'would render the infrastructure feature matrix into EVIDENCE_DIR'
[ "$SHELL_CLI_ARG_COUNT" = 1 ] || { usage >&2; exit 2; }
set -- "${SHELL_CLI_ARGS[0]}"
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
mkdir -p "$1"
out=$(cd "$1" && pwd)
git -C "$root" rev-parse HEAD > "$out/revision.txt"
shasum -a 256 "$root/terraform/kubernetes/scripts/sync-gitea-policies.sh" \
  "$root/terraform/kubernetes/scripts/rewrite-gateway-route-filters.pl" \
  "$root/kubernetes/kind/stages/800-gateway-tls.tfvars" \
  "$root/kubernetes/kind/stages/900-sso.tfvars" \
  "$0" "$(dirname "$0")/check-feature-matrix.py" > "$out/source-sha256.txt"
find "$root/terraform/kubernetes/apps" -type f -name '*.yaml' -print0 | \
  xargs -0 shasum -a 256 >> "$out/source-sha256.txt"
for stage in 800 900; do
  for headlamp in false true; do
    for observability in false true; do
      case_dir="$out/stage${stage}-headlamp${headlamp}-observability${observability}"
      mkdir "$case_dir"
      (
        export STACK_DIR="$root/terraform/kubernetes"
        # Read real cumulative stage booleans; no credentials or production state.
        while read -r key equals value rest; do
          if [[ "$key" == enable_* && "$equals" = = && ( "$value" = true || "$value" = false ) ]]; then
            env_key=$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')
            export "$env_key=$value"
          fi
        done < "$root/kubernetes/kind/stages/${stage}-"*.tfvars
        export ENABLE_HEADLAMP="$headlamp" ENABLE_GRAFANA="$observability"
        export ENABLE_PROMETHEUS="$observability" ENABLE_VICTORIA_LOGS="$observability"
        export ENABLE_OTEL_GATEWAY="$observability" ENABLE_OBSERVABILITY_AGENT=false
        # shellcheck source=/dev/null
        source "$root/terraform/kubernetes/scripts/sync-gitea-policies.sh"
        mkdir -p "$case_dir/repo"
        cp -R "$STACK_DIR/apps" "$case_dir/repo/apps"
        render_gateway_routes_for_cilium "$case_dir/repo"
        prune_argocd_app_manifests "$case_dir/repo/apps/argocd-apps"
        for routes in platform-gateway-routes platform-gateway-routes-sso; do
          prune_gateway_routes_manifests "$case_dir/repo/apps/$routes"
          kubectl kustomize "$case_dir/repo/apps/$routes" > "$case_dir/$routes.yaml"
        done
        printf '%s\n' "stage=$stage headlamp=$headlamp observability=$observability" > "$case_dir/inputs.txt"
      ) > "$case_dir/render.log" 2>&1
    done
  done
done
PYTHONOPTIMIZE=0 uv run --locked --project "$root" python "$script_dir/check-feature-matrix.py" "$out"
