#!/usr/bin/env bash
# Pre-pull container images to Docker Desktop and load them into a kind cluster.
#
# Usage:
#   preload-images.sh [OPTIONS]
#
# Options:
#   --pull-only       Pull images into Docker cache only (no kind cluster required)
#   --print-images    Print the final filtered image list and exit
#   --discover        Dump all images from the running cluster (excludes localhost:30090/*)
#   --image-list FILE Path to image list file (default: kubernetes/kind/preload-images.txt)
#   --tfvars FILE     Optional tfvars file for feature-gated image filtering
#   --cluster NAME    Kind cluster name (default: kind-local)
#   --platform PLAT   Target platform for pulls (default: auto)
#   --lock-file FILE  Digest lock file (default: scripts/preload-images.<platform>.lock)
#   --refresh-lock    Refresh the lock file from registries
#   --parallelism N   Number of parallel docker pulls (default: 4)
#   -h, --help        Show this help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
  cat <<'EOF'
Pre-pull container images to Docker Desktop and load them into a kind cluster.

Usage:
  preload-images.sh [OPTIONS]

Options:
  --pull-only       Pull images into Docker cache only (no kind cluster required)
  --print-images    Print the final filtered image list and exit
  --discover        Dump all images from the running cluster (excludes localhost:30090/*)
  --image-list FILE Path to image list file (default: kubernetes/kind/preload-images.txt)
  --tfvars FILE     Optional tfvars file for feature-gated image filtering
  --cluster NAME    Kind cluster name (default: kind-local)
  --platform PLAT   Target platform for pulls (default: auto)
  --lock-file FILE  Digest lock file (default: scripts/preload-images.<platform>.lock)
  --refresh-lock    Refresh the lock file from registries
  --parallelism N   Number of parallel docker pulls (default: 4)
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

require_cmd() {
  have_cmd "$1" || {
    echo "$1 not found in PATH" >&2
    exit 1
  }
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"
IMAGE_LIST="${REPO_ROOT}/kubernetes/kind/preload-images.txt"
CLUSTER_NAME="kind-local"
USER_PLATFORM=""
TFVARS_FILE=""
LOCK_FILE=""
REFRESH_LOCK=0
PARALLELISM=4
MODE="default"
WORKFLOW_DOCKERFILES=(
  "apps/subnetcalc/api-fastapi-container-app/Dockerfile"
  "apps/subnetcalc/apim-simulator/Dockerfile"
  "apps/subnetcalc/frontend-typescript-vite/Dockerfile"
  "apps/subnetcalc/frontend-react/Dockerfile"
  "apps/sentiment/api-sentiment/Dockerfile"
  "apps/sentiment/frontend-react-vite/sentiment-auth-ui/Dockerfile"
)

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --pull-only)    MODE="pull-only"; shift ;;
    --discover)     MODE="discover"; shift ;;
    --print-images) MODE="print-images"; shift ;;
    --image-list)   IMAGE_LIST="$2"; shift 2 ;;
    --tfvars)       TFVARS_FILE="$2"; shift 2 ;;
    --cluster)      CLUSTER_NAME="$2"; shift 2 ;;
    --platform)     USER_PLATFORM="$2"; shift 2 ;;
    --lock-file)    LOCK_FILE="$2"; shift 2 ;;
    --refresh-lock) REFRESH_LOCK=1; shift ;;
    --parallelism)  PARALLELISM="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

shell_cli_maybe_execute_or_preview_summary usage \
  "would ${MODE} preload image workflow using ${IMAGE_LIST}"

is_true() {
  case "${1:-}" in
    true|TRUE|1|yes|YES|y|Y) return 0 ;;
    *) return 1 ;;
  esac
}

has_toggle_env_overrides() {
  local env_key

  for env_key in PRELOAD_ENABLE_SIGNOZ PRELOAD_ENABLE_PROMETHEUS PRELOAD_ENABLE_GRAFANA PRELOAD_ENABLE_LOKI PRELOAD_ENABLE_VICTORIA_LOGS PRELOAD_ENABLE_TEMPO PRELOAD_ENABLE_HEADLAMP PRELOAD_ENABLE_SSO PRELOAD_ENABLE_ACTIONS_RUNNER; do
    if [[ -n "${!env_key:-}" ]]; then
      return 0
    fi
  done

  return 1
}

DEFAULT_TFVARS_FILE="${SCRIPT_DIR}/../stages/900-sso.tfvars"
if [[ -z "${TFVARS_FILE}" && -f "${DEFAULT_TFVARS_FILE}" ]] && ! has_toggle_env_overrides; then
  TFVARS_FILE="${DEFAULT_TFVARS_FILE}"
fi

terminate_pid_safe() {
  local pid="$1"
  local grace="${2:-2}"
  local waited=0

  kill "$pid" >/dev/null 2>&1 || true
  while kill -0 "$pid" >/dev/null 2>&1 && [[ "$waited" -lt "$grace" ]]; do
    sleep 1
    waited=$((waited + 1))
  done

  if kill -0 "$pid" >/dev/null 2>&1; then
    kill -9 "$pid" >/dev/null 2>&1 || true
  fi

  wait "$pid" >/dev/null 2>&1 || true
}

tfvar_bool() {
  local file="$1"
  local key="$2"
  local line value

  if [[ -z "${file}" || ! -f "${file}" ]]; then
    echo ""
    return 0
  fi

  line=$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "${file}" 2>/dev/null | tail -n 1 || true)
  if [[ -z "${line}" ]]; then
    echo ""
    return 0
  fi

  value=$(echo "${line}" | sed -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"?([^\"#]+)\"?.*$/\1/" | xargs)
  case "${value}" in
    true|false) echo "${value}" ;;
    *) echo "" ;;
  esac
}

toggle_or_default() {
  local key="$1"
  local default="$2"
  local value

  value=$(tfvar_bool "${TFVARS_FILE}" "${key}")
  if [[ -n "${value}" ]]; then
    echo "${value}"
  else
    echo "${default}"
  fi
}

toggle_input_or_default() {
  local env_key="$1"
  local tfvar_key="$2"
  local default="$3"
  local env_val="${!env_key:-}"

  if [[ -n "${env_val}" ]]; then
    if is_true "${env_val}"; then
      echo "true"
    else
      echo "false"
    fi
    return 0
  fi

  toggle_or_default "${tfvar_key}" "${default}"
}

is_signoz_image() {
  local img="$1"
  case "${img}" in
    docker.io/signoz/signoz:*|docker.io/signoz/signoz-otel-collector:*|docker.io/signoz/signoz-schema-migrator:*|docker.io/clickhouse/clickhouse-server:*|docker.io/altinity/clickhouse-operator:*|docker.io/altinity/metrics-exporter:*|signoz/zookeeper:*|docker.io/groundnuty/k8s-wait-for:*|ghcr.io/scolastico-dev/s.containers/signoz-auth-proxy:*)
      return 0
      ;;
    *) return 1 ;;
  esac
}

is_otel_collector_image() {
  local img="$1"
  case "${img}" in
    otel/opentelemetry-collector-contrib:*|docker.io/otel/opentelemetry-collector-contrib:*) return 0 ;;
    *) return 1 ;;
  esac
}

is_prometheus_image() {
  local img="$1"
  case "${img}" in
    dhi.io/prometheus:*|dhi.io/prometheus-config-reloader:*|dhi.io/alertmanager:*|dhi.io/kube-state-metrics:*|dhi.io/node-exporter:*|quay.io/prometheus/*:*|quay.io/prometheus-operator/*:*|docker.io/prom/*:*|docker.io/prometheus-operator/*:*) return 0 ;;
    *) return 1 ;;
  esac
}

is_grafana_image() {
  local img="$1"
  case "${img}" in
    dhi.io/grafana:*|dhi.io/k8s-sidecar:*|grafana/grafana:*|docker.io/grafana/grafana:*|quay.io/kiwigrid/k8s-sidecar:*) return 0 ;;
    *) return 1 ;;
  esac
}

is_loki_image() {
  local img="$1"
  case "${img}" in
    dhi.io/loki:*|grafana/loki:*|docker.io/grafana/loki:*) return 0 ;;
    *) return 1 ;;
  esac
}

is_victoria_logs_image() {
  local img="$1"
  case "${img}" in
    victoriametrics/victoria-logs:*|docker.io/victoriametrics/victoria-logs:*) return 0 ;;
    *) return 1 ;;
  esac
}

is_tempo_image() {
  local img="$1"
  case "${img}" in
    dhi.io/tempo:*|docker.io/grafana/tempo-query:*|grafana/tempo:*|docker.io/grafana/tempo:*) return 0 ;;
    *) return 1 ;;
  esac
}

is_headlamp_image() {
  local img="$1"
  case "${img}" in
    ghcr.io/headlamp-k8s/headlamp:*|node:lts-alpine) return 0 ;;
    *) return 1 ;;
  esac
}

is_sso_image() {
  local img="$1"
  case "${img}" in
    dhi.io/dex:*|dhi.io/oauth2-proxy:*) return 0 ;;
    *) return 1 ;;
  esac
}

is_actions_runner_image() {
  local img="$1"
  case "${img}" in
    docker:*|gitea/act_runner:*|docker.io/gitea/act_runner:*) return 0 ;;
    *) return 1 ;;
  esac
}

filter_images_by_toggles() {
  local enable_signoz="$1"
  local enable_prometheus="$2"
  local enable_grafana="$3"
  local enable_loki="$4"
  local enable_victoria_logs="$5"
  local enable_tempo="$6"
  local enable_headlamp="$7"
  local enable_sso="$8"
  local enable_actions_runner="$9"
  local output=""
  local img

  while IFS= read -r img; do
    [[ -z "${img}" ]] && continue

    if ! is_true "${enable_signoz}" && is_signoz_image "${img}"; then
      continue
    fi

    if ! is_true "${enable_prometheus}" && is_prometheus_image "${img}"; then
      continue
    fi

    if ! is_true "${enable_grafana}" && is_grafana_image "${img}"; then
      continue
    fi

    if ! is_true "${enable_loki}" && is_loki_image "${img}"; then
      continue
    fi

    if ! is_true "${enable_victoria_logs}" && is_victoria_logs_image "${img}"; then
      continue
    fi

    if ! is_true "${enable_tempo}" && is_tempo_image "${img}"; then
      continue
    fi

    if ! is_true "${enable_headlamp}" && is_headlamp_image "${img}"; then
      continue
    fi

    if ! is_true "${enable_sso}" && is_sso_image "${img}"; then
      continue
    fi

    if ! is_true "${enable_actions_runner}" && is_actions_runner_image "${img}"; then
      continue
    fi

    if ! is_true "${enable_signoz}" && ! is_true "${enable_prometheus}" && ! is_true "${enable_grafana}" && ! is_true "${enable_loki}" && ! is_true "${enable_victoria_logs}" && ! is_true "${enable_tempo}" && is_otel_collector_image "${img}"; then
      continue
    fi

    output+="${img}"$'\n'
  done <<< "$images"

  printf "%s" "${output}"
}

normalize_arch() {
  case "${1:-}" in
    amd64|x86_64) echo "amd64" ;;
    arm64|aarch64) echo "arm64" ;;
    *) echo "${1:-}" ;;
  esac
}

kind_get_nodes_safe() {
  local timeout="${PRELOAD_KIND_GET_NODES_TIMEOUT_SECONDS:-20}"
  local tmp pid start elapsed rc

  tmp="$(mktemp)"
  kind get nodes --name "$CLUSTER_NAME" >"$tmp" 2>/dev/null &
  pid=$!
  start="$(date +%s)"

  while kill -0 "$pid" >/dev/null 2>&1; do
    elapsed=$(( $(date +%s) - start ))
    if [[ "$elapsed" -ge "$timeout" ]]; then
      terminate_pid_safe "$pid"
      rm -f "$tmp"
      echo "WARN: kind get nodes timed out after ${timeout}s" >&2
      return 124
    fi
    sleep 1
  done

  wait "$pid"
  rc=$?
  cat "$tmp"
  rm -f "$tmp"
  return "$rc"
}

kind_get_clusters_safe() {
  local timeout="${PRELOAD_KIND_GET_CLUSTERS_TIMEOUT_SECONDS:-10}"
  local tmp pid start elapsed rc

  tmp="$(mktemp)"
  kind get clusters >"$tmp" 2>/dev/null &
  pid=$!
  start="$(date +%s)"

  while kill -0 "$pid" >/dev/null 2>&1; do
    elapsed=$(( $(date +%s) - start ))
    if [[ "$elapsed" -ge "$timeout" ]]; then
      terminate_pid_safe "$pid"
      rm -f "$tmp"
      echo "WARN: kind get clusters timed out after ${timeout}s" >&2
      return 124
    fi
    sleep 1
  done

  wait "$pid"
  rc=$?
  cat "$tmp"
  rm -f "$tmp"
  return "$rc"
}

docker_image_exists() {
  local img="$1"
  local timeout="${PRELOAD_DOCKER_INSPECT_TIMEOUT_SECONDS:-15}"
  local pid start elapsed

  docker image inspect "$img" >/dev/null 2>&1 &
  pid=$!
  start="$(date +%s)"

  while kill -0 "$pid" >/dev/null 2>&1; do
    elapsed=$(( $(date +%s) - start ))
    if [[ "$elapsed" -ge "$timeout" ]]; then
      terminate_pid_safe "$pid"
      echo "WARN: docker image inspect timed out for $img after ${timeout}s" >&2
      return 1
    fi
    sleep 1
  done

  wait "$pid"
}

docker_image_repo_digests() {
  local img="$1"
  local timeout="${PRELOAD_DOCKER_INSPECT_TIMEOUT_SECONDS:-15}"
  local tmp pid start elapsed rc

  tmp="$(mktemp)"
  docker image inspect --format '{{join .RepoDigests "\n"}}' "$img" >"$tmp" 2>/dev/null &
  pid=$!
  start="$(date +%s)"

  while kill -0 "$pid" >/dev/null 2>&1; do
    elapsed=$(( $(date +%s) - start ))
    if [[ "$elapsed" -ge "$timeout" ]]; then
      terminate_pid_safe "$pid"
      rm -f "$tmp"
      echo "WARN: docker repo digest inspect timed out for $img after ${timeout}s" >&2
      return 1
    fi
    sleep 1
  done

  wait "$pid"
  rc=$?
  cat "$tmp"
  rm -f "$tmp"
  return "$rc"
}

docker_pull_safe() {
  local ref="$1"
  shift || true
  local timeout="${PRELOAD_DOCKER_PULL_TIMEOUT_SECONDS:-180}"
  local tmp pid start elapsed rc

  tmp="$(mktemp)"
  docker pull "$@" "$ref" >"$tmp" 2>&1 &
  pid=$!
  start=$(date +%s)

  while kill -0 "$pid" >/dev/null 2>&1; do
    elapsed=$(( $(date +%s) - start ))
    if [[ "$elapsed" -ge "$timeout" ]]; then
      terminate_pid_safe "$pid"
      rm -f "$tmp"
      echo "WARN: docker pull timed out for $ref after ${timeout}s" >&2
      return 1
    fi
    sleep 1
  done

  wait "$pid"
  rc=$?
  cat "$tmp"
  rm -f "$tmp"
  return "$rc"
}

docker_info_field_safe() {
  local format="$1"
  local timeout="${PRELOAD_DOCKER_INFO_TIMEOUT_SECONDS:-10}"
  local tmp pid start elapsed rc

  tmp="$(mktemp)"
  docker info -f "$format" >"$tmp" 2>&1 &
  pid=$!
  start=$(date +%s)

  while kill -0 "$pid" >/dev/null 2>&1; do
    elapsed=$(( $(date +%s) - start ))
    if [[ "$elapsed" -ge "$timeout" ]]; then
      terminate_pid_safe "$pid"
      rm -f "$tmp"
      echo "WARN: docker info timed out after ${timeout}s for format ${format}" >&2
      return 1
    fi
    sleep 1
  done

  wait "$pid"
  rc=$?
  cat "$tmp"
  rm -f "$tmp"
  return "$rc"
}

docker_inspect_field_safe() {
  local target="$1"
  local format="$2"
  local timeout="${PRELOAD_DOCKER_INSPECT_TIMEOUT_SECONDS:-15}"
  local tmp pid start elapsed rc

  tmp="$(mktemp)"
  docker inspect -f "$format" "$target" >"$tmp" 2>&1 &
  pid=$!
  start=$(date +%s)

  while kill -0 "$pid" >/dev/null 2>&1; do
    elapsed=$(( $(date +%s) - start ))
    if [[ "$elapsed" -ge "$timeout" ]]; then
      terminate_pid_safe "$pid"
      rm -f "$tmp"
      echo "WARN: docker inspect timed out for $target after ${timeout}s" >&2
      return 1
    fi
    sleep 1
  done

  wait "$pid"
  rc=$?
  cat "$tmp"
  rm -f "$tmp"
  return "$rc"
}

detect_target_platform() {
  if [[ -n "$USER_PLATFORM" ]]; then
    echo "$USER_PLATFORM"
    return 0
  fi

  if command -v kind >/dev/null 2>&1 && kind_get_clusters_safe | grep -qx "$CLUSTER_NAME"; then
    local node os arch
    node="$(kind_get_nodes_safe | head -n 1 || true)"
    if [[ -n "$node" ]]; then
      os="$(docker_inspect_field_safe "$node" '{{.Platform}}' 2>/dev/null || true)"
      arch="$(docker_inspect_field_safe "$node" '{{.ImageManifestDescriptor.platform.architecture}}' 2>/dev/null || true)"
      if [[ -n "$os" && -n "$arch" ]]; then
        arch="$(normalize_arch "$arch")"
        echo "${os}/${arch}"
        return 0
      fi
    fi
  fi

  local os arch
  os="$(docker_info_field_safe '{{.OSType}}' 2>/dev/null || true)"
  arch="$(docker_info_field_safe '{{.Architecture}}' 2>/dev/null || true)"
  arch="$(normalize_arch "$arch")"

  if [[ -z "$os" ]]; then
    os="linux"
  fi
  if [[ -z "$arch" ]]; then
    arch="$(normalize_arch "$(uname -m)")"
  fi
  echo "${os}/${arch}"
}

image_repo_no_tag() {
  # Strip any @digest, then strip a :tag only if it appears in the last path segment
  # (so we don't break registries with ports, e.g. localhost:5000/repo:tag).
  local ref="${1%@*}"
  local last="${ref##*/}"
  if [[ "$last" == *:* ]]; then
    echo "${ref%:*}"
  else
    echo "$ref"
  fi
}

