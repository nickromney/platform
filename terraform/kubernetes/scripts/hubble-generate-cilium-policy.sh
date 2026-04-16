#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
  cat <<'EOF'
Usage: hubble-generate-cilium-policy.sh [options]

Generate draft Cilium module source manifests from
`hubble-summarise-flows.sh --report edges --aggregate-by workload --format tsv`
output, then render the equivalent `categories/` files.

The script is intentionally conservative:

- it only consumes edge summaries
- it resolves workload labels from the live cluster with `kubectl`
- it writes draft `CiliumNetworkPolicy` source manifests into
  `cilium-module/sources/<category>/`
- it renders the matching `cilium-module/categories/<category>/` file
- it skips pod-like or otherwise unresolvable workload rows with a warning
- it refuses to overwrite an existing source manifest unless `--force` is set

For local work in this repo, if `~/.kube/kind-kind-local.yaml` exists and
`KUBECONFIG` is not already set, that kubeconfig is used automatically for
label resolution so the generator follows the same local-cluster default as the
other Hubble helpers.

Kubernetes API access:
  selector resolution needs `get` on deployments, daemonsets, and statefulsets
  in every source and destination namespace referenced by the TSV input.

Input:
  Read TSV from stdin by default, or use --input FILE.

Options:
  -i, --input FILE
      Read summarised edge TSV from FILE instead of stdin.

  --category NAME
      Output category under `cilium-module/sources/` and `categories/`.
      Defaults to the destination namespace when the input contains exactly one.

  --module-root DIR, --output-root DIR
      Override the cilium-module output root directory.
      Generated files are written under:
      `<root>/sources/<category>/` and `<root>/categories/<category>/`
      Default:
      `terraform/kubernetes/cluster-policies/cilium/cilium-module`

  --policy-name NAME
      Override the generated metadata.name and filename stem.
      Only valid when the input produces a single destination
      workload+protocol+port policy group.

  --force
      Overwrite an existing source manifest.

  --kubeconfig FILE
      Kubeconfig for workload label resolution with `kubectl`.

  --kube-context NAME
      Kube context for workload label resolution with `kubectl`.

  -h, --help
      Show this help text.

Examples:
  # Generate a draft observability policy from a focused OTLP edge summary.
  ./hubble-capture-flows.sh \
    --since 30m \
    --from-namespace dev \
    --to-namespace observability \
    -- --port 4318 \
    | ./hubble-summarise-flows.sh \
        --report edges \
        --aggregate-by workload \
        --direction egress \
        --format tsv \
    | ./hubble-generate-cilium-policy.sh \
        --category observability \
        --policy-name cnp-observability-otel-collector-allow-tcp-4318-from-observed-workloads

  # Use the current kubectx-selected cluster on another machine.
  ./hubble-capture-flows.sh --since 15m --to-namespace observability \
    | ./hubble-summarise-flows.sh --report edges --aggregate-by workload --direction egress --format tsv \
    | ./hubble-generate-cilium-policy.sh --category observability
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

fail() {
  echo "hubble-generate-cilium-policy.sh: $*" >&2
  exit 1
}

warn() {
  echo "hubble-generate-cilium-policy.sh: $*" >&2
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

  for resource in deployments daemonsets statefulsets; do
    require_kubectl_permission "get" "${resource}" "${namespace}" "resolve stable workload selectors"
  done

  printf '%s\n' "${namespace}" >> "${SELECTOR_ACCESS_CHECKED_FILE}"
}

explain_multiple_policy_groups() {
  local groups_file="$1"
  local group_count="$2"
  local dst_ns=""
  local dst=""
  local protocol=""
  local dst_port=""

  printf 'hubble-generate-cilium-policy.sh: --policy-name only supports a single generated policy; this input expands to %s groups:\n' "${group_count}" >&2
  while IFS=$'\t' read -r dst_ns dst protocol dst_port; do
    [[ -n "${dst_ns}" ]] || continue
    printf 'hubble-generate-cilium-policy.sh:   - %s/%s %s/%s\n' \
      "${dst_ns}" \
      "${dst}" \
      "$(printf '%s' "${protocol}" | tr '[:lower:]' '[:upper:]')" \
      "${dst_port}" >&2
  done < "${groups_file}"

  cat >&2 <<'EOF'
hubble-generate-cilium-policy.sh: rerun without --policy-name to let the script auto-name each output, or narrow the capture/summary until only one destination workload+protocol+port group remains.
EOF
}

