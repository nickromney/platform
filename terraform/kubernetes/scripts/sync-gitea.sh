#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="${STACK_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TMP_ROOT}"' EXIT

BRANCH="${GITEA_BRANCH:-main}"
DEFAULT_POLICIES_REMOTE="http://127.0.0.1:30090/platform/policies.git"
GITEA_POLICIES_REMOTE="${GITEA_POLICIES_REMOTE:-${DEFAULT_POLICIES_REMOTE}}"
GITEA_GIT_USER="${GITEA_GIT_USER:-argocd}"
GITEA_GIT_EMAIL="${GITEA_GIT_EMAIL:-argocd@gitea.test}"
GITEA_SYNC_TFVARS_FILE="${GITEA_SYNC_TFVARS_FILE:-${STACK_DIR}/stages/900-sso.tfvars}"
DRY_RUN=0

BASE_APPS_DIR="${STACK_DIR}/apps"
GENERATED_APPS_DIR="${STACK_DIR}/.run/generated-apps"
CLUSTER_POLICIES_DIR="${STACK_DIR}/cluster-policies"

PORT_FORWARD_PID=""
PORT_FORWARD_LOG=""

RSYNC_EXCLUDES=(
  "--exclude=.terraform"
  "--exclude=.terragrunt-cache"
  "--exclude=.run"
  "--exclude=.git"
  "--exclude=.gitignore"
  "--exclude=.gitmodules"
  "--exclude=.venv"
  "--exclude=venv"
  "--exclude=node_modules"
  "--exclude=dist"
  "--exclude=build"
  "--exclude=.cache"
  "--exclude=.pytest_cache"
  "--exclude=__pycache__"
  "--exclude=.DS_Store"
  "--exclude=*.log"
  "--exclude=*.tfstate"
  "--exclude=*.tfstate.backup"
)

usage() {
  cat <<'EOF'
Usage: sync-gitea.sh [--dry-run]

Options:
  --dry-run   Show what would change without committing/pushing
  -h, --help  Show this message

Environment variables:
  GITEA_BRANCH          Branch name to keep in sync (default: main)
  GITEA_POLICIES_REMOTE Remote URL for the policies repo (default: http://127.0.0.1:30090/platform/policies.git)
  GITEA_USER            HTTP username for Gitea (or rely on existing git credentials)
  GITEA_PASSWORD        HTTP password for Gitea
  GITEA_GIT_USER        Git user for the sync commit (default: argocd)
  GITEA_GIT_EMAIL       Git email for the sync commit (default: argocd@gitea.test)
EOF
}

log() {
  printf '==> %s\n' "$*"
}

die() {
  echo "Error: $*" >&2
  exit 1
}

cleanup_port_forward() {
  if [[ -n "${PORT_FORWARD_PID}" ]]; then
    kill "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true
    wait "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true
    PORT_FORWARD_PID=""
  fi
  if [[ -n "${PORT_FORWARD_LOG}" && -f "${PORT_FORWARD_LOG}" ]]; then
    rm -f "${PORT_FORWARD_LOG}" >/dev/null 2>&1 || true
    PORT_FORWARD_LOG=""
  fi
}
trap cleanup_port_forward EXIT

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        DRY_RUN=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown flag: $1"
        ;;
    esac
    shift
  done
}

is_true() {
  case "${1:-}" in
    true|TRUE|1|yes|YES|y|Y) return 0 ;;
    *) return 1 ;;
  esac
}

IMAGE_REPO_OWNER="${GITEA_REPO_OWNER:-}"

tfvar_bool_or_default() {
  local key="$1"
  local default_value="$2"
  if [[ ! -f "${GITEA_SYNC_TFVARS_FILE}" ]]; then
    printf '%s\n' "${default_value}"
    return 0
  fi

  local value
  value="$(sed -nE "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*(true|false).*/\\1/p" "${GITEA_SYNC_TFVARS_FILE}" | tail -n 1)"
  if [[ -n "${value}" ]]; then
    printf '%s\n' "${value}"
  else
    printf '%s\n' "${default_value}"
  fi
}

