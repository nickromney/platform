#!/usr/bin/env bash
set -euo pipefail

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
NC=$'\033[0m'

ok() { echo "${GREEN}✔${NC} $*"; }
warn() { echo "${YELLOW}⚠${NC} $*"; }
fail() { echo "${RED}✖${NC} $*" >&2; exit 1; }

require() {
  local bin="$1"
  command -v "$bin" >/dev/null 2>&1 || fail "$bin not found in PATH"
}

require helm
require jq

cluster_reachable() {
  if ! command -v kubectl >/dev/null 2>&1; then
    return 1
  fi

  # Fast failure when kubeconfig/current-context isn't set.
  local ctx
  ctx=$(kubectl config current-context 2>/dev/null || true)
  if [ -z "$ctx" ]; then
    return 1
  fi

  # Keep this very short; we only want to know whether the API server is reachable.
  kubectl get ns --request-timeout=2s >/dev/null 2>&1
}

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STACK_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../../.." && pwd)
STAGES_DIR="${STAGES_DIR:-${REPO_ROOT}/kubernetes/kind/stages}"
ARGOCD_APPS_DIR="${STACK_DIR}/apps/argocd-apps"
VARIABLES_FILE="${STACK_DIR}/variables.tf"

tfvar_get() {
  local file="$1"
  local key="$2"
  if [ ! -f "$file" ]; then
    echo ""
    return 0
  fi
  local line
  line=$(grep -E "^[[:space:]]*${key}[[:space:]]*=[[:space:]]*" "$file" 2>/dev/null | tail -n 1 || true)
  if [ -z "$line" ]; then
    echo ""
    return 0
  fi
  echo "$line" | sed -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"?([^\"#]+)\"?.*$/\1/" | xargs
}

tfvar_get_any_stage() {
  local key="$1"
  local line
  line=$(grep -hE "^[[:space:]]*${key}[[:space:]]*=[[:space:]]*" "${STAGES_DIR}"/*.tfvars 2>/dev/null | head -n 1 || true)
  if [ -z "$line" ]; then
    echo ""
    return 0
  fi
  echo "$line" | sed -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"?([^\"#]+)\"?.*$/\1/" | xargs
}

tfvar_get_any_stage_or_default() {
  local key="$1"
  local fallback="$2"
  local v
  v=$(tfvar_get_any_stage "$key")
  if [ -n "$v" ]; then
    echo "$v"
  else
    echo "$fallback"
  fi
}

tf_default_from_variables() {
  local key="$1"

  if [ ! -f "${VARIABLES_FILE}" ]; then
    echo ""
    return 0
  fi

  awk -v key="$key" '
    $0 ~ "^[[:space:]]*variable[[:space:]]+\"" key "\"[[:space:]]*{" { in_var=1; next }
    in_var && $0 ~ "^[[:space:]]*default[[:space:]]*=" {
      val=$0
      sub(/^[^=]*=[[:space:]]*/, "", val)
      gsub(/\"/, "", val)
      gsub(/[[:space:]]+$/, "", val)
      gsub(/^[[:space:]]+/, "", val)
      print val
      exit
    }
    in_var && $0 ~ "^[[:space:]]*}" { in_var=0 }
  ' "${VARIABLES_FILE}" || true
}

helm_latest_chart_version() {
  local repo_name="$1"
  local repo_url="$2"
  local chart="$3"

  helm repo add "${repo_name}" "${repo_url}" --force-update >/dev/null 2>&1 || true
  helm repo update "${repo_name}" >/dev/null 2>&1 || true
  helm search repo "${repo_name}/${chart}" --versions -o json 2>/dev/null | jq -r '.[0].version // empty' || true
}

helm_chart_app_version() {
  local repo_name="$1"
  local repo_url="$2"
  local chart="$3"
  local version="$4"

  if [ -z "${version}" ]; then
    echo ""
    return 0
  fi

  helm repo add "${repo_name}" "${repo_url}" --force-update >/dev/null 2>&1 || true
  helm repo update "${repo_name}" >/dev/null 2>&1 || true
  helm show chart "${repo_name}/${chart}" --version "${version}" 2>/dev/null | \
    awk -F': ' '$1=="appVersion"{print $2; exit}' | tr -d '"' | xargs || true
}

image_tag_from_ref() {
  local image_ref="$1"
  local no_digest last_segment

  if [ -z "${image_ref}" ]; then
    echo ""
    return 0
  fi

  no_digest="${image_ref%@*}"
  last_segment="${no_digest##*/}"
  if [[ "${last_segment}" == *:* ]]; then
    echo "${last_segment##*:}"
  else
    echo ""
  fi
}

k8s_deployment_container_image() {
  local namespace="$1"
  local deployment="$2"
  local container="$3"

  if ! command -v kubectl >/dev/null 2>&1; then
    echo ""
    return 0
  fi

  kubectl -n "${namespace}" get deployment "${deployment}" -o json 2>/dev/null | \
    jq -r --arg c "${container}" '.spec.template.spec.containers[]? | select(.name==$c) | .image // empty' | \
    head -n1 | xargs || true
}