sanitize_filename() {
  local value="$1"
  value="$(printf '%s' "${value}" | sed -E 's/[^A-Za-z0-9._-]+/-/g; s/^[.-]+//; s/[.-]+$//; s/-+/-/g')"
  if [[ -z "${value}" ]]; then
    value="policy"
  fi
  printf '%s\n' "${value}"
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

resolve_selector() {
  local namespace="$1"
  local workload="$2"
  local cache_key="${namespace}/${workload}"
  local json=""
  local label_value=""
  local label_key=""
  local kind=""

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

  for kind in deployment daemonset statefulset; do
    if json="$("${KUBECTL_BASE[@]}" -n "${namespace}" get "${kind}" "${workload}" -o json 2>/dev/null)"; then
      break
    fi
    json=""
  done

  if [[ -z "${json}" ]]; then
    RESOLVE_ERROR_MSG="could not resolve workload ${namespace}/${workload} via deployment, daemonset, or statefulset"
    printf '%s\t%s\t\t\t%s\n' \
      "${cache_key}" \
      "error" \
      "${RESOLVE_ERROR_MSG}" >> "${SELECTOR_CACHE_FILE}"
    return 1
  fi

  for label_key in app.kubernetes.io/name k8s-app app; do
    label_value="$(printf '%s\n' "${json}" | jq -r --arg key "${label_key}" '.metadata.labels[$key] // empty')"
    if [[ -n "${label_value}" ]]; then
      RESOLVED_SELECTOR_KEY="${label_key}"
      RESOLVED_SELECTOR_VALUE="${label_value}"
      printf '%s\t%s\t%s\t%s\t\n' \
        "${cache_key}" \
        "ok" \
        "${label_key}" \
        "${label_value}" >> "${SELECTOR_CACHE_FILE}"
      return 0
    fi
  done

  RESOLVE_ERROR_MSG="could not find a stable selector label for ${namespace}/${workload}; tried app.kubernetes.io/name, k8s-app, and app"
  printf '%s\t%s\t\t\t%s\n' \
    "${cache_key}" \
    "error" \
    "${RESOLVE_ERROR_MSG}" >> "${SELECTOR_CACHE_FILE}"
  return 1
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

  IFS=$'\t' read -r SELECTOR_CACHE_STATUS_VALUE SELECTOR_CACHE_KEY_VALUE SELECTOR_CACHE_VALUE_VALUE SELECTOR_CACHE_ERROR_VALUE <<< "${cache_line}"
  return 0
}

write_source_manifest() {
  local source_file="$1"
  local policy_name="$2"
  local title="$3"
  local description="$4"
  local dst_ns="$5"
  local dst_selector_key="$6"
  local dst_selector_value="$7"
  local protocol_upper="$8"
  local dst_port="$9"
  local sources_file="${10}"
  local src_ns=""
  local src_workload=""
  local src_selector_key=""
  local src_selector_value=""

  {
    cat <<EOF
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: ${policy_name}
  namespace: ${dst_ns}
  annotations:
    "policies.cilium.io/title": "$(yaml_escape "${title}")"
    "platform.publiccloudexperiments.net/source-kind": "CiliumNetworkPolicy"
spec:
  description: >-
    $(yaml_escape "${description}")
  endpointSelector:
    matchLabels:
      "k8s:io.kubernetes.pod.namespace": "$(yaml_escape "${dst_ns}")"
      "k8s:$(yaml_escape "${dst_selector_key}")": "$(yaml_escape "${dst_selector_value}")"
  ingress:
    - fromEndpoints:
EOF

    while IFS=$'\t' read -r src_ns src_workload src_selector_key src_selector_value; do
      [[ -n "${src_ns}" ]] || continue
      cat <<EOF
        - matchLabels:
            "k8s:io.kubernetes.pod.namespace": "$(yaml_escape "${src_ns}")"
            "k8s:$(yaml_escape "${src_selector_key}")": "$(yaml_escape "${src_selector_value}")"
EOF
    done < "${sources_file}"

    cat <<EOF
      toPorts:
        - ports:
            - port: "$(yaml_escape "${dst_port}")"
              protocol: ${protocol_upper}
EOF
  } > "${source_file}"
}

input_path="-"
category=""
module_root=""
policy_name_override=""
force=0
kubeconfig=""
kube_context=""
DEFAULT_KIND_KUBECONFIG="${HOME}/.kube/kind-kind-local.yaml"
SELECTOR_ACCESS_CHECKED_FILE=""
SELECTOR_CACHE_FILE=""
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
    -i|--input)
      input_path="${2:-}"
      shift 2
      ;;
    --category)
      category="${2:-}"
      shift 2
      ;;
    --module-root|--output-root)
      module_root="${2:-}"
      shift 2
      ;;
    --policy-name)
      policy_name_override="${2:-}"
      shift 2
      ;;
    --force)
      force=1
      shift
      ;;
    --kubeconfig)
      kubeconfig="${2:-}"
      shift 2
      ;;
    --kube-context)
      kube_context="${2:-}"
      shift 2
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

