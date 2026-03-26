#!/usr/bin/env bash
set -euo pipefail

fail() { echo "sync-gitea-policies: $*" >&2; exit 1; }

DRY_RUN=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${STACK_DIR:?STACK_DIR is required}"
: "${GITEA_ADMIN_USERNAME:?GITEA_ADMIN_USERNAME is required}"
: "${GITEA_ADMIN_PWD:?GITEA_ADMIN_PWD is required}"
: "${GITEA_SSH_USERNAME:?GITEA_SSH_USERNAME is required (typically git)}"
: "${GITEA_REPO_OWNER:?GITEA_REPO_OWNER is required}"
: "${GITEA_REPO_NAME:?GITEA_REPO_NAME is required}"
: "${DEPLOY_KEY_TITLE:?DEPLOY_KEY_TITLE is required}"
: "${DEPLOY_PUBLIC_KEY:?DEPLOY_PUBLIC_KEY is required}"
: "${SSH_PRIVATE_KEY_PATH:?SSH_PRIVATE_KEY_PATH is required}"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/tf-defaults.sh"

POLICIES_REPO_URL_CLUSTER="${POLICIES_REPO_URL_CLUSTER:-ssh://${GITEA_SSH_USERNAME}@gitea-ssh.gitea.svc.cluster.local:22/${GITEA_REPO_OWNER}/${GITEA_REPO_NAME}.git}"
GITEA_REPO_OWNER_IS_ORG="${GITEA_REPO_OWNER_IS_ORG:-false}"
GITEA_REPO_OWNER_FALLBACK="${GITEA_REPO_OWNER_FALLBACK:-}"
ENABLE_HUBBLE="${ENABLE_HUBBLE:-true}"
ENABLE_POLICIES="${ENABLE_POLICIES:-true}"
ENABLE_GATEWAY_TLS="${ENABLE_GATEWAY_TLS:-true}"
GATEWAY_HTTPS_HOST_PORT="${GATEWAY_HTTPS_HOST_PORT:-443}"
ENABLE_CERT_MANAGER="${ENABLE_CERT_MANAGER:-true}"
ENABLE_ACTIONS_RUNNER="${ENABLE_ACTIONS_RUNNER:-true}"
ENABLE_APP_REPO_SENTIMENT="${ENABLE_APP_REPO_SENTIMENT:-false}"
ENABLE_APP_REPO_SUBNETCALC="${ENABLE_APP_REPO_SUBNETCALC:-false}"
ENABLE_PROMETHEUS="${ENABLE_PROMETHEUS:-false}"
ENABLE_GRAFANA="${ENABLE_GRAFANA:-false}"
ENABLE_LOKI="${ENABLE_LOKI:-false}"
ENABLE_VICTORIA_LOGS="${ENABLE_VICTORIA_LOGS:-false}"
ENABLE_TEMPO="${ENABLE_TEMPO:-false}"
ENABLE_SIGNOZ="${ENABLE_SIGNOZ:-false}"
ENABLE_OTEL_GATEWAY="${ENABLE_OTEL_GATEWAY:-false}"
ENABLE_OBSERVABILITY_AGENT="${ENABLE_OBSERVABILITY_AGENT:-false}"
ENABLE_HEADLAMP="${ENABLE_HEADLAMP:-false}"
PREFER_EXTERNAL_WORKLOAD_IMAGES="${PREFER_EXTERNAL_WORKLOAD_IMAGES:-false}"
EXTERNAL_IMAGE_SENTIMENT_API="${EXTERNAL_IMAGE_SENTIMENT_API:-}"
EXTERNAL_IMAGE_SENTIMENT_AUTH_UI="${EXTERNAL_IMAGE_SENTIMENT_AUTH_UI:-}"
EXTERNAL_IMAGE_SUBNETCALC_API_FASTAPI="${EXTERNAL_IMAGE_SUBNETCALC_API_FASTAPI:-}"
EXTERNAL_IMAGE_SUBNETCALC_APIM_SIMULATOR="${EXTERNAL_IMAGE_SUBNETCALC_APIM_SIMULATOR:-}"
EXTERNAL_IMAGE_SUBNETCALC_FRONTEND_REACT="${EXTERNAL_IMAGE_SUBNETCALC_FRONTEND_REACT:-}"
EXTERNAL_IMAGE_SUBNETCALC_FRONTEND_TYPESCRIPT="${EXTERNAL_IMAGE_SUBNETCALC_FRONTEND_TYPESCRIPT:-}"
PREFER_EXTERNAL_PLATFORM_IMAGES="${PREFER_EXTERNAL_PLATFORM_IMAGES:-false}"
EXTERNAL_PLATFORM_IMAGE_GRAFANA="${EXTERNAL_PLATFORM_IMAGE_GRAFANA:-}"
EXTERNAL_PLATFORM_IMAGE_SIGNOZ_AUTH_PROXY="${EXTERNAL_PLATFORM_IMAGE_SIGNOZ_AUTH_PROXY:-}"
HARDENED_IMAGE_REGISTRY="${HARDENED_IMAGE_REGISTRY:-dhi.io}"
SIGNOZ_AUTH_PROXY_IMAGE="${SIGNOZ_AUTH_PROXY_IMAGE:-ghcr.io/scolastico-dev/s.containers/signoz-auth-proxy:latest}"
CERT_MANAGER_CHART_VERSION="${CERT_MANAGER_CHART_VERSION:-$(tf_default_from_variables cert_manager_chart_version)}"
DEX_CHART_VERSION="${DEX_CHART_VERSION:-$(tf_default_from_variables dex_chart_version)}"
GRAFANA_CHART_VERSION="${GRAFANA_CHART_VERSION:-$(tf_default_from_variables grafana_chart_version)}"
GRAFANA_IMAGE_REGISTRY="${GRAFANA_IMAGE_REGISTRY:-$(tf_default_from_variables grafana_image_registry)}"
GRAFANA_IMAGE_REPOSITORY="${GRAFANA_IMAGE_REPOSITORY:-$(tf_default_from_variables grafana_image_repository)}"
GRAFANA_IMAGE_TAG="${GRAFANA_IMAGE_TAG:-$(tf_default_from_variables grafana_image_tag)}"
GRAFANA_SIDECAR_IMAGE_REGISTRY="${GRAFANA_SIDECAR_IMAGE_REGISTRY:-$(tf_default_from_variables grafana_sidecar_image_registry)}"
GRAFANA_SIDECAR_IMAGE_REPOSITORY="${GRAFANA_SIDECAR_IMAGE_REPOSITORY:-$(tf_default_from_variables grafana_sidecar_image_repository)}"
GRAFANA_SIDECAR_IMAGE_TAG="${GRAFANA_SIDECAR_IMAGE_TAG:-$(tf_default_from_variables grafana_sidecar_image_tag)}"
GRAFANA_VICTORIA_LOGS_PLUGIN_URL="${GRAFANA_VICTORIA_LOGS_PLUGIN_URL:-$(tf_default_from_variables grafana_victoria_logs_plugin_url)}"
GRAFANA_LIVENESS_INITIAL_DELAY_SECONDS="${GRAFANA_LIVENESS_INITIAL_DELAY_SECONDS:-$(tf_default_from_variables grafana_liveness_initial_delay_seconds)}"
HEADLAMP_CHART_VERSION="${HEADLAMP_CHART_VERSION:-$(tf_default_from_variables headlamp_chart_version)}"
KYVERNO_CHART_VERSION="${KYVERNO_CHART_VERSION:-$(tf_default_from_variables kyverno_chart_version)}"
LOKI_CHART_VERSION="${LOKI_CHART_VERSION:-$(tf_default_from_variables loki_chart_version)}"
OAUTH2_PROXY_CHART_VERSION="${OAUTH2_PROXY_CHART_VERSION:-$(tf_default_from_variables oauth2_proxy_chart_version)}"
OPENTELEMETRY_COLLECTOR_CHART_VERSION="${OPENTELEMETRY_COLLECTOR_CHART_VERSION:-$(tf_default_from_variables opentelemetry_collector_chart_version)}"
POLICY_REPORTER_CHART_VERSION="${POLICY_REPORTER_CHART_VERSION:-$(tf_default_from_variables policy_reporter_chart_version)}"
PROMETHEUS_CHART_VERSION="${PROMETHEUS_CHART_VERSION:-$(tf_default_from_variables prometheus_chart_version)}"
SIGNOZ_CHART_VERSION="${SIGNOZ_CHART_VERSION:-$(tf_default_from_variables signoz_chart_version)}"
TEMPO_CHART_VERSION="${TEMPO_CHART_VERSION:-$(tf_default_from_variables tempo_chart_version)}"
VICTORIA_LOGS_CHART_VERSION="${VICTORIA_LOGS_CHART_VERSION:-$(tf_default_from_variables victoria_logs_chart_version)}"