resolve_toggle() {
  local env_name="$1"
  local tfvar_key="$2"
  local default_value="$3"
  local current="${!env_name:-}"
  if [[ -n "${current}" ]]; then
    printf '%s\n' "${current}"
    return 0
  fi
  tfvar_bool_or_default "${tfvar_key}" "${default_value}"
}

init_feature_toggles() {
  ENABLE_SSO="$(resolve_toggle ENABLE_SSO enable_sso true)"
  ENABLE_POLICIES="$(resolve_toggle ENABLE_POLICIES enable_policies true)"
  ENABLE_GATEWAY_TLS="$(resolve_toggle ENABLE_GATEWAY_TLS enable_gateway_tls true)"
  ENABLE_ACTIONS_RUNNER="$(resolve_toggle ENABLE_ACTIONS_RUNNER enable_actions_runner true)"
  ENABLE_APP_REPO_SENTIMENT="$(resolve_toggle ENABLE_APP_REPO_SENTIMENT enable_app_repo_sentiment_llm true)"
  ENABLE_APP_REPO_SUBNETCALC="$(resolve_toggle ENABLE_APP_REPO_SUBNETCALC enable_app_repo_subnet_calculator true)"
  ENABLE_PROMETHEUS="$(resolve_toggle ENABLE_PROMETHEUS enable_prometheus true)"
  ENABLE_GRAFANA="$(resolve_toggle ENABLE_GRAFANA enable_grafana true)"
  ENABLE_SIGNOZ="$(resolve_toggle ENABLE_SIGNOZ enable_signoz false)"
  ENABLE_OTEL_GATEWAY="$(resolve_toggle ENABLE_OTEL_GATEWAY enable_otel_gateway false)"
  ENABLE_HEADLAMP="$(resolve_toggle ENABLE_HEADLAMP enable_headlamp true)"
  ENABLE_OBSERVABILITY_AGENT="$(resolve_toggle ENABLE_OBSERVABILITY_AGENT enable_observability_agent false)"
}

remove_if_present() {
  local path="$1"
  if [[ -e "${path}" ]]; then
    rm -f "${path}"
  fi
}

remove_kustomization_entry() {
  local kustomization_file="$1"
  local resource_file="$2"

  if [[ ! -f "${kustomization_file}" ]]; then
    return 0
  fi

  local tmp_file
  tmp_file="$(mktemp)"
  grep -Fv "  - ${resource_file}" "${kustomization_file}" > "${tmp_file}" || true
  mv "${tmp_file}" "${kustomization_file}"
}

rewrite_image_owner() {
  local file="$1"

  if [[ ! -f "${file}" || -z "${IMAGE_REPO_OWNER}" ]]; then
    return 0
  fi

  local image_name out current
  current="${file}"
  for image_name in \
    sentiment-api \
    sentiment-auth-ui \
    subnetcalc-api-fastapi-container-app \
    subnetcalc-apim-simulator \
    subnetcalc-frontend-react \
    subnetcalc-frontend-typescript-vite; do
    out="$(mktemp)"
    sed -E \
      "s|(image:[[:space:]]*[^[:space:]]*/)[^/]+/(${image_name}:)|\\1${IMAGE_REPO_OWNER}/\\2|g" \
      "${current}" > "${out}"
    mv "${out}" "${current}"
  done
}

render_otel_gateway_manifest() {
  local apps_dir="$1"
  local gateway_enabled="false"
  local prom_fanout="false"
  local signoz_fanout="false"
  local mode="debug"
  local template_dir="${STACK_DIR}/templates/otel-gateway"
  local destination="${apps_dir}/96-otel-collector-prometheus.application.yaml"
  local template_path=""

  if is_true "${ENABLE_OTEL_GATEWAY}" || is_true "${ENABLE_PROMETHEUS}" || is_true "${ENABLE_GRAFANA}" || is_true "${ENABLE_SIGNOZ}"; then
    gateway_enabled="true"
  fi

  if is_true "${ENABLE_PROMETHEUS}" || is_true "${ENABLE_GRAFANA}"; then
    prom_fanout="true"
  fi

  if is_true "${ENABLE_SIGNOZ}"; then
    signoz_fanout="true"
  fi

  if ! is_true "${gateway_enabled}"; then
    remove_if_present "${destination}"
    return 0
  fi

  if is_true "${prom_fanout}" && is_true "${signoz_fanout}"; then
    mode="hybrid"
  elif is_true "${prom_fanout}"; then
    mode="prometheus"
  elif is_true "${signoz_fanout}"; then
    mode="signoz"
  fi

  template_path="${template_dir}/${mode}.application.yaml"
  [[ -f "${template_path}" ]] || die "missing OTEL gateway template: ${template_path}"
  cp "${template_path}" "${destination}"
}

