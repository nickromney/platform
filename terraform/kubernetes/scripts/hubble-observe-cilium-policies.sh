#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
  cat <<'EOF'
Usage: hubble-observe-cilium-policies.sh [options]

Capture short Hubble flow windows across namespaces, summarise the observed
traffic, and generate candidate ingress/egress Cilium policies under a
timestamped output directory.

The script is intentionally conservative, but it is also usable for bootstrap
work:

- it captures ordinary Hubble flows by default so bootstrap runs still see
  traffic when no Cilium policies are installed
- `--capture-mode policy-verdict` is available for refinement runs against an
  already-constrained cluster
- it drops `is_reply=true` flows before summarising
- it writes candidate manifests only; it does not change the repo-managed live
  Cilium policy tree or patch the cluster into audit mode
- it emits at most one ingress candidate and one egress candidate per namespace
- if a direction produces more than the row threshold, it falls back from
  workload-level selectors to aggregated namespace/entity rules for that
  direction

Output:
  A run directory containing:
  - raw captures per namespace/iteration
  - filtered captures with reply traffic removed
  - workload and world TSV summaries for ingress and egress
  - namespace/entity aggregate TSV files when threshold fallback is used
  - candidate policy manifests under policies/<namespace>/
  - a run-report.md summary

Options:
  --capture-strategy since|last|adaptive
      Use time-window capture, bounded recent sampling, or recent-sample-first
      observation with a fallback to the current since/iterations flow.
      Default: adaptive

  --since DURATION
      Capture horizon for each iteration. Default: 5m
      The default run asks Hubble for 3 separate 5m windows per namespace.

  --sample-target N
      Target recent-sample size used by `--capture-strategy last|adaptive`.
      Default: 1000

  --sample-min N
      Minimum non-reply usable flow count required for adaptive sampling to
      stop escalating before it falls back to `--since`.
      Default: 200

  --iterations N
      Number of capture rounds per namespace. Default: 3

  --namespace-workers N
      Number of namespaces to capture/summarise in parallel.
      Policy generation still runs serially for deterministic output.
      Default: 1

  --sleep-between SECONDS
      Sleep this many seconds between iterations. Default: 0

  --progress-every SECONDS
      Emit a heartbeat while helper commands are still running.
      Use 0 to disable. Default: 10

  --row-threshold N
      Workload-summary row threshold before falling back to namespace/entity
      aggregation for a direction. Default: 100

  --capture-mode flows|policy-verdict
      Capture ordinary traffic flows (default) or only policy-verdict events.

  --world-egress-mode observed|entity
      For egress flows that Hubble classifies as `world`, either prefer exact
      observed FQDN/CIDR targets and skip unresolved broad world rules
      (`observed`), or preserve legacy `toEntities: world` generation
      (`entity`). Default: observed

  --namespace NS
      Repeatable namespace allowlist. By default, all namespaces are scanned.

  --exclude-namespace NS
      Repeatable namespace exclusion applied after discovery.

  --output-dir DIR
      Write results under DIR. Default:
      <repo>/.run/hubble-observe-<kube-context>/<timestamp>

  --promote-to-module
      Copy generated candidate manifests into `cilium-module/sources/<category>/`
      and render matching `categories/<category>/` files.

  --module-root DIR
      Override the cilium-module root used for promotion. Supplying this option
      also enables `--promote-to-module`.
      Default:
      terraform/kubernetes/cluster-policies/cilium/cilium-module

  --force-module-overwrite
      Replace an existing promoted source manifest when it differs.

  --port-forward-port PORT
      Local port used by hubble-capture-flows.sh. Use 0 to let Hubble pick a
      random free port. Default: 0

  --kubeconfig FILE
      Kubeconfig forwarded to hubble-capture-flows.sh and used for selector
      resolution. Defaults to ~/.kube/kind-kind-local.yaml when present.

  --kube-context NAME
      Kube context for capture and selector resolution.

  --print-command
      Print the underlying capture commands.

  --dry-run
      Print what would be done and exit.

  -h, --help
      Show this help text.

Notes:
  This script produces candidate manifests under .run/ for review. It does not
  replace the existing Argo CD-managed policy tree in
  terraform/kubernetes/cluster-policies/cilium.
  Use `--promote-to-module` when you want the same run to also populate
  `cluster-policies/cilium/cilium-module/sources/` and render
  `cluster-policies/cilium/cilium-module/categories/`.
  Kubernetes API access:
  - if you omit `--namespace`, the script needs `list namespaces`
  - selector resolution needs `get` on deployments, daemonsets, statefulsets,
    pods, and replicasets in any namespace whose workloads appear in the
    generated policy candidates
  - all namespaces are included by default; use `--exclude-namespace` when you
    want to trim bootstrap noise
  - `--world-egress-mode observed` prefers exact external destinations from
    Hubble (`toFQDNs` or `toCIDRSet`) over broad `toEntities: world`

Examples:
  terraform/kubernetes/scripts/hubble-observe-cilium-policies.sh \
    --capture-strategy adaptive \
    --sample-target 1000 \
    --sample-min 200 \
    --since 30s \
    --iterations 1 \
    --exclude-namespace argocd

  terraform/kubernetes/scripts/hubble-observe-cilium-policies.sh \
    --namespace argocd \
    --capture-strategy last \
    --sample-target 1000 \
    --since 30s \
    --iterations 1
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

fail() {
  echo "hubble-observe-cilium-policies.sh: $*" >&2
  exit 1
}

warn() {
  echo "hubble-observe-cilium-policies.sh: $*" >&2
}

warn_once() {
  local cache_key="$1"
  shift

  if [[ -n "${WARNED_MESSAGES_FILE}" ]] && grep -Fqx -- "${cache_key}" "${WARNED_MESSAGES_FILE}" 2>/dev/null; then
    return 0
  fi

  printf '%s\n' "${cache_key}" >> "${WARNED_MESSAGES_FILE}"
  warn "$@"
}

info() {
  echo "hubble-observe-cilium-policies.sh: $*" >&2
}

run_command_with_progress() {
  local label="$1"
  local stdout_file="$2"
  local stderr_file="$3"
  shift 3

  local cmd_pid=""
  local progress_pid=""
  local status=0
  local started_at=$SECONDS
  local elapsed=0

  if [[ "${progress_every}" -eq 0 ]]; then
    if "$@" > "${stdout_file}" 2> "${stderr_file}"; then
      return 0
    fi
    return $?
  fi

  "$@" > "${stdout_file}" 2> "${stderr_file}" &
  cmd_pid=$!

  (
    while true; do
      sleep "${progress_every}"
      if ! kill -0 "${cmd_pid}" 2>/dev/null; then
        exit 0
      fi
      elapsed=$((SECONDS - started_at))
      info "${label}: still running after ${elapsed}s"
    done
  ) &
  progress_pid=$!

  if wait "${cmd_pid}"; then
    status=0
  else
    status=$?
  fi

  if [[ -n "${progress_pid}" ]]; then
    kill "${progress_pid}" 2>/dev/null || true
    wait "${progress_pid}" 2>/dev/null || true
  fi

  return "${status}"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 not found in PATH"
}

kubectl_can_i() {
  local verb="$1"
  local resource="$2"
  local namespace="${3:-}"
  local args=(auth can-i "${verb}" "${resource}")
  local output=""

  if [[ -n "${namespace}" ]]; then
    args+=(-n "${namespace}")
  fi

  if ! output="$("${KUBECTL_BASE[@]}" "${args[@]}" 2>/dev/null)"; then
    CAN_I_ERROR_MSG="failed to query Kubernetes access with: kubectl ${args[*]}"
    return 2
  fi

  output="${output##*$'\n'}"
  output="${output//[[:space:]]/}"

  case "${output}" in
    yes)
      return 0
      ;;
    no)
      return 1
      ;;
    *)
      CAN_I_ERROR_MSG="unexpected output from kubectl ${args[*]}: ${output}"
      return 2
      ;;
  esac
}

require_kubectl_permission() {
  local verb="$1"
  local resource="$2"
  local namespace="$3"
  local reason="$4"
  local scope_msg=""
  local scope_cmd=""
  local status=0

  if [[ -n "${namespace}" ]]; then
    scope_msg=" in namespace ${namespace}"
    scope_cmd=" -n ${namespace}"
  fi

  if kubectl_can_i "${verb}" "${resource}" "${namespace}"; then
    return 0
  fi
  status=$?

  if [[ "${status}" -eq 2 ]]; then
    fail "${CAN_I_ERROR_MSG}"
  fi

  fail "missing required Kubernetes permission to ${reason}: cannot ${verb} ${resource}${scope_msg}. Check: kubectl auth can-i ${verb} ${resource}${scope_cmd}"
}

ensure_selector_resolution_access() {
  local namespace="$1"
  local resource=""

  if [[ -n "${SELECTOR_ACCESS_CHECKED_FILE}" ]] && grep -Fqx -- "${namespace}" "${SELECTOR_ACCESS_CHECKED_FILE}" 2>/dev/null; then
    return 0
  fi

  for resource in deployments daemonsets statefulsets pods replicasets; do
    require_kubectl_permission "get" "${resource}" "${namespace}" "resolve stable workload selectors"
  done

  printf '%s\n' "${namespace}" >> "${SELECTOR_ACCESS_CHECKED_FILE}"
}

sanitize_filename() {
  local value="$1"
  value="$(printf '%s' "${value}" | sed -E 's/[^A-Za-z0-9._-]+/-/g; s/^[.-]+//; s/[.-]+$//; s/-+/-/g')"
  if [[ -z "${value}" ]]; then
    value="policy"
  fi
  printf '%s\n' "${value}"
}

resolve_output_context() {
  local context_value="${kube_context}"
  local kubectl_context_cmd=(kubectl)

  if [[ -z "${context_value}" ]]; then
    if [[ -n "${kubeconfig}" ]]; then
      kubectl_context_cmd+=(--kubeconfig "${kubeconfig}")
    fi
    context_value="$("${kubectl_context_cmd[@]}" config current-context 2>/dev/null || true)"
  fi

  if [[ -z "${context_value}" ]]; then
    context_value="unknown-context"
  fi

  sanitize_filename "${context_value}"
}

title_case_words() {
  printf '%s\n' "$1" | sed 's/-/ /g' | awk '
    {
      for (i = 1; i <= NF; i++) {
        $i = toupper(substr($i, 1, 1)) substr($i, 2)
      }
      print
    }
  '
}

yaml_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

selector_display_name() {
  local selector_key="$1"
  local selector_value="$2"
  local fallback="$3"

  [[ -n "${selector_value}" ]] && printf '%s\n' "${selector_value}" && return 0
  [[ -n "${selector_key}" ]] && printf '%s\n' "${selector_key}" && return 0
  printf '%s\n' "${fallback}"
}

observed_traffic_description() {
  local direction="$1"
  local namespace="$2"
  local workload_name="$3"

  printf 'Observed %s traffic from %s/%s\n' \
    "${direction}" \
    "${namespace}" \
    "${workload_name}"
}

observed_namespace_traffic_description() {
  local direction="$1"
  local namespace="$2"

  printf 'Observed namespace-aggregate %s traffic for %s\n' \
    "${direction}" \
    "${namespace}"
}

is_ip_like() {
  case "$1" in
    *:*)
      return 0
      ;;
  esac

  if [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    return 0
  fi

  return 1
}