command -v curl >/dev/null 2>&1 || fail "curl not found"
command -v git >/dev/null 2>&1 || fail "git not found"
command -v helm >/dev/null 2>&1 || fail "helm not found"

# shellcheck source=/dev/null
source "${STACK_DIR}/scripts/gitea-local-access.sh"

tmp=""
cleanup() {
  local d="${tmp:-}"
  gitea_local_access_cleanup || true
  if [[ -n "$d" && -d "$d" ]]; then
    rm -rf "$d"
  fi
  return 0
}
trap cleanup EXIT

cleanup_tmp() {
  local d="${tmp:-}"
  if [[ -n "$d" && -d "$d" ]]; then
    rm -rf "$d"
  fi
  tmp=""
  return 0
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        DRY_RUN=1
        ;;
      *)
        fail "unknown flag: $1"
        ;;
    esac
    shift
  done
}

wait_for_gitea() {
  local code
  for i in {1..120}; do
    code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 2 --max-time 5 \
      "${GITEA_HTTP_BASE}/api/v1/version" 2>/dev/null || echo 000)"
    if [[ "${code}" =~ ^[234][0-9][0-9]$ ]]; then
      return 0
    fi
    echo "Waiting for Gitea API... ($i/120)" >&2
    sleep 2
  done
  fail "Gitea API not reachable at ${GITEA_HTTP_BASE}"
}

refresh_gitea_git_access() {
  gitea_local_access_reset both
  : "${GITEA_HTTP_BASE:?GITEA_HTTP_BASE is required after local access setup}"
  : "${GITEA_SSH_HOST:?GITEA_SSH_HOST is required after local access setup}"
  : "${GITEA_SSH_PORT:?GITEA_SSH_PORT is required after local access setup}"
  wait_for_gitea
}

is_true() {
  case "${1}" in
    true|TRUE|1|yes|YES|y|Y) return 0 ;;
    *) return 1 ;;
  esac
}

IMAGE_REPO_OWNER="${GITEA_REPO_OWNER}"

