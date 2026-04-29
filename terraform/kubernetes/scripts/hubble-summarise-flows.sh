#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
  cat <<'EOF' | sed "1s|@SCRIPT_NAME@|${0##*/}|"
Usage: @SCRIPT_NAME@ [options]

Summarise Hubble `jsonpb` flow output into deterministic tables that are easier
to translate into Cilium policy source manifests.
The input is newline-delimited JSON from `hubble observe -o jsonpb`, not JSONP.

Input:
  Read JSON lines from stdin by default, or use --input FILE.

Reports:
  edges  Group traffic into source -> destination edges with port/protocol.
  world  Show only flows that touch `reserved:world`.
  dns    Summarise DNS queries and response codes.
  drops  Summarise dropped flows and drop reasons.

Options:
  -i, --input FILE
      Read Hubble JSON lines from FILE instead of stdin.

  --report edges|world|dns|drops
      Report to render. Default: edges

  --aggregate-by workload|pod
      Group workload traffic by stable workload name or by pod name.
      Default: workload

  --direction all|ingress|egress
      Keep only one traffic direction. Default: all

  --namespace NS
      Repeatable filter for flows where either side is in NS.

  --verdict VERDICT
      Repeatable verdict filter.

  --format text|table|tsv|csv
      Output format. Default: text
      `text` is a back-compat alias for `table`.
      `table` renders an aligned terminal table and shows empty cells as `-`.

  --table
      Convenience alias for `--format table`.

  --csv
      Convenience alias for `--format csv`.

  --top N
      Limit output rows after aggregation. Default: 50

  -h, --help
      Show this help text.

Examples:
  # Examples below assume you are already in terraform/kubernetes/scripts/.
  ./hubble-capture-flows.sh -P --kubeconfig ~/.kube/kind-kind-local.yaml --since 15m \
    --from-namespace dev --to-namespace observability \
    | ./hubble-summarise-flows.sh --report edges --aggregate-by workload --direction egress

  hubble observe -P --kubeconfig ~/.kube/kind-kind-local.yaml --since 15m -o jsonpb \
    --from-namespace dev --to-namespace kube-system \
    | ./hubble-summarise-flows.sh --report dns --aggregate-by pod
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

fail() {
  echo "hubble-summarise-flows.sh: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 not found in PATH"
}

render_output() {
  local input_file="$1"

  case "${format}" in
    text|table)
      if command -v column >/dev/null 2>&1; then
        awk '
          BEGIN { OFS = "\t" }
          {
            field_count = split($0, fields, "\t")
            for (i = 1; i <= field_count; i++) {
              if (fields[i] == "") {
                fields[i] = "-"
              }
            }

            for (i = 1; i <= field_count; i++) {
              printf "%s%s", fields[i], (i < field_count ? OFS : ORS)
            }
          }
        ' "${input_file}" | column -ts $'\t'
      else
        awk '
          BEGIN { OFS = "\t" }
          {
            field_count = split($0, fields, "\t")
            for (i = 1; i <= field_count; i++) {
              if (fields[i] == "") {
                fields[i] = "-"
              }
            }

            for (i = 1; i <= field_count; i++) {
              printf "%s%s", fields[i], (i < field_count ? OFS : ORS)
            }
          }
        ' "${input_file}"
      fi
      ;;
    csv)
      awk '
        function csv_escape(value,    escaped) {
          escaped = value
          gsub(/"/, "\"\"", escaped)
          if (escaped ~ /[",\r\n]/ || escaped ~ /^[[:space:]]/ || escaped ~ /[[:space:]]$/) {
            return "\"" escaped "\""
          }
          return escaped
        }

        {
          field_count = split($0, fields, "\t")
          for (i = 1; i <= field_count; i++) {
            printf "%s%s", csv_escape(fields[i]), (i < field_count ? "," : ORS)
          }
        }
      ' "${input_file}"
      ;;
    tsv)
      cat "${input_file}"
      ;;
  esac
}

input_path="-"
report="edges"
aggregate_by="workload"
direction="all"
format="text"
top_n="50"