is_ipv4_address() {
  [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

is_ipv6_address() {
  [[ "$1" == *:* ]]
}

cidr_for_ip() {
  local ip="$1"

  if is_ipv4_address "${ip}"; then
    printf '%s/32\n' "${ip}"
    return 0
  fi

  if is_ipv6_address "${ip}"; then
    printf '%s/128\n' "${ip}"
    return 0
  fi

  return 1
}

normalize_dns_name() {
  local value="$1"

  value="$(printf '%s' "${value}" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/\.$//')"

  [[ -n "${value}" ]] || return 1
  is_ip_like "${value}" && return 1
  [[ "${value}" =~ ^[a-z0-9.-]+$ ]] || return 1
  [[ "${value}" == *.* ]] || return 1

  printf '%s\n' "${value}"
}

collect_world_targets() {
  local direction="$1"
  local world_names="$2"
  local world_ip="$3"
  local value=""
  local normalized=""
  local cidr=""
  local seen=0
  local existing=""
  local -a dns_names=()

  while IFS= read -r value; do
    normalized="$(normalize_dns_name "${value}" 2>/dev/null || true)"
    [[ -n "${normalized}" ]] || continue

    seen=0
    if [[ "${#dns_names[@]}" -gt 0 ]]; then
      for existing in "${dns_names[@]}"; do
        if [[ "${existing}" == "${normalized}" ]]; then
          seen=1
          break
        fi
      done
      if [[ "${seen}" -eq 1 ]]; then
        continue
      fi
    fi

    dns_names+=("${normalized}")
  done < <(printf '%s\n' "${world_names}" | tr ',' '\n')

  if [[ "${direction}" == "egress" ]]; then
    if [[ "${#dns_names[@]}" -eq 1 ]]; then
      printf 'fqdn\t%s\n' "${dns_names[0]}"
      return 0
    fi

    if [[ "${#dns_names[@]}" -gt 1 ]]; then
      if cidr="$(cidr_for_ip "${world_ip}" 2>/dev/null)"; then
        printf 'cidr\t%s\n' "${cidr}"
        return 0
      fi

      for value in "${dns_names[@]}"; do
        printf 'fqdn\t%s\n' "${value}"
      done
      return 0
    fi
  fi

  if cidr="$(cidr_for_ip "${world_ip}" 2>/dev/null)"; then
    printf 'cidr\t%s\n' "${cidr}"
    return 0
  fi

  if [[ "${direction}" == "egress" ]]; then
    if [[ "${world_egress_mode}" == "entity" ]]; then
      printf 'world\tworld\n'
      return 0
    fi
    return 1
  fi

  printf 'world\tworld\n'
}

supported_policy_protocol() {
  case "$1" in
    tcp|udp|sctp)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_host_peer_ip() {
  local value="$1"

  [[ -n "${value}" ]] || return 1
  [[ -f "${HOST_IP_FILE}" ]] || return 1

  grep -Fqx "${value}" "${HOST_IP_FILE}"
}

cache_selector_success() {
  local cache_key="$1"
  local selector_key="$2"
  local selector_value="$3"

  RESOLVED_SELECTOR_KEY="${selector_key}"
  RESOLVED_SELECTOR_VALUE="${selector_value}"
  printf '%s\t%s\t%s\t%s\t\n' \
    "${cache_key}" \
    "ok" \
    "${selector_key}" \
    "${selector_value}" >> "${SELECTOR_CACHE_FILE}"
}

cache_selector_error() {
  local cache_key="$1"
  local error_msg="$2"

  RESOLVE_ERROR_MSG="${error_msg}"
  printf '%s\t%s\t\t\t%s\n' \
    "${cache_key}" \
    "error" \
    "${error_msg}" >> "${SELECTOR_CACHE_FILE}"
}

load_selector_cache() {
  local cache_key="$1"
  local cache_line=""

  cache_line="$(
    awk -F'\t' -v key="${cache_key}" '
      $1 == key {
        status = $2
        selector_key = $3
        selector_value = $4
        error_msg = $5
        found = 1
      }
      END {
        if (found) {
          printf "%s\t%s\t%s\t%s\n", status, selector_key, selector_value, error_msg
        }
      }
    ' "${SELECTOR_CACHE_FILE}"
  )"
  [[ -n "${cache_line}" ]] || return 1

  SELECTOR_CACHE_STATUS_VALUE="$(printf '%s\n' "${cache_line}" | cut -f1)"
  SELECTOR_CACHE_KEY_VALUE="$(printf '%s\n' "${cache_line}" | cut -f2)"
  SELECTOR_CACHE_VALUE_VALUE="$(printf '%s\n' "${cache_line}" | cut -f3)"
  SELECTOR_CACHE_ERROR_VALUE="$(printf '%s\n' "${cache_line}" | cut -f4-)"
  return 0
}

selector_key_is_unstable() {
  local label_key="$1"

  case "${label_key}" in
    pod-template-hash|rollouts-pod-template-hash|controller-revision-hash|controller-uid|statefulset.kubernetes.io/pod-name|apps.kubernetes.io/pod-index|batch.kubernetes.io/controller-uid|batch.kubernetes.io/job-name)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

selector_key_priority() {
  local label_key="$1"

  case "${label_key}" in
    app.kubernetes.io/component|component)
      printf '%s\n' 80
      ;;
    app.kubernetes.io/name|k8s-app|app)
      printf '%s\n' 70
      ;;
    rsName|app.kubernetes.io/instance)
      printf '%s\n' 60
      ;;
    app.kubernetes.io/part-of)
      printf '%s\n' 50
      ;;
    *name)
      printf '%s\n' 40
      ;;
    *)
      printf '%s\n' 10
      ;;
  esac
}

selector_candidate_score() {
  local source="$1"
  local label_key="$2"
  local label_value="$3"
  local workload="$4"
  local score=0
  local workload_lc=""
  local value_lc=""

  score="$(selector_key_priority "${label_key}")"
  if [[ "${source}" == "selector" ]]; then
    score=$((score + 15))
  fi

  workload_lc="$(printf '%s' "${workload}" | tr '[:upper:]' '[:lower:]')"
  value_lc="$(printf '%s' "${label_value}" | tr '[:upper:]' '[:lower:]')"
  if [[ -n "${workload_lc}" && -n "${value_lc}" ]]; then
    if [[ "${value_lc}" == "${workload_lc}" ]]; then
      score=$((score + 25))
    elif [[ "${value_lc}" == *"${workload_lc}"* || "${workload_lc}" == *"${value_lc}"* ]]; then
      score=$((score + 15))
    fi
  fi

  printf '%s\n' "${score}"
}

best_selector_candidate_from_json_source() {
  local json="$1"
  local source="$2"
  local workload="$3"
  local line=""
  local label_key=""
  local label_value=""
  local best_key=""
  local best_value=""
  local best_score="-1"
  local score=0

  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    IFS=$'\t' read -r label_key label_value <<< "${line}"
    [[ -n "${label_key}" && -n "${label_value}" ]] || continue
    if selector_key_is_unstable "${label_key}"; then
      continue
    fi

    score="$(selector_candidate_score "${source}" "${label_key}" "${label_value}" "${workload}")"
    if (( score > best_score )); then
      best_score="${score}"
      best_key="${label_key}"
      best_value="${label_value}"
      continue
    fi

    if (( score == best_score )) && [[ -n "${best_key}" ]]; then
      if [[ "${label_key}" < "${best_key}" || ( "${label_key}" == "${best_key}" && "${label_value}" < "${best_value}" ) ]]; then
        best_key="${label_key}"
        best_value="${label_value}"
      fi
    fi
  done < <(
    printf '%s\n' "${json}" | jq -r --arg source "${source}" '
      if $source == "selector" then
        .spec.selector.matchLabels // {}
      else
        .metadata.labels // {}
      end
      | to_entries[]
      | [.key, (.value | tostring)]
      | @tsv
    '
  )

  if [[ -n "${best_key}" && -n "${best_value}" ]]; then
    RESOLVED_SELECTOR_KEY="${best_key}"
    RESOLVED_SELECTOR_VALUE="${best_value}"
    return 0
  fi

  return 1
}

extract_selector_from_json() {
  local json="$1"
  local workload="${2:-}"

  if best_selector_candidate_from_json_source "${json}" "selector" "${workload}"; then
    return 0
  fi

  if best_selector_candidate_from_json_source "${json}" "metadata" "${workload}"; then
    return 0
  fi

  return 1
}

looks_like_pod_name() {
  local workload="$1"

  [[ "${workload}" == *-* ]] || return 1
  [[ "${workload}" =~ -[0-9]+$ ]] && return 0
  [[ "${workload}" =~ -[a-z0-9]{5}$ ]] && return 0
  [[ "${workload}" =~ -[a-z0-9]{5,10}-[a-z0-9]{5}$ ]] && return 0
  return 1
}