canonicalize_image_ref() {
  local ref="$1"
  local digest=""
  local name="$ref"
  local last tag=""

  if [[ "$name" == *"@"* ]]; then
    digest="@${name##*@}"
    name="${name%@*}"
  fi

  last="${name##*/}"
  if [[ -z "$digest" && "$last" == *:* ]]; then
    tag=":${last##*:}"
    name="${name%:*}"
  fi

  local first="${name%%/*}"
  if [[ "$first" != *.* && "$first" != *:* && "$first" != "localhost" ]]; then
    if [[ "$name" == */* ]]; then
      name="docker.io/${name}"
    else
      name="docker.io/library/${name}"
    fi
  fi

  echo "${name}${tag}${digest}"
}

extract_external_images_from_dockerfile() {
  local dockerfile="$1"

  awk '
    toupper($1) == "FROM" {
      i = 2
      while (i <= NF && $i ~ /^--platform=/) i++
      img = $i
      if (img != "" && img !~ /^\$/) print img
    }
    {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^--from=/) {
          img = $i
          sub(/^--from=/, "", img)
          if (img != "" && img !~ /^\$/ && img ~ /[\/.:]/) print img
        }
      }
    }
  ' "$dockerfile"
}

workflow_required_base_images() {
  local rel abs out=""

  for rel in "${WORKFLOW_DOCKERFILES[@]}"; do
    abs="${REPO_ROOT}/${rel}"
    if [[ ! -f "${abs}" ]]; then
      echo "WARN: workflow Dockerfile not found: ${rel}" >&2
      continue
    fi

    while IFS= read -r img; do
      [[ -z "${img}" ]] && continue
      out+="${img}"$'\n'
    done < <(extract_external_images_from_dockerfile "${abs}")
  done

  if [[ -z "${out}" ]]; then
    return 0
  fi

  printf '%s' "${out}" | sort -u
}

image_list_contains_ref() {
  local list="$1"
  local target="$2"
  local canonical_target canonical_candidate

  canonical_target="$(canonicalize_image_ref "${target}")"
  while IFS= read -r candidate; do
    [[ -z "${candidate}" ]] && continue
    canonical_candidate="$(canonicalize_image_ref "${candidate}")"
    if [[ "${canonical_candidate}" == "${canonical_target}" ]]; then
      return 0
    fi
  done <<< "${list}"
  return 1
}

candidate_refs_for_image() {
  local img="$1"
  local pinned_ref="${2:-}"
  local canonical_img canonical_pinned

  printf '%s\n' "$img"
  canonical_img="$(canonicalize_image_ref "$img")"
  if [[ "$canonical_img" != "$img" ]]; then
    printf '%s\n' "$canonical_img"
  fi

  if [[ -n "$pinned_ref" && "$pinned_ref" != "-" ]]; then
    printf '%s\n' "$pinned_ref"
    canonical_pinned="$(canonicalize_image_ref "$pinned_ref")"
    if [[ "$canonical_pinned" != "$pinned_ref" ]]; then
      printf '%s\n' "$canonical_pinned"
    fi
  fi
}

resolve_platform_digest() {
  local img="$1"
  local os="${TARGET_PLATFORM%/*}"
  local arch="${TARGET_PLATFORM#*/}"
  local digest=""

  if ! digest="$(
    docker buildx imagetools inspect --format '{{json .}}' "$img" 2>/dev/null | \
      jq -r \
        --arg os "$os" \
        --arg arch "$arch" \
        '
        .manifest as $manifest
        | ($manifest.manifests // []) as $manifests
        | (
            [ $manifests[]? | select((.platform.os // "") == $os and (.platform.architecture // "") == $arch) | .digest ]
            | map(select(. != null and . != ""))
            | .[0]
          ) // ($manifest.digest // "")
        '
  )"; then
    return 1
  fi

  [[ -n "${digest}" ]] || return 1
  printf '%s\n' "${digest}"
}

pin_image_to_platform_digest() {
  local img="$1"
  local repo digest ref

  digest="$(resolve_platform_digest "$img")" || return 1
  if [[ -z "$digest" ]]; then
    return 1
  fi

  # If already pinned to the right manifest digest, don't hit the registry again.
  if docker_image_repo_digests "$img" 2>/dev/null | grep -q "@${digest}$"; then
    return 0
  fi

  repo="$(image_repo_no_tag "$img")"
  ref="${repo}@${digest}"

  echo "  pulling $img (pinning to $TARGET_PLATFORM via $ref)"
  docker_pull_safe "$ref" >/dev/null
  docker tag "$ref" "$img"
}

default_lock_file_for_platform() {
  local plat="$1"
  plat="${plat//\//-}"
  echo "${SCRIPT_DIR}/preload-images.${plat}.lock"
}

generate_lock_file() {
  local out="$1"
  local tmp
  local digest repo
  require_cmd jq
  tmp="$(mktemp)"

  : >"$tmp"
  while IFS= read -r img; do
    [[ -z "$img" ]] && continue
    digest="$(resolve_platform_digest "$img" 2>/dev/null || true)"
    if [[ -z "$digest" ]]; then
      echo "  WARN    unable to resolve digest for $img ($TARGET_PLATFORM); will fall back to docker pull --platform" >&2
      printf '%s\t-\n' "$img" >>"$tmp"
      continue
    fi
    repo="$(image_repo_no_tag "$img")"
    printf '%s\t%s@%s\n' "$img" "$repo" "$digest" >>"$tmp"
  done <<< "$images"

  mv -f "$tmp" "$out"
}

lookup_pinned_ref() {
  local img="$1"
  if [[ ! -f "$LOCK_FILE" ]]; then
    return 1
  fi
  awk -F '\t' -v img="$img" '$1 == img {print $2; exit 0}' "$LOCK_FILE"
}

image_has_digest() {
  local img="$1"
  local digest="$2"
  docker_image_repo_digests "$img" 2>/dev/null | grep -q "@${digest}$"
}

ensure_pinned_tag() {
  local img="$1"
  local pinned_ref="$2"

  [[ -z "$pinned_ref" ]] && return 1
  local digest="${pinned_ref##*@}"

  if docker_image_exists "$img" && image_has_digest "$img" "$digest"; then
    return 0
  fi

  # Prefer local availability of the pinned ref to avoid hitting registries.
  if ! docker_image_exists "$pinned_ref"; then
    docker_pull_safe "$pinned_ref" >/dev/null
  fi
  docker tag "$pinned_ref" "$img"
}

# --- Discover mode: dump images from running cluster ---
if [[ "$MODE" == "discover" ]]; then
  require_cmd kubectl
  kubectl get pods --all-namespaces -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{range .spec.initContainers[*]}{.image}{"\n"}{end}{end}' \
    | sort -u \
    | grep -v '^$' \
    | grep -v '^localhost:30090/'
  exit 0
fi

# --- Parse image list ---
parse_images() {
  if [[ ! -f "$IMAGE_LIST" ]]; then
    echo "Image list not found: $IMAGE_LIST" >&2
    exit 1
  fi
  grep -v '^\s*#' "$IMAGE_LIST" | grep -v '^\s*$' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

images="$(parse_images)"

required_workflow_images="$(workflow_required_base_images)"
if [[ -n "${required_workflow_images}" ]]; then
  missing_required_images=""
  while IFS= read -r required_img; do
    [[ -z "${required_img}" ]] && continue
    if ! image_list_contains_ref "${images}" "${required_img}"; then
      missing_required_images+="${required_img}"$'\n'
    fi
  done <<< "${required_workflow_images}"

  if [[ -n "${missing_required_images}" ]]; then
    echo "Auto-adding workflow-required build base image(s) missing from ${IMAGE_LIST}:" >&2
    while IFS= read -r required_img; do
      [[ -z "${required_img}" ]] && continue
      echo "  - ${required_img}" >&2
    done <<< "${missing_required_images}"
    images="$(printf '%s\n%s' "${images}" "${missing_required_images}" | awk 'NF && !seen[$0]++')"
  fi
fi

HAS_TOGGLE_INPUTS="false"
if [[ -n "${TFVARS_FILE}" && -f "${TFVARS_FILE}" ]]; then
  HAS_TOGGLE_INPUTS="true"
fi
for env_key in PRELOAD_ENABLE_SIGNOZ PRELOAD_ENABLE_PROMETHEUS PRELOAD_ENABLE_GRAFANA PRELOAD_ENABLE_LOKI PRELOAD_ENABLE_VICTORIA_LOGS PRELOAD_ENABLE_TEMPO PRELOAD_ENABLE_HEADLAMP PRELOAD_ENABLE_SSO PRELOAD_ENABLE_ACTIONS_RUNNER; do
  if [[ -n "${!env_key:-}" ]]; then
    HAS_TOGGLE_INPUTS="true"
    break
  fi
done

if is_true "${HAS_TOGGLE_INPUTS}"; then
  ENABLE_SIGNOZ="$(toggle_input_or_default "PRELOAD_ENABLE_SIGNOZ" "enable_signoz" "false")"
  ENABLE_PROMETHEUS="$(toggle_input_or_default "PRELOAD_ENABLE_PROMETHEUS" "enable_prometheus" "false")"
  ENABLE_GRAFANA="$(toggle_input_or_default "PRELOAD_ENABLE_GRAFANA" "enable_grafana" "false")"
  ENABLE_LOKI="$(toggle_input_or_default "PRELOAD_ENABLE_LOKI" "enable_loki" "false")"
  ENABLE_VICTORIA_LOGS="$(toggle_input_or_default "PRELOAD_ENABLE_VICTORIA_LOGS" "enable_victoria_logs" "false")"
  ENABLE_TEMPO="$(toggle_input_or_default "PRELOAD_ENABLE_TEMPO" "enable_tempo" "false")"
  ENABLE_HEADLAMP="$(toggle_input_or_default "PRELOAD_ENABLE_HEADLAMP" "enable_headlamp" "false")"
  ENABLE_SSO="$(toggle_input_or_default "PRELOAD_ENABLE_SSO" "enable_sso" "false")"
  ENABLE_ACTIONS_RUNNER="$(toggle_input_or_default "PRELOAD_ENABLE_ACTIONS_RUNNER" "enable_actions_runner" "false")"

  if [[ -n "${TFVARS_FILE}" && -f "${TFVARS_FILE}" ]]; then
    echo "Applying feature filters from ${TFVARS_FILE} with PRELOAD_ENABLE_* env overrides" >&2
  else
    echo "Applying feature filters from PRELOAD_ENABLE_* env overrides" >&2
  fi

  images="$(filter_images_by_toggles \
    "${ENABLE_SIGNOZ}" \
    "${ENABLE_PROMETHEUS}" \
    "${ENABLE_GRAFANA}" \
    "${ENABLE_LOKI}" \
    "${ENABLE_VICTORIA_LOGS}" \
    "${ENABLE_TEMPO}" \
    "${ENABLE_HEADLAMP}" \
    "${ENABLE_SSO}" \
    "${ENABLE_ACTIONS_RUNNER}")"
fi

if [[ -z "$images" ]]; then
  echo "No images found in $IMAGE_LIST"
  exit 0
fi

if [[ "$MODE" == "print-images" ]]; then
  printf '%s\n' "$images"
  exit 0
fi

require_cmd docker

total="$(echo "$images" | wc -l | tr -d ' ')"
echo "Found $total image(s) in $IMAGE_LIST"

INDEX_WIDTH=${#total}
if [[ "$INDEX_WIDTH" -lt 2 ]]; then
  INDEX_WIDTH=2
fi

TARGET_PLATFORM="$(detect_target_platform)"
if [[ "$TARGET_PLATFORM" != */* ]]; then
  echo "WARN: unable to detect a valid platform; defaulting to linux/amd64" >&2
  TARGET_PLATFORM="linux/amd64"
fi
echo "Using platform: $TARGET_PLATFORM"

if [[ -z "$LOCK_FILE" ]]; then
  LOCK_FILE="$(default_lock_file_for_platform "$TARGET_PLATFORM")"
fi

if [[ "$REFRESH_LOCK" -eq 1 || ! -f "$LOCK_FILE" ]]; then
  echo "Generating lock file: $LOCK_FILE"
  generate_lock_file "$LOCK_FILE"
fi

pairs_file="$(mktemp)"
pull_results_dir="$(mktemp -d)"
PULL_RESULTS_DIR="$pull_results_dir"
trap 'rm -f "$pairs_file"; rm -rf "$PULL_RESULTS_DIR"' EXIT
idx=0
while IFS= read -r img; do
  [[ -z "$img" ]] && continue
  idx=$((idx + 1))
  pinned="$(lookup_pinned_ref "$img" || true)"
  [[ -z "$pinned" ]] && pinned="-"
  printf '%s\t%s\t%s\n' "$idx" "$img" "$pinned" >>"$pairs_file"
done <<< "$images"

# --- Pull images (ensure the correct platform is cached locally) ---
pull_image() {
  local idx="$1"
  local img="$2"
  local pinned_ref="${3:-}"
  local prefix
  local result

  prefix="$(printf "%0${INDEX_WIDTH}d/%d" "$idx" "$total")"
  [[ "$pinned_ref" == "-" ]] && pinned_ref=""

  if docker_image_exists "$img"; then
    if [[ -n "$pinned_ref" ]]; then
      if ensure_pinned_tag "$img" "$pinned_ref"; then
        result="  [$prefix] cached  $img (pinned)"
        printf '%s\n' "$result" >"${PULL_RESULTS_DIR}/${idx}.log"
        return 0
      fi
    fi
    result="  [$prefix] cached  $img"
    printf '%s\n' "$result" >"${PULL_RESULTS_DIR}/${idx}.log"
    return 0
  fi

  if [[ -n "$pinned_ref" ]]; then
    if ! ensure_pinned_tag "$img" "$pinned_ref"; then
      result="  WARN    [$prefix] failed to pull/pin $img (continuing)"
      printf '%s\n' "$result" >"${PULL_RESULTS_DIR}/${idx}.log"
      return 0
    fi

    result="  [$prefix] pulled  $img (pinned: $TARGET_PLATFORM)"
    printf '%s\n' "$result" >"${PULL_RESULTS_DIR}/${idx}.log"
    return 0
  fi

  if ! docker_pull_safe "$img" --platform "$TARGET_PLATFORM" | tail -1; then
    result="  WARN    [$prefix] failed to pull $img (continuing)"
    printf '%s\n' "$result" >"${PULL_RESULTS_DIR}/${idx}.log"
    return 0  # graceful: continue with other images
  fi

  result="  [$prefix] pulled  $img ($TARGET_PLATFORM)"
  printf '%s\n' "$result" >"${PULL_RESULTS_DIR}/${idx}.log"
}
export -f pull_image
export TARGET_PLATFORM
export INDEX_WIDTH
export total
export PULL_RESULTS_DIR

export -f terminate_pid_safe
export -f docker_image_exists
export -f docker_image_repo_digests
export -f docker_pull_safe
export -f ensure_pinned_tag
export -f image_has_digest

echo ""
echo "Pulling images (parallelism=$PARALLELISM)..."
xargs -P "$PARALLELISM" -n 3 <"$pairs_file" bash -c 'pull_image "$@"' _

echo "Pull results (ordered):"
pull_results_missing=0
pull_cached=0
while IFS=$'\t' read -r idx img pinned_ref; do
  prefix="$(printf "%0${INDEX_WIDTH}d/%d" "$idx" "$total")"
  if [[ -f "${PULL_RESULTS_DIR}/${idx}.log" ]]; then
    result_line="$(cat "${PULL_RESULTS_DIR}/${idx}.log")"
    echo "$result_line"
    if [[ "$result_line" == *" cached  "* ]]; then
      pull_cached=$((pull_cached + 1))
    fi
  else
    echo "  WARN    [$prefix] no pull result recorded for $img"
    pull_results_missing=$((pull_results_missing + 1))
  fi
done < "$pairs_file"

if [[ "$pull_results_missing" -gt 0 ]]; then
  echo "WARN: missing pull results for ${pull_results_missing} image(s)" >&2
fi

if [[ "$MODE" == "pull-only" ]]; then
  echo ""
  echo "Done (pull-only mode). cached=$pull_cached total=$total"
  exit 0
fi

# --- Load into kind cluster ---
if ! command -v kind >/dev/null 2>&1; then
  require_cmd kind
fi

if ! kind_get_clusters_safe | grep -qx "$CLUSTER_NAME"; then
  echo "Kind cluster '$CLUSTER_NAME' not found" >&2
  exit 1
fi

# Load images one-by-one so a single corrupt manifest doesn't block everything.
loaded=0
skipped=0
failed=0
cluster_cached=0
workdir="$(mktemp -d)"
cluster_refs_dir="$(mktemp -d)"
trap 'rm -rf "$workdir" "$cluster_refs_dir" "$pairs_file" "$PULL_RESULTS_DIR"' EXIT

declare -a CLUSTER_NODES=()
while IFS= read -r node; do
  [[ -z "$node" ]] && continue
  CLUSTER_NODES+=("$node")
done < <(kind_get_nodes_safe || true)

for node in "${CLUSTER_NODES[@]}"; do
  docker exec "$node" ctr --namespace=k8s.io images ls -q >"${cluster_refs_dir}/${node}.txt" || true
done

cluster_has_image_on_all_nodes() {
  local img="$1"
  local pinned_ref="${2:-}"
  local refs_file node

  if [[ "${#CLUSTER_NODES[@]}" -eq 0 ]]; then
    return 1
  fi

  refs_file="$(mktemp)"
  candidate_refs_for_image "$img" "$pinned_ref" | sort -u >"$refs_file"

  for node in "${CLUSTER_NODES[@]}"; do
    if ! grep -Fxf "$refs_file" "${cluster_refs_dir}/${node}.txt" >/dev/null 2>&1; then
      rm -f "$refs_file"
      return 1
    fi
  done

  rm -f "$refs_file"
  return 0
}

save_image_archive() {
  local img="$1"
  local archive="$2"
  local save_timeout="${PRELOAD_SAVE_TIMEOUT_SECONDS:-120}"
  local pid start elapsed

  run_docker_save() {
    if docker save --platform "$TARGET_PLATFORM" -o "$archive" "$img" >/dev/null 2>&1; then
      return 0
    fi

    # Some registries/images do not round-trip cleanly with docker save --platform
    # even when the tag has already been pinned to the desired digest.
    docker save -o "$archive" "$img" >/dev/null 2>&1
  }

  rm -f "$archive"
  run_docker_save &
  pid=$!
  start="$(date +%s)"

  while kill -0 "$pid" >/dev/null 2>&1; do
    elapsed=$(( $(date +%s) - start ))
    if [[ "$elapsed" -ge "$save_timeout" ]]; then
      terminate_pid_safe "$pid"
      rm -f "$archive"
      echo "  WARN    docker save timed out for $img after ${save_timeout}s" >&2
      return 1
    fi
    sleep 1
  done

  wait "$pid"
}

load_image_with_fallback() {
  local img="$1"
  local archive="$2"
  local prefix="$3"
  local tmp_log
  local tmp_fallback_log

  tmp_log="$(mktemp)"
  if kind load image-archive --name "$CLUSTER_NAME" "$archive" >"$tmp_log" 2>&1; then
    rm -f "$tmp_log"
    return 0
  fi

  if grep -Eq 'content digest sha256:[0-9a-f]{64}: not found' "$tmp_log"; then
    echo "  INFO    [$prefix] archive import digest mismatch for $img; trying fallback loader..." >&2
    tmp_fallback_log="$(mktemp)"
    if kind load docker-image --name "$CLUSTER_NAME" "$img" >"$tmp_fallback_log" 2>&1; then
      rm -f "$tmp_fallback_log"
      rm -f "$tmp_log"
      return 0
    fi

    if kind_get_nodes_safe >/dev/null 2>&1; then
      local node
      local all_ok=1
      while IFS= read -r node; do
        [[ -z "$node" ]] && continue
        if ! docker exec --privileged "$node" ctr --namespace=k8s.io images pull --platform "$TARGET_PLATFORM" "$img" >/dev/null 2>&1; then
          all_ok=0
          break
        fi
      done < <(kind_get_nodes_safe || true)

      if [[ "$all_ok" -eq 1 ]]; then
        echo "  INFO    [$prefix] loaded $img via node pull fallback" >&2
        rm -f "$tmp_fallback_log"
        rm -f "$tmp_log"
        return 0
      fi
    fi

    rm -f "$tmp_fallback_log"
  fi

  cat "$tmp_log" >&2
  rm -f "$tmp_log"
  return 1
}

while IFS=$'\t' read -r idx img pinned_ref; do
  prefix="$(printf "%0${INDEX_WIDTH}d/%d" "$idx" "$total")"
  [[ "$pinned_ref" == "-" ]] && pinned_ref=""

  if cluster_has_image_on_all_nodes "$img" "$pinned_ref"; then
    echo "  [$prefix] present $img (already in kind nodes)"
    cluster_cached=$((cluster_cached + 1))
    continue
  fi

  if ! docker_image_exists "$img"; then
    echo "  [$prefix] skip    $img (not in local cache)"
    skipped=$((skipped + 1))
    continue
  fi

  if [[ -n "$pinned_ref" ]]; then
    if ! ensure_pinned_tag "$img" "$pinned_ref"; then
      echo "  WARN    [$prefix] failed to pin $img to $TARGET_PLATFORM (continuing)" >&2
      failed=$((failed + 1))
      continue
    fi
  fi

  archive="${workdir}/image-$(echo "$img" | tr '/:@' '___').tar"
  if ! save_image_archive "$img" "$archive"; then
    echo "  WARN    [$prefix] failed to docker save $img for $TARGET_PLATFORM (continuing)" >&2
    failed=$((failed + 1))
    continue
  fi

  if load_image_with_fallback "$img" "$archive" "$prefix"; then
    loaded=$((loaded + 1))
    echo "  [$prefix] loaded  $img"
    continue
  fi

  echo "  INFO    [$prefix] load failed for $img; refreshing pinned ref and retrying once..." >&2
  if [[ -n "$pinned_ref" ]] && ensure_pinned_tag "$img" "$pinned_ref"; then
    save_image_archive "$img" "$archive" >/dev/null 2>&1 || true
  fi

  if load_image_with_fallback "$img" "$archive" "$prefix"; then
    loaded=$((loaded + 1))
    echo "  [$prefix] loaded  $img"
  else
    echo "  WARN    [$prefix] failed to load $img into kind (continuing)" >&2
    failed=$((failed + 1))
  fi
done < "$pairs_file"

echo ""
echo "Done. cached=$pull_cached cluster_cached=$cluster_cached loaded=$loaded skipped=$skipped failed=$failed total=$total"