print_row() {
  local name="$1"
  local deployed="$2"
  local codebase="$3"
  local latest="$4"
  local deployed_tag="$5"
  local codebase_tag="$6"
  local dhi_tag="$7"
  local latest_tag="$8"
  local prefer_hardened="${9:-0}"
  local status
  local deploy_state
  local latest_state
  local update_available=0
  local all_match=0

  if [ -n "$codebase" ] && [ -n "$latest" ] && [ "$codebase" != "$latest" ] && ! { [ "${prefer_hardened}" = "1" ] && [ -n "${dhi_tag}" ]; }; then
    update_available=1
  fi

  if [ "${CLUSTER_OK}" -ne 1 ]; then
    deploy_state="deployed ? (cluster unreachable)"
  elif [ -z "$deployed" ]; then
    deploy_state="not deployed"
  elif [ -n "$codebase" ] && [ "$deployed" = "$codebase" ]; then
    deploy_state="deployed == codebase (${codebase})"
  else
    if [ -n "$codebase" ]; then
      deploy_state="deployed != codebase (${deployed} vs ${codebase})"
    else
      deploy_state="deployed == ${deployed}"
    fi
  fi

  if [ -z "$latest" ]; then
    latest_state="latest ?"
  elif [ "${prefer_hardened}" = "1" ] && [ -n "${dhi_tag}" ]; then
    latest_state="latest non-hardened ignored (DHI preferred: ${dhi_tag})"
  else
    latest_state="latest == ${latest}"
  fi

  if [ -n "$codebase" ] && [ -n "$deployed" ] && [ -n "$latest" ] && \
    [ "$codebase" = "$deployed" ] && [ "$codebase" = "$latest" ]; then
    all_match=1
    status="deployed == codebase == latest (${codebase})"
  else
    status="${deploy_state}; ${latest_state}"
  fi

  if [[ "$deploy_state" == deployed\ !=* ]]; then
    status="${RED}${status}${NC}"
  elif [ "${all_match}" -eq 1 ]; then
    status="${GREEN}${status}${NC}"
  elif [ "${update_available}" -eq 1 ] || [[ "$deploy_state" == not* ]] || [[ "$deploy_state" == deployed\ ?* ]] || [[ "$latest_state" == latest\ ?* ]]; then
    status="${YELLOW}${status}${NC}"
  else
    status="${GREEN}${status}${NC}"
  fi

  # Emit a sortable TSV row; rendering happens after sorting by component name.
  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$name" "${deployed:-}" "$codebase" "$latest" "${deployed_tag:-}" "${codebase_tag:-}" "${dhi_tag:-}" "${latest_tag:-}" "$status"
}

check_preload_image_version_alignment() {
  local preload_file="${SCRIPT_DIR}/preload-images.txt"
  local expected_argocd_image_ref="$1"
  local expected_prometheus_tag="$2"
  local expected_grafana_tag="$3"
  local expected_loki_tag="$4"
  local expected_tempo_tag="$5"

  if [ ! -f "${preload_file}" ]; then
    warn "preload-images.txt not found at ${preload_file}"
    return 0
  fi

  check_preload_image_ref_alignment "${preload_file}" "ArgoCD" '^[[:space:]]*((dhi\.io/argocd)|(quay\.io/argoproj/argocd)):' "${expected_argocd_image_ref}"
  check_preload_repo_tag_alignment "${preload_file}" "Prometheus" '^[[:space:]]*quay\.io/prometheus/prometheus:' 's|^[[:space:]]*quay\.io/prometheus/prometheus:([^[:space:]]+).*|\1|' "${expected_prometheus_tag}"
  check_preload_repo_tag_alignment "${preload_file}" "Grafana" '^[[:space:]]*(docker\.io/)?grafana/grafana:' 's|^[[:space:]]*(docker\.io/)?grafana/grafana:([^[:space:]]+).*|\2|' "${expected_grafana_tag}"
  check_preload_repo_tag_alignment "${preload_file}" "Loki" '^[[:space:]]*(docker\.io/)?grafana/loki:' 's|^[[:space:]]*(docker\.io/)?grafana/loki:([^[:space:]]+).*|\2|' "${expected_loki_tag}"
  check_preload_repo_tag_alignment "${preload_file}" "Tempo" '^[[:space:]]*(docker\.io/)?grafana/tempo:' 's|^[[:space:]]*(docker\.io/)?grafana/tempo:([^[:space:]]+).*|\2|' "${expected_tempo_tag}"
  echo ""
}

check_preload_image_ref_alignment() {
  local preload_file="$1"
  local component="$2"
  local line_regex="$3"
  local expected_ref="$4"
  local matches has_exact mismatch_count

  if [ -z "${expected_ref}" ]; then
    warn "preload image check skipped for ${component}: expected image ref is unknown"
    return 0
  fi

  matches=$(grep -nE "${line_regex}" "${preload_file}" 2>/dev/null || true)
  if [ -z "${matches}" ]; then
    warn "preload image missing for ${component}: expected ${expected_ref}"
    return 0
  fi

  has_exact=0
  mismatch_count=0

  while IFS= read -r entry; do
    [ -z "${entry}" ] && continue

    local lineno image_ref found_ref
    lineno="${entry%%:*}"
    image_ref="${entry#*:}"
    found_ref=$(echo "${image_ref}" | sed -E 's/[[:space:]]+$//' | xargs || true)

    if [ "${found_ref}" = "${expected_ref}" ]; then
      has_exact=1
      continue
    fi

    mismatch_count=$((mismatch_count + 1))
    warn "stale preload candidate (line ${lineno}): ${image_ref} (expected ${component} image ${expected_ref})"
  done <<< "${matches}"

  if [ "${has_exact}" -eq 1 ]; then
    if [ "${mismatch_count}" -eq 0 ]; then
      ok "${component} preload image matches configured image (${expected_ref})"
    else
      warn "${component} preload includes ${mismatch_count} non-matching line(s); expected image is ${expected_ref}"
    fi
  else
    warn "preload image missing exact ${component} image: ${expected_ref}"
  fi
}

