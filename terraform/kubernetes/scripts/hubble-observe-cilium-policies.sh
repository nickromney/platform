#!/usr/bin/env bash
set -euo pipefail

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
  --since DURATION
      Capture horizon for each iteration. Default: 5m

  --iterations N
      Number of capture rounds per namespace. Default: 3

  --sleep-between SECONDS
      Sleep this many seconds between iterations. Default: 0

  --row-threshold N
      Workload-summary row threshold before falling back to namespace/entity
      aggregation for a direction. Default: 100

  --capture-mode flows|policy-verdict
      Capture ordinary traffic flows (default) or only policy-verdict events.

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
EOF
}

fail() {
  echo "hubble-observe-cilium-policies.sh: $*" >&2
  exit 1
}

warn() {
  echo "hubble-observe-cilium-policies.sh: $*" >&2
}

info() {
  echo "hubble-observe-cilium-policies.sh: $*" >&2
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

  if [[ -n "${SELECTOR_ACCESS_CHECKED[${namespace}]+x}" ]]; then
    return 0
  fi

  for resource in deployments daemonsets statefulsets pods replicasets; do
    require_kubectl_permission "get" "${resource}" "${namespace}" "resolve stable workload selectors"
  done

  SELECTOR_ACCESS_CHECKED["${namespace}"]=1
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

resolve_selector() {
  local namespace="$1"
  local workload="$2"
  local json=""
  local label_value=""
  local label_key=""
  local kind=""
  local pod_json=""
  local owner_kind=""
  local owner_name=""
  local rs_json=""

  ensure_selector_resolution_access "${namespace}"

  for kind in deployment daemonset statefulset; do
    if json="$("${KUBECTL_BASE[@]}" -n "${namespace}" get "${kind}" "${workload}" -o json 2>/dev/null)"; then
      break
    fi
    json=""
  done

  if [[ -z "${json}" ]] && pod_json="$("${KUBECTL_BASE[@]}" -n "${namespace}" get pod "${workload}" -o json 2>/dev/null)"; then
    owner_kind="$(printf '%s\n' "${pod_json}" | jq -r '.metadata.ownerReferences[0].kind // empty' | tr '[:upper:]' '[:lower:]')"
    owner_name="$(printf '%s\n' "${pod_json}" | jq -r '.metadata.ownerReferences[0].name // empty')"

    if [[ "${owner_kind}" == "replicaset" && -n "${owner_name}" ]]; then
      rs_json="$("${KUBECTL_BASE[@]}" -n "${namespace}" get replicaset "${owner_name}" -o json 2>/dev/null || true)"
      if [[ -n "${rs_json}" ]]; then
        owner_kind="$(printf '%s\n' "${rs_json}" | jq -r '.metadata.ownerReferences[0].kind // empty' | tr '[:upper:]' '[:lower:]')"
        owner_name="$(printf '%s\n' "${rs_json}" | jq -r '.metadata.ownerReferences[0].name // empty')"
      fi
    fi

    case "${owner_kind}" in
      deployment|daemonset|statefulset)
        json="$("${KUBECTL_BASE[@]}" -n "${namespace}" get "${owner_kind}" "${owner_name}" -o json 2>/dev/null || true)"
        ;;
    esac
  fi

  if [[ -z "${json}" ]]; then
    RESOLVE_ERROR_MSG="could not resolve workload ${namespace}/${workload} via deployment, daemonset, statefulset, or pod owner"
    return 1
  fi

  for label_key in app.kubernetes.io/name k8s-app app; do
    label_value="$(printf '%s\n' "${json}" | jq -r --arg key "${label_key}" '.metadata.labels[$key] // empty')"
    if [[ -n "${label_value}" ]]; then
      RESOLVED_SELECTOR_KEY="${label_key}"
      RESOLVED_SELECTOR_VALUE="${label_value}"
      return 0
    fi
  done

  RESOLVE_ERROR_MSG="could not find a stable selector label for ${namespace}/${workload}; tried app.kubernetes.io/name, k8s-app, and app"
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

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${namespace}" \
    "${direction}" \
    "${raw_row_count}" \
    "${usable_row_count}" \
    "${mode}" \
    "${policy_file}" \
    "${aggregate_file}" >> "${REPORT_ROWS_FILE}"
}