replace_image_ref() {
  local file="$1"
  local image_name="$2"
  local new_image_ref="$3"

  if [[ -z "${new_image_ref}" || ! -f "${file}" ]]; then
    return 0
  fi

  local out
  out="$(mktemp)"
  sed -E "s|(image:[[:space:]]*)([^[:space:]]*/)?${image_name}:[^[:space:]]+|\1${new_image_ref}|g" "${file}" > "${out}"
  mv "${out}" "${file}"
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

rewrite_hardened_registry() {
  local root_dir="$1"
  local file tmp_file

  if [[ -z "${HARDENED_IMAGE_REGISTRY}" || "${HARDENED_IMAGE_REGISTRY}" == "dhi.io" || ! -d "${root_dir}" ]]; then
    return 0
  fi

  while IFS= read -r -d '' file; do
    tmp_file="$(mktemp)"
    sed "s|dhi\\.io/|${HARDENED_IMAGE_REGISTRY}/|g" "${file}" > "${tmp_file}"
    mv "${tmp_file}" "${file}"
  done < <(find "${root_dir}" -type f \( -name '*.yaml' -o -name '*.yml' \) -print0)
}

replace_literal() {
  local file="$1"
  local from="$2"
  local to="$3"

  [[ -f "${file}" ]] || return 0

  local out
  out="$(mktemp)"
  sed "s|${from}|${to}|g" "${file}" > "${out}"
  mv "${out}" "${file}"
}

replace_literal_block() {
  local file="$1"
  local from="$2"
  local to="$3"

  [[ -f "${file}" ]] || return 0

  FILE_PATH="${file}" FROM_LITERAL="${from}" TO_LITERAL="${to}" perl -0pi -e '
    my $from = $ENV{"FROM_LITERAL"};
    my $to = $ENV{"TO_LITERAL"};
    s/\Q$from\E/$to/g;
  ' "${file}"
}

parse_image_ref() {
  local image_ref="$1"
  local __registry_var="$2"
  local __repository_var="$3"
  local __tag_var="$4"
  local repo tag registry repository

  repo="${image_ref%:*}"
  tag="${image_ref##*:}"

  if [[ -z "${image_ref}" || "${repo}" == "${image_ref}" || -z "${repo}" || -z "${tag}" || "${repo}" != */* ]]; then
    fail "invalid image ref '${image_ref}'"
  fi

  registry="${repo%%/*}"
  repository="${repo#*/}"

  if [[ -z "${registry}" || -z "${repository}" ]]; then
    fail "invalid image ref '${image_ref}'"
  fi

  printf -v "${__registry_var}" '%s' "${registry}"
  printf -v "${__repository_var}" '%s' "${repository}"
  printf -v "${__tag_var}" '%s' "${tag}"
}

join_by() {
  local delimiter="$1"
  shift

  local out=""
  local item
  for item in "$@"; do
    [[ -n "${item}" ]] || continue
    if [[ -z "${out}" ]]; then
      out="${item}"
    else
      out="${out}${delimiter}${item}"
    fi
  done

  printf '%s\n' "${out}"
}

strip_wrapping_quotes() {
  local value="$1"
  value="${value%\"}"
  value="${value#\"}"
  printf '%s\n' "${value}"
}

yaml_scalar_for_key() {
  local file="$1"
  local key="$2"
  local value=""

  [[ -f "${file}" ]] || return 0

  value="$(sed -nE "s/^[[:space:]]*${key}:[[:space:]]*(.+)[[:space:]]*$/\\1/p" "${file}" | head -n 1 | xargs)"
  strip_wrapping_quotes "${value}"
}

chart_version_override_for_name() {
  local chart="$1"

  case "${chart}" in
    cert-manager) printf '%s\n' "${CERT_MANAGER_CHART_VERSION}" ;;
    dex) printf '%s\n' "${DEX_CHART_VERSION}" ;;
    grafana) printf '%s\n' "${GRAFANA_CHART_VERSION}" ;;
    headlamp) printf '%s\n' "${HEADLAMP_CHART_VERSION}" ;;
    kyverno) printf '%s\n' "${KYVERNO_CHART_VERSION}" ;;
    loki) printf '%s\n' "${LOKI_CHART_VERSION}" ;;
    oauth2-proxy) printf '%s\n' "${OAUTH2_PROXY_CHART_VERSION}" ;;
    opentelemetry-collector) printf '%s\n' "${OPENTELEMETRY_COLLECTOR_CHART_VERSION}" ;;
    policy-reporter) printf '%s\n' "${POLICY_REPORTER_CHART_VERSION}" ;;
    prometheus) printf '%s\n' "${PROMETHEUS_CHART_VERSION}" ;;
    signoz) printf '%s\n' "${SIGNOZ_CHART_VERSION}" ;;
    tempo) printf '%s\n' "${TEMPO_CHART_VERSION}" ;;
    victoria-logs-single) printf '%s\n' "${VICTORIA_LOGS_CHART_VERSION}" ;;
    *) printf '%s\n' "" ;;
  esac
}

assert_pinned_chart_version() {
  local chart="$1"
  local version="$2"

  case "${version}" in
    ""|"*"|HEAD|head|main|master)
      fail "chart ${chart} must use a pinned version, got '${version}'"
      ;;
  esac
}

vendor_chart() {
  local repo_url="$1"
  local chart="$2"
  local version="$3"
  local vendor_root="$4"
  local repo_name

  assert_pinned_chart_version "${chart}" "${version}"
  mkdir -p "${vendor_root}"
  rm -rf "${vendor_root:?}/${chart}"
  repo_name="vendor-$(printf '%s' "${repo_url}" | cksum | awk '{print $1}')"
  helm repo add "${repo_name}" "${repo_url}" --force-update >/dev/null 2>&1 || true
  helm repo update "${repo_name}" >/dev/null 2>&1 || true
  helm pull "${repo_name}/${chart}" --version "${version}" --untar --untardir "${vendor_root}" >/dev/null
}

patch_vendored_headlamp_chart() {
  local vendor_root="$1"
  local deployment_file="${vendor_root}/headlamp/templates/deployment.yaml"
  local schema_file="${vendor_root}/headlamp/values.schema.json"

  [[ -f "${deployment_file}" ]] || return 0

  perl -0pi -e 's/\{\{- if hasKey \.Values\.config "sessionTTL" \}\}\n            - "-session-ttl=\{\{ \.Values\.config\.sessionTTL \}\}"\n            \{\{- end \}\}/{{- with .Values.config.sessionTTL }}\n            - "-session-ttl={{ . }}"\n            {{- end }}/g' "${deployment_file}"

  if [[ -f "${schema_file}" ]]; then
    perl -0pi -e 's/("sessionTTL":\s*\{\s*"type":\s*"integer",\s*"description":\s*"The time in seconds for the session to be valid",\s*"default":\s*86400,\s*"minimum":\s*)1,/${1}0,/s' "${schema_file}"
  fi
}

rewrite_argocd_app_to_vendored_chart() {
  local app_file="$1"
  local chart_path="$2"

  [[ -f "${app_file}" ]] || return 0

  local out
  out="$(mktemp)"
  awk -v repo_url="${POLICIES_REPO_URL_CLUSTER}" -v chart_path="${chart_path}" '
    /^[[:space:]]*repoURL:[[:space:]]*/ {
      sub(/repoURL:.*/, "repoURL: " repo_url)
      print
      next
    }
    /^[[:space:]]*chart:[[:space:]]*/ {
      next
    }
    /^[[:space:]]*targetRevision:[[:space:]]*/ {
      sub(/targetRevision:.*/, "targetRevision: main")
      print
      print "    path: " chart_path
      path_printed=1
      next
    }
    /^[[:space:]]*path:[[:space:]]*/ {
      next
    }
    /^[[:space:]]*helm:[[:space:]]*/ && !path_printed {
      print "    path: " chart_path
      path_printed=1
      print
      next
    }
    { print }
  ' "${app_file}" > "${out}"
  mv "${out}" "${app_file}"
}

rewrite_external_argocd_apps_to_vendored_charts() {
  local apps_dir="$1"
  local vendor_root="$2"
  local app_file repo_url chart version chart_path version_override

  [[ -d "${apps_dir}" ]] || return 0

  while IFS= read -r app_file; do
    repo_url="$(yaml_scalar_for_key "${app_file}" "repoURL")"
    chart="$(yaml_scalar_for_key "${app_file}" "chart")"
    version="$(yaml_scalar_for_key "${app_file}" "targetRevision")"

    if [[ -z "${repo_url}" || -z "${chart}" ]]; then
      continue
    fi

    if [[ "${repo_url}" == "https://dl.gitea.io/charts/" ]]; then
      continue
    fi

    version_override="$(chart_version_override_for_name "${chart}")"
    if [[ -n "${version_override}" ]]; then
      version="${version_override}"
    fi

    assert_pinned_chart_version "${chart}" "${version}"
    vendor_chart "${repo_url}" "${chart}" "${version}" "${vendor_root}"
    chart_path="apps/vendor/charts/${chart}"
    rewrite_argocd_app_to_vendored_chart "${app_file}" "${chart_path}"
  done < <(find "${apps_dir}" -maxdepth 1 -type f -name '*.yaml' | sort)
}