check_preload_repo_tag_alignment() {
  local preload_file="$1"
  local component="$2"
  local line_regex="$3"
  local tag_extract_sed="$4"
  local expected_tag="$5"
  local matches has_expected mismatch_count

  if [ -z "${expected_tag}" ]; then
    warn "preload image check skipped for ${component}: expected chart appVersion is unknown"
    return 0
  fi

  matches=$(grep -nE "${line_regex}" "${preload_file}" 2>/dev/null || true)
  if [ -z "${matches}" ]; then
    warn "preload image missing for ${component}: expected tag ${expected_tag}"
    return 0
  fi

  has_expected=0
  mismatch_count=0

  while IFS= read -r entry; do
    [ -z "${entry}" ] && continue

    local lineno image_ref found_tag
    lineno="${entry%%:*}"
    image_ref="${entry#*:}"
    found_tag=$(echo "${image_ref}" | sed -E "${tag_extract_sed}" | xargs || true)

    if [ "${found_tag}" = "${expected_tag}" ]; then
      has_expected=1
      continue
    fi

    mismatch_count=$((mismatch_count + 1))
    warn "stale preload candidate (line ${lineno}): ${image_ref} (expected ${component} tag ${expected_tag})"
  done <<< "${matches}"

  if [ "${has_expected}" -eq 1 ]; then
    if [ "${mismatch_count}" -eq 0 ]; then
      ok "${component} preload image tag matches chart appVersion (${expected_tag})"
    else
      warn "${component} preload includes ${mismatch_count} non-matching tag line(s); expected tag is ${expected_tag}"
    fi
  else
    warn "preload image missing exact ${component} tag: ${expected_tag}"
  fi
}

preload_expected_chart_version_for_section() {
  local section="$1"

  case "${section}" in
    Cilium) echo "${CODE_CILIUM}" ;;
    ArgoCD) echo "${CODE_ARGOCD}" ;;
    Gitea) echo "${CODE_GITEA}" ;;
    Kyverno) echo "${CODE_KYVERNO}" ;;
    cert-manager) echo "${CODE_CERT_MANAGER}" ;;
    SigNoz) echo "${CODE_SIGNOZ}" ;;
    Prometheus) echo "${CODE_PROMETHEUS}" ;;
    Loki) echo "${CODE_LOKI}" ;;
    Tempo) echo "${CODE_TEMPO}" ;;
    Grafana) echo "${CODE_GRAFANA}" ;;
    Headlamp) echo "${CODE_HEADLAMP}" ;;
    Dex) echo "${CODE_DEX}" ;;
    oauth2-proxy) echo "${CODE_OAUTH2_PROXY}" ;;
    "OpenTelemetry Collector") echo "${CODE_OTEL_COLLECTOR}" ;;
    "NGINX Gateway Fabric") echo "main" ;;
    *) echo "" ;;
  esac
}

check_preload_chart_section_version_alignment() {
  local preload_file="${SCRIPT_DIR}/preload-images.txt"

  if [ ! -f "${preload_file}" ]; then
    warn "preload-images.txt not found at ${preload_file}"
    return 0
  fi

  local line lineno section section_chart expected section_drift
  local drift_sections=0
  local stale_lines=0
  lineno=0
  section_drift=0
  section=""

  while IFS= read -r line || [ -n "${line}" ]; do
    lineno=$((lineno + 1))

    if echo "${line}" | grep -Eq '^[[:space:]]*#[[:space:]]*---[[:space:]]*.+[[:space:]]+\(chart[[:space:]]+[^)]*\)[[:space:]]*---[[:space:]]*$'; then
      section=$(echo "${line}" | sed -E 's/^[[:space:]]*#[[:space:]]*---[[:space:]]*(.+)[[:space:]]+\(chart[[:space:]]+([^)]*)\)[[:space:]]*---[[:space:]]*$/\1/' | xargs)
      section_chart=$(echo "${line}" | sed -E 's/^[[:space:]]*#[[:space:]]*---[[:space:]]*(.+)[[:space:]]+\(chart[[:space:]]+([^)]*)\)[[:space:]]*---[[:space:]]*$/\2/' | xargs)
      expected=$(preload_expected_chart_version_for_section "${section}")
      section_drift=0

      if [ -n "${expected}" ] && [ "${section_chart}" != "${expected}" ]; then
        warn "preload section drift (line ${lineno}): ${section} chart ${section_chart} but codebase expects ${expected}"
        section_drift=1
        drift_sections=$((drift_sections + 1))
      fi
      continue
    fi

    if [ "${section_drift}" -eq 1 ] && ! echo "${line}" | grep -Eq '^[[:space:]]*(#|$)'; then
      stale_lines=$((stale_lines + 1))
      warn "stale preload candidate (line ${lineno}): ${line} (section ${section} is on the wrong chart version)"
    fi
  done < "${preload_file}"

  if [ "${drift_sections}" -eq 0 ]; then
    ok "preload-images section chart versions match chart versions in codebase"
  else
    warn "preload-images chart section drift found in ${drift_sections} section(s), with ${stale_lines} stale image line candidate(s)"
  fi

  echo ""
}

helm_deployed_chart_version() {
  local namespace="$1"
  local release="$2"

  local json chart
  json=$(helm -n "$namespace" list -o json 2>/dev/null || true)
  chart=$(echo "$json" | jq -r ".[] | select(.name==\"${release}\") | .chart" 2>/dev/null || true)
  if [ -z "$chart" ]; then
    echo ""
    return 0
  fi

  # chart looks like "cilium-1.18.6" or "argo-cd-9.3.7".
  echo "$chart" | sed -E 's/^.*-([0-9][0-9A-Za-z.+-]+)$/\1/'
}

argocd_app_deployed_target_revision() {
  local app="$1"
  local ns="${2:-argocd}"

  if ! command -v kubectl >/dev/null 2>&1; then
    echo ""
    return 0
  fi

  # Prefer the live synced revision when present; fall back to desired targetRevision.
  local rev
  rev=$(kubectl -n "$ns" get application "$app" -o jsonpath='{.status.sync.revision}' 2>/dev/null || true)
  if [ -n "$rev" ]; then
    echo "$rev"
    return 0
  fi

  kubectl -n "$ns" get application "$app" -o jsonpath='{.spec.source.targetRevision}' 2>/dev/null || true
}