declare -a namespaces=()
declare -a verdicts=()

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
    --report)
      report="${2:-}"
      shift 2
      ;;
    --aggregate-by)
      aggregate_by="${2:-}"
      shift 2
      ;;
    --direction)
      direction="${2:-}"
      shift 2
      ;;
    --namespace)
      namespaces+=("${2:-}")
      shift 2
      ;;
    --verdict)
      verdicts+=("${2:-}")
      shift 2
      ;;
    --format)
      format="${2:-}"
      shift 2
      ;;
    --table)
      format="table"
      shift
      ;;
    --csv)
      format="csv"
      shift
      ;;
    --top)
      top_n="${2:-}"
      shift 2
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

shell_cli_maybe_execute_or_preview_summary usage \
  "would summarise Hubble flows from ${input_path} with report=${report}, aggregate-by=${aggregate_by}, format=${format}"

case "${report}" in
  edges|world|dns|drops) ;;
  *)
    fail "unsupported --report value: ${report}"
    ;;
esac

case "${aggregate_by}" in
  workload|pod) ;;
  *)
    fail "unsupported --aggregate-by value: ${aggregate_by}"
    ;;
esac

case "${direction}" in
  all|ingress|egress) ;;
  *)
    fail "unsupported --direction value: ${direction}"
    ;;
esac

case "${format}" in
  text|table|tsv|csv) ;;
  *)
    fail "unsupported --format value: ${format}"
    ;;
esac

[[ "${top_n}" =~ ^[0-9]+$ ]] || fail "--top must be a non-negative integer"

require_cmd jq
require_cmd awk
require_cmd sort

tmp_jq="$(mktemp "${TMPDIR:-/tmp}/summarise-hubble.jq.XXXXXX")"
tmp_rows="$(mktemp "${TMPDIR:-/tmp}/summarise-hubble.rows.XXXXXX")"
tmp_agg="$(mktemp "${TMPDIR:-/tmp}/summarise-hubble.agg.XXXXXX")"
tmp_output="$(mktemp "${TMPDIR:-/tmp}/summarise-hubble.out.XXXXXX")"
trap 'rm -f "${tmp_jq}" "${tmp_rows}" "${tmp_agg}" "${tmp_output}"' EXIT

namespaces_blob=""
verdicts_blob=""

if [[ "${#namespaces[@]}" -gt 0 ]]; then
  namespaces_blob="$(printf '%s\n' "${namespaces[@]}")"
fi

if [[ "${#verdicts[@]}" -gt 0 ]]; then
  verdicts_blob="$(printf '%s\n' "${verdicts[@]}")"
fi

case "${report}" in
  edges)
    header=$'count\tdirection\tverdict\tprotocol\tsrc_ns\tsrc\tdst_class\tdst_ns\tdst\tdst_port'
    cat > "${tmp_jq}" <<'JQ'