vendor_direct_tf_only_charts() {
  local vendor_root="$1"

  vendor_chart "https://charts.dexidp.io" "dex" "${DEX_CHART_VERSION}" "${vendor_root}"
  vendor_chart "https://oauth2-proxy.github.io/manifests" "oauth2-proxy" "${OAUTH2_PROXY_CHART_VERSION}" "${vendor_root}"
  vendor_chart "https://kubernetes-sigs.github.io/headlamp/" "headlamp" "${HEADLAMP_CHART_VERSION}" "${vendor_root}"
  patch_vendored_headlamp_chart "${vendor_root}"
}

apply_external_workload_images() {
  local workload_file="$1"

  if ! is_true "${PREFER_EXTERNAL_WORKLOAD_IMAGES}"; then
    return 0
  fi

  replace_image_ref "${workload_file}" "sentiment-api" "${EXTERNAL_IMAGE_SENTIMENT_API}"
  replace_image_ref "${workload_file}" "sentiment-auth-ui" "${EXTERNAL_IMAGE_SENTIMENT_AUTH_UI}"
  replace_image_ref "${workload_file}" "subnetcalc-api-fastapi-container-app" "${EXTERNAL_IMAGE_SUBNETCALC_API_FASTAPI}"
  replace_image_ref "${workload_file}" "subnetcalc-apim-simulator" "${EXTERNAL_IMAGE_SUBNETCALC_APIM_SIMULATOR}"
  replace_image_ref "${workload_file}" "subnetcalc-frontend-react" "${EXTERNAL_IMAGE_SUBNETCALC_FRONTEND_REACT}"
  replace_image_ref "${workload_file}" "subnetcalc-frontend-typescript-vite" "${EXTERNAL_IMAGE_SUBNETCALC_FRONTEND_TYPESCRIPT}"
}

apply_external_platform_images() {
  local root_dir="$1"
  local signoz_manifest="${root_dir}/apps/platform-gateway-routes-sso/signoz-auth-proxy-deployment.yaml"

  if ! is_true "${PREFER_EXTERNAL_PLATFORM_IMAGES}"; then
    return 0
  fi

  if [[ -n "${EXTERNAL_PLATFORM_IMAGE_GRAFANA}" ]]; then
    parse_image_ref "${EXTERNAL_PLATFORM_IMAGE_GRAFANA}" GRAFANA_IMAGE_REGISTRY GRAFANA_IMAGE_REPOSITORY GRAFANA_IMAGE_TAG
    GRAFANA_VICTORIA_LOGS_PLUGIN_URL=""
  fi

  if [[ -n "${EXTERNAL_PLATFORM_IMAGE_SIGNOZ_AUTH_PROXY}" ]]; then
    SIGNOZ_AUTH_PROXY_IMAGE="${EXTERNAL_PLATFORM_IMAGE_SIGNOZ_AUTH_PROXY}"
  fi

  replace_image_ref "${signoz_manifest}" "signoz-auth-proxy" "${SIGNOZ_AUTH_PROXY_IMAGE}"
}

render_grafana_application_manifest() {
  local app_file="$1"
  local plugins_block="        plugins: []"

  [[ -f "${app_file}" ]] || return 0

  if [[ -n "${GRAFANA_VICTORIA_LOGS_PLUGIN_URL}" ]]; then
    plugins_block=$'        plugins:\n          - '"${GRAFANA_VICTORIA_LOGS_PLUGIN_URL}"
  fi

  replace_literal "${app_file}" "__GRAFANA_IMAGE_REGISTRY__" "${GRAFANA_IMAGE_REGISTRY}"
  replace_literal "${app_file}" "__GRAFANA_IMAGE_REPOSITORY__" "${GRAFANA_IMAGE_REPOSITORY}"
  replace_literal "${app_file}" "__GRAFANA_IMAGE_TAG__" "${GRAFANA_IMAGE_TAG}"
  replace_literal "${app_file}" "__GRAFANA_SIDECAR_IMAGE_REGISTRY__" "${GRAFANA_SIDECAR_IMAGE_REGISTRY}"
  replace_literal "${app_file}" "__GRAFANA_SIDECAR_IMAGE_REPOSITORY__" "${GRAFANA_SIDECAR_IMAGE_REPOSITORY}"
  replace_literal "${app_file}" "__GRAFANA_SIDECAR_IMAGE_TAG__" "${GRAFANA_SIDECAR_IMAGE_TAG}"
  replace_literal_block "${app_file}" "__GRAFANA_PLUGINS_VALUES__" "${plugins_block}"
  replace_literal "${app_file}" "__GRAFANA_LIVENESS_INITIAL_DELAY_SECONDS__" "${GRAFANA_LIVENESS_INITIAL_DELAY_SECONDS}"
}

remove_if_present() {
  local path="$1"
  if [[ -e "$path" ]]; then
    rm -f "$path"
  fi
}

remove_kustomization_entry() {
  local kustomization_file="$1"
  local resource_file="$2"

  if [[ ! -f "${kustomization_file}" ]]; then
    return 0
  fi

  local tmp_file
  tmp_file=$(mktemp)
  grep -Fv "  - ${resource_file}" "${kustomization_file}" > "${tmp_file}" || true
  mv "${tmp_file}" "${kustomization_file}"
}

add_kustomization_entry() {
  local kustomization_file="$1"
  local resource_file="$2"

  if [[ ! -f "${kustomization_file}" ]]; then
    return 0
  fi

  if grep -Fqx "  - ${resource_file}" "${kustomization_file}"; then
    return 0
  fi

  printf '  - %s\n' "${resource_file}" >> "${kustomization_file}"
}