check_consistent_tfvars() {
  local key="$1"
  local uniq

  uniq=$(grep -hE "^[[:space:]]*${key}[[:space:]]*=[[:space:]]*" "${STAGES_DIR}"/*.tfvars 2>/dev/null | \
    sed -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"?([^\"#]+)\"?.*$/\1/" | xargs -n1 | sort -u || true)

  if [ -z "$uniq" ]; then
    return 0
  fi

  local count
  count=$(echo "$uniq" | wc -l | tr -d ' ')
  if [ "$count" -gt 1 ]; then
    warn "Inconsistent ${key} across stages:"
    while IFS= read -r line; do
      echo "  - ${line}"
    done <<<"${uniq}"
    echo ""
  fi
}

check_app_yaml_tfvar_drift() {
  if [ ! -d "${ARGOCD_APPS_DIR}" ]; then
    return 0
  fi

  local warned=0
  local file app revision tfvar_key expected
  for file in "${ARGOCD_APPS_DIR}"/*.yaml; do
    [ -f "$file" ] || continue

    revision=$(awk '/^[[:space:]]*targetRevision:[[:space:]]*/ { print $2; exit }' "$file" | tr -d '"' | xargs)
    if [ -z "$revision" ]; then
      continue
    fi

    case "$revision" in
      main|master|HEAD)
        continue
        ;;
    esac

    app=$(awk '
      /^metadata:[[:space:]]*$/ { in_meta=1; next }
      in_meta && /^[[:space:]]*name:[[:space:]]*/ { print $2; exit }
      in_meta && /^[^[:space:]]/ { in_meta=0 }
    ' "$file" | tr -d '"' | xargs)

    tfvar_key=""
    case "$app" in
      cert-manager) tfvar_key="cert_manager_chart_version" ;;
      kyverno) tfvar_key="kyverno_chart_version" ;;
      prometheus) tfvar_key="prometheus_chart_version" ;;
      grafana) tfvar_key="grafana_chart_version" ;;
      loki) tfvar_key="loki_chart_version" ;;
      tempo) tfvar_key="tempo_chart_version" ;;
      signoz) tfvar_key="signoz_chart_version" ;;
      otel-collector-agent|otel-collector-prometheus) tfvar_key="opentelemetry_collector_chart_version" ;;
      *) continue ;;
    esac

    expected=$(tfvar_get_any_stage "$tfvar_key")
    if [ -z "$expected" ]; then
      expected=$(tf_default_from_variables "$tfvar_key")
    fi
    if [ -z "$expected" ]; then
      warn "YAML↔tfvar drift: $(basename "$file") targetRevision=${revision} but ${tfvar_key} is missing from stages/*.tfvars"
      warned=1
      continue
    fi

    if [ "$revision" != "$expected" ]; then
      warn "YAML↔tfvar drift: $(basename "$file") targetRevision=${revision} but ${tfvar_key}=${expected}"
      warned=1
    fi
  done

  if [ "$warned" -eq 0 ]; then
    ok "No app-of-apps targetRevision drift detected"
  fi
  echo ""
}

echo ""
ok "Version check (Deployed vs Codebase vs Latest)"
echo ""

CODE_ARGOCD=$(tfvar_get "${STAGES_DIR}/100-cluster.tfvars" "argocd_chart_version")
CODE_ARGOCD_IMAGE_REPO=$(tfvar_get_any_stage_or_default "argocd_image_repository" "$(tf_default_from_variables "argocd_image_repository")")
CODE_ARGOCD_IMAGE_TAG=$(tfvar_get_any_stage_or_default "argocd_image_tag" "$(tf_default_from_variables "argocd_image_tag")")
CODE_GITEA=$(tfvar_get "${STAGES_DIR}/500-gitea.tfvars" "gitea_chart_version")
CODE_CILIUM=$(tfvar_get "${STAGES_DIR}/200-cilium.tfvars" "cilium_version")
CODE_PROMETHEUS=$(tfvar_get_any_stage_or_default "prometheus_chart_version" "$(tf_default_from_variables "prometheus_chart_version")")
CODE_GRAFANA=$(tfvar_get_any_stage_or_default "grafana_chart_version" "$(tf_default_from_variables "grafana_chart_version")")
CODE_LOKI=$(tfvar_get_any_stage_or_default "loki_chart_version" "$(tf_default_from_variables "loki_chart_version")")
CODE_TEMPO=$(tfvar_get_any_stage_or_default "tempo_chart_version" "$(tf_default_from_variables "tempo_chart_version")")
CODE_SIGNOZ=$(tfvar_get_any_stage_or_default "signoz_chart_version" "$(tf_default_from_variables "signoz_chart_version")")
CODE_OTEL_COLLECTOR=$(tfvar_get_any_stage_or_default "opentelemetry_collector_chart_version" "$(tf_default_from_variables "opentelemetry_collector_chart_version")")
CODE_HEADLAMP=$(tfvar_get "${STAGES_DIR}/800-gateway-tls.tfvars" "headlamp_chart_version")
CODE_KYVERNO=$(tfvar_get "${STAGES_DIR}/100-cluster.tfvars" "kyverno_chart_version")
CODE_CERT_MANAGER=$(tfvar_get "${STAGES_DIR}/100-cluster.tfvars" "cert_manager_chart_version")
CODE_DEX=$(tfvar_get "${STAGES_DIR}/900-sso.tfvars" "dex_chart_version")
CODE_OAUTH2_PROXY=$(tfvar_get "${STAGES_DIR}/900-sso.tfvars" "oauth2_proxy_chart_version")
if [ -z "${CODE_ARGOCD_IMAGE_REPO}" ]; then
  CODE_ARGOCD_IMAGE_REPO="quay.io/argoproj/argocd"
fi

CODE_ARGOCD_IMAGE_REF=""
if [ -n "${CODE_ARGOCD_IMAGE_REPO}" ] && [ -n "${CODE_ARGOCD_IMAGE_TAG}" ]; then
  CODE_ARGOCD_IMAGE_REF="${CODE_ARGOCD_IMAGE_REPO}:${CODE_ARGOCD_IMAGE_TAG}"