shell_cli_maybe_execute_or_preview_summary usage \
  "would generate draft Cilium module policy manifests from ${input_path}"

require_cmd jq
require_cmd kubectl
require_cmd sort
require_cmd cut
require_cmd sed

REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"
RENDER_SCRIPT="${REPO_ROOT}/terraform/kubernetes/scripts/render-cilium-policy-values.sh"
MODULE_ROOT_DEFAULT="${REPO_ROOT}/terraform/kubernetes/cluster-policies/cilium/cilium-module"

if [[ -z "${module_root}" ]]; then
  module_root="${MODULE_ROOT_DEFAULT}"
fi

if [[ -z "${kubeconfig}" && -z "${KUBECONFIG:-}" && -f "${DEFAULT_KIND_KUBECONFIG}" ]]; then
  kubeconfig="${DEFAULT_KIND_KUBECONFIG}"
fi

module_root="$(cd "${module_root}" && pwd)"
[[ -d "${module_root}" ]] || fail "module root not found: ${module_root}"
[[ -x "${RENDER_SCRIPT}" ]] || fail "render-cilium-policy-values.sh not found at ${RENDER_SCRIPT}"

KUBECTL_BASE=(kubectl)
if [[ -n "${kubeconfig}" ]]; then
  KUBECTL_BASE+=(--kubeconfig "${kubeconfig}")
fi
if [[ -n "${kube_context}" ]]; then
  KUBECTL_BASE+=(--context "${kube_context}")
fi

tmp_input="$(mktemp "${TMPDIR:-/tmp}/hubble-generate-policy.input.XXXXXX")"
tmp_rows="$(mktemp "${TMPDIR:-/tmp}/hubble-generate-policy.rows.XXXXXX")"
tmp_groups="$(mktemp "${TMPDIR:-/tmp}/hubble-generate-policy.groups.XXXXXX")"
tmp_namespaces="$(mktemp "${TMPDIR:-/tmp}/hubble-generate-policy.namespaces.XXXXXX")"
SELECTOR_ACCESS_CHECKED_FILE="$(mktemp "${TMPDIR:-/tmp}/hubble-generate-policy.selector-access.XXXXXX")"
SELECTOR_CACHE_FILE="$(mktemp "${TMPDIR:-/tmp}/hubble-generate-policy.selector-cache.XXXXXX")"
trap 'rm -f "${tmp_input}" "${tmp_rows}" "${tmp_groups}" "${tmp_namespaces}" "${SELECTOR_ACCESS_CHECKED_FILE}" "${SELECTOR_CACHE_FILE}"' EXIT

if [[ "${input_path}" == "-" ]]; then
  cat > "${tmp_input}"
else
  cat "${input_path}" > "${tmp_input}"
fi

if ! grep -q $'\t' "${tmp_input}"; then
  fail "expected TSV input from hubble-summarise-flows.sh --format tsv"
fi

