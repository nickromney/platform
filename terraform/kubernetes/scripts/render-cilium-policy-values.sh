#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../scripts/lib/shell-cli.sh"

usage() {
  cat <<'EOF'
Usage: render-cilium-policy-values.sh [options] <input-file|->

Convert raw Cilium policy manifests into the Helm values shape expected by
templates that render:

  metadata:
    ...
  specs:
    - ...

The input may be a single Cilium policy document or a multi-document YAML file.
When the input uses top-level `spec`, this script rewrites it to a one-item
`specs` list. Existing `specs` lists are passed through unchanged.

Paths are interpreted relative to the current working directory, not relative
to this script. Pass full paths when you want stable behavior across shells or
automation.

Options:
  -o, --output FILE
      Write output to FILE instead of stdout. FILE is cwd-relative unless you
      pass a full path.

  --list-key KEY
      Wrap the converted policies under KEY. Useful for multi-document inputs,
      for example `--list-key policies`.

  --wrap-key PATH
      Wrap the rendered output under a dot-separated key path. Useful when the
      target chart expects values nested under a higher-level key.
      Example: `--wrap-key networkPolicy`.

  --set-name NAME
      Override metadata.name. Only valid for single-document input.

  --set-namespace NAMESPACE
      Override metadata.namespace for namespaced CiliumNetworkPolicy input.
      Refuses to add a namespace to clusterwide input.

  --split-dir DIR
      Write one rendered output file per input document into DIR using
      `<index>-<metadata.name>.yaml` filenames. Incompatible with `--output`.
      DIR is cwd-relative unless you pass a full path.

  -h, --help
      Show this help text.

Examples:
  render-cilium-policy-values.sh \
    terraform/kubernetes/cluster-policies/cilium/shared/shared-baseline.yaml

  render-cilium-policy-values.sh --list-key policies \
    terraform/kubernetes/cluster-policies/cilium/projects/sentiment/sentiment-runtime.yaml

  render-cilium-policy-values.sh --list-key policies --wrap-key networkPolicy \
    terraform/kubernetes/cluster-policies/cilium/projects/sentiment/sentiment-runtime.yaml \
    > values.generated.yaml

  render-cilium-policy-values.sh --split-dir /tmp/cilium-values \
    terraform/kubernetes/cluster-policies/cilium/projects/sentiment/sentiment-runtime.yaml

  render-cilium-policy-values.sh --set-namespace karpenter \
    path/to/karpenter-cnp.yaml
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

fail() {
  echo "render-cilium-policy-values.sh: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 not found in PATH"
}

sanitize_filename() {
  local value="$1"
  value="$(printf '%s' "${value}" | sed -E 's/[^A-Za-z0-9._-]+/-/g; s/^[.-]+//; s/[.-]+$//')"
  if [[ -z "${value}" ]]; then
    value="policy"
  fi
  printf '%s\n' "${value}"
}

output_path=""
list_key=""
wrap_key=""
set_name=""
set_namespace=""
split_dir=""
input_path=""

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    -o|--output)
      output_path="${2:-}"
      shift 2
      ;;
    --list-key)
      list_key="${2:-}"
      shift 2
      ;;
    --wrap-key)
      wrap_key="${2:-}"
      shift 2
      ;;
    --set-name)
      set_name="${2:-}"
      shift 2
      ;;
    --set-namespace)
      set_namespace="${2:-}"
      shift 2
      ;;
    --split-dir)
      split_dir="${2:-}"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -)
      if [[ -n "${input_path}" ]]; then
        fail "only one input path is supported"
      fi
      input_path="-"
      shift
      ;;
    -*)
      echo "render-cilium-policy-values.sh: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ -n "${input_path}" ]]; then
        fail "only one input path is supported"
      fi
      input_path="$1"
      shift
      ;;
  esac
done

shell_cli_maybe_execute_or_preview_summary usage \
  "would render Cilium policy values from ${input_path:-<stdin or unspecified>}"

if [[ -z "${input_path}" ]]; then
  echo "render-cilium-policy-values.sh: missing input path" >&2
  usage >&2
  exit 2
fi

if [[ -n "${output_path}" && -n "${split_dir}" ]]; then
  fail "--output and --split-dir cannot be combined"
fi

require_cmd jq
require_cmd yq

slurp_docs_json() {
  local docs_json
  if [[ "${input_path}" == "-" ]]; then
    docs_json="$(yq eval-all -o=json '.' - | jq -sc '[.[] | select(. != null)]')" || fail "failed to parse YAML input"
  else
    docs_json="$(yq eval-all -o=json '.' "${input_path}" | jq -sc '[.[] | select(. != null)]')" || fail "failed to parse YAML input"
  fi
  printf '%s\n' "${docs_json}"
}