prune_argocd_app_manifests() {
  local apps_dir="$1"
  local otel_gateway_enabled="false"
  local observability_enabled="false"

  if is_true "${ENABLE_OTEL_GATEWAY}" || is_true "${ENABLE_PROMETHEUS}" || is_true "${ENABLE_GRAFANA}" || is_true "${ENABLE_SIGNOZ}"; then
    otel_gateway_enabled="true"
  fi

  if is_true "${otel_gateway_enabled}" || is_true "${ENABLE_PROMETHEUS}" || is_true "${ENABLE_GRAFANA}" || is_true "${ENABLE_SIGNOZ}"; then
    observability_enabled="true"
  fi

  render_otel_gateway_manifest "${apps_dir}"

  if ! is_true "${ENABLE_POLICIES}"; then
    remove_if_present "${apps_dir}/31-policy-reporter.application.yaml"
    remove_if_present "${apps_dir}/20-kyverno.application.yaml"
    remove_if_present "${apps_dir}/30-kyverno-policies.application.yaml"
    remove_if_present "${apps_dir}/40-cilium-policies.application.yaml"
  fi

  if ! is_true "${ENABLE_GATEWAY_TLS}"; then
    remove_if_present "${apps_dir}/001-cert-manager.application.yaml"
    remove_if_present "${apps_dir}/002-nginx-gateway-fabric-crds.application.yaml"
    remove_if_present "${apps_dir}/002-nginx-gateway-fabric.application.yaml"
    remove_if_present "${apps_dir}/003-platform-gateway.application.yaml"
    remove_if_present "${apps_dir}/10-cert-manager-config.application.yaml"
    remove_if_present "${apps_dir}/50-platform-gateway-routes.application.yaml"
  fi

  if ! is_true "${ENABLE_ACTIONS_RUNNER}"; then
    remove_if_present "${apps_dir}/60-gitea-actions-runner.application.yaml"
  fi

  if ! is_true "${ENABLE_APP_REPO_SENTIMENT}" && ! is_true "${ENABLE_APP_REPO_SUBNETCALC}"; then
    remove_if_present "${apps_dir}/72-apim.application.yaml"
    remove_if_present "${apps_dir}/74-dev.application.yaml"
    remove_if_present "${apps_dir}/76-uat.application.yaml"
  fi

  if ! is_true "${ENABLE_SIGNOZ}"; then
    remove_if_present "${apps_dir}/82-signoz-clickhouse.service.yaml"
    remove_if_present "${apps_dir}/90-signoz.application.yaml"
    remove_if_present "${apps_dir}/110-signoz-ui-nodeport.service.yaml"
  fi

  if ! is_true "${observability_enabled}"; then
    remove_if_present "${apps_dir}/80-observability.namespace.yaml"
    remove_if_present "${apps_dir}/90-prometheus.application.yaml"
    remove_if_present "${apps_dir}/95-grafana.application.yaml"
    remove_if_present "${apps_dir}/96-otel-collector-prometheus.application.yaml"
    remove_if_present "${apps_dir}/110-grafana-ui-nodeport.service.yaml"
  fi

  if ! is_true "${ENABLE_PROMETHEUS}"; then
    remove_if_present "${apps_dir}/90-prometheus.application.yaml"
  fi

  if ! is_true "${ENABLE_GRAFANA}"; then
    remove_if_present "${apps_dir}/95-grafana.application.yaml"
    remove_if_present "${apps_dir}/110-grafana-ui-nodeport.service.yaml"
  fi

  if ! is_true "${ENABLE_OBSERVABILITY_AGENT}" || ! is_true "${ENABLE_SIGNOZ}"; then
    remove_if_present "${apps_dir}/100-otel-collector-agent.application.yaml"
  fi

  if ! is_true "${ENABLE_OTEL_GATEWAY}" && ! is_true "${ENABLE_PROMETHEUS}" && ! is_true "${ENABLE_GRAFANA}" && ! is_true "${ENABLE_SIGNOZ}" && ! is_true "${ENABLE_OBSERVABILITY_AGENT}"; then
    remove_if_present "${apps_dir}/80-observability.namespace.yaml"
  fi
}