remove_referencegrant_service() {
  local file="$1"
  local service_name="$2"

  [[ -f "${file}" ]] || return 0

  local tmp_file
  tmp_file="$(mktemp)"
  awk -v service_name="${service_name}" '
    /^[[:space:]]*-[[:space:]]*group:[[:space:]]*""[[:space:]]*$/ {
      line1 = $0
      if ((getline line2) > 0 && (getline line3) > 0) {
        if (line2 ~ /^[[:space:]]*kind:[[:space:]]*Service[[:space:]]*$/ &&
            line3 ~ ("^[[:space:]]*name:[[:space:]]*" service_name "[[:space:]]*$")) {
          next
        }
        print line1
        print line2
        print line3
        next
      }
    }
    { print }
  ' "${file}" > "${tmp_file}"
  mv "${tmp_file}" "${file}"
}

remove_observability_targetref_route() {
  local file="$1"
  local route_name="$2"

  [[ -f "${file}" ]] || return 0

  local tmp_file
  tmp_file="$(mktemp)"
  awk -v route_name="${route_name}" '
    /^[[:space:]]*-[[:space:]]*group:[[:space:]]*gateway\.networking\.k8s\.io[[:space:]]*$/ {
      line1 = $0
      if ((getline line2) > 0 && (getline line3) > 0) {
        if (line2 ~ /^[[:space:]]*kind:[[:space:]]*HTTPRoute[[:space:]]*$/ &&
            line3 ~ ("^[[:space:]]*name:[[:space:]]*" route_name "[[:space:]]*$")) {
          next
        }
        print line1
        print line2
        print line3
        next
      }
    }
    { print }
  ' "${file}" > "${tmp_file}"
  mv "${tmp_file}" "${file}"
}

render_otel_gateway_manifest() {
  local apps_dir="$1"
  local gateway_enabled="false"
  local prom_fanout="false"
  local loki_fanout="false"
  local victoria_logs_fanout="false"
  local tempo_fanout="false"
  local signoz_fanout="false"
  local destination="${apps_dir}/96-otel-collector-prometheus.application.yaml"
  local traces_exporters=()
  local metrics_exporters=()
  local logs_exporters=()
  local traces_exporters_csv=""
  local metrics_exporters_csv=""
  local logs_exporters_csv=""

  if is_true "${ENABLE_OTEL_GATEWAY}" || is_true "${ENABLE_PROMETHEUS}" || is_true "${ENABLE_GRAFANA}" || is_true "${ENABLE_LOKI}" || is_true "${ENABLE_VICTORIA_LOGS}" || is_true "${ENABLE_TEMPO}" || is_true "${ENABLE_SIGNOZ}"; then
    gateway_enabled="true"
  fi

  if is_true "${ENABLE_PROMETHEUS}" || is_true "${ENABLE_GRAFANA}"; then
    prom_fanout="true"
  fi

  if is_true "${ENABLE_LOKI}"; then
    loki_fanout="true"
  fi

  if is_true "${ENABLE_VICTORIA_LOGS}"; then
    victoria_logs_fanout="true"
  fi

  if is_true "${ENABLE_TEMPO}"; then
    tempo_fanout="true"
  fi

  if is_true "${ENABLE_SIGNOZ}"; then
    signoz_fanout="true"
  fi

  if ! is_true "${gateway_enabled}"; then
    remove_if_present "${destination}"
    return 0
  fi

  if is_true "${prom_fanout}"; then
    traces_exporters+=("spanmetrics")
    metrics_exporters+=("prometheus")
  fi

  if is_true "${signoz_fanout}"; then
    traces_exporters+=("otlp/signoz")
    metrics_exporters+=("otlp/signoz")
  fi

  if is_true "${tempo_fanout}"; then
    traces_exporters+=("otlp/tempo")
  fi

  if is_true "${loki_fanout}"; then
    logs_exporters+=("otlphttp/loki")
  fi

  if is_true "${victoria_logs_fanout}"; then
    logs_exporters+=("otlphttp/victoria-logs")
  fi

  if [[ "${#logs_exporters[@]}" -eq 0 ]] && is_true "${signoz_fanout}"; then
    logs_exporters+=("otlp/signoz")
  fi

  if [[ "${#traces_exporters[@]}" -eq 0 ]]; then
    traces_exporters=("debug")
  fi

  if [[ "${#metrics_exporters[@]}" -eq 0 ]]; then
    metrics_exporters=("debug")
  fi

  if [[ "${#logs_exporters[@]}" -eq 0 ]]; then
    logs_exporters=("debug")
  fi

  traces_exporters_csv="$(join_by ", " "${traces_exporters[@]}")"
  metrics_exporters_csv="$(join_by ", " "${metrics_exporters[@]}")"
  logs_exporters_csv="$(join_by ", " "${logs_exporters[@]}")"

  cat > "${destination}" <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: otel-collector-prometheus
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "96"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: observability
    server: https://kubernetes.default.svc
  source:
    repoURL: https://open-telemetry.github.io/opentelemetry-helm-charts
    chart: opentelemetry-collector
    targetRevision: ${OPENTELEMETRY_COLLECTOR_CHART_VERSION}
    helm:
      releaseName: otel-collector-prometheus
      values: |
        mode: deployment

        nameOverride: otel-collector
        fullnameOverride: otel-collector

        image:
          repository: otel/opentelemetry-collector-contrib

        replicaCount: 1

        service:
          enabled: true
          type: ClusterIP
EOF

  if is_true "${prom_fanout}"; then
    cat >> "${destination}" <<'EOF'
          annotations:
            prometheus.io/scrape: "true"
            prometheus.io/path: /metrics
            prometheus.io/port: "9464"
EOF
  fi

  cat >> "${destination}" <<EOF

        ports:
          otlp:
            enabled: true
            hostPort: 0
            containerPort: 4317
            servicePort: 4317
          otlp-http:
            enabled: true
            hostPort: 0
            containerPort: 4318
            servicePort: 4318
          metrics:
            enabled: ${prom_fanout}
            hostPort: 0
            containerPort: 9464
            servicePort: 9464
          jaeger-compact:
            enabled: false
          jaeger-thrift:
            enabled: false
          jaeger-grpc:
            enabled: false
          zipkin:
            enabled: false

        presets:
          kubernetesAttributes:
            enabled: true
          logsCollection:
            enabled: true
            includeCollectorLogs: false
            storeCheckpoints: true

        resources:
          requests:
            cpu: 50m
            memory: 128Mi
          limits:
            cpu: 300m
            memory: 384Mi

        config:
          receivers:
            otlp:
              protocols:
                grpc:
                  endpoint: 0.0.0.0:4317
                http:
                  endpoint: 0.0.0.0:4318

          processors:
            batch:
              timeout: 1s
              send_batch_size: 1024
            memory_limiter:
              check_interval: 1s
              limit_percentage: 75
              spike_limit_percentage: 15
EOF

  if is_true "${prom_fanout}"; then
    cat >> "${destination}" <<'EOF'

          connectors:
            spanmetrics:
              histogram:
                unit: ms
              dimensions:
                - name: k8s.namespace.name
                - name: http.method
                - name: http.status_code
                - name: service.version
EOF
  fi

  cat >> "${destination}" <<'EOF'

          exporters:
EOF

  if is_true "${prom_fanout}"; then
    cat >> "${destination}" <<'EOF'
            prometheus:
              endpoint: 0.0.0.0:9464
              resource_to_telemetry_conversion:
                enabled: true
EOF
  fi

  if is_true "${signoz_fanout}"; then
    cat >> "${destination}" <<'EOF'
            otlp/signoz:
              endpoint: signoz-otel-collector.observability.svc.cluster.local:4317
              tls:
                insecure: true
EOF
  fi

  if is_true "${loki_fanout}"; then
    cat >> "${destination}" <<'EOF'
            otlphttp/loki:
              endpoint: http://loki.observability.svc.cluster.local:3100/otlp
EOF
  fi

  if is_true "${victoria_logs_fanout}"; then
    cat >> "${destination}" <<'EOF'
            otlphttp/victoria-logs:
              logs_endpoint: http://victoria-logs-victoria-logs-single-server.observability.svc.cluster.local:9428/insert/opentelemetry/v1/logs
EOF
  fi

  if is_true "${tempo_fanout}"; then
    cat >> "${destination}" <<'EOF'
            otlp/tempo:
              endpoint: tempo.observability.svc.cluster.local:4317
              tls:
                insecure: true
EOF
  fi

  if [[ "${traces_exporters_csv}" == "debug" || "${metrics_exporters_csv}" == "debug" || "${logs_exporters_csv}" == "debug" ]]; then
    cat >> "${destination}" <<'EOF'
            debug:
              verbosity: basic
EOF
  fi

  cat >> "${destination}" <<EOF

          service:
            pipelines:
              traces:
                receivers: [otlp]
                processors: [memory_limiter, k8sattributes, batch]
                exporters: [${traces_exporters_csv}]
              metrics:
                receivers: [$(if is_true "${prom_fanout}"; then printf 'otlp, spanmetrics'; else printf 'otlp'; fi)]
                processors: [memory_limiter, k8sattributes, batch]
                exporters: [${metrics_exporters_csv}]
              logs:
                receivers: [filelog]
                processors: [memory_limiter, k8sattributes, batch]
                exporters: [${logs_exporters_csv}]
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - SkipDryRunOnMissingResource=true
EOF
}