fi
CODE_DHI_TAG_ARGOCD=""
if [ "${CODE_ARGOCD_IMAGE_REPO}" = "dhi.io/argocd" ] && [ -n "${CODE_ARGOCD_IMAGE_TAG}" ]; then
  CODE_DHI_TAG_ARGOCD="${CODE_ARGOCD_IMAGE_TAG}"
fi

EXPECTED_CLUSTER_NAME=$(tfvar_get "${STAGES_DIR}/100-cluster.tfvars" "cluster_name")
if [ -z "$EXPECTED_CLUSTER_NAME" ]; then EXPECTED_CLUSTER_NAME="kind-local"; fi

LATEST_ARGOCD=$(helm_latest_chart_version "argo" "https://argoproj.github.io/argo-helm" "argo-cd")
LATEST_GITEA=$(helm_latest_chart_version "gitea" "https://dl.gitea.io/charts/" "gitea")
LATEST_CILIUM=$(helm_latest_chart_version "cilium" "https://helm.cilium.io" "cilium")
LATEST_PROMETHEUS=$(helm_latest_chart_version "prometheus-community" "https://prometheus-community.github.io/helm-charts" "prometheus")
LATEST_GRAFANA=$(helm_latest_chart_version "grafana" "https://grafana.github.io/helm-charts" "grafana")
LATEST_LOKI=$(helm_latest_chart_version "grafana" "https://grafana.github.io/helm-charts" "loki")
LATEST_TEMPO=$(helm_latest_chart_version "grafana" "https://grafana.github.io/helm-charts" "tempo")
LATEST_SIGNOZ=$(helm_latest_chart_version "signoz" "https://charts.signoz.io" "signoz")
LATEST_OTEL_COLLECTOR=$(helm_latest_chart_version "open-telemetry" "https://open-telemetry.github.io/opentelemetry-helm-charts" "opentelemetry-collector")
LATEST_HEADLAMP=$(helm_latest_chart_version "headlamp" "https://kubernetes-sigs.github.io/headlamp/" "headlamp")
LATEST_KYVERNO=$(helm_latest_chart_version "kyverno" "https://kyverno.github.io/kyverno/" "kyverno")
LATEST_CERT_MANAGER=$(helm_latest_chart_version "jetstack" "https://charts.jetstack.io" "cert-manager")
LATEST_DEX=$(helm_latest_chart_version "dex" "https://charts.dexidp.io" "dex")
LATEST_OAUTH2_PROXY=$(helm_latest_chart_version "oauth2-proxy" "https://oauth2-proxy.github.io/manifests" "oauth2-proxy")

CODETAG_ARGOCD_CHART=$(helm_chart_app_version "argo" "https://argoproj.github.io/argo-helm" "argo-cd" "${CODE_ARGOCD}")
CODETAG_ARGOCD="${CODETAG_ARGOCD_CHART}"
CODETAG_GITEA=$(helm_chart_app_version "gitea" "https://dl.gitea.io/charts/" "gitea" "${CODE_GITEA}")
CODETAG_CILIUM=$(helm_chart_app_version "cilium" "https://helm.cilium.io" "cilium" "${CODE_CILIUM}")
CODETAG_PROMETHEUS=$(helm_chart_app_version "prometheus-community" "https://prometheus-community.github.io/helm-charts" "prometheus" "${CODE_PROMETHEUS}")
CODETAG_GRAFANA=$(helm_chart_app_version "grafana" "https://grafana.github.io/helm-charts" "grafana" "${CODE_GRAFANA}")
CODETAG_LOKI=$(helm_chart_app_version "grafana" "https://grafana.github.io/helm-charts" "loki" "${CODE_LOKI}")
CODETAG_TEMPO=$(helm_chart_app_version "grafana" "https://grafana.github.io/helm-charts" "tempo" "${CODE_TEMPO}")
CODETAG_SIGNOZ=$(helm_chart_app_version "signoz" "https://charts.signoz.io" "signoz" "${CODE_SIGNOZ}")
CODETAG_OTEL_COLLECTOR=$(helm_chart_app_version "open-telemetry" "https://open-telemetry.github.io/opentelemetry-helm-charts" "opentelemetry-collector" "${CODE_OTEL_COLLECTOR}")
CODETAG_HEADLAMP=$(helm_chart_app_version "headlamp" "https://kubernetes-sigs.github.io/headlamp/" "headlamp" "${CODE_HEADLAMP}")
CODETAG_KYVERNO=$(helm_chart_app_version "kyverno" "https://kyverno.github.io/kyverno/" "kyverno" "${CODE_KYVERNO}")
CODETAG_CERT_MANAGER=$(helm_chart_app_version "jetstack" "https://charts.jetstack.io" "cert-manager" "${CODE_CERT_MANAGER}")
CODETAG_DEX=$(helm_chart_app_version "dex" "https://charts.dexidp.io" "dex" "${CODE_DEX}")
CODETAG_OAUTH2_PROXY=$(helm_chart_app_version "oauth2-proxy" "https://oauth2-proxy.github.io/manifests" "oauth2-proxy" "${CODE_OAUTH2_PROXY}")

