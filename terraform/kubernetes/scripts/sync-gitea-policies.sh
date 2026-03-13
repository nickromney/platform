#!/usr/bin/env bash
set -euo pipefail

fail() { echo "sync-gitea-policies: $*" >&2; exit 1; }

DRY_RUN=0

: "${STACK_DIR:?STACK_DIR is required}"
: "${GITEA_HTTP_BASE:?GITEA_HTTP_BASE is required (e.g. http://127.0.0.1:30090)}"
: "${GITEA_ADMIN_USERNAME:?GITEA_ADMIN_USERNAME is required}"
: "${GITEA_ADMIN_PWD:?GITEA_ADMIN_PWD is required}"
: "${GITEA_SSH_USERNAME:?GITEA_SSH_USERNAME is required (typically git)}"
: "${GITEA_SSH_HOST:?GITEA_SSH_HOST is required (typically 127.0.0.1)}"
: "${GITEA_SSH_PORT:?GITEA_SSH_PORT is required}"
: "${GITEA_REPO_OWNER:?GITEA_REPO_OWNER is required}"
: "${GITEA_REPO_NAME:?GITEA_REPO_NAME is required}"
: "${DEPLOY_KEY_TITLE:?DEPLOY_KEY_TITLE is required}"
: "${DEPLOY_PUBLIC_KEY:?DEPLOY_PUBLIC_KEY is required}"
: "${SSH_PRIVATE_KEY_PATH:?SSH_PRIVATE_KEY_PATH is required}"

POLICIES_REPO_URL_CLUSTER="${POLICIES_REPO_URL_CLUSTER:-ssh://${GITEA_SSH_USERNAME}@gitea-ssh.gitea.svc.cluster.local:22/${GITEA_REPO_OWNER}/${GITEA_REPO_NAME}.git}"
GITEA_REPO_OWNER_IS_ORG="${GITEA_REPO_OWNER_IS_ORG:-false}"
GITEA_REPO_OWNER_FALLBACK="${GITEA_REPO_OWNER_FALLBACK:-}"
ENABLE_POLICIES="${ENABLE_POLICIES:-true}"
ENABLE_GATEWAY_TLS="${ENABLE_GATEWAY_TLS:-true}"
ENABLE_CERT_MANAGER="${ENABLE_CERT_MANAGER:-true}"
ENABLE_ACTIONS_RUNNER="${ENABLE_ACTIONS_RUNNER:-true}"
ENABLE_APP_REPO_SENTIMENT="${ENABLE_APP_REPO_SENTIMENT:-false}"
ENABLE_APP_REPO_SUBNETCALC="${ENABLE_APP_REPO_SUBNETCALC:-false}"
ENABLE_PROMETHEUS="${ENABLE_PROMETHEUS:-false}"
ENABLE_GRAFANA="${ENABLE_GRAFANA:-false}"
ENABLE_LOKI="${ENABLE_LOKI:-false}"
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
HARDENED_IMAGE_REGISTRY="${HARDENED_IMAGE_REGISTRY:-dhi.io}"
LLM_GATEWAY_MODE="${LLM_GATEWAY_MODE:-litellm}"
LLM_GATEWAY_EXTERNAL_NAME="${LLM_GATEWAY_EXTERNAL_NAME:-host.docker.internal}"
LLM_GATEWAY_EXTERNAL_CIDR="${LLM_GATEWAY_EXTERNAL_CIDR:-}"
LLAMA_CPP_IMAGE="${LLAMA_CPP_IMAGE:-ghcr.io/ggml-org/llama.cpp:server}"
LLAMA_CPP_HF_REPO="${LLAMA_CPP_HF_REPO:-bartowski/SmolLM2-1.7B-Instruct-GGUF}"
LLAMA_CPP_HF_FILE="${LLAMA_CPP_HF_FILE:-SmolLM2-1.7B-Instruct-Q4_K_M.gguf}"
LLAMA_CPP_MODEL_ALIAS="${LLAMA_CPP_MODEL_ALIAS:-local-classifier}"
LLAMA_CPP_CTX_SIZE="${LLAMA_CPP_CTX_SIZE:-2048}"
LITELLM_UPSTREAM_MODEL="${LITELLM_UPSTREAM_MODEL:-openai/local-classifier}"
LITELLM_UPSTREAM_API_BASE="${LITELLM_UPSTREAM_API_BASE:-http://llama-cpp:8080/v1}"
LITELLM_UPSTREAM_API_KEY="${LITELLM_UPSTREAM_API_KEY:-dummy}"
CERT_MANAGER_CHART_VERSION="${CERT_MANAGER_CHART_VERSION:-v1.19.4}"
DEX_CHART_VERSION="${DEX_CHART_VERSION:-0.24.0}"
GRAFANA_CHART_VERSION="${GRAFANA_CHART_VERSION:-10.5.15}"
HEADLAMP_CHART_VERSION="${HEADLAMP_CHART_VERSION:-0.40.0}"
KYVERNO_CHART_VERSION="${KYVERNO_CHART_VERSION:-3.7.1}"
LOKI_CHART_VERSION="${LOKI_CHART_VERSION:-6.53.0}"
OAUTH2_PROXY_CHART_VERSION="${OAUTH2_PROXY_CHART_VERSION:-10.1.4}"
OPENTELEMETRY_COLLECTOR_CHART_VERSION="${OPENTELEMETRY_COLLECTOR_CHART_VERSION:-0.146.1}"
POLICY_REPORTER_CHART_VERSION="${POLICY_REPORTER_CHART_VERSION:-3.7.3}"
PROMETHEUS_CHART_VERSION="${PROMETHEUS_CHART_VERSION:-28.13.0}"
SIGNOZ_CHART_VERSION="${SIGNOZ_CHART_VERSION:-0.114.0}"
TEMPO_CHART_VERSION="${TEMPO_CHART_VERSION:-1.24.4}"