while IFS=$'\t' read -r count direction verdict protocol src_ns src dst_class dst_ns dst dst_port; do
  if [[ "${count}" == "count" && "${direction}" == "direction" ]]; then
    continue
  fi

  [[ -n "${count}" ]] || continue
  [[ "${verdict}" == "FORWARDED" ]] || continue
  [[ "${dst_class}" == "workload" ]] || continue
  [[ -n "${src_ns}" && -n "${src}" && -n "${dst_ns}" && -n "${dst}" && -n "${protocol}" && -n "${dst_port}" ]] || continue

  case "${protocol}" in
    tcp|udp|sctp) ;;
    *)
      continue
      ;;
  esac

  if is_ip_like "${src_ns}" || is_ip_like "${dst_ns}"; then
    continue
  fi

  case "${src}" in
    workload|name|ip|unknown)
      continue
      ;;
  esac

  case "${dst}" in
    workload|name|ip|unknown)
      continue
      ;;
  esac

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${dst_ns}" "${dst}" "${protocol}" "${dst_port}" "${src_ns}" "${src}" >> "${tmp_rows}"
done < "${tmp_input}"

if [[ ! -s "${tmp_rows}" ]]; then
  fail "no supported workload edges found in the summary input"
fi

sort -u "${tmp_rows}" -o "${tmp_rows}"
cut -f1-4 "${tmp_rows}" | sort -u > "${tmp_groups}"
cut -f1 "${tmp_rows}" | sort -u > "${tmp_namespaces}"
cut -f5 "${tmp_rows}" | sort -u >> "${tmp_namespaces}"
sort -u "${tmp_namespaces}" -o "${tmp_namespaces}"

if [[ -z "${category}" ]]; then
  if [[ "$(wc -l < "${tmp_namespaces}" | tr -d ' ')" != "1" ]]; then
    fail "--category is required when the input spans multiple destination namespaces"
  fi
  category="$(head -n 1 "${tmp_namespaces}")"
fi

while IFS= read -r selector_namespace; do
  [[ -n "${selector_namespace}" ]] || continue
  ensure_selector_resolution_access "${selector_namespace}"
done < "${tmp_namespaces}"

group_count="$(wc -l < "${tmp_groups}" | tr -d ' ')"
if [[ -n "${policy_name_override}" && "${group_count}" != "1" ]]; then
  explain_multiple_policy_groups "${tmp_groups}" "${group_count}"
  exit 1
fi

sources_dir="${module_root}/sources/${category}"
categories_dir="${module_root}/categories/${category}"
mkdir -p "${sources_dir}" "${categories_dir}"

