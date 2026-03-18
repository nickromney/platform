#!/usr/bin/env bash
set -euo pipefail

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
}

output_path=""
list_key=""
wrap_key=""
set_name=""
set_namespace=""
split_dir=""
input_path=""

while [[ $# -gt 0 ]]; do
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
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "render-cilium-policy-values.sh: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ -n "${input_path}" ]]; then
        echo "render-cilium-policy-values.sh: only one input path is supported" >&2
        exit 2
      fi
      input_path="$1"
      shift
      ;;
  esac
done

if [[ -z "${input_path}" ]]; then
  echo "render-cilium-policy-values.sh: missing input path" >&2
  usage >&2
  exit 2
fi

if [[ -n "${output_path}" && -n "${split_dir}" ]]; then
  echo "render-cilium-policy-values.sh: --output and --split-dir cannot be combined" >&2
  exit 2
fi

render() {
  python3 - "${input_path}" "${list_key}" "${wrap_key}" "${set_name}" "${set_namespace}" "${split_dir}" <<'PY'
import copy
import os
import re
import sys
import yaml


def fail(message: str) -> None:
    print(f"render-cilium-policy-values.sh: {message}", file=sys.stderr)
    raise SystemExit(1)


class DoubleQuotedWhenNeededDumper(yaml.SafeDumper):
    """Prefer double quotes in cases where scalar quoting is required."""

    def choose_scalar_style(self):
        if self.analysis is None:
            self.analysis = self.analyze_scalar(self.event.value)
        if self.event.style == '"' or self.canonical:
            return '"'
        if not self.event.style and self.event.implicit[0]:
            if (
                not (self.simple_key_context and (self.analysis.empty or self.analysis.multiline))
                and (
                    (self.flow_level and self.analysis.allow_flow_plain)
                    or (not self.flow_level and self.analysis.allow_block_plain)
                )
            ):
                return ""
        if self.event.style and self.event.style in "|>":
            if not self.flow_level and not self.simple_key_context and self.analysis.allow_block:
                return self.event.style
        return '"'


def sanitize_filename(value: str) -> str:
    sanitized = re.sub(r"[^A-Za-z0-9._-]+", "-", value).strip("-.")
    return sanitized or "policy"


def apply_wrap_key(value, path: str):
    if not path:
        return value

    parts = path.split(".")
    if any(not part for part in parts):
        fail("--wrap-key must be a dot-separated path with non-empty segments")

    wrapped = value
    for part in reversed(parts):
        wrapped = {part: wrapped}
    return wrapped


def dump_yaml(value, handle) -> None:
    yaml.dump(value, handle, Dumper=DoubleQuotedWhenNeededDumper, sort_keys=False)


input_path, list_key, wrap_key, set_name, set_namespace, split_dir = sys.argv[1:7]

if input_path == "-":
    raw = sys.stdin.read()
else:
    with open(input_path, "r", encoding="utf-8") as handle:
        raw = handle.read()

docs = [doc for doc in yaml.safe_load_all(raw) if doc is not None]
if not docs:
    fail("input did not contain any YAML documents")

if set_name and len(docs) != 1:
    fail("--set-name only supports single-document input")

converted = []
for index, doc in enumerate(docs, start=1):
    if not isinstance(doc, dict):
        fail(f"document {index} is not a mapping")

    kind = doc.get("kind")
    if kind not in {"CiliumNetworkPolicy", "CiliumClusterwideNetworkPolicy"}:
        fail(
            f"document {index} has unsupported kind {kind!r}; "
            "expected CiliumNetworkPolicy or CiliumClusterwideNetworkPolicy"
        )

    has_spec = "spec" in doc and doc.get("spec") is not None
    has_specs = "specs" in doc and doc.get("specs") is not None
    if not has_spec and not has_specs:
        fail(f"document {index} has neither spec nor specs")
    if has_spec and has_specs:
        fail(f"document {index} has both spec and specs; refusing ambiguous input")

    metadata = copy.deepcopy(doc.get("metadata") or {})
    if not isinstance(metadata, dict):
        fail(f"document {index} metadata is not a mapping")

    if set_name:
        metadata["name"] = set_name

    if "name" not in metadata or not metadata["name"]:
        fail(f"document {index} metadata.name is required")

    if kind == "CiliumClusterwideNetworkPolicy":
        if set_namespace:
            fail("--set-namespace cannot be used with CiliumClusterwideNetworkPolicy input")
        metadata.pop("namespace", None)
    elif set_namespace:
        metadata["namespace"] = set_namespace

    if has_specs:
        specs = copy.deepcopy(doc["specs"])
        if not isinstance(specs, list):
            fail(f"document {index} specs must be a list")
    else:
        specs = [copy.deepcopy(doc["spec"])]

    converted.append(
        {
            "metadata": metadata,
            "specs": specs,
        }
    )

if list_key:
    result = {list_key: converted}
else:
    result = converted[0] if len(converted) == 1 else converted

result = apply_wrap_key(result, wrap_key)

if split_dir:
    os.makedirs(split_dir, exist_ok=True)
    for index, item in enumerate(converted, start=1):
        per_item = {list_key: [item]} if list_key else item
        per_item = apply_wrap_key(per_item, wrap_key)
        filename = f"{index:02d}-{sanitize_filename(item['metadata']['name'])}.yaml"
        path = os.path.join(split_dir, filename)
        with open(path, "w", encoding="utf-8") as handle:
            dump_yaml(per_item, handle)
else:
    dump_yaml(result, sys.stdout)
PY
}

if [[ -n "${output_path}" ]]; then
  render > "${output_path}"
else
  render
fi