command -v curl >/dev/null 2>&1 || fail "curl not found"
command -v git >/dev/null 2>&1 || fail "git not found"
command -v helm >/dev/null 2>&1 || fail "helm not found"

tmp=""
cleanup_tmp() {
  local d="${tmp:-}"
  if [[ -n "$d" && -d "$d" ]]; then
    rm -rf "$d"
  fi
  return 0
}
trap cleanup_tmp EXIT

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

rewrite_llm_gateway_external_name() {
  local workload_file="$1"

  if [[ ! -f "${workload_file}" || -z "${LLM_GATEWAY_EXTERNAL_NAME}" ]]; then
    return 0
  fi

  local out
  out="$(mktemp)"
  sed -E "s|(^[[:space:]]*externalName:[[:space:]]*).*$|\\1${LLM_GATEWAY_EXTERNAL_NAME}|g" "${workload_file}" > "${out}"
  mv "${out}" "${workload_file}"
}

resolve_ipv4_for_host() {
  local host="$1"
  local ip=""

  if [[ -z "${host}" ]]; then
    return 1
  fi

  if command -v python3 >/dev/null 2>&1; then
    ip="$(python3 - "${host}" <<'PY'
import socket
import sys

host = sys.argv[1]
try:
    infos = socket.getaddrinfo(host, None, socket.AF_INET, socket.SOCK_STREAM)
except socket.gaierror:
    sys.exit(1)

for info in infos:
    ip = info[4][0]
    if ip:
        print(ip)
        sys.exit(0)

sys.exit(1)
PY
)"
  elif command -v getent >/dev/null 2>&1; then
    ip="$(getent ahostsv4 "${host}" 2>/dev/null | awk 'NR == 1 { print $1 }')"
  elif command -v dig >/dev/null 2>&1; then
    ip="$(dig +short A "${host}" 2>/dev/null | awk 'NF { print; exit }')"
  fi

  [[ -n "${ip}" ]] || return 1
  printf '%s\n' "${ip}"
}