generated_count=0
skipped_group_count=0
skipped_source_count=0
while IFS=$'\t' read -r dst_ns dst protocol dst_port; do
  [[ -n "${dst_ns}" ]] || continue

  tmp_sources_raw="$(mktemp "${TMPDIR:-/tmp}/hubble-generate-policy.sources.XXXXXX")"
  tmp_sources_resolved="$(mktemp "${TMPDIR:-/tmp}/hubble-generate-policy.sources-resolved.XXXXXX")"
  trap 'rm -f "${tmp_input}" "${tmp_rows}" "${tmp_groups}" "${tmp_namespaces}" "${tmp_sources_raw}" "${tmp_sources_resolved}" "${SELECTOR_ACCESS_CHECKED_FILE}" "${SELECTOR_CACHE_FILE}"' EXIT

  awk -F'\t' -v target_ns="${dst_ns}" -v target_dst="${dst}" -v target_proto="${protocol}" -v target_port="${dst_port}" '
    $1 == target_ns && $2 == target_dst && $3 == target_proto && $4 == target_port {
      print $5 "\t" $6
    }
  ' "${tmp_rows}" | sort -u > "${tmp_sources_raw}"

  protocol_lower="$(printf '%s' "${protocol}" | tr '[:upper:]' '[:lower:]')"
  protocol_upper="$(printf '%s' "${protocol}" | tr '[:lower:]' '[:upper:]')"

  if ! resolve_selector "${dst_ns}" "${dst}"; then
    warn "skipping ${dst_ns}/${dst} ${protocol_upper}/${dst_port}: ${RESOLVE_ERROR_MSG}"
    skipped_group_count=$((skipped_group_count + 1))
    rm -f "${tmp_sources_raw}" "${tmp_sources_resolved}"
    trap 'rm -f "${tmp_input}" "${tmp_rows}" "${tmp_groups}" "${tmp_namespaces}" "${SELECTOR_ACCESS_CHECKED_FILE}" "${SELECTOR_CACHE_FILE}"' EXIT
    continue
  fi
  dst_selector_key="${RESOLVED_SELECTOR_KEY}"
  dst_selector_value="${RESOLVED_SELECTOR_VALUE}"

  source_desc=""
  while IFS=$'\t' read -r src_ns src_workload; do
    [[ -n "${src_ns}" ]] || continue
    if ! resolve_selector "${src_ns}" "${src_workload}"; then
      warn "skipping source ${src_ns}/${src_workload} for ${dst_ns}/${dst} ${protocol_upper}/${dst_port}: ${RESOLVE_ERROR_MSG}"
      skipped_source_count=$((skipped_source_count + 1))
      continue
    fi
    printf '%s\t%s\t%s\t%s\n' \
      "${src_ns}" "${src_workload}" "${RESOLVED_SELECTOR_KEY}" "${RESOLVED_SELECTOR_VALUE}" >> "${tmp_sources_resolved}"

    if [[ -n "${source_desc}" ]]; then
      source_desc="${source_desc}, "
    fi
    source_desc="${source_desc}${src_ns}/${src_workload}"
  done < "${tmp_sources_raw}"

  if [[ ! -s "${tmp_sources_resolved}" ]]; then
    warn "skipping ${dst_ns}/${dst} ${protocol_upper}/${dst_port}: no resolvable source workloads remained after filtering"
    skipped_group_count=$((skipped_group_count + 1))
    rm -f "${tmp_sources_raw}" "${tmp_sources_resolved}"
    trap 'rm -f "${tmp_input}" "${tmp_rows}" "${tmp_groups}" "${tmp_namespaces}" "${SELECTOR_ACCESS_CHECKED_FILE}" "${SELECTOR_CACHE_FILE}"' EXIT
    continue
  fi

  if [[ -n "${policy_name_override}" ]]; then
    policy_name="${policy_name_override}"
  else
    policy_name="$(sanitize_filename "cnp-${category}-${dst}-allow-${protocol_lower}-${dst_port}-from-observed-workloads")"
  fi

  title_category="$(title_case_words "${category}")"
  title="${title_category} allow ${protocol_upper} ${dst_port} to ${dst} from observed workloads"
  description="Observed via Hubble edge summary as ${protocol_upper} ingress into ${dst_ns}/${dst} on ${dst_port}/${protocol_upper} from ${source_desc}."

  source_file="${sources_dir}/${policy_name}.yaml"
  rendered_file="${categories_dir}/${policy_name}.yaml"

  if [[ -f "${source_file}" && "${force}" -ne 1 ]]; then
    fail "source manifest already exists: ${source_file} (rerun with --force to overwrite)"
  fi

  write_source_manifest \
    "${source_file}" \
    "${policy_name}" \
    "${title}" \
    "${description}" \
    "${dst_ns}" \
    "${dst_selector_key}" \
    "${dst_selector_value}" \
    "${protocol_upper}" \
    "${dst_port}" \
    "${tmp_sources_resolved}"

  "${RENDER_SCRIPT}" --execute --output "${rendered_file}" "${source_file}"

  printf 'generated source: %s\n' "${source_file}"
  printf 'rendered category: %s\n' "${rendered_file}"
  generated_count=$((generated_count + 1))

  rm -f "${tmp_sources_raw}" "${tmp_sources_resolved}"
  trap 'rm -f "${tmp_input}" "${tmp_rows}" "${tmp_groups}" "${tmp_namespaces}" "${SELECTOR_ACCESS_CHECKED_FILE}" "${SELECTOR_CACHE_FILE}"' EXIT
done < "${tmp_groups}"

[[ "${generated_count}" -gt 0 ]] || fail "no policies were generated"

if [[ "${skipped_group_count}" -gt 0 || "${skipped_source_count}" -gt 0 ]]; then
  warn "generated ${generated_count} policies; skipped ${skipped_group_count} groups and ${skipped_source_count} source entries that could not be resolved to stable workload selectors"
fi