controller_name_candidates_from_pod_name() {
  local workload="$1"
  local candidate=""

  if [[ "${workload}" =~ ^(.+)-[0-9]+$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  fi

  if [[ "${workload}" =~ ^(.+)-[a-z0-9]{5,10}-[a-z0-9]{5}$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  fi

  if [[ "${workload}" =~ ^(.+)-[a-z0-9]{5}$ ]]; then
    candidate="${BASH_REMATCH[1]}"
    if [[ "${candidate}" != "${workload}" ]]; then
      printf '%s\n' "${candidate}"
    fi
  fi | awk '!seen[$0]++'
}

lookup_controller_json() {
  local namespace="$1"
  local workload="$2"
  local kind=""
  local json=""

  for kind in deployment daemonset statefulset replicaset; do
    if json="$("${KUBECTL_BASE[@]}" -n "${namespace}" get "${kind}" "${workload}" -o json 2>/dev/null)"; then
      LOOKUP_CONTROLLER_JSON="${json}"
      LOOKUP_CONTROLLER_KIND="${kind}"
      return 0
    fi
  done

  LOOKUP_CONTROLLER_JSON=""
  LOOKUP_CONTROLLER_KIND=""
  return 1
}

lookup_owner_controller_json() {
  local namespace="$1"
  local json="$2"
  local owner_kind=""
  local owner_name=""
  local owner_json=""

  owner_kind="$(printf '%s\n' "${json}" | jq -r '.metadata.ownerReferences[0].kind // empty' | tr '[:upper:]' '[:lower:]')"
  owner_name="$(printf '%s\n' "${json}" | jq -r '.metadata.ownerReferences[0].name // empty')"

  case "${owner_kind}" in
    deployment|daemonset|statefulset|replicaset)
      ;;
    *)
      LOOKUP_OWNER_CONTROLLER_JSON=""
      LOOKUP_OWNER_CONTROLLER_KIND=""
      return 1
      ;;
  esac

  if [[ -z "${owner_name}" ]]; then
    LOOKUP_OWNER_CONTROLLER_JSON=""
    LOOKUP_OWNER_CONTROLLER_KIND=""
    return 1
  fi

  if owner_json="$("${KUBECTL_BASE[@]}" -n "${namespace}" get "${owner_kind}" "${owner_name}" -o json 2>/dev/null)"; then
    LOOKUP_OWNER_CONTROLLER_JSON="${owner_json}"
    LOOKUP_OWNER_CONTROLLER_KIND="${owner_kind}"
    return 0
  fi

  LOOKUP_OWNER_CONTROLLER_JSON=""
  LOOKUP_OWNER_CONTROLLER_KIND=""
  return 1
}

resolve_selector() {
  local namespace="$1"
  local workload="$2"
  local cache_key="${namespace}/${workload}"
  local json=""
  local label_value=""
  local label_key=""
  local kind=""
  local pod_json=""
  local owner_kind=""
  local owner_name=""
  local rs_json=""
  local candidate=""

  if load_selector_cache "${cache_key}"; then
    if [[ "${SELECTOR_CACHE_STATUS_VALUE}" == "ok" ]]; then
      RESOLVED_SELECTOR_KEY="${SELECTOR_CACHE_KEY_VALUE}"
      RESOLVED_SELECTOR_VALUE="${SELECTOR_CACHE_VALUE_VALUE}"
      return 0
    fi

    RESOLVE_ERROR_MSG="${SELECTOR_CACHE_ERROR_VALUE}"
    return 1
  fi

  ensure_selector_resolution_access "${namespace}"

  if looks_like_pod_name "${workload}" && pod_json="$("${KUBECTL_BASE[@]}" -n "${namespace}" get pod "${workload}" -o json 2>/dev/null)"; then
    if extract_selector_from_json "${pod_json}" "${workload}"; then
      cache_selector_success "${cache_key}" "${RESOLVED_SELECTOR_KEY}" "${RESOLVED_SELECTOR_VALUE}"
      return 0
    fi

    owner_kind="$(printf '%s\n' "${pod_json}" | jq -r '.metadata.ownerReferences[0].kind // empty' | tr '[:upper:]' '[:lower:]')"
    owner_name="$(printf '%s\n' "${pod_json}" | jq -r '.metadata.ownerReferences[0].name // empty')"

    if [[ "${owner_kind}" == "replicaset" && -n "${owner_name}" ]]; then
      rs_json="$("${KUBECTL_BASE[@]}" -n "${namespace}" get replicaset "${owner_name}" -o json 2>/dev/null || true)"
      if [[ -n "${rs_json}" ]]; then
        if extract_selector_from_json "${rs_json}" "${workload}"; then
          cache_selector_success "${cache_key}" "${RESOLVED_SELECTOR_KEY}" "${RESOLVED_SELECTOR_VALUE}"
          return 0
        fi
        owner_kind="$(printf '%s\n' "${rs_json}" | jq -r '.metadata.ownerReferences[0].kind // empty' | tr '[:upper:]' '[:lower:]')"
        owner_name="$(printf '%s\n' "${rs_json}" | jq -r '.metadata.ownerReferences[0].name // empty')"
      fi
    fi

    case "${owner_kind}" in
      deployment|daemonset|statefulset)
        json="$("${KUBECTL_BASE[@]}" -n "${namespace}" get "${owner_kind}" "${owner_name}" -o json 2>/dev/null || true)"
        ;;
    esac
  elif looks_like_pod_name "${workload}"; then
    while IFS= read -r candidate; do
      [[ -n "${candidate}" ]] || continue
      if lookup_controller_json "${namespace}" "${candidate}"; then
        json="${LOOKUP_CONTROLLER_JSON}"
        break
      fi
    done < <(controller_name_candidates_from_pod_name "${workload}")
  fi

  if [[ -z "${json}" ]]; then
    if lookup_controller_json "${namespace}" "${workload}"; then
      json="${LOOKUP_CONTROLLER_JSON}"
    fi
  fi

  if [[ -z "${json}" ]]; then
    cache_selector_error "${cache_key}" "could not resolve workload ${namespace}/${workload} via deployment, daemonset, statefulset, or pod owner"
    return 1
  fi

  if extract_selector_from_json "${json}" "${workload}"; then
    cache_selector_success "${cache_key}" "${RESOLVED_SELECTOR_KEY}" "${RESOLVED_SELECTOR_VALUE}"
    return 0
  fi

  if lookup_owner_controller_json "${namespace}" "${json}" && extract_selector_from_json "${LOOKUP_OWNER_CONTROLLER_JSON}" "${workload}"; then
    cache_selector_success "${cache_key}" "${RESOLVED_SELECTOR_KEY}" "${RESOLVED_SELECTOR_VALUE}"
    return 0
  fi

  cache_selector_error "${cache_key}" "could not find a stable selector label for ${namespace}/${workload}; checked controller selectors and metadata labels while ignoring unstable rollout-only labels"
  return 1
}

count_data_rows() {
  local file="$1"

  awk 'NR > 1 { count++ } END { print count + 0 }' "${file}"
}

count_lines() {
  local file="$1"

  awk 'END { print NR + 0 }' "${file}"
}

append_report_row() {
  local namespace="$1"
  local direction="$2"
  local raw_row_count="$3"
  local usable_row_count="$4"
  local mode="$5"
  local policy_file="$6"
  local aggregate_file="$7"
  local capture_strategy_requested="$8"
  local capture_strategy_used="$9"
  local capture_sample_target="${10}"
  local filtered_flow_count="${11}"
  local capture_fallback_used="${12}"
  local capture_seconds="${13}"
  local summary_seconds="${14}"
  local generation_seconds="${15}"

  printf '%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s\n' \
    "${namespace}" \
    "${REPORT_ROW_DELIM}" \
    "${direction}" \
    "${REPORT_ROW_DELIM}" \
    "${raw_row_count}" \
    "${REPORT_ROW_DELIM}" \
    "${usable_row_count}" \
    "${REPORT_ROW_DELIM}" \
    "${mode}" \
    "${REPORT_ROW_DELIM}" \
    "${policy_file}" \
    "${REPORT_ROW_DELIM}" \
    "${aggregate_file}" \
    "${REPORT_ROW_DELIM}" \
    "${capture_strategy_requested}" \
    "${REPORT_ROW_DELIM}" \
    "${capture_strategy_used}" \
    "${REPORT_ROW_DELIM}" \
    "${capture_sample_target}" \
    "${REPORT_ROW_DELIM}" \
    "${filtered_flow_count}" \
    "${REPORT_ROW_DELIM}" \
    "${capture_fallback_used}" \
    "${REPORT_ROW_DELIM}" \
    "${capture_seconds}" \
    "${REPORT_ROW_DELIM}" \
    "${summary_seconds}" \
    "${REPORT_ROW_DELIM}" \
    "${generation_seconds}" >> "${REPORT_ROWS_FILE}"
}

record_promotion_error() {
  local message="$1"

  [[ -n "${message}" ]] || return 0
  warn "${message}"
  printf '%s\n' "${message}" >> "${PROMOTION_ERRORS_FILE}"
  FINAL_EXIT_STATUS=1
}

namespace_is_explicitly_requested() {
  local namespace="$1"
  local value=""

  if [[ "${#namespaces[@]}" -gt 0 ]]; then
    for value in "${namespaces[@]}"; do
      if [[ "${value}" == "${namespace}" ]]; then
        return 0
      fi
    done
  fi

  return 1
}

namespace_is_user_excluded() {
  local namespace="$1"
  local value=""

  if [[ "${#excluded_namespaces[@]}" -gt 0 ]]; then
    for value in "${excluded_namespaces[@]}"; do
      if [[ "${value}" == "${namespace}" ]]; then
        return 0
      fi
    done
  fi

  return 1
}

namespace_is_default_excluded() {
  local namespace="$1"
  local value=""

  if [[ "${#DEFAULT_EXCLUDED_NAMESPACES[@]}" -gt 0 ]]; then
    for value in "${DEFAULT_EXCLUDED_NAMESPACES[@]}"; do
      if [[ "${value}" == "${namespace}" ]]; then
        if namespace_is_explicitly_requested "${namespace}"; then
          return 1
        fi
        return 0
      fi
    done
  fi

  return 1
}

peer_namespace_should_be_excluded() {
  local namespace="$1"

  [[ -n "${namespace}" ]] || return 1
  namespace_is_user_excluded "${namespace}" && return 0
  namespace_is_default_excluded "${namespace}" && return 0
  return 1
}

join_csv() {
  local value=""
  local joined=""

  for value in "$@"; do
    [[ -n "${value}" ]] || continue
    if [[ -n "${joined}" ]]; then
      joined+=","
    fi
    joined+="${value}"
  done

  printf '%s\n' "${joined}"
}

discover_namespaces() {
  local discovered_file="$1"
  local namespace=""
  local excluded=0
  local candidate_file

  candidate_file="$(mktemp "${TMPDIR:-/tmp}/hubble-audit-namespaces.XXXXXX")"

  if [[ "${#namespaces[@]}" -gt 0 ]]; then
    for namespace in "${namespaces[@]}"; do
      [[ -n "${namespace}" ]] || continue

      excluded=0
      namespace_is_user_excluded "${namespace}" && excluded=1
      if [[ "${excluded}" -eq 1 ]]; then
        continue
      fi

      printf '%s\n' "${namespace}" >> "${candidate_file}"
    done

    awk '!seen[$0]++' "${candidate_file}" > "${discovered_file}"
    rm -f "${candidate_file}"
    return 0
  fi

  require_kubectl_permission "list" "namespaces" "" "discover namespaces when --namespace is not provided"

  "${KUBECTL_BASE[@]}" get namespaces -o json \
    | jq -r '.items[].metadata.name' \
    | sort -u > "${candidate_file}"

  while IFS= read -r namespace; do
    [[ -n "${namespace}" ]] || continue

    excluded=0
    if namespace_is_user_excluded "${namespace}" || namespace_is_default_excluded "${namespace}"; then
      excluded=1
    fi
    if [[ "${excluded}" -eq 1 ]]; then
      continue
    fi

    printf '%s\n' "${namespace}" >> "${discovered_file}"
  done < "${candidate_file}"

  rm -f "${candidate_file}"
}

filter_edge_summary_excluded_peers() {
  local direction="$1"
  local input_file="$2"
  local output_file="$3"
  local explicit_csv=""
  local user_excluded_csv=""
  local default_excluded_csv=""

  if [[ "${#namespaces[@]}" -gt 0 ]]; then
    explicit_csv="$(join_csv "${namespaces[@]}")"
  fi
  if [[ "${#excluded_namespaces[@]}" -gt 0 ]]; then
    user_excluded_csv="$(join_csv "${excluded_namespaces[@]}")"
  fi
  if [[ "${#DEFAULT_EXCLUDED_NAMESPACES[@]}" -gt 0 ]]; then
    default_excluded_csv="$(join_csv "${DEFAULT_EXCLUDED_NAMESPACES[@]}")"
  fi

  awk -F'\t' \
    -v OFS='\t' \
    -v direction="${direction}" \
    -v explicit_csv="${explicit_csv}" \
    -v user_excluded_csv="${user_excluded_csv}" \
    -v default_excluded_csv="${default_excluded_csv}" '
      function in_csv(value, csv, n, items, i) {
        if (value == "" || csv == "") {
          return 0
        }
        n = split(csv, items, ",")
        for (i = 1; i <= n; i++) {
          if (items[i] == value) {
            return 1
          }
        }
        return 0
      }

      NR == 1 {
        print
        next
      }

      {
        peer_ns = (direction == "ingress" ? $5 : $8)
        if (peer_ns != "" && (in_csv(peer_ns, user_excluded_csv) || (in_csv(peer_ns, default_excluded_csv) && !in_csv(peer_ns, explicit_csv)))) {
          next
        }
        print
      }
    ' "${input_file}" > "${output_file}"
}

filter_capture_non_reply() {
  local input_file="$1"
  local output_file="$2"

  jq -c 'select((((.flow // .).is_reply) // false) != true)' "${input_file}" > "${output_file}"
}

discover_host_peer_ips() {
  local status=0

  : > "${HOST_IP_FILE}"

  if kubectl_can_i "get" "ciliumnodes.cilium.io"; then
    "${KUBECTL_BASE[@]}" get ciliumnodes -o json 2>/dev/null \
      | jq -r '
          .items[]
          | (.spec.addresses // [])
          | .[]
          | select(.type == "CiliumInternalIP" or .type == "InternalIP")
          | .ip // empty
        ' >> "${HOST_IP_FILE}" || true
  else
    status=$?
    if [[ "${status}" -eq 2 ]]; then
      warn "${CAN_I_ERROR_MSG}; host peer detection from CiliumNode IPs is disabled"
    else
      warn "cannot read ciliumnodes.cilium.io; host peer detection from CiliumNode IPs is disabled"
    fi
  fi

  if kubectl_can_i "get" "nodes"; then
    "${KUBECTL_BASE[@]}" get nodes -o json 2>/dev/null \
      | jq -r '
          .items[]
          | (.status.addresses // [])
          | .[]
          | select(.type == "InternalIP")
          | .address // empty
        ' >> "${HOST_IP_FILE}" || true
  else
    status=$?
    if [[ "${status}" -eq 2 ]]; then
      warn "${CAN_I_ERROR_MSG}; host peer detection from node InternalIPs is disabled"
    else
      warn "cannot read nodes; host peer detection from node InternalIPs is disabled"
    fi
  fi

  if [[ -s "${HOST_IP_FILE}" ]]; then
    sort -u "${HOST_IP_FILE}" -o "${HOST_IP_FILE}"
  fi
}

tsv_rows() {
  local input_file="$1"

  tr '\t' '\037' < "${input_file}"
}

adaptive_last_steps() {
  local target="$1"

  if [[ "${target}" -le 100 ]]; then
    printf '%s\n' "${target}"
  elif [[ "${target}" -le 300 ]]; then
    printf '100\n%s\n' "${target}"
  else
    printf '100\n300\n%s\n' "${target}"
  fi | awk '!seen[$0]++'
}

ensure_hubble_port_forward_access() {
  require_kubectl_permission "get" "services" "kube-system" "look up the Hubble relay Service for a shared port-forward"
  require_kubectl_permission "get" "pods" "kube-system" "locate the Hubble relay pod for a shared port-forward"
  require_kubectl_permission "create" "pods/portforward" "kube-system" "open a shared Hubble relay port-forward"
}

discover_hubble_relay_service_port() {
  local service_json=""
  local service_port=""

  if ! service_json="$("${KUBECTL_BASE[@]}" -n kube-system get service hubble-relay -o json 2>/dev/null)"; then
    fail "failed to read Service kube-system/hubble-relay while preparing the shared Hubble relay port-forward"
  fi

  service_port="$(printf '%s\n' "${service_json}" | jq -r '
    (
      [.spec.ports[]? | select((.protocol // "TCP") == "TCP" and (.name // "") == "grpc") | .port][0]
      // [.spec.ports[]? | select((.protocol // "TCP") == "TCP" and (.name // "") == "hubble-relay") | .port][0]
      // [.spec.ports[]? | select((.protocol // "TCP") == "TCP" and (.name // "") == "relay") | .port][0]
      // [.spec.ports[]? | select((.protocol // "TCP") == "TCP") | .port][0]
      // empty
    )
  ')"

  [[ "${service_port}" =~ ^[0-9]+$ ]] || fail "could not determine a TCP Service port for kube-system/hubble-relay"
  SHARED_HUBBLE_SERVICE_PORT="${service_port}"
}

stop_shared_hubble_relay() {
  if [[ -n "${SHARED_HUBBLE_RELAY_PID:-}" ]]; then
    kill "${SHARED_HUBBLE_RELAY_PID}" 2>/dev/null || true
    wait "${SHARED_HUBBLE_RELAY_PID}" 2>/dev/null || true
    SHARED_HUBBLE_RELAY_PID=""
  fi
}

start_shared_hubble_relay() {
  local port_spec=""
  local local_port=""
  local deadline=0

  [[ "${dry_run}" -eq 0 ]] || return 0
  [[ -z "${SHARED_HUBBLE_SERVER:-}" ]] || return 0

  ensure_hubble_port_forward_access
  discover_hubble_relay_service_port

  SHARED_HUBBLE_RELAY_LOG="$(mktemp "${TMPDIR:-/tmp}/hubble-observe-port-forward.XXXXXX")"
  if [[ "${port_forward_port}" == "0" ]]; then
    port_spec=":${SHARED_HUBBLE_SERVICE_PORT}"
  else
    port_spec="${port_forward_port}:${SHARED_HUBBLE_SERVICE_PORT}"
  fi

  (
    "${KUBECTL_BASE[@]}" -n kube-system port-forward --address 127.0.0.1 service/hubble-relay "${port_spec}"
  ) > "${SHARED_HUBBLE_RELAY_LOG}" 2>&1 &
  SHARED_HUBBLE_RELAY_PID=$!

  deadline=$((SECONDS + 15))
  while [[ "${SECONDS}" -lt "${deadline}" ]]; do
    if [[ -s "${SHARED_HUBBLE_RELAY_LOG}" ]]; then
      local_port="$(sed -nE 's/.*127\.0\.0\.1:([0-9]+).*/\1/p' "${SHARED_HUBBLE_RELAY_LOG}" | tail -n 1)"
      if [[ -z "${local_port}" ]]; then
        local_port="$(sed -nE 's/.*\[::1\]:([0-9]+).*/\1/p' "${SHARED_HUBBLE_RELAY_LOG}" | tail -n 1)"
      fi
      if [[ -n "${local_port}" ]]; then
        SHARED_HUBBLE_SERVER="127.0.0.1:${local_port}"
        info "shared Hubble relay ready on ${SHARED_HUBBLE_SERVER}"
        return 0
      fi
    fi

    if ! kill -0 "${SHARED_HUBBLE_RELAY_PID}" 2>/dev/null; then
      [[ -s "${SHARED_HUBBLE_RELAY_LOG}" ]] && cat "${SHARED_HUBBLE_RELAY_LOG}" >&2
      fail "shared Hubble relay port-forward exited before becoming ready"
    fi

    sleep 1
  done

  [[ -s "${SHARED_HUBBLE_RELAY_LOG}" ]] && cat "${SHARED_HUBBLE_RELAY_LOG}" >&2
  fail "timed out waiting for shared Hubble relay port-forward to become ready"
}

build_capture_command() {
  local namespace="$1"
  local mode="$2"
  local since_override="$3"
  local sample_target_override="$4"

  CAPTURE_CMD=("${CAPTURE_SCRIPT}" --execute)
  CAPTURE_CMD+=(--namespace "${namespace}")
  CAPTURE_CMD+=(--field-mask-profile policy-observe)

  case "${mode}" in
    since)
      CAPTURE_CMD+=(--capture-strategy since)
      CAPTURE_CMD+=(--since "${since_override}")
      ;;
    last)
      CAPTURE_CMD+=(--capture-strategy last)
      CAPTURE_CMD+=(--sample-target "${sample_target_override}")
      ;;
    *)
      fail "unsupported observe capture mode: ${mode}"
      ;;
  esac

  if [[ "${capture_mode}" == "policy-verdict" ]]; then
    CAPTURE_CMD+=(--type policy-verdict)
  else
    CAPTURE_CMD+=(--verdict FORWARDED)
  fi

  if [[ -n "${SHARED_HUBBLE_SERVER:-}" ]]; then
    CAPTURE_CMD+=(--server "${SHARED_HUBBLE_SERVER}")
  else
    CAPTURE_CMD+=(--port-forward-port "${port_forward_port}")
    if [[ -n "${kubeconfig}" ]]; then
      CAPTURE_CMD+=(--kubeconfig "${kubeconfig}")
    fi
    if [[ -n "${kube_context}" ]]; then
      CAPTURE_CMD+=(--kube-context "${kube_context}")
    fi
  fi

  if [[ "${print_command}" -eq 1 ]]; then
    CAPTURE_CMD+=(--print-command)
  fi
}

run_capture_command() {
  local label="$1"
  local output_file="$2"
  shift 2
  local capture_err=""

  if [[ "${dry_run}" -eq 1 ]]; then
    printf '%s\n' "${label}: $*"
    return 0
  fi

  capture_err="$(mktemp "${TMPDIR:-/tmp}/hubble-observe-capture.XXXXXX")"

  if ! run_command_with_progress "${label}" "${output_file}" "${capture_err}" "$@"; then
    if [[ -s "${capture_err}" ]]; then
      cat "${capture_err}" >&2
    fi
    rm -f "${capture_err}"
    return 1
  fi

  if [[ -s "${capture_err}" ]]; then
    emit_capture_stderr "${capture_err}"
  fi

  rm -f "${capture_err}"
}

capture_namespace_since_iterations() {
  local namespace="$1"
  local combined_raw="$2"
  local iteration_index=1
  local iteration_capture=""

  if [[ "${dry_run}" -eq 0 ]]; then
    : > "${combined_raw}"
  fi
  while [[ "${iteration_index}" -le "${iterations}" ]]; do
    iteration_capture="${namespace_dir}/capture-${iteration_index}.jsonl"
    build_capture_command "${namespace}" "since" "${since_value}" ""
    info "${namespace}: capture iteration ${iteration_index}/${iterations} (since=${since_value}, mode=${capture_mode})"
    run_capture_command \
      "capture ${namespace} iteration ${iteration_index}/${iterations}" \
      "${iteration_capture}" \
      "${CAPTURE_CMD[@]}"

    [[ "${dry_run}" -eq 1 ]] || cat "${iteration_capture}" >> "${combined_raw}"

    if [[ "${sleep_between}" -gt 0 && "${iteration_index}" -lt "${iterations}" ]]; then
      sleep "${sleep_between}"
    fi
    iteration_index=$((iteration_index + 1))
  done
}

capture_namespace_last_sample() {
  local namespace="$1"
  local combined_raw="$2"
  local sample_size="$3"
  local sample_capture="${namespace_dir}/capture-last-${sample_size}.jsonl"

  build_capture_command "${namespace}" "last" "" "${sample_size}"
  info "${namespace}: capture recent sample (last=${sample_size}, mode=${capture_mode})"
  run_capture_command "capture ${namespace} last ${sample_size}" "${sample_capture}" "${CAPTURE_CMD[@]}"
  [[ "${dry_run}" -eq 1 ]] || cat "${sample_capture}" > "${combined_raw}"
}

capture_namespace_adaptive() {
  local namespace="$1"
  local combined_raw="$2"
  local sample_size=""
  local usable_file=""
  local usable_count=0
  local sample_capture=""

  CAPTURE_STRATEGY_USED="last"
  CAPTURE_FALLBACK_USED="0"

  while IFS= read -r sample_size; do
    [[ -n "${sample_size}" ]] || continue
    sample_capture="${namespace_dir}/capture-last-${sample_size}.jsonl"
    capture_namespace_last_sample "${namespace}" "${combined_raw}" "${sample_size}"

    if [[ "${dry_run}" -eq 1 ]]; then
      continue
    fi

    usable_file="$(mktemp "${TMPDIR:-/tmp}/hubble-observe-sample.XXXXXX")"
    filter_capture_non_reply "${sample_capture}" "${usable_file}"
    usable_count="$(count_lines "${usable_file}")"
    rm -f "${usable_file}"

    info "${namespace}: adaptive sample last=${sample_size} yielded ${usable_count} non-reply flows"
    if [[ "${usable_count}" -ge "${sample_min}" ]]; then
      return 0
    fi
  done < <(adaptive_last_steps "${sample_target}")

  CAPTURE_STRATEGY_USED="since"
  CAPTURE_FALLBACK_USED="1"
  info "${namespace}: adaptive sampling was too sparse; falling back to since ${since_value} across ${iterations} iteration(s)"
  capture_namespace_since_iterations "${namespace}" "${combined_raw}"
}

summarise_report() {
  local namespace="$1"
  local input_file="$2"
  local report="$3"
  local output_file="$4"
  local summary_cmd=("${SUMMARIZE_SCRIPT}" --execute)
  local summary_err=""

  summary_cmd+=(--input "${input_file}")
  summary_cmd+=(--report "${report}")
  summary_cmd+=(--aggregate-by workload)
  summary_cmd+=(--direction all)
  summary_cmd+=(--format tsv)
  summary_cmd+=(--top 0)
  summary_cmd+=(--verdict FORWARDED)

  summary_err="$(mktemp "${TMPDIR:-/tmp}/hubble-observe-summary.XXXXXX")"

  if ! run_command_with_progress \
    "summarise ${namespace} ${report}" \
    "${output_file}" \
    "${summary_err}" \
    "${summary_cmd[@]}"; then
    if [[ -s "${summary_err}" ]]; then
      cat "${summary_err}" >&2
    fi
    rm -f "${summary_err}"
    return 1
  fi

  if [[ -s "${summary_err}" ]]; then
    emit_summary_stderr "${summary_err}"
  fi

  rm -f "${summary_err}"
}

split_summary_by_direction() {
  local input_file="$1"
  local ingress_output="$2"
  local egress_output="$3"

  awk -F'\t' -v ingress="${ingress_output}" -v egress="${egress_output}" '
    NR == 1 {
      print > ingress
      print > egress
      next
    }
    toupper($2) == "INGRESS" { print > ingress }
    toupper($2) == "EGRESS" { print > egress }
  ' "${input_file}"
}

emit_capture_stderr() {
  local err_file="$1"
  local line=""

  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ -n "${line}" ]] || continue
    if [[ "${line}" == *"Hubble CLI version is lower than Hubble Relay"* ]]; then
      continue
    fi
    printf '%s\n' "${line}" >&2
  done < "${err_file}"
}

emit_summary_stderr() {
  local err_file="$1"
  local line=""

  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ -n "${line}" ]] || continue
    if [[ "${line}" == "hubble-summarise-flows.sh: no matching flows" ]]; then
      continue
    fi
    printf '%s\n' "${line}" >&2
  done < "${err_file}"
}