LATESTTAG_ARGOCD_CHART=$(helm_chart_app_version "argo" "https://argoproj.github.io/argo-helm" "argo-cd" "${LATEST_ARGOCD}")
LATESTTAG_ARGOCD="${LATESTTAG_ARGOCD_CHART}"
LATESTTAG_GITEA=$(helm_chart_app_version "gitea" "https://dl.gitea.io/charts/" "gitea" "${LATEST_GITEA}")
LATESTTAG_CILIUM=$(helm_chart_app_version "cilium" "https://helm.cilium.io" "cilium" "${LATEST_CILIUM}")
LATESTTAG_PROMETHEUS=$(helm_chart_app_version "prometheus-community" "https://prometheus-community.github.io/helm-charts" "prometheus" "${LATEST_PROMETHEUS}")
LATESTTAG_GRAFANA=$(helm_chart_app_version "grafana" "https://grafana.github.io/helm-charts" "grafana" "${LATEST_GRAFANA}")
LATESTTAG_LOKI=$(helm_chart_app_version "grafana" "https://grafana.github.io/helm-charts" "loki" "${LATEST_LOKI}")
LATESTTAG_TEMPO=$(helm_chart_app_version "grafana" "https://grafana.github.io/helm-charts" "tempo" "${LATEST_TEMPO}")
LATESTTAG_SIGNOZ=$(helm_chart_app_version "signoz" "https://charts.signoz.io" "signoz" "${LATEST_SIGNOZ}")
LATESTTAG_OTEL_COLLECTOR=$(helm_chart_app_version "open-telemetry" "https://open-telemetry.github.io/opentelemetry-helm-charts" "opentelemetry-collector" "${LATEST_OTEL_COLLECTOR}")
LATESTTAG_HEADLAMP=$(helm_chart_app_version "headlamp" "https://kubernetes-sigs.github.io/headlamp/" "headlamp" "${LATEST_HEADLAMP}")
LATESTTAG_KYVERNO=$(helm_chart_app_version "kyverno" "https://kyverno.github.io/kyverno/" "kyverno" "${LATEST_KYVERNO}")
LATESTTAG_CERT_MANAGER=$(helm_chart_app_version "jetstack" "https://charts.jetstack.io" "cert-manager" "${LATEST_CERT_MANAGER}")
LATESTTAG_DEX=$(helm_chart_app_version "dex" "https://charts.dexidp.io" "dex" "${LATEST_DEX}")
LATESTTAG_OAUTH2_PROXY=$(helm_chart_app_version "oauth2-proxy" "https://oauth2-proxy.github.io/manifests" "oauth2-proxy" "${LATEST_OAUTH2_PROXY}")

CLUSTER_OK=0
if command -v kind >/dev/null 2>&1; then
  if ! kind get clusters 2>/dev/null | grep -qx "${EXPECTED_CLUSTER_NAME}"; then
    warn "Cluster '${EXPECTED_CLUSTER_NAME}' not found; Deployed=Unavailable"
  elif cluster_reachable; then
    CLUSTER_OK=1
  else
    warn "Cluster '${EXPECTED_CLUSTER_NAME}' exists but API is unreachable; Deployed=Unavailable"
  fi
else
  if cluster_reachable; then
    CLUSTER_OK=1
  else
    warn "Cluster API unreachable (and 'kind' not found); Deployed=Unavailable"
  fi
fi

DEPLOYED_CILIUM=""
DEPLOYED_ARGOCD=""
DEPLOYED_GITEA=""
DEPLOYED_SIGNOZ=""
DEPLOYED_PROMETHEUS=""
DEPLOYED_GRAFANA=""
DEPLOYED_LOKI=""
DEPLOYED_TEMPO=""
DEPLOYED_OTEL_COLLECTOR=""
DEPLOYED_HEADLAMP=""
DEPLOYED_KYVERNO=""
DEPLOYED_CERT_MANAGER=""
DEPLOYED_DEX=""
DEPLOYED_OAUTH2_PROXY=""
DEPLOYEDTAG_CILIUM=""
DEPLOYEDTAG_ARGOCD=""
DEPLOYED_ARGOCD_IMAGE_REF=""
DEPLOYEDTAG_GITEA=""
DEPLOYEDTAG_PROMETHEUS=""
DEPLOYEDTAG_GRAFANA=""
DEPLOYEDTAG_LOKI=""
DEPLOYEDTAG_TEMPO=""
DEPLOYEDTAG_SIGNOZ=""
DEPLOYEDTAG_OTEL_COLLECTOR=""
DEPLOYEDTAG_HEADLAMP=""
DEPLOYEDTAG_KYVERNO=""
DEPLOYEDTAG_CERT_MANAGER=""
DEPLOYEDTAG_DEX=""
DEPLOYEDTAG_OAUTH2_PROXY=""