is_loopback_ipv4() {
  case "$1" in
    127.*) return 0 ;;
    *) return 1 ;;
  esac
}

resolve_ipv4_for_host_from_kind_node() {
  local host="$1"
  local node_name=""
  local ip=""

  [[ -n "${host}" ]] || return 1
  command -v docker >/dev/null 2>&1 || return 1

  node_name="$(
    docker ps --format '{{.Names}}' 2>/dev/null | \
      awk '/-control-plane$/ { print; exit }'
  )"
  [[ -n "${node_name}" ]] || return 1

  ip="$(
    docker exec "${node_name}" getent hosts "${host}" 2>/dev/null | \
      awk 'NF { print $1; exit }'
  )"
  [[ -n "${ip}" ]] || return 1
  printf '%s\n' "${ip}"
}

determine_llm_gateway_external_cidr() {
  local cidr="${LLM_GATEWAY_EXTERNAL_CIDR}"
  local ip=""
  local use_kind_resolution="false"

  if [[ -n "${cidr}" ]]; then
    printf '%s\n' "${cidr}"
    return 0
  fi

  ip="$(resolve_ipv4_for_host "${LLM_GATEWAY_EXTERNAL_NAME}")" || true

  if [[ "${LLM_GATEWAY_EXTERNAL_NAME}" == "host.docker.internal" ]]; then
    if [[ -z "${ip}" ]] || is_loopback_ipv4 "${ip}"; then
      use_kind_resolution="true"
    fi
  fi

  if [[ "${use_kind_resolution}" == "true" ]]; then
    ip="$(resolve_ipv4_for_host_from_kind_node "${LLM_GATEWAY_EXTERNAL_NAME}")" || true
  fi

  [[ -n "${ip}" ]] || \
    fail "could not resolve LLM_GATEWAY_EXTERNAL_NAME=${LLM_GATEWAY_EXTERNAL_NAME}; set LLM_GATEWAY_EXTERNAL_CIDR explicitly"

  printf '%s/32\n' "${ip}"
}

rewrite_llm_gateway_policy_cidr() {
  local policy_file="$1"
  local cidr="$2"

  [[ -f "${policy_file}" ]] || return 0

  local out
  out="$(mktemp)"
  sed "s|__LLM_GATEWAY_EXTERNAL_CIDR__|${cidr}|g" "${policy_file}" > "${out}"
  mv "${out}" "${policy_file}"
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
}

rewrite_llm_gateway_mode_value() {
  local workload_file="$1"
  local mode="$2"

  [[ -f "${workload_file}" ]] || return 0

  local out
  out="$(mktemp)"
  awk -v mode="${mode}" '
    /name:[[:space:]]*LLM_GATEWAY_MODE/ { in_env=1; print; next }
    in_env && /value:/ {
      sub(/".*"/, "\"" mode "\"")
      in_env=0
      print
      next
    }
    { print }
  ' "${workload_file}" > "${out}"
  mv "${out}" "${workload_file}"
}