write_namespace_metadata() {
  local meta_file="$1"
  local capture_strategy_requested="$2"
  local capture_strategy_used="$3"
  local capture_sample_target="$4"
  local filtered_flow_count="$5"
  local capture_fallback_used="$6"
  local capture_seconds="$7"
  local summary_seconds="$8"

  {
    printf 'CAPTURE_STRATEGY_REQUESTED=%q\n' "${capture_strategy_requested}"
    printf 'CAPTURE_STRATEGY_USED=%q\n' "${capture_strategy_used}"
    printf 'CAPTURE_SAMPLE_TARGET=%q\n' "${capture_sample_target}"
    printf 'FILTERED_FLOW_COUNT=%q\n' "${filtered_flow_count}"
    printf 'CAPTURE_FALLBACK_USED=%q\n' "${capture_fallback_used}"
    printf 'CAPTURE_SECONDS=%q\n' "${capture_seconds}"
    printf 'SUMMARY_SECONDS=%q\n' "${summary_seconds}"
  } > "${meta_file}"
}

collect_namespace_data() {
  local namespace="$1"
  local namespace_index="$2"
  local namespace_dir="${output_dir}/namespaces/${namespace}"
  local combined_raw="${namespace_dir}/combined.jsonl"
  local filtered_raw="${namespace_dir}/combined.non-reply.jsonl"
  local metadata_file="${namespace_dir}/observe-metadata.env"
  local edges_all="${namespace_dir}/edges.all.tsv"
  local world_all="${namespace_dir}/world.all.tsv"
  local capture_started=0
  local capture_seconds=0
  local summary_started=0
  local summary_seconds=0
  local filtered_flow_count=0
  local capture_sample_target="0"

  NAMESPACE_DIR="${namespace_dir}"
  info "observing namespace ${namespace} (${namespace_index}/${TOTAL_NAMESPACES})"

  if [[ "${dry_run}" -eq 0 ]]; then
    mkdir -p "${namespace_dir}"
  fi

  CAPTURE_STRATEGY_USED="${capture_strategy}"
  CAPTURE_FALLBACK_USED="0"
  if [[ "${capture_strategy}" == "last" || "${capture_strategy}" == "adaptive" ]]; then
    capture_sample_target="${sample_target}"
  fi

  capture_started=$SECONDS
  case "${capture_strategy}" in
    since)
      CAPTURE_STRATEGY_USED="since"
      capture_namespace_since_iterations "${namespace}" "${combined_raw}"
      ;;
    last)
      CAPTURE_STRATEGY_USED="last"
      capture_namespace_last_sample "${namespace}" "${combined_raw}" "${sample_target}"
      ;;
    adaptive)
      capture_namespace_adaptive "${namespace}" "${combined_raw}"
      ;;
  esac
  capture_seconds=$((SECONDS - capture_started))

  if [[ "${dry_run}" -eq 1 ]]; then
    return 0
  fi

  info "${namespace}: filtering reply traffic and building summaries"
  filter_capture_non_reply "${combined_raw}" "${filtered_raw}"
  filtered_flow_count="$(count_lines "${filtered_raw}")"

  summary_started=$SECONDS
  summarise_report "${namespace}" "${filtered_raw}" "edges" "${edges_all}"
  summarise_report "${namespace}" "${filtered_raw}" "world" "${world_all}"
  split_summary_by_direction "${edges_all}" "${namespace_dir}/ingress.edges.workload.tsv" "${namespace_dir}/egress.edges.workload.tsv"
  split_summary_by_direction "${world_all}" "${namespace_dir}/ingress.world.tsv" "${namespace_dir}/egress.world.tsv"
  filter_edge_summary_excluded_peers "ingress" "${namespace_dir}/ingress.edges.workload.tsv" "${namespace_dir}/ingress.edges.workload.tsv.filtered"
  mv "${namespace_dir}/ingress.edges.workload.tsv.filtered" "${namespace_dir}/ingress.edges.workload.tsv"
  filter_edge_summary_excluded_peers "egress" "${namespace_dir}/egress.edges.workload.tsv" "${namespace_dir}/egress.edges.workload.tsv.filtered"
  mv "${namespace_dir}/egress.edges.workload.tsv.filtered" "${namespace_dir}/egress.edges.workload.tsv"
  summary_seconds=$((SECONDS - summary_started))

  write_namespace_metadata \
    "${metadata_file}" \
    "${capture_strategy}" \
    "${CAPTURE_STRATEGY_USED}" \
    "${capture_sample_target}" \
    "${filtered_flow_count}" \
    "${CAPTURE_FALLBACK_USED}" \
    "${capture_seconds}" \
    "${summary_seconds}"
}

wait_for_pid_batch() {
  local pid=""

  for pid in "$@"; do
    wait "${pid}" || return 1
  done
}

build_namespace_aggregate_report() {
  local namespace="$1"
  local direction="$2"
  local edges_file="$3"
  local world_file="$4"
  local output_file="$5"
  local tmp_rows
  local target_kind=""
  local target_value=""

  tmp_rows="$(mktemp "${TMPDIR:-/tmp}/hubble-audit-aggregate.XXXXXX")"

  while IFS=$'\037' read -r count row_direction verdict protocol src_ns src dst_class dst_ns dst dst_port; do
    if [[ "${count}" == "count" && "${row_direction}" == "direction" ]]; then
      continue
    fi

    [[ "${verdict}" == "FORWARDED" ]] || continue
    supported_policy_protocol "${protocol}" || continue

    if [[ "${direction}" == "ingress" ]]; then
      [[ "${dst_ns}" == "${namespace}" ]] || continue
      [[ "${dst_class}" == "workload" ]] || continue
      if [[ -n "${src_ns}" ]]; then
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "${count}" "${direction}" "${protocol}" "namespace" "${src_ns}" "${dst_port}" >> "${tmp_rows}"
      elif is_host_peer_ip "${src}"; then
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "${count}" "${direction}" "${protocol}" "host" "host" "${dst_port}" >> "${tmp_rows}"
      fi
    else
      [[ "${src_ns}" == "${namespace}" ]] || continue
      [[ "${dst_class}" == "workload" ]] || continue
      if [[ -n "${dst_ns}" ]]; then
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "${count}" "${direction}" "${protocol}" "namespace" "${dst_ns}" "${dst_port}" >> "${tmp_rows}"
      elif is_host_peer_ip "${dst}"; then
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "${count}" "${direction}" "${protocol}" "host" "host" "${dst_port}" >> "${tmp_rows}"
      fi
    fi
  done < <(tsv_rows "${edges_file}")

  while IFS=$'\037' read -r count row_direction verdict protocol world_side peer_ns peer world_names world_ip port; do
    if [[ "${count}" == "count" && "${row_direction}" == "direction" ]]; then
      continue
    fi
    : "${world_names}" "${world_ip}"

    [[ "${verdict}" == "FORWARDED" ]] || continue
    supported_policy_protocol "${protocol}" || continue

    if [[ "${direction}" == "ingress" ]]; then
      [[ "${world_side}" == "source" && "${peer_ns}" == "${namespace}" ]] || continue
      while IFS=$'\t' read -r target_kind target_value; do
        [[ -n "${target_kind}" && -n "${target_value}" ]] || continue
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "${count}" "${direction}" "${protocol}" "${target_kind}" "${target_value}" "${port}" >> "${tmp_rows}"
      done < <({ collect_world_targets "ingress" "${world_names}" "${world_ip}" || true; })
    else
      [[ "${world_side}" == "destination" && "${peer_ns}" == "${namespace}" ]] || continue
      while IFS=$'\t' read -r target_kind target_value; do
        [[ -n "${target_kind}" && -n "${target_value}" ]] || continue
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "${count}" "${direction}" "${protocol}" "${target_kind}" "${target_value}" "${port}" >> "${tmp_rows}"
      done < <({ collect_world_targets "egress" "${world_names}" "${world_ip}" || true; })
    fi
  done < <(tsv_rows "${world_file}")

  {
    printf 'count\tdirection\tprotocol\tpeer_class\tpeer\tport\n'
    if [[ -s "${tmp_rows}" ]]; then
      awk -F'\t' '
        {
          key = $2 FS $3 FS $4 FS $5 FS $6
          counts[key] += $1
        }
        END {
          for (key in counts) {
            split(key, parts, FS)
            printf "%s\t%s\t%s\t%s\t%s\t%s\n", counts[key], parts[1], parts[2], parts[3], parts[4], parts[5]
          }
        }
      ' "${tmp_rows}" | LC_ALL=C sort -t $'\t' -k1,1nr -k2,2 -k3,3 -k4,4 -k5,5
    fi
  } > "${output_file}"

  rm -f "${tmp_rows}"
}