if [ "${CLUSTER_OK}" -eq 1 ]; then
  DEPLOYED_CILIUM=$(helm_deployed_chart_version "kube-system" "cilium")
  DEPLOYED_ARGOCD=$(helm_deployed_chart_version "argocd" "argocd")
  DEPLOYED_ARGOCD_IMAGE_REF=$(k8s_deployment_container_image "argocd" "argocd-server" "server")

  DEPLOYED_GITEA=$(argocd_app_deployed_target_revision "gitea" "argocd")
  DEPLOYED_PROMETHEUS=$(argocd_app_deployed_target_revision "prometheus" "argocd")
  DEPLOYED_GRAFANA=$(argocd_app_deployed_target_revision "grafana" "argocd")
  DEPLOYED_LOKI=$(argocd_app_deployed_target_revision "loki" "argocd")
  DEPLOYED_TEMPO=$(argocd_app_deployed_target_revision "tempo" "argocd")
  DEPLOYED_SIGNOZ=$(argocd_app_deployed_target_revision "signoz" "argocd")
  DEPLOYED_OTEL_COLLECTOR=$(argocd_app_deployed_target_revision "otel-collector-agent" "argocd")
  if [ -z "${DEPLOYED_OTEL_COLLECTOR}" ]; then
    DEPLOYED_OTEL_COLLECTOR=$(argocd_app_deployed_target_revision "otel-collector-prometheus" "argocd")
  fi
  DEPLOYED_HEADLAMP=$(argocd_app_deployed_target_revision "headlamp" "argocd")

  DEPLOYED_KYVERNO=$(argocd_app_deployed_target_revision "kyverno" "argocd")
  DEPLOYED_CERT_MANAGER=$(argocd_app_deployed_target_revision "cert-manager" "argocd")

  DEPLOYED_DEX=$(argocd_app_deployed_target_revision "dex" "argocd")
  DEPLOYED_OAUTH2_PROXY=$(argocd_app_deployed_target_revision "oauth2-proxy-argocd" "argocd")

  DEPLOYEDTAG_CILIUM=$(helm_chart_app_version "cilium" "https://helm.cilium.io" "cilium" "${DEPLOYED_CILIUM}")
  DEPLOYEDTAG_ARGOCD=$(image_tag_from_ref "${DEPLOYED_ARGOCD_IMAGE_REF}")
  if [ -z "${DEPLOYEDTAG_ARGOCD}" ]; then
    DEPLOYEDTAG_ARGOCD=$(helm_chart_app_version "argo" "https://argoproj.github.io/argo-helm" "argo-cd" "${DEPLOYED_ARGOCD}")
  fi
  DEPLOYEDTAG_GITEA=$(helm_chart_app_version "gitea" "https://dl.gitea.io/charts/" "gitea" "${DEPLOYED_GITEA}")
  DEPLOYEDTAG_PROMETHEUS=$(helm_chart_app_version "prometheus-community" "https://prometheus-community.github.io/helm-charts" "prometheus" "${DEPLOYED_PROMETHEUS}")
  DEPLOYEDTAG_GRAFANA=$(helm_chart_app_version "grafana" "https://grafana.github.io/helm-charts" "grafana" "${DEPLOYED_GRAFANA}")
  DEPLOYEDTAG_LOKI=$(helm_chart_app_version "grafana" "https://grafana.github.io/helm-charts" "loki" "${DEPLOYED_LOKI}")
  DEPLOYEDTAG_TEMPO=$(helm_chart_app_version "grafana" "https://grafana.github.io/helm-charts" "tempo" "${DEPLOYED_TEMPO}")
  DEPLOYEDTAG_SIGNOZ=$(helm_chart_app_version "signoz" "https://charts.signoz.io" "signoz" "${DEPLOYED_SIGNOZ}")
  DEPLOYEDTAG_OTEL_COLLECTOR=$(helm_chart_app_version "open-telemetry" "https://open-telemetry.github.io/opentelemetry-helm-charts" "opentelemetry-collector" "${DEPLOYED_OTEL_COLLECTOR}")
  DEPLOYEDTAG_HEADLAMP=$(helm_chart_app_version "headlamp" "https://kubernetes-sigs.github.io/headlamp/" "headlamp" "${DEPLOYED_HEADLAMP}")
  DEPLOYEDTAG_KYVERNO=$(helm_chart_app_version "kyverno" "https://kyverno.github.io/kyverno/" "kyverno" "${DEPLOYED_KYVERNO}")
  DEPLOYEDTAG_CERT_MANAGER=$(helm_chart_app_version "jetstack" "https://charts.jetstack.io" "cert-manager" "${DEPLOYED_CERT_MANAGER}")
  DEPLOYEDTAG_DEX=$(helm_chart_app_version "dex" "https://charts.dexidp.io" "dex" "${DEPLOYED_DEX}")
  DEPLOYEDTAG_OAUTH2_PROXY=$(helm_chart_app_version "oauth2-proxy" "https://oauth2-proxy.github.io/manifests" "oauth2-proxy" "${DEPLOYED_OAUTH2_PROXY}")
else
  DEPLOYED_CILIUM="Unavailable"
  DEPLOYED_ARGOCD="Unavailable"
  DEPLOYED_GITEA="Unavailable"
  DEPLOYED_PROMETHEUS="Unavailable"
  DEPLOYED_GRAFANA="Unavailable"
  DEPLOYED_LOKI="Unavailable"
  DEPLOYED_TEMPO="Unavailable"
  DEPLOYED_SIGNOZ="Unavailable"
  DEPLOYED_OTEL_COLLECTOR="Unavailable"
  DEPLOYED_HEADLAMP="Unavailable"
  DEPLOYED_KYVERNO="Unavailable"
  DEPLOYED_CERT_MANAGER="Unavailable"
  DEPLOYED_DEX="Unavailable"
  DEPLOYED_OAUTH2_PROXY="Unavailable"
  DEPLOYEDTAG_CILIUM="Unavailable"
  DEPLOYEDTAG_ARGOCD="Unavailable"
  DEPLOYEDTAG_GITEA="Unavailable"
  DEPLOYEDTAG_PROMETHEUS="Unavailable"
  DEPLOYEDTAG_GRAFANA="Unavailable"
  DEPLOYEDTAG_LOKI="Unavailable"
  DEPLOYEDTAG_TEMPO="Unavailable"
  DEPLOYEDTAG_SIGNOZ="Unavailable"
  DEPLOYEDTAG_OTEL_COLLECTOR="Unavailable"
  DEPLOYEDTAG_HEADLAMP="Unavailable"
  DEPLOYEDTAG_KYVERNO="Unavailable"
  DEPLOYEDTAG_CERT_MANAGER="Unavailable"
  DEPLOYEDTAG_DEX="Unavailable"
  DEPLOYEDTAG_OAUTH2_PROXY="Unavailable"
fi

echo "Component versions"
printf "%-16s %-12s %-12s %-12s %-13s %-10s %-15s %-10s %s\n" "Component" "Deployed" "Codebase" "Latest" "DeployTag" "CodeTag" "DHI" "LatestTag" "Status"
printf "%-16s %-12s %-12s %-12s %-13s %-10s %-15s %-10s %s\n" "---------" "--------" "--------" "------" "---------" "-------" "---" "---------" "------"