prune_argocd_app_manifests() {
  local apps_dir="$1"
  local otel_gateway_enabled="false"
  local observability_enabled="false"

  if is_true "${ENABLE_OTEL_GATEWAY}" || is_true "${ENABLE_PROMETHEUS}" || is_true "${ENABLE_GRAFANA}" || is_true "${ENABLE_LOKI}" || is_true "${ENABLE_VICTORIA_LOGS}" || is_true "${ENABLE_TEMPO}" || is_true "${ENABLE_SIGNOZ}"; then
    otel_gateway_enabled="true"
  fi

  if is_true "${otel_gateway_enabled}" || is_true "${ENABLE_PROMETHEUS}" || is_true "${ENABLE_GRAFANA}" || is_true "${ENABLE_LOKI}" || is_true "${ENABLE_VICTORIA_LOGS}" || is_true "${ENABLE_TEMPO}" || is_true "${ENABLE_SIGNOZ}"; then
    observability_enabled="true"
  fi

  render_otel_gateway_manifest "${apps_dir}"

  if ! is_true "${ENABLE_POLICIES}"; then
    remove_if_present "${apps_dir}/31-policy-reporter.application.yaml"
    remove_if_present "${apps_dir}/20-kyverno.application.yaml"
    remove_if_present "${apps_dir}/30-kyverno-policies.application.yaml"
    remove_if_present "${apps_dir}/40-cilium-policies.application.yaml"
  fi

  if ! is_true "${ENABLE_CERT_MANAGER}"; then
    remove_if_present "${apps_dir}/001-cert-manager.application.yaml"
  fi

  if ! is_true "${ENABLE_GATEWAY_TLS}"; then
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
    remove_if_present "${apps_dir}/91-loki.application.yaml"
    remove_if_present "${apps_dir}/92-victoria-logs.application.yaml"
    remove_if_present "${apps_dir}/92-tempo.application.yaml"
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

  if ! is_true "${ENABLE_LOKI}"; then
    remove_if_present "${apps_dir}/91-loki.application.yaml"
  fi

  if ! is_true "${ENABLE_VICTORIA_LOGS}"; then
    remove_if_present "${apps_dir}/92-victoria-logs.application.yaml"
  fi

  if ! is_true "${ENABLE_TEMPO}"; then
    remove_if_present "${apps_dir}/92-tempo.application.yaml"
  fi

  if ! is_true "${ENABLE_OBSERVABILITY_AGENT}" || ! is_true "${ENABLE_SIGNOZ}"; then
    remove_if_present "${apps_dir}/100-otel-collector-agent.application.yaml"
  fi

  if ! is_true "${ENABLE_OTEL_GATEWAY}" && ! is_true "${ENABLE_PROMETHEUS}" && ! is_true "${ENABLE_GRAFANA}" && ! is_true "${ENABLE_LOKI}" && ! is_true "${ENABLE_VICTORIA_LOGS}" && ! is_true "${ENABLE_SIGNOZ}" && ! is_true "${ENABLE_OBSERVABILITY_AGENT}"; then
    remove_if_present "${apps_dir}/80-observability.namespace.yaml"
  fi
}