emit_selector_block() {
  local namespace="$1"
  local selector_key="$2"
  local selector_value="$3"

  printf '      matchLabels:\n'
  printf '        "k8s:io.kubernetes.pod.namespace": "%s"\n' "$(yaml_escape "${namespace}")"
  if [[ -n "${selector_key}" && -n "${selector_value}" ]]; then
    printf '        "k8s:%s": "%s"\n' "$(yaml_escape "${selector_key}")" "$(yaml_escape "${selector_value}")"
  fi
}

write_namespace_policy_header() {
  local policy_file="$1"
  local policy_name="$2"
  local namespace="$3"
  local title="$4"
  local direction="$5"
  local mode="$6"
  local row_count="$7"

  {
    printf 'apiVersion: cilium.io/v2\n'
    printf 'kind: CiliumNetworkPolicy\n'
    printf 'metadata:\n'
    printf '  name: %s\n' "${policy_name}"
    printf '  namespace: %s\n' "${namespace}"
    printf '  annotations:\n'
    printf '    "policies.cilium.io/title": "%s"\n' "$(yaml_escape "${title}")"
    printf '    "platform.publiccloudexperiments.net/source-kind": "CiliumNetworkPolicy"\n'
    printf '    "platform.publiccloudexperiments.net/hubble-policy-candidate": "true"\n'
    printf '    "platform.publiccloudexperiments.net/hubble-policy-direction": "%s"\n' "${direction}"
    printf '    "platform.publiccloudexperiments.net/hubble-policy-mode": "%s"\n' "${mode}"
    printf '    "platform.publiccloudexperiments.net/hubble-policy-row-count": "%s"\n' "${row_count}"
    printf '    "platform.publiccloudexperiments.net/hubble-policy-since": "%s"\n' "${since_value}"
    printf '    "platform.publiccloudexperiments.net/hubble-policy-iterations": "%s"\n' "${iterations}"
    printf '    "platform.publiccloudexperiments.net/hubble-policy-capture-mode": "%s"\n' "${capture_mode}"
    printf 'specs:\n'
  } > "${policy_file}"
}

append_ingress_spec() {
  local policy_file="$1"
  local description="$2"
  local namespace="$3"
  local selector_key="$4"
  local selector_value="$5"
  local rules_file="$6"

  {
    printf '  - description: >-\n'
    printf '      %s\n' "$(yaml_escape "${description}")"
    printf '    endpointSelector:\n'
    emit_selector_block "${namespace}" "${selector_key}" "${selector_value}"
    printf '    ingress:\n'
    cat "${rules_file}"
  } >> "${policy_file}"
}

append_egress_spec() {
  local policy_file="$1"
  local description="$2"
  local namespace="$3"
  local selector_key="$4"
  local selector_value="$5"
  local rules_file="$6"

  {
    printf '  - description: >-\n'
    printf '      %s\n' "$(yaml_escape "${description}")"
    printf '    endpointSelector:\n'
    emit_selector_block "${namespace}" "${selector_key}" "${selector_value}"
    printf '    egress:\n'
    cat "${rules_file}"
  } >> "${policy_file}"
}

build_ingress_rule_block() {
  local items_file="$1"
  local protocol="$2"
  local port="$3"
  local kind="$4"
  local output_file="$5"
  local peer_ns=""
  local selector_key=""
  local selector_value=""

  if [[ "${kind}" == "cidr" ]]; then
    {
      printf '      - fromCIDRSet:\n'
      while IFS= read -r selector_value; do
        [[ -n "${selector_value}" ]] || continue
        printf '          - cidr: "%s"\n' "$(yaml_escape "${selector_value}")"
      done < "${items_file}"
      printf '        toPorts:\n'
      printf '          - ports:\n'
      printf '              - port: "%s"\n' "$(yaml_escape "${port}")"
      printf '                protocol: %s\n' "$(printf '%s' "${protocol}" | tr '[:lower:]' '[:upper:]')"
    } > "${output_file}"
    return 0
  fi

  if [[ "${kind}" == "world" || "${kind}" == "host" ]]; then
    {
      printf '      - fromEntities:\n'
      printf '          - %s\n' "${kind}"
      printf '        toPorts:\n'
      printf '          - ports:\n'
      printf '              - port: "%s"\n' "$(yaml_escape "${port}")"
      printf '                protocol: %s\n' "$(printf '%s' "${protocol}" | tr '[:lower:]' '[:upper:]')"
    } > "${output_file}"
    return 0
  fi

  {
    printf '      - fromEndpoints:\n'
    while IFS=$'\037' read -r peer_ns selector_key selector_value; do
      [[ -n "${peer_ns}" ]] || continue
      printf '          - matchLabels:\n'
      printf '              "k8s:io.kubernetes.pod.namespace": "%s"\n' "$(yaml_escape "${peer_ns}")"
      if [[ "${kind}" == "workload" ]]; then
        printf '              "k8s:%s": "%s"\n' "$(yaml_escape "${selector_key}")" "$(yaml_escape "${selector_value}")"
      fi
    done < <(tsv_rows "${items_file}")
    printf '        toPorts:\n'
    printf '          - ports:\n'
    printf '              - port: "%s"\n' "$(yaml_escape "${port}")"
    printf '                protocol: %s\n' "$(printf '%s' "${protocol}" | tr '[:lower:]' '[:upper:]')"
  } > "${output_file}"
}

build_egress_rule_block() {
  local items_file="$1"
  local protocol="$2"
  local port="$3"
  local kind="$4"
  local output_file="$5"
  local peer_ns=""
  local selector_key=""
  local selector_value=""

  if [[ "${kind}" == "fqdn" ]]; then
    {
      printf '      - toFQDNs:\n'
      while IFS= read -r selector_value; do
        [[ -n "${selector_value}" ]] || continue
        printf '          - matchName: "%s"\n' "$(yaml_escape "${selector_value}")"
      done < "${items_file}"
      printf '        toPorts:\n'
      printf '          - ports:\n'
      printf '              - port: "%s"\n' "$(yaml_escape "${port}")"
      printf '                protocol: %s\n' "$(printf '%s' "${protocol}" | tr '[:lower:]' '[:upper:]')"
    } > "${output_file}"
    return 0
  fi

  if [[ "${kind}" == "cidr" ]]; then
    {
      printf '      - toCIDRSet:\n'
      while IFS= read -r selector_value; do
        [[ -n "${selector_value}" ]] || continue
        printf '          - cidr: "%s"\n' "$(yaml_escape "${selector_value}")"
      done < "${items_file}"
      printf '        toPorts:\n'
      printf '          - ports:\n'
      printf '              - port: "%s"\n' "$(yaml_escape "${port}")"
      printf '                protocol: %s\n' "$(printf '%s' "${protocol}" | tr '[:lower:]' '[:upper:]')"
    } > "${output_file}"
    return 0
  fi

  if [[ "${kind}" == "world" || "${kind}" == "host" ]]; then
    {
      printf '      - toEntities:\n'
      printf '          - %s\n' "${kind}"
      printf '        toPorts:\n'
      printf '          - ports:\n'
      printf '              - port: "%s"\n' "$(yaml_escape "${port}")"
      printf '                protocol: %s\n' "$(printf '%s' "${protocol}" | tr '[:lower:]' '[:upper:]')"
    } > "${output_file}"
    return 0
  fi

  {
    printf '      - toEndpoints:\n'
    while IFS=$'\037' read -r peer_ns selector_key selector_value; do
      [[ -n "${peer_ns}" ]] || continue
      printf '          - matchLabels:\n'
      printf '              "k8s:io.kubernetes.pod.namespace": "%s"\n' "$(yaml_escape "${peer_ns}")"
      if [[ "${kind}" == "workload" ]]; then
        printf '              "k8s:%s": "%s"\n' "$(yaml_escape "${selector_key}")" "$(yaml_escape "${selector_value}")"
      fi
    done < <(tsv_rows "${items_file}")
    printf '        toPorts:\n'
    printf '          - ports:\n'
    printf '              - port: "%s"\n' "$(yaml_escape "${port}")"
    printf '                protocol: %s\n' "$(printf '%s' "${protocol}" | tr '[:lower:]' '[:upper:]')"
  } > "${output_file}"
}