discover_namespaces() {
  local discovered_file="$1"
  local namespace=""
  local excluded=0
  local candidate_file

  candidate_file="$(mktemp "${TMPDIR:-/tmp}/hubble-audit-namespaces.XXXXXX")"
  trap 'rm -f "${candidate_file}"' RETURN

  if [[ "${#namespaces[@]}" -gt 0 ]]; then
    for namespace in "${namespaces[@]}"; do
      [[ -n "${namespace}" ]] || continue

      excluded=0
      for value in "${excluded_namespaces[@]}"; do
        if [[ "${namespace}" == "${value}" ]]; then
          excluded=1
          break
        fi
      done
      if [[ "${excluded}" -eq 1 ]]; then
        continue
      fi

      printf '%s\n' "${namespace}" >> "${candidate_file}"
    done

    sort -u "${candidate_file}" -o "${candidate_file}"
    cat "${candidate_file}" > "${discovered_file}"
    return 0
  fi

  require_kubectl_permission "list" "namespaces" "" "discover namespaces when --namespace is not provided"

  "${KUBECTL_BASE[@]}" get namespaces -o json \
    | jq -r '.items[].metadata.name' \
    | sort -u > "${candidate_file}"

  while IFS= read -r namespace; do
    [[ -n "${namespace}" ]] || continue

    excluded=0
    for value in "${excluded_namespaces[@]}"; do
      if [[ "${namespace}" == "${value}" ]]; then
        excluded=1
        break
      fi
    done
    if [[ "${excluded}" -eq 1 ]]; then
      continue
    fi

    printf '%s\n' "${namespace}" >> "${discovered_file}"
  done < "${candidate_file}"
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

capture_namespace_iteration() {
  local namespace="$1"
  local iteration="$2"
  local output_file="$3"
  local capture_cmd=("${CAPTURE_SCRIPT}")
  local capture_err=""

  capture_cmd+=(--since "${since_value}")
  capture_cmd+=(--namespace "${namespace}")
  if [[ "${capture_mode}" == "policy-verdict" ]]; then
    capture_cmd+=(--type policy-verdict)
  fi
  capture_cmd+=(--port-forward-port "${port_forward_port}")

  if [[ -n "${kubeconfig}" ]]; then
    capture_cmd+=(--kubeconfig "${kubeconfig}")
  fi
  if [[ -n "${kube_context}" ]]; then
    capture_cmd+=(--kube-context "${kube_context}")
  fi
  if [[ "${print_command}" -eq 1 ]]; then
    capture_cmd+=(--print-command)
  fi

  if [[ "${dry_run}" -eq 1 ]]; then
    printf '%s\n' "capture ${namespace} iteration ${iteration}: ${capture_cmd[*]}"
    return 0
  fi

  capture_err="$(mktemp "${TMPDIR:-/tmp}/hubble-observe-capture.XXXXXX")"
  trap 'rm -f "${capture_err}"' RETURN

  if ! "${capture_cmd[@]}" > "${output_file}" 2> "${capture_err}"; then
    if [[ -s "${capture_err}" ]]; then
      cat "${capture_err}" >&2
    fi
    return 1
  fi

  if [[ -s "${capture_err}" ]]; then
    emit_capture_stderr "${capture_err}"
  fi
}

summarise_direction() {
  local input_file="$1"
  local direction="$2"
  local report="$3"
  local output_file="$4"
  local summary_cmd=("${SUMMARIZE_SCRIPT}")
  local summary_err=""

  summary_cmd+=(--input "${input_file}")
  summary_cmd+=(--report "${report}")
  summary_cmd+=(--aggregate-by workload)
  summary_cmd+=(--direction "${direction}")
  summary_cmd+=(--format tsv)
  summary_cmd+=(--top 0)
  summary_cmd+=(--verdict FORWARDED)

  summary_err="$(mktemp "${TMPDIR:-/tmp}/hubble-observe-summary.XXXXXX")"
  trap 'rm -f "${summary_err}"' RETURN

  if ! "${summary_cmd[@]}" > "${output_file}" 2> "${summary_err}"; then
    if [[ -s "${summary_err}" ]]; then
      cat "${summary_err}" >&2
    fi
    return 1
  fi

  if [[ -s "${summary_err}" ]]; then
    emit_summary_stderr "${summary_err}"
  fi
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

build_namespace_aggregate_report() {
  local namespace="$1"
  local direction="$2"
  local edges_file="$3"
  local world_file="$4"
  local output_file="$5"
  local tmp_rows

  tmp_rows="$(mktemp "${TMPDIR:-/tmp}/hubble-audit-aggregate.XXXXXX")"
  trap 'rm -f "${tmp_rows}"' RETURN

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
        printf '%s\t%s\t%s\t%s\t%s\n' "${count}" "${direction}" "${protocol}" "namespace" "${src_ns}:${dst_port}" >> "${tmp_rows}"
      elif is_host_peer_ip "${src}"; then
        printf '%s\t%s\t%s\t%s\t%s\n' "${count}" "${direction}" "${protocol}" "host" "host:${dst_port}" >> "${tmp_rows}"
      fi
    else
      [[ "${src_ns}" == "${namespace}" ]] || continue
      [[ "${dst_class}" == "workload" ]] || continue
      if [[ -n "${dst_ns}" ]]; then
        printf '%s\t%s\t%s\t%s\t%s\n' "${count}" "${direction}" "${protocol}" "namespace" "${dst_ns}:${dst_port}" >> "${tmp_rows}"
      elif is_host_peer_ip "${dst}"; then
        printf '%s\t%s\t%s\t%s\t%s\n' "${count}" "${direction}" "${protocol}" "host" "host:${dst_port}" >> "${tmp_rows}"
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
      printf '%s\t%s\t%s\t%s\t%s\n' "${count}" "${direction}" "${protocol}" "world" "world:${port}" >> "${tmp_rows}"
    else
      [[ "${world_side}" == "destination" && "${peer_ns}" == "${namespace}" ]] || continue
      printf '%s\t%s\t%s\t%s\t%s\n' "${count}" "${direction}" "${protocol}" "world" "world:${port}" >> "${tmp_rows}"
    fi
  done < <(tsv_rows "${world_file}")

  {
    printf 'count\tdirection\tprotocol\tpeer_class\tpeer\tport\n'
    if [[ -s "${tmp_rows}" ]]; then
      awk -F'\t' '
        {
          key = $2 FS $3 FS $4 FS $5
          counts[key] += $1
        }
        END {
          for (key in counts) {
            split(key, parts, FS)
            split(parts[4], peer_parts, ":")
        printf "%s\t%s\t%s\t%s\t%s\t%s\n", counts[key], parts[1], parts[2], parts[3], peer_parts[1], peer_parts[2]
      }
    }
      ' "${tmp_rows}" | LC_ALL=C sort -t $'\t' -k1,1nr -k2,2 -k3,3 -k4,4 -k5,5
    fi
  } > "${output_file}"
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

  tmp_entries="$(mktemp "${TMPDIR:-/tmp}/hubble-audit-ingress-entries.XXXXXX")"
  tmp_rules="$(mktemp "${TMPDIR:-/tmp}/hubble-audit-ingress-rules.XXXXXX")"
  tmp_group="$(mktemp "${TMPDIR:-/tmp}/hubble-audit-ingress-group.XXXXXX")"
  tmp_used_entries="$(mktemp "${TMPDIR:-/tmp}/hubble-audit-ingress-used.XXXXXX")"
  trap 'rm -f "${tmp_entries}" "${tmp_rules}" "${tmp_group}" "${tmp_used_entries}"' RETURN
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
        warn "skipping ingress target ${namespace}/${dst}: ${RESOLVE_ERROR_MSG}"
        continue
      fi
      target_selector_key="${RESOLVED_SELECTOR_KEY}"
      target_selector_value="${RESOLVED_SELECTOR_VALUE}"

      if [[ -n "${src_ns}" ]]; then
        is_ip_like "${src_ns}" && continue
        if ! resolve_selector "${src_ns}" "${src}"; then
          warn "skipping ingress source ${src_ns}/${src} for ${namespace}/${dst}: ${RESOLVE_ERROR_MSG}"
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
        warn "skipping ingress target ${namespace}/${peer}: ${RESOLVE_ERROR_MSG}"
        continue
      fi

      printf '%s\t%s\t%s\t%s\tworld\t\t\t\n' \
        "${RESOLVED_SELECTOR_KEY}" \
        "${RESOLVED_SELECTOR_VALUE}" \
        "${protocol}" \
        "${port}" >> "${tmp_entries}"
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
        awk -F'\t' -v key="${target_selector_key}" -v val="${target_selector_value}" -v p="${protocol}" -v d="${port}" -v k="${kind}" '
          $1 == key && $2 == val && $3 == p && $4 == d && $5 == k {
            print $6 "\t" $7 "\t" $8
          }
        ' "${tmp_entries}" | sort -u > "${tmp_group}"
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
        printf '%s\t%s\tnamespace\t%s\t\t\t\n' \
          "${protocol}" \
          "${dst_port}" \
          "${src_ns}" >> "${tmp_entries}"
      elif is_host_peer_ip "${src}"; then
        printf '%s\t%s\thost\t\t\t\t\n' "${protocol}" "${dst_port}" >> "${tmp_entries}"
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

      printf '%s\t%s\tworld\t\t\t\t\n' "${protocol}" "${port}" >> "${tmp_entries}"
    done < <(tsv_rows "${world_file}")

    if [[ ! -s "${tmp_entries}" ]]; then
      return 1
    fi

    sort -u "${tmp_entries}" -o "${tmp_entries}"

    policy_name="$(sanitize_filename "cnp-${namespace}-observed-ingress-candidate")"
    title="$(title_case_words "${namespace}") observed ingress candidate"
    write_namespace_policy_header "${policy_file}" "${policy_name}" "${namespace}" "${title}" "ingress" "${mode}" "${row_count}"

    : > "${tmp_rules}"
    while IFS=$'\t' read -r protocol port kind peer_ns _ _ _; do
      [[ -n "${protocol}" && -n "${port}" && -n "${kind}" ]] || continue
      awk -F'\t' -v p="${protocol}" -v d="${port}" -v k="${kind}" '
        $1 == p && $2 == d && $3 == k { print $4 "\t" $5 "\t" $6 }
      ' "${tmp_entries}" | sort -u > "${tmp_group}"
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
    return 1
  fi

  LAST_POLICY_USABLE_ROWS="${usable_row_count}"
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

  tmp_entries="$(mktemp "${TMPDIR:-/tmp}/hubble-audit-egress-entries.XXXXXX")"
  tmp_rules="$(mktemp "${TMPDIR:-/tmp}/hubble-audit-egress-rules.XXXXXX")"
  tmp_group="$(mktemp "${TMPDIR:-/tmp}/hubble-audit-egress-group.XXXXXX")"
  tmp_used_entries="$(mktemp "${TMPDIR:-/tmp}/hubble-audit-egress-used.XXXXXX")"
  trap 'rm -f "${tmp_entries}" "${tmp_rules}" "${tmp_group}" "${tmp_used_entries}"' RETURN
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
        warn "skipping egress source ${namespace}/${src}: ${RESOLVE_ERROR_MSG}"
        continue
      fi
      source_selector_key="${RESOLVED_SELECTOR_KEY}"
      source_selector_value="${RESOLVED_SELECTOR_VALUE}"

      if [[ -n "${dst_ns}" ]]; then
        is_ip_like "${dst_ns}" && continue
        if ! resolve_selector "${dst_ns}" "${dst}"; then
          warn "skipping egress destination ${dst_ns}/${dst} for ${namespace}/${src}: ${RESOLVE_ERROR_MSG}"
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
        warn "skipping egress source ${namespace}/${peer}: ${RESOLVE_ERROR_MSG}"
        continue
      fi

      printf '%s\t%s\t%s\t%s\tworld\t\t\t\n' \
        "${RESOLVED_SELECTOR_KEY}" \
        "${RESOLVED_SELECTOR_VALUE}" \
        "${protocol}" \
        "${port}" >> "${tmp_entries}"
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
        awk -F'\t' -v key="${source_selector_key}" -v val="${source_selector_value}" -v p="${protocol}" -v d="${port}" -v k="${kind}" '
          $1 == key && $2 == val && $3 == p && $4 == d && $5 == k {
            print $6 "\t" $7 "\t" $8
          }
        ' "${tmp_entries}" | sort -u > "${tmp_group}"
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
        printf '%s\t%s\tnamespace\t%s\t\t\t\n' \
          "${protocol}" \
          "${dst_port}" \
          "${dst_ns}" >> "${tmp_entries}"
      elif is_host_peer_ip "${dst}"; then
        printf '%s\t%s\thost\t\t\t\t\n' "${protocol}" "${dst_port}" >> "${tmp_entries}"
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

      printf '%s\t%s\tworld\t\t\t\t\n' "${protocol}" "${port}" >> "${tmp_entries}"
    done < <(tsv_rows "${world_file}")

    if [[ ! -s "${tmp_entries}" ]]; then
      return 1
    fi

    sort -u "${tmp_entries}" -o "${tmp_entries}"

    policy_name="$(sanitize_filename "cnp-${namespace}-observed-egress-candidate")"
    title="$(title_case_words "${namespace}") observed egress candidate"
    write_namespace_policy_header "${policy_file}" "${policy_name}" "${namespace}" "${title}" "egress" "${mode}" "${row_count}"

    : > "${tmp_rules}"
    while IFS=$'\t' read -r protocol port kind peer_ns _ _ _; do
      [[ -n "${protocol}" && -n "${port}" && -n "${kind}" ]] || continue
      awk -F'\t' -v p="${protocol}" -v d="${port}" -v k="${kind}" '
        $1 == p && $2 == d && $3 == k { print $4 "\t" $5 "\t" $6 }
      ' "${tmp_entries}" | sort -u > "${tmp_group}"
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
    return 1
  fi

  LAST_POLICY_USABLE_ROWS="${usable_row_count}"
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

  {
    printf '# Hubble Policy Observation\n\n'
    printf -- "- Since: \`%s\`\n" "${since_value}"
    printf -- "- Iterations: \`%s\`\n" "${iterations}"
    printf -- "- Sleep between: \`%s\` seconds\n" "${sleep_between}"
    printf -- "- Row threshold: \`%s\`\n" "${row_threshold}"
    printf -- "- Capture mode: \`%s\`, reply traffic removed\n" "${capture_mode}"
    printf -- "- Output root: \`%s\`\n\n" "${output_dir}"
    if [[ "${promote_to_module}" -eq 1 ]]; then
      printf -- "- Module promotion: enabled -> \`%s\`\n\n" "${module_root}"
    fi

    while IFS=$'\t' read -r namespace direction raw_row_count usable_row_count mode policy_file aggregate_file; do
      [[ -n "${namespace}" ]] || continue
      printf '## %s %s\n\n' "${namespace}" "${direction}"
      printf -- "- Raw summary rows: \`%s\`\n" "${raw_row_count}"
      printf -- "- Policy-usable rows: \`%s\`\n" "${usable_row_count}"
      printf -- "- Generation mode: \`%s\`\n" "${mode}"
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

  [[ -n "${policy_file}" ]] || return 0

  source_dir="${module_root}/sources/${namespace}"
  category_dir="${module_root}/categories/${namespace}"
  source_file="${source_dir}/$(basename "${policy_file}")"
  category_file="${category_dir}/$(basename "${policy_file}")"

  mkdir -p "${source_dir}" "${category_dir}"

  if [[ -e "${source_file}" ]]; then
    if cmp -s "${policy_file}" "${source_file}"; then
      :
    elif [[ "${force_module_overwrite}" -eq 1 ]]; then
      cp "${policy_file}" "${source_file}"
    else
      fail "module source already exists and differs: ${source_file} (rerun with --force-module-overwrite to replace it)"
    fi
  else
    cp "${policy_file}" "${source_file}"
  fi

  "${RENDER_VALUES_SCRIPT}" --output "${category_file}" "${source_file}"
  PROMOTED_CANDIDATE_POLICIES=$((PROMOTED_CANDIDATE_POLICIES + 1))
}

since_value="5m"
iterations="3"
sleep_between="0"
row_threshold="100"
capture_mode="flows"
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
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
CAPTURE_SCRIPT="${SCRIPT_DIR}/hubble-capture-flows.sh"
SUMMARIZE_SCRIPT="${SCRIPT_DIR}/hubble-summarise-flows.sh"
RENDER_VALUES_SCRIPT="${SCRIPT_DIR}/render-cilium-policy-values.sh"
DEFAULT_MODULE_ROOT="${REPO_ROOT}/terraform/kubernetes/cluster-policies/cilium/cilium-module"

declare -a namespaces=()
declare -a excluded_namespaces=()
declare -A SELECTOR_ACCESS_CHECKED=()
LAST_POLICY_USABLE_ROWS=0
NAMESPACES_SCANNED=0
TOTAL_CANDIDATE_POLICIES=0
PROMOTED_CANDIDATE_POLICIES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --since)
      since_value="${2:-}"
      shift 2
      ;;
    --iterations)
      iterations="${2:-}"
      shift 2
      ;;
    --sleep-between)
      sleep_between="${2:-}"
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
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