rows=()
rows+=("$(print_row "argo-cd chart" "${DEPLOYED_ARGOCD}" "${CODE_ARGOCD}" "${LATEST_ARGOCD}" "${DEPLOYEDTAG_ARGOCD}" "${CODETAG_ARGOCD}" "${CODE_DHI_TAG_ARGOCD}" "${LATESTTAG_ARGOCD}" "1")")
rows+=("$(print_row "gitea chart" "${DEPLOYED_GITEA}" "${CODE_GITEA}" "${LATEST_GITEA}" "${DEPLOYEDTAG_GITEA}" "${CODETAG_GITEA}" "" "${LATESTTAG_GITEA}" "0")")
rows+=("$(print_row "cilium chart" "${DEPLOYED_CILIUM}" "${CODE_CILIUM}" "${LATEST_CILIUM}" "${DEPLOYEDTAG_CILIUM}" "${CODETAG_CILIUM}" "" "${LATESTTAG_CILIUM}" "0")")
rows+=("$(print_row "prometheus chart" "${DEPLOYED_PROMETHEUS}" "${CODE_PROMETHEUS}" "${LATEST_PROMETHEUS}" "${DEPLOYEDTAG_PROMETHEUS}" "${CODETAG_PROMETHEUS}" "" "${LATESTTAG_PROMETHEUS}" "0")")
rows+=("$(print_row "grafana chart" "${DEPLOYED_GRAFANA}" "${CODE_GRAFANA}" "${LATEST_GRAFANA}" "${DEPLOYEDTAG_GRAFANA}" "${CODETAG_GRAFANA}" "" "${LATESTTAG_GRAFANA}" "0")")
rows+=("$(print_row "loki chart" "${DEPLOYED_LOKI}" "${CODE_LOKI}" "${LATEST_LOKI}" "${DEPLOYEDTAG_LOKI}" "${CODETAG_LOKI}" "" "${LATESTTAG_LOKI}" "0")")
rows+=("$(print_row "tempo chart" "${DEPLOYED_TEMPO}" "${CODE_TEMPO}" "${LATEST_TEMPO}" "${DEPLOYEDTAG_TEMPO}" "${CODETAG_TEMPO}" "" "${LATESTTAG_TEMPO}" "0")")
rows+=("$(print_row "signoz chart" "${DEPLOYED_SIGNOZ}" "${CODE_SIGNOZ}" "${LATEST_SIGNOZ}" "${DEPLOYEDTAG_SIGNOZ}" "${CODETAG_SIGNOZ}" "" "${LATESTTAG_SIGNOZ}" "0")")
rows+=("$(print_row "otel-collector" "${DEPLOYED_OTEL_COLLECTOR}" "${CODE_OTEL_COLLECTOR}" "${LATEST_OTEL_COLLECTOR}" "${DEPLOYEDTAG_OTEL_COLLECTOR}" "${CODETAG_OTEL_COLLECTOR}" "" "${LATESTTAG_OTEL_COLLECTOR}" "0")")
rows+=("$(print_row "headlamp chart" "${DEPLOYED_HEADLAMP}" "${CODE_HEADLAMP}" "${LATEST_HEADLAMP}" "${DEPLOYEDTAG_HEADLAMP}" "${CODETAG_HEADLAMP}" "" "${LATESTTAG_HEADLAMP}" "0")")
rows+=("$(print_row "kyverno chart" "${DEPLOYED_KYVERNO}" "${CODE_KYVERNO}" "${LATEST_KYVERNO}" "${DEPLOYEDTAG_KYVERNO}" "${CODETAG_KYVERNO}" "" "${LATESTTAG_KYVERNO}" "0")")
rows+=("$(print_row "cert-manager" "${DEPLOYED_CERT_MANAGER}" "${CODE_CERT_MANAGER}" "${LATEST_CERT_MANAGER}" "${DEPLOYEDTAG_CERT_MANAGER}" "${CODETAG_CERT_MANAGER}" "" "${LATESTTAG_CERT_MANAGER}" "0")")
rows+=("$(print_row "dex chart" "${DEPLOYED_DEX}" "${CODE_DEX}" "${LATEST_DEX}" "${DEPLOYEDTAG_DEX}" "${CODETAG_DEX}" "" "${LATESTTAG_DEX}" "0")")
rows+=("$(print_row "oauth2-proxy" "${DEPLOYED_OAUTH2_PROXY}" "${CODE_OAUTH2_PROXY}" "${LATEST_OAUTH2_PROXY}" "${DEPLOYEDTAG_OAUTH2_PROXY}" "${CODETAG_OAUTH2_PROXY}" "" "${LATESTTAG_OAUTH2_PROXY}" "0")")

printf "%s\n" "${rows[@]}" | sort -t $'\t' -k1,1 | \
  awk -F $'\t' '{
    printf "%-16s %-12s %-12s %-12s %-13s %-10s %-15s %-10s %s\n", $1, $2, $3, $4, $5, $6, $7, $8, $9
  }'
echo ""

check_consistent_tfvars "argocd_chart_version"
check_consistent_tfvars "argocd_image_repository"
check_consistent_tfvars "argocd_image_tag"
check_consistent_tfvars "gitea_chart_version"
check_consistent_tfvars "cilium_version"
check_consistent_tfvars "prometheus_chart_version"
check_consistent_tfvars "grafana_chart_version"
check_consistent_tfvars "loki_chart_version"
check_consistent_tfvars "tempo_chart_version"
check_consistent_tfvars "signoz_chart_version"
check_consistent_tfvars "opentelemetry_collector_chart_version"
check_consistent_tfvars "headlamp_chart_version"
check_consistent_tfvars "kyverno_chart_version"
check_consistent_tfvars "cert_manager_chart_version"
check_consistent_tfvars "dex_chart_version"
check_consistent_tfvars "oauth2_proxy_chart_version"

check_app_yaml_tfvar_drift
check_preload_chart_section_version_alignment
check_preload_image_version_alignment "${CODE_ARGOCD_IMAGE_REF}" "${CODETAG_PROMETHEUS}" "${CODETAG_GRAFANA}" "${CODETAG_LOKI}" "${CODETAG_TEMPO}"

if [ -n "${CODE_ARGOCD_IMAGE_REF}" ] && [ "${CODE_ARGOCD_IMAGE_REPO}" != "quay.io/argoproj/argocd" ]; then
  ok "Argo CD image override active: ${CODE_ARGOCD_IMAGE_REF} (chart appVersion ${CODETAG_ARGOCD_CHART}, latest upstream appVersion ${LATESTTAG_ARGOCD_CHART})"
  echo ""
fi

ok "Done"