generate_ingress_policy() {
  local namespace="$1"
  local mode="$2"
  local edges_file="$3"
  local world_file="$4"
  local policy_file="$5"
  local row_count="$6"
  local tmp_entries
  local tmp_rules
  local tmp_group
  local tmp_used_entries
  local spec_count=0
  local usable_row_count=0
  local target_selector_key=""
  local target_selector_value=""
  local target_display_name=""
  local protocol=""
  local port=""
  local kind=""
  local description=""
  local policy_name=""
  local title=""
  local target_kind=""
  local target_value=""

  tmp_entries="$(mktemp "${TMPDIR:-/tmp}/hubble-audit-ingress-entries.XXXXXX")"
  tmp_rules="$(mktemp "${TMPDIR:-/tmp}/hubble-audit-ingress-rules.XXXXXX")"
  tmp_group="$(mktemp "${TMPDIR:-/tmp}/hubble-audit-ingress-group.XXXXXX")"
  tmp_used_entries="$(mktemp "${TMPDIR:-/tmp}/hubble-audit-ingress-used.XXXXXX")"
  LAST_POLICY_USABLE_ROWS=0

  if [[ "${mode}" == "workload" ]]; then
    while IFS=$'\037' read -r count direction verdict protocol src_ns src dst_class dst_ns dst dst_port; do
      if [[ "${count}" == "count" && "${direction}" == "direction" ]]; then
        continue
      fi

      [[ "${verdict}" == "FORWARDED" ]] || continue
      supported_policy_protocol "${protocol}" || continue
      [[ "${dst_class}" == "workload" && "${dst_ns}" == "${namespace}" ]] || continue
      [[ -n "${src}" && -n "${dst}" && -n "${dst_port}" ]] || continue

      if ! resolve_selector "${namespace}" "${dst}"; then
        warn_once "selector:ingress-target:${namespace}/${dst}:${RESOLVE_ERROR_MSG}" "skipping ingress target ${namespace}/${dst}: ${RESOLVE_ERROR_MSG}"
        continue
      fi
      target_selector_key="${RESOLVED_SELECTOR_KEY}"
      target_selector_value="${RESOLVED_SELECTOR_VALUE}"

      if [[ -n "${src_ns}" ]]; then
        is_ip_like "${src_ns}" && continue
        if ! resolve_selector "${src_ns}" "${src}"; then
          warn_once "selector:ingress-source:${src_ns}/${src}:${RESOLVE_ERROR_MSG}" "skipping ingress source ${src_ns}/${src} for ${namespace}/${dst}: ${RESOLVE_ERROR_MSG}"
          continue
        fi

        printf '%s\t%s\t%s\t%s\tworkload\t%s\t%s\t%s\n' \
          "${target_selector_key}" \
          "${target_selector_value}" \
          "${protocol}" \
          "${dst_port}" \
          "${src_ns}" \
          "${RESOLVED_SELECTOR_KEY}" \
          "${RESOLVED_SELECTOR_VALUE}" >> "${tmp_entries}"
      elif is_host_peer_ip "${src}"; then
        printf '%s\t%s\t%s\t%s\thost\t\t\t\n' \
          "${target_selector_key}" \
          "${target_selector_value}" \
          "${protocol}" \
          "${dst_port}" >> "${tmp_entries}"
      fi
    done < <(tsv_rows "${edges_file}")

    while IFS=$'\037' read -r count direction verdict protocol world_side peer_ns peer world_names world_ip port; do
      if [[ "${count}" == "count" && "${direction}" == "direction" ]]; then
        continue
      fi
      : "${world_names}" "${world_ip}"

      [[ "${verdict}" == "FORWARDED" ]] || continue
      supported_policy_protocol "${protocol}" || continue
      [[ "${world_side}" == "source" && "${peer_ns}" == "${namespace}" && -n "${peer}" && -n "${port}" ]] || continue

      if ! resolve_selector "${namespace}" "${peer}"; then
        warn_once "selector:ingress-target:${namespace}/${peer}:${RESOLVE_ERROR_MSG}" "skipping ingress target ${namespace}/${peer}: ${RESOLVE_ERROR_MSG}"
        continue
      fi

      while IFS=$'\t' read -r target_kind target_value; do
        [[ -n "${target_kind}" && -n "${target_value}" ]] || continue
        printf '%s\t%s\t%s\t%s\t%s\t%s\t\t\n' \
          "${RESOLVED_SELECTOR_KEY}" \
          "${RESOLVED_SELECTOR_VALUE}" \
          "${protocol}" \
          "${port}" \
          "${target_kind}" \
          "${target_value}" >> "${tmp_entries}"
      done < <({ collect_world_targets "ingress" "${world_names}" "${world_ip}" || true; })
    done < <(tsv_rows "${world_file}")

    if [[ ! -s "${tmp_entries}" ]]; then
      return 1
    fi

    sort -u "${tmp_entries}" -o "${tmp_entries}"

    policy_name="$(sanitize_filename "cnp-${namespace}-observed-ingress-candidate")"
    title="$(title_case_words "${namespace}") observed ingress candidate"
    write_namespace_policy_header "${policy_file}" "${policy_name}" "${namespace}" "${title}" "ingress" "${mode}" "${row_count}"
    : > "${tmp_used_entries}"

    while IFS=$'\t' read -r target_selector_key target_selector_value; do
      [[ -n "${target_selector_value}" ]] || continue

      : > "${tmp_rules}"
      while IFS=$'\t' read -r protocol port kind; do
        [[ -n "${protocol}" && -n "${port}" && -n "${kind}" ]] || continue
        case "${kind}" in
          workload|namespace)
            awk -F'\t' -v key="${target_selector_key}" -v val="${target_selector_value}" -v p="${protocol}" -v d="${port}" -v k="${kind}" '
              $1 == key && $2 == val && $3 == p && $4 == d && $5 == k {
                print $6 "\t" $7 "\t" $8
              }
            ' "${tmp_entries}" | sort -u > "${tmp_group}"
            ;;
          cidr)
            awk -F'\t' -v key="${target_selector_key}" -v val="${target_selector_value}" -v p="${protocol}" -v d="${port}" -v k="${kind}" '
              $1 == key && $2 == val && $3 == p && $4 == d && $5 == k && $6 != "" {
                print $6
              }
            ' "${tmp_entries}" | sort -u > "${tmp_group}"
            ;;
          host|world)
            : > "${tmp_group}"
            ;;
          *)
            continue
            ;;
        esac
        build_ingress_rule_block "${tmp_group}" "${protocol}" "${port}" "${kind}" "${tmp_group}.rule"
        cat "${tmp_group}.rule" >> "${tmp_rules}"
        rm -f "${tmp_group}.rule"
      done < <(awk -F'\t' -v key="${target_selector_key}" -v val="${target_selector_value}" '$1 == key && $2 == val { print $3 "\t" $4 "\t" $5 }' "${tmp_entries}" | sort -u)

      if [[ ! -s "${tmp_rules}" ]]; then
        continue
      fi

      target_display_name="$(selector_display_name "${target_selector_key}" "${target_selector_value}" "")"
      description="$(observed_traffic_description "ingress" "${namespace}" "${target_display_name}")"
      append_ingress_spec \
        "${policy_file}" \
        "${description}" \
        "${namespace}" \
        "${target_selector_key}" \
        "${target_selector_value}" \
        "${tmp_rules}"
      awk -F'\t' -v key="${target_selector_key}" -v val="${target_selector_value}" '$1 == key && $2 == val { print }' "${tmp_entries}" >> "${tmp_used_entries}"
      spec_count=$((spec_count + 1))
    done < <(awk -F'\t' '{ print $1 "\t" $2 }' "${tmp_entries}" | sort -u)

    if [[ -s "${tmp_used_entries}" ]]; then
      sort -u "${tmp_used_entries}" -o "${tmp_used_entries}"
      usable_row_count="$(count_lines "${tmp_used_entries}")"
    fi
  else
    while IFS=$'\037' read -r count direction verdict protocol src_ns src dst_class dst_ns dst dst_port; do
      if [[ "${count}" == "count" && "${direction}" == "direction" ]]; then
        continue
      fi

      [[ "${verdict}" == "FORWARDED" ]] || continue
      supported_policy_protocol "${protocol}" || continue
      [[ "${dst_class}" == "workload" && "${dst_ns}" == "${namespace}" && -n "${dst_port}" ]] || continue

      if [[ -n "${src_ns}" ]]; then
        printf '%s\t%s\tnamespace\t%s\t\t\n' \
          "${protocol}" \
          "${dst_port}" \
          "${src_ns}" >> "${tmp_entries}"
      elif is_host_peer_ip "${src}"; then
        printf '%s\t%s\thost\thost\t\t\n' "${protocol}" "${dst_port}" >> "${tmp_entries}"
      fi
    done < <(tsv_rows "${edges_file}")

    while IFS=$'\037' read -r count direction verdict protocol world_side peer_ns peer world_names world_ip port; do
      if [[ "${count}" == "count" && "${direction}" == "direction" ]]; then
        continue
      fi
      : "${world_names}" "${world_ip}"

      [[ "${verdict}" == "FORWARDED" ]] || continue
      supported_policy_protocol "${protocol}" || continue
      [[ "${world_side}" == "source" && "${peer_ns}" == "${namespace}" && -n "${port}" ]] || continue

      while IFS=$'\t' read -r target_kind target_value; do
        [[ -n "${target_kind}" && -n "${target_value}" ]] || continue
        printf '%s\t%s\t%s\t%s\t\t\n' "${protocol}" "${port}" "${target_kind}" "${target_value}" >> "${tmp_entries}"
      done < <({ collect_world_targets "ingress" "${world_names}" "${world_ip}" || true; })
    done < <(tsv_rows "${world_file}")

    if [[ ! -s "${tmp_entries}" ]]; then
      return 1
    fi

    sort -u "${tmp_entries}" -o "${tmp_entries}"

    policy_name="$(sanitize_filename "cnp-${namespace}-observed-ingress-candidate")"
    title="$(title_case_words "${namespace}") observed ingress candidate"
    write_namespace_policy_header "${policy_file}" "${policy_name}" "${namespace}" "${title}" "ingress" "${mode}" "${row_count}"

    : > "${tmp_rules}"
    while IFS=$'\t' read -r protocol port kind peer_value _ _; do
      [[ -n "${protocol}" && -n "${port}" && -n "${kind}" ]] || continue
      case "${kind}" in
        namespace)
          awk -F'\t' -v p="${protocol}" -v d="${port}" -v k="${kind}" '
            $1 == p && $2 == d && $3 == k { print $4 "\t" $5 "\t" $6 }
          ' "${tmp_entries}" | sort -u > "${tmp_group}"
          ;;
        cidr)
          awk -F'\t' -v p="${protocol}" -v d="${port}" -v k="${kind}" '
            $1 == p && $2 == d && $3 == k && $4 != "" { print $4 }
          ' "${tmp_entries}" | sort -u > "${tmp_group}"
          ;;
        host|world)
          : > "${tmp_group}"
          ;;
        *)
          continue
          ;;
      esac
      build_ingress_rule_block "${tmp_group}" "${protocol}" "${port}" "${kind}" "${tmp_group}.rule"
      cat "${tmp_group}.rule" >> "${tmp_rules}"
      rm -f "${tmp_group}.rule"
    done < <(awk -F'\t' '{ print $1 "\t" $2 "\t" $3 }' "${tmp_entries}" | sort -u)

    if [[ -s "${tmp_rules}" ]]; then
      description="$(observed_namespace_traffic_description "ingress" "${namespace}")"
      append_ingress_spec "${policy_file}" "${description}" "${namespace}" "" "" "${tmp_rules}"
      spec_count=1
      usable_row_count="$(count_lines "${tmp_entries}")"
    fi
  fi

  if [[ "${spec_count}" -eq 0 ]]; then
    LAST_POLICY_USABLE_ROWS=0
    rm -f "${policy_file}"
    rm -f "${tmp_entries}" "${tmp_rules}" "${tmp_group}" "${tmp_used_entries}"
    return 1
  fi

  LAST_POLICY_USABLE_ROWS="${usable_row_count}"
  rm -f "${tmp_entries}" "${tmp_rules}" "${tmp_group}" "${tmp_used_entries}"
  return 0
}

generate_egress_policy() {
  local namespace="$1"
  local mode="$2"
  local edges_file="$3"
  local world_file="$4"
  local policy_file="$5"
  local row_count="$6"
  local tmp_entries
  local tmp_rules
  local tmp_group
  local tmp_used_entries
  local spec_count=0
  local usable_row_count=0
  local source_selector_key=""
  local source_selector_value=""
  local source_display_name=""
  local protocol=""
  local port=""
  local kind=""
  local description=""
  local policy_name=""
  local title=""
  local target_kind=""
  local target_value=""
  local world_targets_added=0

  tmp_entries="$(mktemp "${TMPDIR:-/tmp}/hubble-audit-egress-entries.XXXXXX")"
  tmp_rules="$(mktemp "${TMPDIR:-/tmp}/hubble-audit-egress-rules.XXXXXX")"
  tmp_group="$(mktemp "${TMPDIR:-/tmp}/hubble-audit-egress-group.XXXXXX")"
  tmp_used_entries="$(mktemp "${TMPDIR:-/tmp}/hubble-audit-egress-used.XXXXXX")"
  LAST_POLICY_USABLE_ROWS=0

  if [[ "${mode}" == "workload" ]]; then
    while IFS=$'\037' read -r count direction verdict protocol src_ns src dst_class dst_ns dst dst_port; do
      if [[ "${count}" == "count" && "${direction}" == "direction" ]]; then
        continue
      fi

      [[ "${verdict}" == "FORWARDED" ]] || continue
      supported_policy_protocol "${protocol}" || continue
      [[ "${src_ns}" == "${namespace}" && "${dst_class}" == "workload" ]] || continue
      [[ -n "${src}" && -n "${dst}" && -n "${dst_port}" ]] || continue

      if ! resolve_selector "${namespace}" "${src}"; then
        warn_once "selector:egress-source:${namespace}/${src}:${RESOLVE_ERROR_MSG}" "skipping egress source ${namespace}/${src}: ${RESOLVE_ERROR_MSG}"
        continue
      fi
      source_selector_key="${RESOLVED_SELECTOR_KEY}"
      source_selector_value="${RESOLVED_SELECTOR_VALUE}"

      if [[ -n "${dst_ns}" ]]; then
        is_ip_like "${dst_ns}" && continue
        if ! resolve_selector "${dst_ns}" "${dst}"; then
          warn_once "selector:egress-destination:${dst_ns}/${dst}:${RESOLVE_ERROR_MSG}" "skipping egress destination ${dst_ns}/${dst} for ${namespace}/${src}: ${RESOLVE_ERROR_MSG}"
          continue
        fi

        printf '%s\t%s\t%s\t%s\tworkload\t%s\t%s\t%s\n' \
          "${source_selector_key}" \
          "${source_selector_value}" \
          "${protocol}" \
          "${dst_port}" \
          "${dst_ns}" \
          "${RESOLVED_SELECTOR_KEY}" \
          "${RESOLVED_SELECTOR_VALUE}" >> "${tmp_entries}"
      elif is_host_peer_ip "${dst}"; then
        printf '%s\t%s\t%s\t%s\thost\t\t\t\n' \
          "${source_selector_key}" \
          "${source_selector_value}" \
          "${protocol}" \
          "${dst_port}" >> "${tmp_entries}"
      fi
    done < <(tsv_rows "${edges_file}")

    while IFS=$'\037' read -r count direction verdict protocol world_side peer_ns peer world_names world_ip port; do
      if [[ "${count}" == "count" && "${direction}" == "direction" ]]; then
        continue
      fi
      : "${world_names}" "${world_ip}"

      [[ "${verdict}" == "FORWARDED" ]] || continue
      supported_policy_protocol "${protocol}" || continue
      [[ "${world_side}" == "destination" && "${peer_ns}" == "${namespace}" && -n "${peer}" && -n "${port}" ]] || continue

      if ! resolve_selector "${namespace}" "${peer}"; then
        warn_once "selector:egress-source:${namespace}/${peer}:${RESOLVE_ERROR_MSG}" "skipping egress source ${namespace}/${peer}: ${RESOLVE_ERROR_MSG}"
        continue
      fi

      world_targets_added=0
      while IFS=$'\t' read -r target_kind target_value; do
        [[ -n "${target_kind}" && -n "${target_value}" ]] || continue
        printf '%s\t%s\t%s\t%s\t%s\t%s\t\t\n' \
          "${RESOLVED_SELECTOR_KEY}" \
          "${RESOLVED_SELECTOR_VALUE}" \
          "${protocol}" \
          "${port}" \
          "${target_kind}" \
          "${target_value}" >> "${tmp_entries}"
        world_targets_added=1
      done < <({ collect_world_targets "egress" "${world_names}" "${world_ip}" || true; })
      if [[ "${world_targets_added}" -eq 0 ]]; then
        warn "skipping egress world destination for ${namespace}/${peer} on ${protocol}/${port}: no observed FQDN or IP"
      fi
    done < <(tsv_rows "${world_file}")

    if [[ ! -s "${tmp_entries}" ]]; then
      return 1
    fi

    sort -u "${tmp_entries}" -o "${tmp_entries}"

    policy_name="$(sanitize_filename "cnp-${namespace}-observed-egress-candidate")"
    title="$(title_case_words "${namespace}") observed egress candidate"
    write_namespace_policy_header "${policy_file}" "${policy_name}" "${namespace}" "${title}" "egress" "${mode}" "${row_count}"
    : > "${tmp_used_entries}"

    while IFS=$'\t' read -r source_selector_key source_selector_value; do
      [[ -n "${source_selector_value}" ]] || continue
      : > "${tmp_rules}"
      while IFS=$'\t' read -r protocol port kind; do
        [[ -n "${protocol}" && -n "${port}" && -n "${kind}" ]] || continue
        case "${kind}" in
          workload|namespace)
            awk -F'\t' -v key="${source_selector_key}" -v val="${source_selector_value}" -v p="${protocol}" -v d="${port}" -v k="${kind}" '
              $1 == key && $2 == val && $3 == p && $4 == d && $5 == k {
                print $6 "\t" $7 "\t" $8
              }
            ' "${tmp_entries}" | sort -u > "${tmp_group}"
            ;;
          fqdn|cidr)
            awk -F'\t' -v key="${source_selector_key}" -v val="${source_selector_value}" -v p="${protocol}" -v d="${port}" -v k="${kind}" '
              $1 == key && $2 == val && $3 == p && $4 == d && $5 == k && $6 != "" {
                print $6
              }
            ' "${tmp_entries}" | sort -u > "${tmp_group}"
            ;;
          host|world)
            : > "${tmp_group}"
            ;;
          *)
            continue
            ;;
        esac
        build_egress_rule_block "${tmp_group}" "${protocol}" "${port}" "${kind}" "${tmp_group}.rule"
        cat "${tmp_group}.rule" >> "${tmp_rules}"
        rm -f "${tmp_group}.rule"
      done < <(awk -F'\t' -v key="${source_selector_key}" -v val="${source_selector_value}" '$1 == key && $2 == val { print $3 "\t" $4 "\t" $5 }' "${tmp_entries}" | sort -u)

      if [[ ! -s "${tmp_rules}" ]]; then
        continue
      fi

      source_display_name="$(selector_display_name "${source_selector_key}" "${source_selector_value}" "")"
      description="$(observed_traffic_description "egress" "${namespace}" "${source_display_name}")"
      append_egress_spec \
        "${policy_file}" \
        "${description}" \
        "${namespace}" \
        "${source_selector_key}" \
        "${source_selector_value}" \
        "${tmp_rules}"
      awk -F'\t' -v key="${source_selector_key}" -v val="${source_selector_value}" '$1 == key && $2 == val { print }' "${tmp_entries}" >> "${tmp_used_entries}"
      spec_count=$((spec_count + 1))
    done < <(awk -F'\t' '{ print $1 "\t" $2 }' "${tmp_entries}" | sort -u)

    if [[ -s "${tmp_used_entries}" ]]; then
      sort -u "${tmp_used_entries}" -o "${tmp_used_entries}"
      usable_row_count="$(count_lines "${tmp_used_entries}")"
    fi
  else
    while IFS=$'\037' read -r count direction verdict protocol src_ns src dst_class dst_ns dst dst_port; do
      if [[ "${count}" == "count" && "${direction}" == "direction" ]]; then
        continue
      fi

      [[ "${verdict}" == "FORWARDED" ]] || continue
      supported_policy_protocol "${protocol}" || continue
      [[ "${src_ns}" == "${namespace}" && "${dst_class}" == "workload" && -n "${dst_port}" ]] || continue

      if [[ -n "${dst_ns}" ]]; then
        printf '%s\t%s\tnamespace\t%s\t\t\n' \
          "${protocol}" \
          "${dst_port}" \
          "${dst_ns}" >> "${tmp_entries}"
      elif is_host_peer_ip "${dst}"; then
        printf '%s\t%s\thost\thost\t\t\n' "${protocol}" "${dst_port}" >> "${tmp_entries}"
      fi
    done < <(tsv_rows "${edges_file}")

    while IFS=$'\037' read -r count direction verdict protocol world_side peer_ns peer world_names world_ip port; do
      if [[ "${count}" == "count" && "${direction}" == "direction" ]]; then
        continue
      fi
      : "${world_names}" "${world_ip}"

      [[ "${verdict}" == "FORWARDED" ]] || continue
      supported_policy_protocol "${protocol}" || continue
      [[ "${world_side}" == "destination" && "${peer_ns}" == "${namespace}" && -n "${port}" ]] || continue

      world_targets_added=0
      while IFS=$'\t' read -r target_kind target_value; do
        [[ -n "${target_kind}" && -n "${target_value}" ]] || continue
        printf '%s\t%s\t%s\t%s\t\t\n' "${protocol}" "${port}" "${target_kind}" "${target_value}" >> "${tmp_entries}"
        world_targets_added=1
      done < <({ collect_world_targets "egress" "${world_names}" "${world_ip}" || true; })
      if [[ "${world_targets_added}" -eq 0 ]]; then
        warn "skipping namespace-aggregate world egress for ${namespace} on ${protocol}/${port}: no observed FQDN or IP"
      fi
    done < <(tsv_rows "${world_file}")

    if [[ ! -s "${tmp_entries}" ]]; then
      return 1
    fi

    sort -u "${tmp_entries}" -o "${tmp_entries}"

    policy_name="$(sanitize_filename "cnp-${namespace}-observed-egress-candidate")"
    title="$(title_case_words "${namespace}") observed egress candidate"
    write_namespace_policy_header "${policy_file}" "${policy_name}" "${namespace}" "${title}" "egress" "${mode}" "${row_count}"

    : > "${tmp_rules}"
    while IFS=$'\t' read -r protocol port kind peer_value _ _; do
      [[ -n "${protocol}" && -n "${port}" && -n "${kind}" ]] || continue
      case "${kind}" in
        namespace)
          awk -F'\t' -v p="${protocol}" -v d="${port}" -v k="${kind}" '
            $1 == p && $2 == d && $3 == k { print $4 "\t" $5 "\t" $6 }
          ' "${tmp_entries}" | sort -u > "${tmp_group}"
          ;;
        fqdn|cidr)
          awk -F'\t' -v p="${protocol}" -v d="${port}" -v k="${kind}" '
            $1 == p && $2 == d && $3 == k && $4 != "" { print $4 }
          ' "${tmp_entries}" | sort -u > "${tmp_group}"
          ;;
        host|world)
          : > "${tmp_group}"
          ;;
        *)
          continue
          ;;
      esac
      build_egress_rule_block "${tmp_group}" "${protocol}" "${port}" "${kind}" "${tmp_group}.rule"
      cat "${tmp_group}.rule" >> "${tmp_rules}"
      rm -f "${tmp_group}.rule"
    done < <(awk -F'\t' '{ print $1 "\t" $2 "\t" $3 }' "${tmp_entries}" | sort -u)

    if [[ -s "${tmp_rules}" ]]; then
      description="$(observed_namespace_traffic_description "egress" "${namespace}")"
      append_egress_spec "${policy_file}" "${description}" "${namespace}" "" "" "${tmp_rules}"
      spec_count=1
      usable_row_count="$(count_lines "${tmp_entries}")"
    fi
  fi

  if [[ "${spec_count}" -eq 0 ]]; then
    LAST_POLICY_USABLE_ROWS=0
    rm -f "${policy_file}"
    rm -f "${tmp_entries}" "${tmp_rules}" "${tmp_group}" "${tmp_used_entries}"
    return 1
  fi

  LAST_POLICY_USABLE_ROWS="${usable_row_count}"
  rm -f "${tmp_entries}" "${tmp_rules}" "${tmp_group}" "${tmp_used_entries}"
  return 0
}