[[ "${iterations}" =~ ^[0-9]+$ ]] || fail "--iterations must be a non-negative integer"
[[ "${sleep_between}" =~ ^[0-9]+$ ]] || fail "--sleep-between must be a non-negative integer"
[[ "${row_threshold}" =~ ^[0-9]+$ ]] || fail "--row-threshold must be a non-negative integer"
case "${capture_mode}" in
  flows|policy-verdict) ;;
  *)
    fail "--capture-mode must be one of: flows, policy-verdict"
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
trap 'rm -f "${REPORT_ROWS_FILE}" "${NAMESPACE_FILE}" "${HOST_IP_FILE}"' EXIT

if [[ "${dry_run}" -eq 0 ]]; then
  mkdir -p "${output_dir}"
fi

discover_namespaces "${NAMESPACE_FILE}"
discover_host_peer_ips
[[ -s "${NAMESPACE_FILE}" ]] || fail "no namespaces matched the requested filters"

while IFS= read -r namespace; do
  [[ -n "${namespace}" ]] || continue
  NAMESPACES_SCANNED=$((NAMESPACES_SCANNED + 1))
  if [[ "${dry_run}" -eq 0 ]]; then
    info "observing namespace ${namespace}"
  fi

  namespace_dir="${output_dir}/namespaces/${namespace}"
  policy_dir="${output_dir}/policies/${namespace}"
  combined_raw="${namespace_dir}/combined.jsonl"
  filtered_raw="${namespace_dir}/combined.non-reply.jsonl"
  report_file="${output_dir}/run-report.md"

  if [[ "${dry_run}" -eq 0 ]]; then
    mkdir -p "${namespace_dir}" "${policy_dir}"
    : > "${combined_raw}"
  fi

  iteration_index=1
  while [[ "${iteration_index}" -le "${iterations}" ]]; do
    iteration_capture="${namespace_dir}/capture-${iteration_index}.jsonl"
    capture_namespace_iteration "${namespace}" "${iteration_index}" "${iteration_capture}"

    if [[ "${dry_run}" -eq 0 ]]; then
      cat "${iteration_capture}" >> "${combined_raw}"
    fi

    if [[ "${sleep_between}" -gt 0 && "${iteration_index}" -lt "${iterations}" ]]; then
      sleep "${sleep_between}"
    fi
    iteration_index=$((iteration_index + 1))
  done

  if [[ "${dry_run}" -eq 1 ]]; then
    append_report_row "${namespace}" "ingress" "0" "0" "dry-run" "" ""
    append_report_row "${namespace}" "egress" "0" "0" "dry-run" "" ""
    continue
  fi

  filter_capture_non_reply "${combined_raw}" "${filtered_raw}"

  ingress_edges="${namespace_dir}/ingress.edges.workload.tsv"
  egress_edges="${namespace_dir}/egress.edges.workload.tsv"
  ingress_world="${namespace_dir}/ingress.world.tsv"
  egress_world="${namespace_dir}/egress.world.tsv"

  summarise_direction "${filtered_raw}" "ingress" "edges" "${ingress_edges}"
  summarise_direction "${filtered_raw}" "egress" "edges" "${egress_edges}"
  summarise_direction "${filtered_raw}" "ingress" "world" "${ingress_world}"
  summarise_direction "${filtered_raw}" "egress" "world" "${egress_world}"

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

  ingress_policy_path="${policy_dir}/cnp-${namespace}-observed-ingress-candidate.yaml"
  if generate_ingress_policy "${namespace}" "${ingress_mode}" "${ingress_edges}" "${ingress_world}" "${ingress_policy_path}" "${ingress_raw_rows}"; then
    ingress_policy="${ingress_policy_path}"
    TOTAL_CANDIDATE_POLICIES=$((TOTAL_CANDIDATE_POLICIES + 1))
    if [[ "${promote_to_module}" -eq 1 ]]; then
      promote_policy_to_module "${namespace}" "${ingress_policy}"
    fi
  fi
  ingress_usable_rows="${LAST_POLICY_USABLE_ROWS}"

  egress_policy_path="${policy_dir}/cnp-${namespace}-observed-egress-candidate.yaml"
  if generate_egress_policy "${namespace}" "${egress_mode}" "${egress_edges}" "${egress_world}" "${egress_policy_path}" "${egress_raw_rows}"; then
    egress_policy="${egress_policy_path}"
    TOTAL_CANDIDATE_POLICIES=$((TOTAL_CANDIDATE_POLICIES + 1))
    if [[ "${promote_to_module}" -eq 1 ]]; then
      promote_policy_to_module "${namespace}" "${egress_policy}"
    fi
  fi
  egress_usable_rows="${LAST_POLICY_USABLE_ROWS}"

  rmdir "${policy_dir}" 2>/dev/null || true
  append_report_row "${namespace}" "ingress" "${ingress_raw_rows}" "${ingress_usable_rows}" "${ingress_mode}" "${ingress_policy}" "${ingress_aggregate}"
  append_report_row "${namespace}" "egress" "${egress_raw_rows}" "${egress_usable_rows}" "${egress_mode}" "${egress_policy}" "${egress_aggregate}"

  if [[ "${dry_run}" -eq 0 ]]; then
    info "${namespace}: ingress raw=${ingress_raw_rows} usable=${ingress_usable_rows} candidate=$([[ -n "${ingress_policy}" ]] && printf present || printf omitted), egress raw=${egress_raw_rows} usable=${egress_usable_rows} candidate=$([[ -n "${egress_policy}" ]] && printf present || printf omitted)"
  fi
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