prune_gateway_routes_manifests() {
  local routes_dir="$1"
  local kustomization_file="${routes_dir}/kustomization.yaml"

  if ! is_true "${ENABLE_POLICIES}" || ! is_true "${ENABLE_GATEWAY_TLS}"; then
    remove_if_present "${routes_dir}/httproute-kyverno.yaml"
    remove_if_present "${routes_dir}/referencegrant-policy-reporter.yaml"
    remove_kustomization_entry "${kustomization_file}" "httproute-kyverno.yaml"
    remove_kustomization_entry "${kustomization_file}" "referencegrant-policy-reporter.yaml"
  fi

  if ! is_true "${ENABLE_HEADLAMP}"; then
    remove_if_present "${routes_dir}/httproute-headlamp.yaml"
    remove_if_present "${routes_dir}/referencegrant-headlamp.yaml"
    remove_kustomization_entry "${kustomization_file}" "httproute-headlamp.yaml"
    remove_kustomization_entry "${kustomization_file}" "referencegrant-headlamp.yaml"
  fi

  if ! is_true "${ENABLE_SIGNOZ}"; then
    remove_if_present "${routes_dir}/httproute-signoz.yaml"
    remove_if_present "${routes_dir}/referencegrant-signoz.yaml"
    remove_if_present "${routes_dir}/referencegrant-signoz-sso.yaml"
    remove_if_present "${routes_dir}/observabilitypolicy-tracing-signoz.yaml"
    remove_if_present "${routes_dir}/rbac-signoz-bootstrap.yaml"
    remove_if_present "${routes_dir}/job-signoz-bootstrap.yaml"
    remove_if_present "${routes_dir}/signoz-auth-proxy-configmap.yaml"
    remove_if_present "${routes_dir}/signoz-auth-proxy-deployment.yaml"
    remove_if_present "${routes_dir}/signoz-auth-proxy-service.yaml"
    remove_kustomization_entry "${kustomization_file}" "httproute-signoz.yaml"
    remove_kustomization_entry "${kustomization_file}" "referencegrant-signoz.yaml"
    remove_kustomization_entry "${kustomization_file}" "referencegrant-signoz-sso.yaml"
    remove_kustomization_entry "${kustomization_file}" "observabilitypolicy-tracing-signoz.yaml"
    remove_kustomization_entry "${kustomization_file}" "rbac-signoz-bootstrap.yaml"
    remove_kustomization_entry "${kustomization_file}" "job-signoz-bootstrap.yaml"
    remove_kustomization_entry "${kustomization_file}" "signoz-auth-proxy-configmap.yaml"
    remove_kustomization_entry "${kustomization_file}" "signoz-auth-proxy-deployment.yaml"
    remove_kustomization_entry "${kustomization_file}" "signoz-auth-proxy-service.yaml"
  fi

  if ! is_true "${ENABLE_GRAFANA}"; then
    remove_if_present "${routes_dir}/httproute-grafana.yaml"
    remove_kustomization_entry "${kustomization_file}" "httproute-grafana.yaml"
  fi

  if ! is_true "${ENABLE_APP_REPO_SENTIMENT}"; then
    remove_if_present "${routes_dir}/httproute-sentiment-dev.yaml"
    remove_if_present "${routes_dir}/httproute-sentiment-uat.yaml"
    remove_kustomization_entry "${kustomization_file}" "httproute-sentiment-dev.yaml"
    remove_kustomization_entry "${kustomization_file}" "httproute-sentiment-uat.yaml"
  fi

  if ! is_true "${ENABLE_APP_REPO_SUBNETCALC}"; then
    remove_if_present "${routes_dir}/httproute-subnetcalc-dev.yaml"
    remove_if_present "${routes_dir}/httproute-subnetcalc-uat.yaml"
    remove_kustomization_entry "${kustomization_file}" "httproute-subnetcalc-dev.yaml"
    remove_kustomization_entry "${kustomization_file}" "httproute-subnetcalc-uat.yaml"
  fi
}