write_report_markdown() {
  local report_file="$1"
  local namespace=""
  local direction=""
  local raw_row_count=""
  local usable_row_count=""
  local mode=""
  local policy_file=""
  local aggregate_file=""
  local capture_strategy_requested=""
  local capture_strategy_used=""
  local capture_sample_target=""
  local filtered_flow_count=""
  local capture_fallback_used=""
  local capture_seconds=""
  local summary_seconds=""
  local generation_seconds=""

  {
    printf '# Hubble Policy Observation\n\n'
    printf -- "- Capture strategy: \`%s\`\n" "${capture_strategy}"
    printf -- "- Since: \`%s\`\n" "${since_value}"
    printf -- "- Sample target: \`%s\`\n" "${sample_target}"
    printf -- "- Sample minimum: \`%s\`\n" "${sample_min}"
    printf -- "- Iterations: \`%s\`\n" "${iterations}"
    printf -- "- Namespace workers: \`%s\`\n" "${namespace_workers}"
    printf -- "- Sleep between: \`%s\` seconds\n" "${sleep_between}"
    printf -- "- Progress heartbeat: \`%s\` seconds\n" "${progress_every}"
    printf -- "- Row threshold: \`%s\`\n" "${row_threshold}"
    printf -- "- Capture mode: \`%s\`, reply traffic removed\n" "${capture_mode}"
    printf -- "- Output root: \`%s\`\n\n" "${output_dir}"
    if [[ "${promote_to_module}" -eq 1 ]]; then
      printf -- "- Module promotion: enabled -> \`%s\`\n\n" "${module_root}"
    fi
    if [[ -s "${PROMOTION_ERRORS_FILE}" ]]; then
      printf '## Promotion Errors\n\n'
      while IFS= read -r promotion_error; do
        [[ -n "${promotion_error}" ]] || continue
        printf -- '- %s\n' "${promotion_error}"
      done < "${PROMOTION_ERRORS_FILE}"
      printf '\n'
    fi

    while IFS="${REPORT_ROW_DELIM}" read -r namespace direction raw_row_count usable_row_count mode policy_file aggregate_file capture_strategy_requested capture_strategy_used capture_sample_target filtered_flow_count capture_fallback_used capture_seconds summary_seconds generation_seconds; do
      [[ -n "${namespace}" ]] || continue
      printf '## %s %s\n\n' "${namespace}" "${direction}"
      printf -- "- Raw summary rows: \`%s\`\n" "${raw_row_count}"
      printf -- "- Policy-usable rows: \`%s\`\n" "${usable_row_count}"
      printf -- "- Generation mode: \`%s\`\n" "${mode}"
      printf -- "- Requested capture strategy: \`%s\`\n" "${capture_strategy_requested}"
      printf -- "- Effective capture strategy: \`%s\`\n" "${capture_strategy_used}"
      printf -- "- Sample target: \`%s\`\n" "${capture_sample_target}"
      printf -- "- Non-reply usable flows: \`%s\`\n" "${filtered_flow_count}"
      printf -- "- Fell back to since: \`%s\`\n" "${capture_fallback_used}"
      printf -- "- Capture elapsed: \`%ss\`\n" "${capture_seconds}"
      printf -- "- Summary elapsed: \`%ss\`\n" "${summary_seconds}"
      printf -- "- Generation elapsed: \`%ss\`\n" "${generation_seconds}"
      if [[ -n "${policy_file}" ]]; then
        printf -- "- Candidate policy: \`%s\`\n" "${policy_file}"
      else
        printf -- '- Candidate policy: omitted\n'
      fi
      if [[ -n "${aggregate_file}" ]]; then
        printf -- "- Aggregate report: \`%s\`\n" "${aggregate_file}"
      fi
      printf '\n'
    done < "${REPORT_ROWS_FILE}"
  } > "${report_file}"
}

promote_policy_to_module() {
  local namespace="$1"
  local policy_file="$2"
  local source_dir=""
  local category_dir=""
  local source_file=""
  local category_file=""
  local error_message=""

  [[ -n "${policy_file}" ]] || return 0

  source_dir="${module_root}/sources/${namespace}"
  category_dir="${module_root}/categories/${namespace}"
  source_file="${source_dir}/$(basename "${policy_file}")"
  category_file="${category_dir}/$(basename "${policy_file}")"
  PROMOTION_ERROR_MSG=""

  if ! mkdir -p "${source_dir}" "${category_dir}"; then
    PROMOTION_ERROR_MSG="failed to create module output directories for ${namespace} under ${module_root}"
    return 1
  fi

  if [[ -e "${source_file}" ]]; then
    if cmp -s "${policy_file}" "${source_file}"; then
      :
    elif [[ "${force_module_overwrite}" -eq 1 ]]; then
      if ! cp "${policy_file}" "${source_file}"; then
        PROMOTION_ERROR_MSG="failed to overwrite module source ${source_file}"
        return 1
      fi
    else
      PROMOTION_ERROR_MSG="module source already exists and differs: ${source_file} (rerun with --force-module-overwrite to replace it)"
      return 1
    fi
  else
    if ! cp "${policy_file}" "${source_file}"; then
      PROMOTION_ERROR_MSG="failed to write module source ${source_file}"
      return 1
    fi
  fi

  if ! "${RENDER_VALUES_SCRIPT}" --execute --output "${category_file}" "${source_file}"; then
    error_message="${PROMOTION_ERROR_MSG:-failed to render module category ${category_file} from ${source_file}}"
    PROMOTION_ERROR_MSG="${error_message}"
    return 1
  fi

  PROMOTED_CANDIDATE_POLICIES=$((PROMOTED_CANDIDATE_POLICIES + 1))
  PROMOTION_ERROR_MSG=""
  return 0
}

capture_strategy="adaptive"
since_value="5m"
sample_target="1000"
sample_min="200"
iterations="3"
namespace_workers="1"
sleep_between="0"
progress_every="10"
row_threshold="100"
capture_mode="flows"
world_egress_mode="observed"
output_dir=""
promote_to_module=0
module_root=""
force_module_overwrite=0
port_forward_port="0"
kubeconfig=""
kube_context=""
print_command=0
dry_run=0
DEFAULT_KIND_KUBECONFIG="${HOME}/.kube/kind-kind-local.yaml"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"
CAPTURE_SCRIPT="${SCRIPT_DIR}/hubble-capture-flows.sh"
SUMMARIZE_SCRIPT="${SCRIPT_DIR}/hubble-summarise-flows.sh"
RENDER_VALUES_SCRIPT="${SCRIPT_DIR}/render-cilium-policy-values.sh"
DEFAULT_MODULE_ROOT="${REPO_ROOT}/terraform/kubernetes/cluster-policies/cilium/cilium-module"

declare -a namespaces=()
declare -a excluded_namespaces=()
declare -a DEFAULT_EXCLUDED_NAMESPACES=()
LAST_POLICY_USABLE_ROWS=0
PROMOTION_ERROR_MSG=""
NAMESPACES_SCANNED=0
TOTAL_CANDIDATE_POLICIES=0
PROMOTED_CANDIDATE_POLICIES=0
TOTAL_NAMESPACES=0
FINAL_EXIT_STATUS=0
SHARED_HUBBLE_SERVER=""
SHARED_HUBBLE_RELAY_PID=""
SHARED_HUBBLE_RELAY_LOG=""
SHARED_HUBBLE_SERVICE_PORT=""
CAPTURE_STRATEGY_USED=""
CAPTURE_FALLBACK_USED="0"
SELECTOR_ACCESS_CHECKED_FILE=""
SELECTOR_CACHE_FILE=""
WARNED_MESSAGES_FILE=""
SELECTOR_CACHE_STATUS_VALUE=""
SELECTOR_CACHE_KEY_VALUE=""
SELECTOR_CACHE_VALUE_VALUE=""
SELECTOR_CACHE_ERROR_VALUE=""

shell_cli_init_standard_flags

while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --capture-strategy)
      capture_strategy="${2:-}"
      shift 2
      ;;
    --since)
      since_value="${2:-}"
      shift 2
      ;;
    --sample-target)
      sample_target="${2:-}"
      shift 2
      ;;
    --sample-min)
      sample_min="${2:-}"
      shift 2
      ;;
    --iterations)
      iterations="${2:-}"
      shift 2
      ;;
    --namespace-workers)
      namespace_workers="${2:-}"
      shift 2
      ;;
    --sleep-between)
      sleep_between="${2:-}"
      shift 2
      ;;
    --progress-every)
      progress_every="${2:-}"
      shift 2
      ;;
    --row-threshold)
      row_threshold="${2:-}"
      shift 2
      ;;
    --capture-mode)
      capture_mode="${2:-}"
      shift 2
      ;;
    --world-egress-mode)
      world_egress_mode="${2:-}"
      shift 2
      ;;
    --namespace)
      namespaces+=("${2:-}")
      shift 2
      ;;
    --exclude-namespace)
      excluded_namespaces+=("${2:-}")
      shift 2
      ;;
    --output-dir)
      output_dir="${2:-}"
      shift 2
      ;;
    --promote-to-module)
      promote_to_module=1
      shift
      ;;
    --module-root)
      module_root="${2:-}"
      shift 2
      ;;
    --force-module-overwrite)
      force_module_overwrite=1
      shift
      ;;
    --port-forward-port)
      port_forward_port="${2:-}"
      shift 2
      ;;
    --kubeconfig)
      kubeconfig="${2:-}"
      shift 2
      ;;
    --kube-context)
      kube_context="${2:-}"
      shift 2
      ;;
    --print-command)
      print_command=1
      shift
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