render_llm_gateway_manifests() {
  local workloads_dir="$1"
  local kustomization_file="${workloads_dir}/kustomization.yaml"
  local shared_workloads="${workloads_dir}/all.yaml"
  local direct_manifest="${workloads_dir}/llm-direct.yaml"
  local litellm_manifest="${workloads_dir}/llm-litellm.yaml"

  case "${LLM_GATEWAY_MODE}" in
    litellm)
      rewrite_llm_gateway_mode_value "${shared_workloads}" "litellm"
      remove_if_present "${direct_manifest}"
      remove_kustomization_entry "${kustomization_file}" "llm-direct.yaml"
      add_kustomization_entry "${kustomization_file}" "llm-litellm.yaml"
      replace_literal "${litellm_manifest}" "__LLAMA_CPP_IMAGE__" "${LLAMA_CPP_IMAGE}"
      replace_literal "${litellm_manifest}" "__LLAMA_CPP_HF_REPO__" "${LLAMA_CPP_HF_REPO}"
      replace_literal "${litellm_manifest}" "__LLAMA_CPP_HF_FILE__" "${LLAMA_CPP_HF_FILE}"
      replace_literal "${litellm_manifest}" "__LLAMA_CPP_MODEL_ALIAS__" "${LLAMA_CPP_MODEL_ALIAS}"
      replace_literal "${litellm_manifest}" "__LLAMA_CPP_CTX_SIZE__" "${LLAMA_CPP_CTX_SIZE}"
      replace_literal "${litellm_manifest}" "__LITELLM_UPSTREAM_MODEL__" "${LITELLM_UPSTREAM_MODEL}"
      replace_literal "${litellm_manifest}" "__LITELLM_UPSTREAM_API_BASE__" "${LITELLM_UPSTREAM_API_BASE}"
      replace_literal "${litellm_manifest}" "__LITELLM_UPSTREAM_API_KEY__" "${LITELLM_UPSTREAM_API_KEY}"
      ;;
    direct)
      rewrite_llm_gateway_mode_value "${shared_workloads}" "direct"
      remove_if_present "${litellm_manifest}"
      remove_kustomization_entry "${kustomization_file}" "llm-litellm.yaml"
      add_kustomization_entry "${kustomization_file}" "llm-direct.yaml"
      replace_literal "${direct_manifest}" "__LLM_GATEWAY_EXTERNAL_NAME__" "${LLM_GATEWAY_EXTERNAL_NAME}"
      ;;
    *)
      fail "unsupported LLM_GATEWAY_MODE=${LLM_GATEWAY_MODE}"
      ;;
  esac
}

render_llm_gateway_policies() {
  local shared_dir="$1"
  local kustomization_file="${shared_dir}/kustomization.yaml"

  case "${LLM_GATEWAY_MODE}" in
    litellm)
      remove_if_present "${shared_dir}/sentiment-api-llm-egress.yaml"
      remove_kustomization_entry "${kustomization_file}" "sentiment-api-llm-egress.yaml"
      add_kustomization_entry "${kustomization_file}" "sentiment-llama-cpp-world-egress.yaml"
      ;;
    direct)
      local llm_gateway_cidr
      llm_gateway_cidr="$(determine_llm_gateway_external_cidr)"
      remove_if_present "${shared_dir}/sentiment-llama-cpp-world-egress.yaml"
      remove_kustomization_entry "${kustomization_file}" "sentiment-llama-cpp-world-egress.yaml"
      add_kustomization_entry "${kustomization_file}" "sentiment-api-llm-egress.yaml"
      rewrite_llm_gateway_policy_cidr "${shared_dir}/sentiment-api-llm-egress.yaml" "${llm_gateway_cidr}"
      ;;
    *)
      fail "unsupported LLM_GATEWAY_MODE=${LLM_GATEWAY_MODE}"
      ;;
  esac
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

render_otel_gateway_manifest() {
  local apps_dir="$1"
  local gateway_enabled="false"
  local prom_fanout="false"
  local loki_fanout="false"
  local tempo_fanout="false"
  local signoz_fanout="false"
  local mode="debug"
  local template_dir="${STACK_DIR}/templates/otel-gateway"
  local destination="${apps_dir}/96-otel-collector-prometheus.application.yaml"
  local template_path=""

  if is_true "${ENABLE_OTEL_GATEWAY}" || is_true "${ENABLE_PROMETHEUS}" || is_true "${ENABLE_GRAFANA}" || is_true "${ENABLE_LOKI}" || is_true "${ENABLE_TEMPO}" || is_true "${ENABLE_SIGNOZ}"; then
    gateway_enabled="true"
  fi

  if is_true "${ENABLE_PROMETHEUS}" || is_true "${ENABLE_GRAFANA}"; then
    prom_fanout="true"
  fi

  if is_true "${ENABLE_LOKI}"; then
    loki_fanout="true"
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

  # Determine mode based on enabled exporters
  if is_true "${prom_fanout}" && is_true "${signoz_fanout}"; then
    mode="hybrid"
  elif is_true "${prom_fanout}" || is_true "${loki_fanout}" || is_true "${tempo_fanout}"; then
    mode="prometheus"  # prometheus template now handles loki/tempo too
  elif is_true "${signoz_fanout}"; then
    mode="signoz"
  fi

  template_path="${template_dir}/${mode}.application.yaml"
  [[ -f "${template_path}" ]] || fail "missing OTEL gateway template: ${template_path}"
  cp "${template_path}" "${destination}"
}