prune_gateway_routes_manifests() {
  local routes_dir="$1"
  local kustomization_file="${routes_dir}/kustomization.yaml"

  if ! is_true "${ENABLE_HUBBLE}"; then
    remove_if_present "${routes_dir}/httproute-hubble.yaml"
    remove_if_present "${routes_dir}/referencegrant-hubble.yaml"
    remove_kustomization_entry "${kustomization_file}" "httproute-hubble.yaml"
    remove_kustomization_entry "${kustomization_file}" "referencegrant-hubble.yaml"
    remove_referencegrant_service "${routes_dir}/referencegrant-sso.yaml" "oauth2-proxy-hubble"
    remove_observability_targetref_route "${routes_dir}/observabilitypolicy-tracing.yaml" "hubble"
  fi

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

route_has_oauth2_proxy_backend() {
  local route_file="$1"
  grep -qE '^[[:space:]]*name:[[:space:]]*oauth2-proxy-' "${route_file}"
}

route_primary_hostname() {
  local route_file="$1"
  awk '
    /^[[:space:]]*hostnames:[[:space:]]*$/ { in_hostnames=1; next }
    in_hostnames && /^[[:space:]]*-[[:space:]]*/ {
      sub(/^[[:space:]]*-[[:space:]]*/, "", $0)
      print
      exit
    }
    in_hostnames && /^[^[:space:]]/ { exit }
  ' "${route_file}"
}

render_gateway_route_forwarded_headers() {
  local routes_dir="$1"
  local route_file host tmp_file

  [[ "${GATEWAY_HTTPS_HOST_PORT}" != "443" ]] || return 0
  [[ -d "${routes_dir}" ]] || return 0

  while IFS= read -r -d '' route_file; do
    route_has_oauth2_proxy_backend "${route_file}" || continue
    host="$(route_primary_hostname "${route_file}")"
    [[ -n "${host}" ]] || continue

    tmp_file="$(mktemp)"
    awk -v host="${host}" -v port="${GATEWAY_HTTPS_HOST_PORT}" '
      /^[[:space:]]*backendRefs:[[:space:]]*$/ && !injected {
        print "      filters:"
        print "        - type: RequestHeaderModifier"
        print "          requestHeaderModifier:"
        print "            set:"
        print "              - name: X-Forwarded-Host"
        print "                value: " host ":" port
        print "              - name: X-Forwarded-Port"
        print "                value: \"" port "\""
        print "              - name: X-Forwarded-Proto"
        print "                value: https"
        injected=1
      }
      { print }
    ' "${route_file}" > "${tmp_file}"
    mv "${tmp_file}" "${route_file}"
  done < <(find "${routes_dir}" -maxdepth 1 -type f -name 'httproute-*.yaml' -print0)
}

repo_exists_for_owner() {
  local owner="$1"
  local code
  code=$(curl -sS -o /dev/null -w "%{http_code}" \
    -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
    "${GITEA_HTTP_BASE}/api/v1/repos/${owner}/${GITEA_REPO_NAME}" || echo 000)
  [[ "$code" == "200" ]]
}

ensure_org_exists() {
  if ! is_true "${GITEA_REPO_OWNER_IS_ORG}"; then
    return 0
  fi

  local code payload
  code=$(curl -sS -o /dev/null -w "%{http_code}" \
    -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
    "${GITEA_HTTP_BASE}/api/v1/orgs/${GITEA_REPO_OWNER}" || echo 000)

  if [[ "${code}" == "200" ]]; then
    return 0
  fi

  payload=$(cat <<EOF
{"username":"${GITEA_REPO_OWNER}"}
EOF
)

  echo "Gitea org '${GITEA_REPO_OWNER}' is missing; creating it before syncing repos" >&2
  code=$(curl -sS -o /dev/null -w "%{http_code}" \
    -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
    -H "Content-Type: application/json" \
    -d "${payload}" \
    "${GITEA_HTTP_BASE}/api/v1/orgs" || echo 000)

  if [[ "${code}" != "201" && "${code}" != "409" && "${code}" != "422" ]]; then
    fail "create org '${GITEA_REPO_OWNER}' returned HTTP ${code}"
  fi

  code=$(curl -sS -o /dev/null -w "%{http_code}" \
    -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
    "${GITEA_HTTP_BASE}/api/v1/orgs/${GITEA_REPO_OWNER}" || echo 000)
  [[ "${code}" == "200" ]] || fail "organization '${GITEA_REPO_OWNER}' is still unavailable after create attempt (HTTP ${code})"
}

transfer_repo_if_needed() {
  if ! is_true "${GITEA_REPO_OWNER_IS_ORG}"; then
    return 0
  fi

  if [[ -z "${GITEA_REPO_OWNER_FALLBACK}" ]]; then
    return 0
  fi

  if repo_exists_for_owner "${GITEA_REPO_OWNER}"; then
    return 0
  fi

  if ! repo_exists_for_owner "${GITEA_REPO_OWNER_FALLBACK}"; then
    return 0
  fi

  local payload code
  payload=$(cat <<EOF
{"new_owner":"${GITEA_REPO_OWNER}"}
EOF
)

  code=$(curl -sS -o /dev/null -w "%{http_code}" \
    -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
    -H "Content-Type: application/json" \
    -d "${payload}" \
    "${GITEA_HTTP_BASE}/api/v1/repos/${GITEA_REPO_OWNER_FALLBACK}/${GITEA_REPO_NAME}/transfer" || echo 000)

  if [[ "${code}" != "202" && "${code}" != "201" && "${code}" != "409" ]]; then
    fail "Transfer repo returned HTTP $code"
  fi
}

create_repo_if_missing() {
  if repo_exists_for_owner "${GITEA_REPO_OWNER}"; then
    return 0
  fi

  ensure_org_exists

  transfer_repo_if_needed
  if repo_exists_for_owner "${GITEA_REPO_OWNER}"; then
    return 0
  fi

  local payload code
  payload=$(cat <<EOF
{"name":"${GITEA_REPO_NAME}","private":true,"auto_init":false,"default_branch":"main"}
EOF
)

  local create_url
  if is_true "${GITEA_REPO_OWNER_IS_ORG}"; then
    create_url="${GITEA_HTTP_BASE}/api/v1/orgs/${GITEA_REPO_OWNER}/repos"
  else
    create_url="${GITEA_HTTP_BASE}/api/v1/user/repos"
  fi

  code=$(curl -sS -o /dev/null -w "%{http_code}" \
    -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
    -H "Content-Type: application/json" \
    -d "${payload}" \
    "${create_url}" || echo 000)

  if [[ "$code" != "201" && "$code" != "409" ]]; then
    fail "Create repo returned HTTP $code"
  fi
}

ensure_deploy_key() {
  local payload code
  payload=$(cat <<EOF
{"title":"${DEPLOY_KEY_TITLE}","key":"${DEPLOY_PUBLIC_KEY}","read_only":false}
EOF
)

  code=$(curl -sS -o /dev/null -w "%{http_code}" \
    -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
    -H "Content-Type: application/json" \
    -d "${payload}" \
    "${GITEA_HTTP_BASE}/api/v1/repos/${GITEA_REPO_OWNER}/${GITEA_REPO_NAME}/keys" || echo 000)

  # 201 created, 422 already exists (duplicate key/title), 409 conflict.
  if [[ "$code" != "201" && "$code" != "422" && "$code" != "409" ]]; then
    fail "Add deploy key returned HTTP $code"
  fi
}

render_repo() {
  local root_dir="$1"
  local repo_dir="${root_dir}/repo"
  local vendor_root="${repo_dir}/apps/vendor/charts"

  mkdir -p "${repo_dir}"
  cp -R "${STACK_DIR}/apps" "${repo_dir}/apps"
  cp -R "${STACK_DIR}/cluster-policies" "${repo_dir}/cluster-policies"
  apply_external_workload_images "${repo_dir}/apps/apim/all.yaml"
  apply_external_workload_images "${repo_dir}/apps/workloads/base/all.yaml"
  apply_external_workload_images "${repo_dir}/apps/dev/all.yaml"
  apply_external_workload_images "${repo_dir}/apps/uat/all.yaml"
  apply_external_platform_images "${repo_dir}"
  render_grafana_application_manifest "${repo_dir}/apps/argocd-apps/95-grafana.application.yaml"
  rewrite_image_owner "${repo_dir}/apps/apim/all.yaml"
  rewrite_image_owner "${repo_dir}/apps/workloads/base/all.yaml"
  rewrite_image_owner "${repo_dir}/apps/dev/all.yaml"
  rewrite_image_owner "${repo_dir}/apps/uat/all.yaml"
  prune_argocd_app_manifests "${repo_dir}/apps/argocd-apps"
  mkdir -p "${vendor_root}"
  rewrite_external_argocd_apps_to_vendored_charts "${repo_dir}/apps/argocd-apps" "${vendor_root}"
  vendor_direct_tf_only_charts "${vendor_root}"
  if [[ -d "${repo_dir}/apps/platform-gateway-routes" ]]; then
    prune_gateway_routes_manifests "${repo_dir}/apps/platform-gateway-routes"
    render_gateway_route_forwarded_headers "${repo_dir}/apps/platform-gateway-routes"
  fi
  if [[ -d "${repo_dir}/apps/platform-gateway-routes-sso" ]]; then
    prune_gateway_routes_manifests "${repo_dir}/apps/platform-gateway-routes-sso"
    render_gateway_route_forwarded_headers "${repo_dir}/apps/platform-gateway-routes-sso"
  fi
  rewrite_hardened_registry "${repo_dir}"

  printf '%s\n' "${repo_dir}"
}

clone_remote_repo() {
  local dest="$1"
  local remote_url ssh_cmd

  for i in {1..20}; do
    refresh_gitea_git_access
    remote_url="ssh://${GITEA_SSH_USERNAME}@${GITEA_SSH_HOST}:${GITEA_SSH_PORT}/${GITEA_REPO_OWNER}/${GITEA_REPO_NAME}.git"
    ssh_cmd="ssh -i ${SSH_PRIVATE_KEY_PATH} -p ${GITEA_SSH_PORT} -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

    rm -rf "${dest}"
    if GIT_SSH_COMMAND="$ssh_cmd" git clone -q --depth 1 --branch main "${remote_url}" "${dest}"; then
      return 0
    fi
    if GIT_SSH_COMMAND="$ssh_cmd" git clone -q --depth 1 "${remote_url}" "${dest}"; then
      return 0
    fi
    echo "git clone failed, retrying... ($i/20)" >&2
    sleep 3
  done

  return 1
}

show_dry_run_diff() {
  local rendered_dir="$1"
  local remote_dir
  local changes=""

  remote_dir="$(dirname "${rendered_dir}")/remote"
  if ! clone_remote_repo "${remote_dir}"; then
    fail "could not clone remote repo for dry-run"
  fi

  rsync -a --delete --exclude=.git "${rendered_dir}/" "${remote_dir}/"
  changes="$(git -C "${remote_dir}" status --short --untracked-files=all)"

  if [[ -z "${changes// }" ]]; then
    echo "No diff after sync for policies; nothing to push."
    return 0
  fi

  echo "==> [dry-run] Would commit with message: sync(policies): $(date -Iseconds)"
  printf '%s\n' "${changes}"
}

push_rendered_repo() {
  local rendered_dir="$1"

  pushd "${rendered_dir}" >/dev/null
  git init -q
  git config user.email "kind-demo@local"
  git config user.name "kind-demo"
  # Avoid failures when the host has global commit signing enabled (e.g. 1Password integration).
  git config commit.gpgsign false
  git add -A

  if git diff --cached --quiet; then
    # Ensure we still push at least once on fresh repos.
    echo "(no changes to commit; still ensuring remote is populated)" >&2
    git commit -q --allow-empty -m "sync policies"
  else
    git commit -q -m "sync policies"
  fi

  git branch -M main

  local pushed="false"
  for i in {1..20}; do
    local remote_url ssh_cmd
    refresh_gitea_git_access
    remote_url="ssh://${GITEA_SSH_USERNAME}@${GITEA_SSH_HOST}:${GITEA_SSH_PORT}/${GITEA_REPO_OWNER}/${GITEA_REPO_NAME}.git"
    ssh_cmd="ssh -i ${SSH_PRIVATE_KEY_PATH} -p ${GITEA_SSH_PORT} -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    if git remote get-url origin >/dev/null 2>&1; then
      git remote set-url origin "${remote_url}"
    else
      git remote add origin "${remote_url}"
    fi
    if GIT_SSH_COMMAND="$ssh_cmd" git push -q --force origin main; then
      pushed="true"
      break
    fi
    echo "git push failed, retrying... ($i/20)" >&2
    sleep 3
  done

  popd >/dev/null
  if [[ "$pushed" != "true" ]]; then
    echo "git push failed after retries" >&2
    return 1
  fi

  return 0
}

main() {
  local rendered_dir=""

  parse_args "$@"
  gitea_local_access_setup both
  : "${GITEA_HTTP_BASE:?GITEA_HTTP_BASE is required after local access setup}"
  : "${GITEA_SSH_HOST:?GITEA_SSH_HOST is required after local access setup}"
  : "${GITEA_SSH_PORT:?GITEA_SSH_PORT is required after local access setup}"
  wait_for_gitea
  create_repo_if_missing
  ensure_deploy_key

  cleanup_tmp || true
  tmp="$(mktemp -d)"
  rendered_dir="$(render_repo "${tmp}")"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    show_dry_run_diff "${rendered_dir}"
    return 0
  fi

  if ! push_rendered_repo "${rendered_dir}"; then
    fail "git push failed"
  fi

  echo "Synced ${GITEA_REPO_OWNER}/${GITEA_REPO_NAME} from ${STACK_DIR}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