if [[ "${SHELL_CLI_DRY_RUN}" -eq 1 ]]; then
  dry_run=1
elif [[ "${SHELL_CLI_EXECUTE}" -ne 1 ]]; then
  usage
  dry_run=1
fi

case "${capture_strategy}" in
  since|last|adaptive) ;;
  *)
    fail "--capture-strategy must be one of: since, last, adaptive"
    ;;
esac

[[ "${sample_target}" =~ ^[0-9]+$ ]] || fail "--sample-target must be a non-negative integer"
[[ "${sample_min}" =~ ^[0-9]+$ ]] || fail "--sample-min must be a non-negative integer"
[[ "${iterations}" =~ ^[0-9]+$ ]] || fail "--iterations must be a non-negative integer"
[[ "${namespace_workers}" =~ ^[0-9]+$ ]] || fail "--namespace-workers must be a non-negative integer"
[[ "${sleep_between}" =~ ^[0-9]+$ ]] || fail "--sleep-between must be a non-negative integer"
[[ "${progress_every}" =~ ^[0-9]+$ ]] || fail "--progress-every must be a non-negative integer"
[[ "${row_threshold}" =~ ^[0-9]+$ ]] || fail "--row-threshold must be a non-negative integer"
[[ "${sample_target}" -gt 0 ]] || fail "--sample-target must be greater than zero"
[[ "${namespace_workers}" -gt 0 ]] || fail "--namespace-workers must be greater than zero"
case "${capture_mode}" in
  flows|policy-verdict) ;;
  *)
    fail "--capture-mode must be one of: flows, policy-verdict"
    ;;
esac

case "${world_egress_mode}" in
  observed|entity) ;;
  *)
    fail "--world-egress-mode must be one of: observed, entity"
    ;;
esac

if [[ -n "${module_root}" ]]; then
  promote_to_module=1
fi

if [[ "${force_module_overwrite}" -eq 1 && "${promote_to_module}" -ne 1 ]]; then
  fail "--force-module-overwrite requires --promote-to-module"
fi

if [[ "${promote_to_module}" -eq 1 && -z "${module_root}" ]]; then
  module_root="${DEFAULT_MODULE_ROOT}"
fi

if [[ "${dry_run}" -eq 1 ]]; then
  shell_cli_print_dry_run_summary "would observe Hubble flows and generate candidate Cilium policies"
  exit 0
fi

require_cmd jq
require_cmd kubectl
require_cmd awk
require_cmd sort
require_cmd cmp

[[ -x "${CAPTURE_SCRIPT}" ]] || fail "capture script not found at ${CAPTURE_SCRIPT}"
[[ -x "${SUMMARIZE_SCRIPT}" ]] || fail "summarise script not found at ${SUMMARIZE_SCRIPT}"
if [[ "${promote_to_module}" -eq 1 ]]; then
  [[ -x "${RENDER_VALUES_SCRIPT}" ]] || fail "render script not found at ${RENDER_VALUES_SCRIPT}"
fi

if [[ -z "${kubeconfig}" && -z "${KUBECONFIG:-}" && -f "${DEFAULT_KIND_KUBECONFIG}" ]]; then
  kubeconfig="${DEFAULT_KIND_KUBECONFIG}"
fi

KUBECTL_BASE=(kubectl)
if [[ -n "${kubeconfig}" ]]; then
  KUBECTL_BASE+=(--kubeconfig "${kubeconfig}")
fi
if [[ -n "${kube_context}" ]]; then
  KUBECTL_BASE+=(--context "${kube_context}")
fi

if [[ -z "${output_dir}" ]]; then
  output_context="$(resolve_output_context)"
  output_dir="${REPO_ROOT}/.run/hubble-observe-${output_context}/$(date +%Y%m%d-%H%M%S)"
fi

REPORT_ROWS_FILE="$(mktemp "${TMPDIR:-/tmp}/hubble-audit-report-rows.XXXXXX")"
NAMESPACE_FILE="$(mktemp "${TMPDIR:-/tmp}/hubble-audit-namespaces.XXXXXX")"
HOST_IP_FILE="$(mktemp "${TMPDIR:-/tmp}/hubble-audit-host-ips.XXXXXX")"
PROMOTION_ERRORS_FILE="$(mktemp "${TMPDIR:-/tmp}/hubble-audit-promotion-errors.XXXXXX")"
SELECTOR_ACCESS_CHECKED_FILE="$(mktemp "${TMPDIR:-/tmp}/hubble-audit-selector-access.XXXXXX")"
SELECTOR_CACHE_FILE="$(mktemp "${TMPDIR:-/tmp}/hubble-audit-selector-cache.XXXXXX")"
WARNED_MESSAGES_FILE="$(mktemp "${TMPDIR:-/tmp}/hubble-audit-warned-messages.XXXXXX")"
REPORT_ROW_DELIM=$'\037'
trap 'stop_shared_hubble_relay; rm -f "${REPORT_ROWS_FILE}" "${NAMESPACE_FILE}" "${HOST_IP_FILE}" "${PROMOTION_ERRORS_FILE}" "${SELECTOR_ACCESS_CHECKED_FILE}" "${SELECTOR_CACHE_FILE}" "${WARNED_MESSAGES_FILE}" "${SHARED_HUBBLE_RELAY_LOG:-}"' EXIT

if [[ "${dry_run}" -eq 0 ]]; then
  mkdir -p "${output_dir}"
fi

discover_namespaces "${NAMESPACE_FILE}"
discover_host_peer_ips
[[ -s "${NAMESPACE_FILE}" ]] || fail "no namespaces matched the requested filters"
TOTAL_NAMESPACES="$(count_lines "${NAMESPACE_FILE}")"

if [[ "${dry_run}" -eq 0 ]]; then
  start_shared_hubble_relay
fi

if [[ "${dry_run}" -eq 1 ]]; then
  namespace_index=0
  while IFS= read -r namespace; do
    [[ -n "${namespace}" ]] || continue
    namespace_index=$((namespace_index + 1))
    collect_namespace_data "${namespace}" "${namespace_index}"
  done < "${NAMESPACE_FILE}"
  exit 0
fi

declare -a batch_pids=()
namespace_index=0
while IFS= read -r namespace; do
  [[ -n "${namespace}" ]] || continue
  namespace_index=$((namespace_index + 1))
  collect_namespace_data "${namespace}" "${namespace_index}" &
  batch_pids+=("$!")

  if [[ "${#batch_pids[@]}" -ge "${namespace_workers}" ]]; then
    wait_for_pid_batch "${batch_pids[@]}" || fail "namespace capture/summarise phase failed"
    batch_pids=()
  fi
done < "${NAMESPACE_FILE}"

if [[ "${#batch_pids[@]}" -gt 0 ]]; then
  wait_for_pid_batch "${batch_pids[@]}" || fail "namespace capture/summarise phase failed"
fi

while IFS= read -r namespace; do
  [[ -n "${namespace}" ]] || continue
  NAMESPACES_SCANNED=$((NAMESPACES_SCANNED + 1))

  namespace_dir="${output_dir}/namespaces/${namespace}"
  policy_dir="${output_dir}/policies/${namespace}"
  metadata_file="${namespace_dir}/observe-metadata.env"
  ingress_edges="${namespace_dir}/ingress.edges.workload.tsv"
  egress_edges="${namespace_dir}/egress.edges.workload.tsv"
  ingress_world="${namespace_dir}/ingress.world.tsv"
  egress_world="${namespace_dir}/egress.world.tsv"
  generation_started=$SECONDS

  # shellcheck disable=SC1090
  source "${metadata_file}"

  mkdir -p "${policy_dir}"

  ingress_raw_rows="$(count_data_rows "${ingress_edges}")"
  egress_raw_rows="$(count_data_rows "${egress_edges}")"

  ingress_mode="workload"
  egress_mode="workload"
  ingress_policy=""
  egress_policy=""
  ingress_aggregate=""
  egress_aggregate=""
  ingress_usable_rows="0"
  egress_usable_rows="0"

  if [[ "${ingress_raw_rows}" -gt "${row_threshold}" ]]; then
    ingress_mode="namespace"
    ingress_aggregate="${namespace_dir}/ingress.aggregate-namespace.tsv"
    build_namespace_aggregate_report "${namespace}" "ingress" "${ingress_edges}" "${ingress_world}" "${ingress_aggregate}"
  fi

  if [[ "${egress_raw_rows}" -gt "${row_threshold}" ]]; then
    egress_mode="namespace"
    egress_aggregate="${namespace_dir}/egress.aggregate-namespace.tsv"
    build_namespace_aggregate_report "${namespace}" "egress" "${egress_edges}" "${egress_world}" "${egress_aggregate}"
  fi

  info "${namespace}: generating ingress candidate (mode=${ingress_mode}, raw rows=${ingress_raw_rows})"
  ingress_policy_path="${policy_dir}/cnp-${namespace}-observed-ingress-candidate.yaml"
  if generate_ingress_policy "${namespace}" "${ingress_mode}" "${ingress_edges}" "${ingress_world}" "${ingress_policy_path}" "${ingress_raw_rows}"; then
    ingress_policy="${ingress_policy_path}"
    TOTAL_CANDIDATE_POLICIES=$((TOTAL_CANDIDATE_POLICIES + 1))
    if [[ "${promote_to_module}" -eq 1 ]]; then
      if ! promote_policy_to_module "${namespace}" "${ingress_policy}"; then
        record_promotion_error "${PROMOTION_ERROR_MSG}"
      fi
    fi
  fi
  ingress_usable_rows="${LAST_POLICY_USABLE_ROWS}"

  info "${namespace}: generating egress candidate (mode=${egress_mode}, raw rows=${egress_raw_rows})"
  egress_policy_path="${policy_dir}/cnp-${namespace}-observed-egress-candidate.yaml"
  if generate_egress_policy "${namespace}" "${egress_mode}" "${egress_edges}" "${egress_world}" "${egress_policy_path}" "${egress_raw_rows}"; then
    egress_policy="${egress_policy_path}"
    TOTAL_CANDIDATE_POLICIES=$((TOTAL_CANDIDATE_POLICIES + 1))
    if [[ "${promote_to_module}" -eq 1 ]]; then
      if ! promote_policy_to_module "${namespace}" "${egress_policy}"; then
        record_promotion_error "${PROMOTION_ERROR_MSG}"
      fi
    fi
  fi
  egress_usable_rows="${LAST_POLICY_USABLE_ROWS}"

  generation_seconds=$((SECONDS - generation_started))
  rmdir "${policy_dir}" 2>/dev/null || true

  append_report_row \
    "${namespace}" \
    "ingress" \
    "${ingress_raw_rows}" \
    "${ingress_usable_rows}" \
    "${ingress_mode}" \
    "${ingress_policy}" \
    "${ingress_aggregate}" \
    "${CAPTURE_STRATEGY_REQUESTED}" \
    "${CAPTURE_STRATEGY_USED}" \
    "${CAPTURE_SAMPLE_TARGET}" \
    "${FILTERED_FLOW_COUNT}" \
    "${CAPTURE_FALLBACK_USED}" \
    "${CAPTURE_SECONDS}" \
    "${SUMMARY_SECONDS}" \
    "${generation_seconds}"

  append_report_row \
    "${namespace}" \
    "egress" \
    "${egress_raw_rows}" \
    "${egress_usable_rows}" \
    "${egress_mode}" \
    "${egress_policy}" \
    "${egress_aggregate}" \
    "${CAPTURE_STRATEGY_REQUESTED}" \
    "${CAPTURE_STRATEGY_USED}" \
    "${CAPTURE_SAMPLE_TARGET}" \
    "${FILTERED_FLOW_COUNT}" \
    "${CAPTURE_FALLBACK_USED}" \
    "${CAPTURE_SECONDS}" \
    "${SUMMARY_SECONDS}" \
    "${generation_seconds}"

  info "${namespace}: ingress raw=${ingress_raw_rows} usable=${ingress_usable_rows} candidate=$([[ -n "${ingress_policy}" ]] && printf present || printf omitted), egress raw=${egress_raw_rows} usable=${egress_usable_rows} candidate=$([[ -n "${egress_policy}" ]] && printf present || printf omitted)"
done < "${NAMESPACE_FILE}"

if [[ "${dry_run}" -eq 0 ]]; then
  rmdir "${output_dir}/policies" 2>/dev/null || true
  write_report_markdown "${output_dir}/run-report.md"
  if [[ "${TOTAL_CANDIDATE_POLICIES}" -eq 0 ]]; then
    warn "no candidate policies generated across ${NAMESPACES_SCANNED} namespace(s); widen --since, increase --iterations, or narrow --namespace"
  else
    info "generated ${TOTAL_CANDIDATE_POLICIES} candidate policies across ${NAMESPACES_SCANNED} namespace(s)"
  fi
  if [[ "${promote_to_module}" -eq 1 ]]; then
    if [[ "${PROMOTED_CANDIDATE_POLICIES}" -eq 0 ]]; then
      warn "no candidate policies promoted into ${module_root}"
    else
      info "promoted ${PROMOTED_CANDIDATE_POLICIES} candidate policies into ${module_root}"
    fi
  fi
  printf 'output dir: %s\n' "${output_dir}"
  printf 'report: %s\n' "${output_dir}/run-report.md"
fi

exit "${FINAL_EXIT_STATUS}"