prune_argocd_app_manifests() {
  local apps_dir="$1"
  local otel_gateway_enabled="false"
  local observability_enabled="false"

  if is_true "${ENABLE_OTEL_GATEWAY}" || is_true "${ENABLE_PROMETHEUS}" || is_true "${ENABLE_GRAFANA}" || is_true "${ENABLE_LOKI}" || is_true "${ENABLE_TEMPO}" || is_true "${ENABLE_SIGNOZ}"; then
    otel_gateway_enabled="true"
  fi

  if is_true "${otel_gateway_enabled}" || is_true "${ENABLE_PROMETHEUS}" || is_true "${ENABLE_GRAFANA}" || is_true "${ENABLE_LOKI}" || is_true "${ENABLE_TEMPO}" || is_true "${ENABLE_SIGNOZ}"; then
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

  local code
  code=$(curl -sS -o /dev/null -w "%{http_code}" \
    -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
    "${GITEA_HTTP_BASE}/api/v1/orgs/${GITEA_REPO_OWNER}" || echo 000)

  if [[ "${code}" == "200" ]]; then
    return 0
  fi

  fail "organization '${GITEA_REPO_OWNER}' not found; create it before syncing repos"
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
  render_llm_gateway_manifests "${repo_dir}/apps/workloads/base"
  render_llm_gateway_policies "${repo_dir}/cluster-policies/cilium/shared"
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
  fi
  if [[ -d "${repo_dir}/apps/platform-gateway-routes-sso" ]]; then
    prune_gateway_routes_manifests "${repo_dir}/apps/platform-gateway-routes-sso"
  fi
  rewrite_hardened_registry "${repo_dir}"

  printf '%s\n' "${repo_dir}"
}

clone_remote_repo() {
  local dest="$1"
  local remote_url="ssh://${GITEA_SSH_USERNAME}@${GITEA_SSH_HOST}:${GITEA_SSH_PORT}/${GITEA_REPO_OWNER}/${GITEA_REPO_NAME}.git"
  local ssh_cmd

  rm -rf "${dest}"
  ssh_cmd="ssh -i ${SSH_PRIVATE_KEY_PATH} -p ${GITEA_SSH_PORT} -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

  if GIT_SSH_COMMAND="$ssh_cmd" git clone -q --depth 1 --branch main "${remote_url}" "${dest}"; then
    return 0
  fi

  GIT_SSH_COMMAND="$ssh_cmd" git clone -q --depth 1 "${remote_url}" "${dest}"
}

show_dry_run_diff() {
  local rendered_dir="$1"
  local remote_dir="$(dirname "${rendered_dir}")/remote"
  local changes=""

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
  git remote add origin "ssh://${GITEA_SSH_USERNAME}@${GITEA_SSH_HOST}:${GITEA_SSH_PORT}/${GITEA_REPO_OWNER}/${GITEA_REPO_NAME}.git"

  local ssh_cmd
  ssh_cmd="ssh -i ${SSH_PRIVATE_KEY_PATH} -p ${GITEA_SSH_PORT} -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

  local pushed="false"
  for i in {1..20}; do
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