setup_auth() {
  if [[ -n "${GITEA_USER:-}" && -n "${GITEA_PASSWORD:-}" ]]; then
    export GITEA_USER
    export GITEA_PASSWORD
    local askpass="${TMP_ROOT}/git-askpass.sh"
    cat <<'EOF' > "${askpass}"
#!/usr/bin/env bash
case "$1" in
  *Username*) printf '%s\n' "${GITEA_USER}" ;;
  *Password*) printf '%s\n' "${GITEA_PASSWORD}" ;;
esac
EOF
    chmod +x "${askpass}"
    export GIT_ASKPASS="${askpass}"
    export GIT_TERMINAL_PROMPT=0
  fi
}

tcp_connect_ok() {
  local host="$1"
  local port="$2"
  timeout 1 bash -c "exec 3<>/dev/tcp/${host}/${port}" >/dev/null 2>&1
}

pick_free_local_port() {
  # Pick a port very unlikely to conflict with the hostPort mappings (30080/30090/etc).
  local p
  for p in $(seq 18090 18150); do
    if ! tcp_connect_ok 127.0.0.1 "${p}"; then
      echo "${p}"
      return 0
    fi
  done
  return 1
}

ensure_policies_remote_reachable() {
  # If the policies remote points at a kind hostPort (default 30090) but the port isn't actually reachable
  # (common when the cluster wasn't created with extraPortMappings), fall back to a kubectl port-forward.
  #
  # This keeps `make gitea-sync` working even if NodePorts/hostPorts aren't accessible locally.
  local url="${GITEA_POLICIES_REMOTE}"
  if [[ "${url}" =~ ^https?://(127\.0\.0\.1|localhost):([0-9]+)/ ]]; then
    local host="${BASH_REMATCH[1]}"
    local port="${BASH_REMATCH[2]}"
    if tcp_connect_ok "${host}" "${port}"; then
      return 0
    fi

    command -v kubectl >/dev/null 2>&1 || die "kubectl not found (required for port-forward fallback)"

    local pf_port
    pf_port="$(pick_free_local_port)" || die "failed to find a free local port for gitea port-forward"
    PORT_FORWARD_LOG="${TMP_ROOT}/kubectl-port-forward-gitea.log"

    log "Gitea not reachable at ${host}:${port}; starting port-forward on 127.0.0.1:${pf_port} -> gitea/gitea-http:3000"
    kubectl -n gitea port-forward svc/gitea-http "${pf_port}:3000" >"${PORT_FORWARD_LOG}" 2>&1 &
    PORT_FORWARD_PID="$!"

    for _ in $(seq 1 40); do
      if tcp_connect_ok 127.0.0.1 "${pf_port}"; then
        break
      fi
      sleep 0.25
    done
    if ! tcp_connect_ok 127.0.0.1 "${pf_port}"; then
      log "port-forward log (tail):"
      tail -n 50 "${PORT_FORWARD_LOG}" || true
      die "gitea port-forward did not become ready"
    fi

    # Swap the remote to use the port-forward.
    GITEA_POLICIES_REMOTE="$(echo "${url}" | sed -E "s#^https?://(127\\.0\\.0\\.1|localhost):[0-9]+/#http://127.0.0.1:${pf_port}/#")"
    log "Using policies remote via port-forward: ${GITEA_POLICIES_REMOTE}"
  fi
}

clone_repo() {
  local url="$1"
  local dest="$2"
  rm -rf "${dest}"
  if git clone --depth 1 --branch "${BRANCH}" "${url}" "${dest}" >/dev/null 2>&1; then
    :
  else
    git clone --depth 1 "${url}" "${dest}"
  fi
  git -C "${dest}" config core.fileMode false >/dev/null
}

build_stage() {
  local stage="${TMP_ROOT}/policies-stage"
  local launchpad_renderer="${STACK_DIR}/scripts/render-platform-launchpad.sh"
  local launchpad_target=""
  mkdir -p "${stage}/apps/_applications"

  if [[ -d "${BASE_APPS_DIR}" ]]; then
    rsync -a --delete "${RSYNC_EXCLUDES[@]}" "${BASE_APPS_DIR}/" "${stage}/apps/"
  fi

  if compgen -G "${stage}/apps/*.yaml" >/dev/null; then
    for appfile in "${stage}/apps/"*.yaml; do
      mv "${appfile}" "${stage}/apps/_applications/" || true
    done
  fi

  if [[ -d "${GENERATED_APPS_DIR}" ]]; then
    rsync -a --delete "${RSYNC_EXCLUDES[@]}" "${GENERATED_APPS_DIR}/" "${stage}/apps/_applications/"
    shopt -s nullglob
    for dir in "${GENERATED_APPS_DIR}"/*/; do
      rsync -a "${RSYNC_EXCLUDES[@]}" "${dir}" "${stage}/apps/$(basename "${dir}")/"
    done
    shopt -u nullglob
  fi

  if [[ -d "${CLUSTER_POLICIES_DIR}" ]]; then
    rsync -a --delete "${RSYNC_EXCLUDES[@]}" "${CLUSTER_POLICIES_DIR}/" "${stage}/cluster-policies/"
  fi

  rewrite_image_owner "${stage}/apps/workloads/base/all.yaml"
  rewrite_image_owner "${stage}/apps/dev/all.yaml"
  rewrite_image_owner "${stage}/apps/uat/all.yaml"

  if [[ -d "${stage}/apps/argocd-apps" ]]; then
    prune_argocd_app_manifests "${stage}/apps/argocd-apps"
  fi
  if [[ -d "${stage}/apps/platform-gateway-routes" ]]; then
    prune_gateway_routes_manifests "${stage}/apps/platform-gateway-routes"
  fi
  if [[ -d "${stage}/apps/platform-gateway-routes-sso" ]]; then
    prune_gateway_routes_manifests "${stage}/apps/platform-gateway-routes-sso"
  fi

  launchpad_target="${stage}/apps/argocd-apps/95-grafana.application.yaml"
  if [[ -f "${launchpad_target}" ]]; then
    [[ -x "${launchpad_renderer}" ]] || die "missing launchpad renderer: ${launchpad_renderer}"
    ENABLE_SSO="${ENABLE_SSO}" \
    ENABLE_HEADLAMP="${ENABLE_HEADLAMP}" \
    ENABLE_APP_REPO_SENTIMENT="${ENABLE_APP_REPO_SENTIMENT}" \
    ENABLE_APP_REPO_SUBNETCALC="${ENABLE_APP_REPO_SUBNETCALC}" \
    STACK_DIR="${STACK_DIR}" \
    "${launchpad_renderer}" --target "${launchpad_target}"
  fi

  echo "${stage}"
}

sync_policies() {
  local stage
  stage="$(build_stage)"
  local dest="${TMP_ROOT}/policies"

  ensure_policies_remote_reachable

  log "Cloning ${GITEA_POLICIES_REMOTE} -> ${dest}"
  clone_repo "${GITEA_POLICIES_REMOTE}" "${dest}"

  rsync -a --delete "${RSYNC_EXCLUDES[@]}" "${stage}/" "${dest}/"

  local changes
  changes="$(git -C "${dest}" status --short --untracked-files=all)"
  if [[ -z "${changes// }" ]]; then
    log "No diff after sync for policies; nothing to push."
    return 0
  fi

  git -C "${dest}" config user.name "${GITEA_GIT_USER}"
  git -C "${dest}" config user.email "${GITEA_GIT_EMAIL}"
  git -C "${dest}" add .

  local message
  message="${GITEA_SYNC_MESSAGE:-sync(policies): $(date -Iseconds)}"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "[dry-run] Would commit with message: ${message}"
    git -C "${dest}" status --short --untracked-files=all
    return 0
  fi

  git -C "${dest}" -c commit.gpgsign=false commit -m "${message}" >/dev/null
  log "Pushing policies to ${GITEA_POLICIES_REMOTE} (${BRANCH})"
  git -C "${dest}" push origin "${BRANCH}"
}

main() {
  parse_args "$@"
  init_feature_toggles
  setup_auth
  sync_policies
}

main "$@"