def namespace_filters: ($namespaces | split("\n") | map(select(length > 0)));
def verdict_filters: ($verdicts | split("\n") | map(select(length > 0)));
def flow_obj: .flow // .;
def endpoint_namespace($ep): $ep.namespace // "";
def endpoint_pod($ep): $ep.pod_name // $ep.podName // "";
def endpoint_workload($ep):
  if $aggregate_by == "pod" then
    endpoint_pod($ep)
  else
    (($ep.workloads // [])[0].name // endpoint_pod($ep))
  end;
def endpoint_labels($ep): ($ep.labels // []);
def flow_ip($flow; $side):
  ($flow.IP // $flow.ip // {}) as $ip
  | if $side == "source" then ($ip.source // "") else ($ip.destination // "") end;
def flow_names($flow; $side):
  if $side == "source" then ($flow.source_names // $flow.sourceNames // [])
  else ($flow.destination_names // $flow.destinationNames // [])
  end;
def endpoint_class($flow; $ep; $side):
  if any(endpoint_labels($ep)[]?; . == "reserved:world") then "world"
  elif any(endpoint_labels($ep)[]?; . == "reserved:kube-apiserver") then "kube-apiserver"
  elif any(endpoint_labels($ep)[]?; . == "reserved:host") then "host"
  elif any(endpoint_labels($ep)[]?; . == "reserved:remote-node") then "remote-node"
  elif endpoint_namespace($ep) != "" then "workload"
  elif (flow_names($flow; $side) | length) > 0 then "name"
  elif flow_ip($flow; $side) != "" then "ip"
  else "unknown"
  end;
def endpoint_id($flow; $ep; $side):
  if endpoint_workload($ep) != "" then endpoint_workload($ep)
  elif endpoint_namespace($ep) != "" and endpoint_pod($ep) != "" then endpoint_pod($ep)
  elif (flow_names($flow; $side) | length) > 0 then (flow_names($flow; $side) | join(","))
  elif flow_ip($flow; $side) != "" then flow_ip($flow; $side)
  else endpoint_class($flow; $ep; $side)
  end;
def flow_protocol($flow):
  if (($flow.l7 // {}).http // null) != null then "http"
  elif (($flow.l7 // {}).dns // null) != null then "dns"
  elif (($flow.l4 // {}).TCP // null) != null then "tcp"
  elif (($flow.l4 // {}).UDP // null) != null then "udp"
  elif (($flow.l4 // {}).SCTP // null) != null then "sctp"
  elif (($flow.l4 // {}).ICMPv4 // null) != null then "icmpv4"
  elif (($flow.l4 // {}).ICMPv6 // null) != null then "icmpv6"
  else "unknown"
  end;
def destination_port($flow):
  if (($flow.l4 // {}).TCP // null) != null then (($flow.l4.TCP.destination_port // $flow.l4.TCP.destinationPort // 0) | tostring)
  elif (($flow.l4 // {}).UDP // null) != null then (($flow.l4.UDP.destination_port // $flow.l4.UDP.destinationPort // 0) | tostring)
  elif (($flow.l4 // {}).SCTP // null) != null then (($flow.l4.SCTP.destination_port // $flow.l4.SCTP.destinationPort // 0) | tostring)
  else ""
  end;
def direction_value($flow): ($flow.traffic_direction // $flow.trafficDirection // "UNKNOWN");
def direction_match($flow):
  if $direction == "all" then true
  else ((direction_value($flow) | ascii_downcase) == $direction)
  end;
def namespace_match($flow):
  (namespace_filters) as $ns
  | if ($ns | length) == 0 then true
    else (endpoint_namespace($flow.source // {}) as $src
      | endpoint_namespace($flow.destination // {}) as $dst
      | any($ns[]; . == $src or . == $dst))
    end;
def verdict_match($flow):
  (verdict_filters) as $filters
  | if ($filters | length) == 0 then true
    else any($filters[]; . == ($flow.verdict // ""))
    end;
inputs
| flow_obj as $flow
| select(($flow | type) == "object")
| select(direction_match($flow))
| select(namespace_match($flow))
| select(verdict_match($flow))
| [
    direction_value($flow),
    ($flow.verdict // ""),
    flow_protocol($flow),
    endpoint_namespace($flow.source // {}),
    endpoint_id($flow; $flow.source // {}; "source"),
    endpoint_class($flow; $flow.destination // {}; "destination"),
    endpoint_namespace($flow.destination // {}),
    endpoint_id($flow; $flow.destination // {}; "destination"),
    destination_port($flow)
  ]
| @tsv
JQ
    ;;
  world)
    header=$'count\tdirection\tverdict\tprotocol\tworld_side\tpeer_ns\tpeer\tworld_names\tworld_ip\tport'
    cat > "${tmp_jq}" <<'JQ'
def namespace_filters: ($namespaces | split("\n") | map(select(length > 0)));
def verdict_filters: ($verdicts | split("\n") | map(select(length > 0)));
def flow_obj: .flow // .;
def endpoint_namespace($ep): $ep.namespace // "";
def endpoint_pod($ep): $ep.pod_name // $ep.podName // "";
def endpoint_workload($ep):
  if $aggregate_by == "pod" then
    endpoint_pod($ep)
  else
    (($ep.workloads // [])[0].name // endpoint_pod($ep))
  end;
def endpoint_labels($ep): ($ep.labels // []);
def flow_ip($flow; $side):
  ($flow.IP // $flow.ip // {}) as $ip
  | if $side == "source" then ($ip.source // "") else ($ip.destination // "") end;
def flow_names($flow; $side):
  if $side == "source" then ($flow.source_names // $flow.sourceNames // [])
  else ($flow.destination_names // $flow.destinationNames // [])
  end;
def endpoint_class($flow; $ep; $side):
  if any(endpoint_labels($ep)[]?; . == "reserved:world") then "world"
  elif endpoint_namespace($ep) != "" then "workload"
  elif (flow_names($flow; $side) | length) > 0 then "name"
  elif flow_ip($flow; $side) != "" then "ip"
  else "unknown"
  end;
def endpoint_id($flow; $ep; $side):
  if endpoint_workload($ep) != "" then endpoint_workload($ep)
  elif endpoint_namespace($ep) != "" and endpoint_pod($ep) != "" then endpoint_pod($ep)
  elif (flow_names($flow; $side) | length) > 0 then (flow_names($flow; $side) | join(","))
  elif flow_ip($flow; $side) != "" then flow_ip($flow; $side)
  else endpoint_class($flow; $ep; $side)
  end;
def flow_protocol($flow):
  if (($flow.l7 // {}).http // null) != null then "http"
  elif (($flow.l7 // {}).dns // null) != null then "dns"
  elif (($flow.l4 // {}).TCP // null) != null then "tcp"
  elif (($flow.l4 // {}).UDP // null) != null then "udp"
  elif (($flow.l4 // {}).SCTP // null) != null then "sctp"
  elif (($flow.l4 // {}).ICMPv4 // null) != null then "icmpv4"
  elif (($flow.l4 // {}).ICMPv6 // null) != null then "icmpv6"
  else "unknown"
  end;
def source_port($flow):
  if (($flow.l4 // {}).TCP // null) != null then (($flow.l4.TCP.source_port // $flow.l4.TCP.sourcePort // 0) | tostring)
  elif (($flow.l4 // {}).UDP // null) != null then (($flow.l4.UDP.source_port // $flow.l4.UDP.sourcePort // 0) | tostring)
  elif (($flow.l4 // {}).SCTP // null) != null then (($flow.l4.SCTP.source_port // $flow.l4.SCTP.sourcePort // 0) | tostring)
  else ""
  end;
def destination_port($flow):
  if (($flow.l4 // {}).TCP // null) != null then (($flow.l4.TCP.destination_port // $flow.l4.TCP.destinationPort // 0) | tostring)
  elif (($flow.l4 // {}).UDP // null) != null then (($flow.l4.UDP.destination_port // $flow.l4.UDP.destinationPort // 0) | tostring)
  elif (($flow.l4 // {}).SCTP // null) != null then (($flow.l4.SCTP.destination_port // $flow.l4.SCTP.destinationPort // 0) | tostring)
  else ""
  end;
def direction_value($flow): ($flow.traffic_direction // $flow.trafficDirection // "UNKNOWN");
def direction_match($flow):
  if $direction == "all" then true
  else ((direction_value($flow) | ascii_downcase) == $direction)
  end;
def namespace_match($flow):
  (namespace_filters) as $ns
  | if ($ns | length) == 0 then true
    else (endpoint_namespace($flow.source // {}) as $src
      | endpoint_namespace($flow.destination // {}) as $dst
      | any($ns[]; . == $src or . == $dst))
    end;
def verdict_match($flow):
  (verdict_filters) as $filters
  | if ($filters | length) == 0 then true
    else any($filters[]; . == ($flow.verdict // ""))
    end;
inputs
| flow_obj as $flow
| select(($flow | type) == "object")
| select(direction_match($flow))
| select(namespace_match($flow))
| select(verdict_match($flow))
| (endpoint_class($flow; $flow.source // {}; "source")) as $src_class
| (endpoint_class($flow; $flow.destination // {}; "destination")) as $dst_class
| select($src_class == "world" or $dst_class == "world")
| if $dst_class == "world" then
    [
      direction_value($flow),
      ($flow.verdict // ""),
      flow_protocol($flow),
      "destination",
      endpoint_namespace($flow.source // {}),
      endpoint_id($flow; $flow.source // {}; "source"),
      (flow_names($flow; "destination") | join(",")),
      flow_ip($flow; "destination"),
      destination_port($flow)
    ]
  else
    [
      direction_value($flow),
      ($flow.verdict // ""),
      flow_protocol($flow),
      "source",
      endpoint_namespace($flow.destination // {}),
      endpoint_id($flow; $flow.destination // {}; "destination"),
      (flow_names($flow; "source") | join(",")),
      flow_ip($flow; "source"),
      source_port($flow)
    ]
  end
| @tsv
JQ
    ;;
  dns)
    header=$'count\tdirection\tverdict\tsrc_ns\tsrc\tdns_server\tquery\tqtypes\trcode'
    cat > "${tmp_jq}" <<'JQ'
def namespace_filters: ($namespaces | split("\n") | map(select(length > 0)));
def verdict_filters: ($verdicts | split("\n") | map(select(length > 0)));
def flow_obj: .flow // .;
def endpoint_namespace($ep): $ep.namespace // "";
def endpoint_pod($ep): $ep.pod_name // $ep.podName // "";
def endpoint_workload($ep):
  if $aggregate_by == "pod" then
    endpoint_pod($ep)
  else
    (($ep.workloads // [])[0].name // endpoint_pod($ep))
  end;
def endpoint_id($ep):
  if endpoint_workload($ep) != "" then endpoint_workload($ep)
  else endpoint_pod($ep)
  end;
def direction_value($flow): ($flow.traffic_direction // $flow.trafficDirection // "UNKNOWN");
def direction_match($flow):
  if $direction == "all" then true
  else ((direction_value($flow) | ascii_downcase) == $direction)
  end;
def namespace_match($flow):
  (namespace_filters) as $ns
  | if ($ns | length) == 0 then true
    else (endpoint_namespace($flow.source // {}) as $src
      | endpoint_namespace($flow.destination // {}) as $dst
      | any($ns[]; . == $src or . == $dst))
    end;
def verdict_match($flow):
  (verdict_filters) as $filters
  | if ($filters | length) == 0 then true
    else any($filters[]; . == ($flow.verdict // ""))
    end;
inputs
| flow_obj as $flow
| select(($flow | type) == "object")
| select(direction_match($flow))
| select(namespace_match($flow))
| select(verdict_match($flow))
| (($flow.l7 // {}).dns // null) as $dns
| select($dns != null)
| [
    direction_value($flow),
    ($flow.verdict // ""),
    endpoint_namespace($flow.source // {}),
    endpoint_id($flow.source // {}),
    ((endpoint_namespace($flow.destination // {}) + "/" + endpoint_id($flow.destination // {})) | ltrimstr("/")),
    ($dns.query // ""),
    (($dns.qtypes // $dns.q_types // []) | join(",")),
    ($dns.rcode // "")
  ]
| @tsv
JQ
    ;;
  drops)
    header=$'count\tdirection\tverdict\tdrop_reason\tprotocol\tsrc_ns\tsrc\tdst_class\tdst_ns\tdst\tdst_port'
    cat > "${tmp_jq}" <<'JQ'
def namespace_filters: ($namespaces | split("\n") | map(select(length > 0)));
def verdict_filters: ($verdicts | split("\n") | map(select(length > 0)));
def flow_obj: .flow // .;
def endpoint_namespace($ep): $ep.namespace // "";
def endpoint_pod($ep): $ep.pod_name // $ep.podName // "";
def endpoint_workload($ep):
  if $aggregate_by == "pod" then
    endpoint_pod($ep)
  else
    (($ep.workloads // [])[0].name // endpoint_pod($ep))
  end;
def endpoint_labels($ep): ($ep.labels // []);
def flow_ip($flow; $side):
  ($flow.IP // $flow.ip // {}) as $ip
  | if $side == "source" then ($ip.source // "") else ($ip.destination // "") end;
def flow_names($flow; $side):
  if $side == "source" then ($flow.source_names // $flow.sourceNames // [])
  else ($flow.destination_names // $flow.destinationNames // [])
  end;
def endpoint_class($flow; $ep; $side):
  if any(endpoint_labels($ep)[]?; . == "reserved:world") then "world"
  elif any(endpoint_labels($ep)[]?; . == "reserved:kube-apiserver") then "kube-apiserver"
  elif any(endpoint_labels($ep)[]?; . == "reserved:host") then "host"
  elif any(endpoint_labels($ep)[]?; . == "reserved:remote-node") then "remote-node"
  elif endpoint_namespace($ep) != "" then "workload"
  elif (flow_names($flow; $side) | length) > 0 then "name"
  elif flow_ip($flow; $side) != "" then "ip"
  else "unknown"
  end;
def endpoint_id($flow; $ep; $side):
  if endpoint_workload($ep) != "" then endpoint_workload($ep)
  elif endpoint_namespace($ep) != "" and endpoint_pod($ep) != "" then endpoint_pod($ep)
  elif (flow_names($flow; $side) | length) > 0 then (flow_names($flow; $side) | join(","))
  elif flow_ip($flow; $side) != "" then flow_ip($flow; $side)
  else endpoint_class($flow; $ep; $side)
  end;
def flow_protocol($flow):
  if (($flow.l7 // {}).http // null) != null then "http"
  elif (($flow.l7 // {}).dns // null) != null then "dns"
  elif (($flow.l4 // {}).TCP // null) != null then "tcp"
  elif (($flow.l4 // {}).UDP // null) != null then "udp"
  elif (($flow.l4 // {}).SCTP // null) != null then "sctp"
  elif (($flow.l4 // {}).ICMPv4 // null) != null then "icmpv4"
  elif (($flow.l4 // {}).ICMPv6 // null) != null then "icmpv6"
  else "unknown"
  end;
def destination_port($flow):
  if (($flow.l4 // {}).TCP // null) != null then (($flow.l4.TCP.destination_port // $flow.l4.TCP.destinationPort // 0) | tostring)
  elif (($flow.l4 // {}).UDP // null) != null then (($flow.l4.UDP.destination_port // $flow.l4.UDP.destinationPort // 0) | tostring)
  elif (($flow.l4 // {}).SCTP // null) != null then (($flow.l4.SCTP.destination_port // $flow.l4.SCTP.destinationPort // 0) | tostring)
  else ""
  end;
def direction_value($flow): ($flow.traffic_direction // $flow.trafficDirection // "UNKNOWN");
def direction_match($flow):
  if $direction == "all" then true
  else ((direction_value($flow) | ascii_downcase) == $direction)
  end;
def namespace_match($flow):
  (namespace_filters) as $ns
  | if ($ns | length) == 0 then true
    else (endpoint_namespace($flow.source // {}) as $src
      | endpoint_namespace($flow.destination // {}) as $dst
      | any($ns[]; . == $src or . == $dst))
    end;
def verdict_match($flow):
  (verdict_filters) as $filters
  | if ($filters | length) == 0 then true
    else any($filters[]; . == ($flow.verdict // ""))
    end;
inputs
| flow_obj as $flow
| select(($flow | type) == "object")
| select(direction_match($flow))
| select(namespace_match($flow))
| select(verdict_match($flow))
| select(($flow.verdict // "") == "DROPPED" or (($flow.drop_reason_desc // $flow.dropReasonDesc // "") != ""))
| [
    direction_value($flow),
    ($flow.verdict // ""),
    ($flow.drop_reason_desc // $flow.dropReasonDesc // ""),
    flow_protocol($flow),
    endpoint_namespace($flow.source // {}),
    endpoint_id($flow; $flow.source // {}; "source"),
    endpoint_class($flow; $flow.destination // {}; "destination"),
    endpoint_namespace($flow.destination // {}),
    endpoint_id($flow; $flow.destination // {}; "destination"),
    destination_port($flow)
  ]
| @tsv
JQ
    ;;
esac

if [[ "${input_path}" == "-" ]]; then
  jq -nr \
    --arg aggregate_by "${aggregate_by}" \
    --arg direction "${direction}" \
    --arg namespaces "${namespaces_blob}" \
    --arg verdicts "${verdicts_blob}" \
    -f "${tmp_jq}" < /dev/stdin > "${tmp_rows}"
else
  jq -nr \
    --arg aggregate_by "${aggregate_by}" \
    --arg direction "${direction}" \
    --arg namespaces "${namespaces_blob}" \
    --arg verdicts "${verdicts_blob}" \
    -f "${tmp_jq}" < "${input_path}" > "${tmp_rows}"
fi

if [[ ! -s "${tmp_rows}" ]]; then
  printf '%s\n' "${header}" > "${tmp_output}"
  render_output "${tmp_output}"
  echo "hubble-summarise-flows.sh: no matching flows" >&2
  exit 0
fi

LC_ALL=C sort "${tmp_rows}" \
  | uniq -c \
  | awk '{
      line = $0
      sub(/^ +/, "", line)
      count = line
      sub(/ .*/, "", count)
      sub(/^[0-9]+ +/, "", line)
      printf "%s\t%s\n", count, line
    }' \
  | LC_ALL=C sort -t $'\t' -k1,1nr -k2,2 -k3,3 -k4,4 -k5,5 -k6,6 \
  > "${tmp_agg}"

if [[ "${top_n}" != "0" ]]; then
  head -n "${top_n}" "${tmp_agg}" > "${tmp_output}"
  mv "${tmp_output}" "${tmp_agg}"
fi

printf '%s\n' "${header}" > "${tmp_output}"
cat "${tmp_agg}" >> "${tmp_output}"

render_output "${tmp_output}"