render_bundle_json() {
  local docs_json="$1"
  local jq_program_file

  jq_program_file="$(mktemp "${TMPDIR:-/tmp}/render-cilium.XXXXXX")"
  trap 'rm -f "${jq_program_file}"' RETURN

  cat > "${jq_program_file}" <<'JQ'
def fail($msg): error($msg);
def apply_wrap_key($path; $value):
  if $path == "" then $value
  else ($path | split(".")) as $parts
  | if any($parts[]; . == "") then fail("--wrap-key must be a dot-separated path with non-empty segments")
    else reduce ($parts | reverse[]) as $part ($value; {($part): .})
    end
  end;
def convert_doc($doc; $index):
  if ($doc | type) != "object" then fail("document \($index) is not a mapping") else null end
  | ($doc.kind // null) as $kind
  | if ($kind != "CiliumNetworkPolicy" and $kind != "CiliumClusterwideNetworkPolicy") then fail("document \($index) has unsupported kind \($kind|@json); expected CiliumNetworkPolicy or CiliumClusterwideNetworkPolicy") else null end
  | (($doc | has("spec")) and ($doc.spec != null)) as $has_spec
  | (($doc | has("specs")) and ($doc.specs != null)) as $has_specs
  | if (($has_spec | not) and ($has_specs | not)) then fail("document \($index) has neither spec nor specs")
    elif ($has_spec and $has_specs) then fail("document \($index) has both spec and specs; refusing ambiguous input")
    else null end
  | ($doc.metadata // {}) as $metadata0
  | if ($metadata0 | type) != "object" then fail("document \($index) metadata is not a mapping") else null end
  | ($metadata0
      | if $set_name != "" then .name = $set_name else . end
      | if ((.name // "") == "") then fail("document \($index) metadata.name is required") else . end
      | if $kind == "CiliumClusterwideNetworkPolicy" then
          if $set_namespace != "" then fail("--set-namespace cannot be used with CiliumClusterwideNetworkPolicy input") else del(.namespace) end
        elif $set_namespace != "" then .namespace = $set_namespace
        else . end
    ) as $metadata
  | if $has_specs and (($doc.specs | type) != "array") then fail("document \($index) specs must be a list") else null end
  | {metadata: $metadata, specs: (if $has_specs then $doc.specs else [$doc.spec] end)};

if ($set_name != "" and ($docs | length) != 1) then fail("--set-name only supports single-document input") else null end
| ($docs | to_entries | map(convert_doc(.value; (.key + 1)))) as $converted
| ($list_key | if . != "" then {(.): $converted} else if ($converted | length) == 1 then $converted[0] else $converted end end) as $result
| {converted: $converted, result: apply_wrap_key($wrap_key; $result)}
JQ

  jq -n \
    -f "${jq_program_file}" \
    --argjson docs "${docs_json}" \
    --arg list_key "${list_key}" \
    --arg wrap_key "${wrap_key}" \
    --arg set_name "${set_name}" \
    --arg set_namespace "${set_namespace}" \
    2>/dev/null || fail "failed to transform input"
}

compose_result_json() {
  local item_json="$1"

  jq -cn \
    --argjson item "${item_json}" \
    --arg list_key "${list_key}" \
    --arg wrap_key "${wrap_key}" \
    '
    def fail($msg): error($msg);
    def apply_wrap_key($path; $value):
      if $path == "" then $value
      else ($path | split(".")) as $parts
      | if any($parts[]; . == "") then fail("--wrap-key must be a dot-separated path with non-empty segments")
        else reduce ($parts | reverse[]) as $part ($value; {($part): .})
        end
      end;
    ($list_key | if . != "" then {(.): [$item]} else $item end) as $value
    | apply_wrap_key($wrap_key; $value)
    ' 2>/dev/null || fail "failed to compose rendered output"
}

emit_yaml() {
  local json_input="$1"
  printf '%s\n' "${json_input}" | yq -P '.' -
}

render() {
  local docs_json
  local bundle_json

  docs_json="$(slurp_docs_json)"
  if [[ "${docs_json}" == "[]" ]]; then
    fail "input did not contain any YAML documents"
  fi

  bundle_json="$(render_bundle_json "${docs_json}")"

  if [[ -n "${split_dir}" ]]; then
    local index=0
    mkdir -p "${split_dir}"
    while IFS= read -r item_json; do
      local index name filename path per_item_json
      index=$((index + 1))
      name="$(jq -r '.metadata.name' <<< "${item_json}")"
      filename="$(printf '%02d-%s.yaml' "${index}" "$(sanitize_filename "${name}")")"
      path="${split_dir}/${filename}"
      per_item_json="$(compose_result_json "${item_json}")"
      emit_yaml "${per_item_json}" > "${path}"
    done < <(jq -c '.converted[]' <<< "${bundle_json}")
  else
    emit_yaml "$(jq -c '.result' <<< "${bundle_json}")"
  fi
}

if [[ -n "${output_path}" ]]; then
  render > "${output_path}"
else
  render
fi
