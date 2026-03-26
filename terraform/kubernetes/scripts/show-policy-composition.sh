#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: show-policy-composition.sh [options]

Render a filterable view of the checked-in cluster policy composition.

Options:
  --target all|cilium|kyverno
      Policy tree to inspect. Default: all

  --format markdown|text
      Output format. Default: markdown

  --namespace all|shared|dev|uat|sit
      Limit the view to one overlay / namespace slice. Default: all

  --label TERM
      Repeatable case-insensitive substring filter applied to source paths,
      rendered resource names, and manifest content.

  --ingress
      Show only policies that define ingress or ingressDeny rules.

  --egress
      Show only policies that define egress or egressDeny rules.

Compatibility aliases:
  --overlay NAME
  --direction all|ingress|egress
  --match TERM

Examples:
  show-policy-composition.sh --target cilium --namespace dev --label sentiment --egress
  show-policy-composition.sh --target cilium --namespace uat --label deny --ingress
  show-policy-composition.sh --target kyverno --format text
EOF
}

TARGET="all"
FORMAT="markdown"
NAMESPACE="all"
DIRECTION="all"
LABEL_TERMS=()
LIST_SEP=$'\036'

set_direction() {
  local requested="$1"

  if [[ "${DIRECTION}" != "all" && "${DIRECTION}" != "${requested}" ]]; then
    echo "show-policy-composition: cannot combine --ingress and --egress" >&2
    exit 1
  fi

  DIRECTION="${requested}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      TARGET="${2:-}"
      shift 2
      ;;
    --format)
      FORMAT="${2:-}"
      shift 2
      ;;
    --namespace|--overlay)
      NAMESPACE="${2:-}"
      shift 2
      ;;
    --label|--match)
      LABEL_TERMS+=("${2:-}")
      shift 2
      ;;
    --direction)
      set_direction "${2:-}"
      shift 2
      ;;
    --ingress)
      set_direction "ingress"
      shift
      ;;
    --egress)
      set_direction "egress"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "show-policy-composition: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

case "${TARGET}" in
  all|cilium|kyverno) ;;
  *)
    echo "show-policy-composition: unsupported target: ${TARGET}" >&2
    exit 1
    ;;
esac

case "${FORMAT}" in
  markdown|text) ;;
  *)
    echo "show-policy-composition: unsupported format: ${FORMAT}" >&2
    exit 1
    ;;
esac

case "${NAMESPACE}" in
  all|shared|dev|uat|sit) ;;
  *)
    echo "show-policy-composition: unsupported namespace: ${NAMESPACE}" >&2
    exit 1
    ;;
esac

case "${DIRECTION}" in
  all|ingress|egress) ;;
  *)
    echo "show-policy-composition: unsupported direction: ${DIRECTION}" >&2
    exit 1
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
POLICY_ROOT="${REPO_ROOT}/terraform/kubernetes/cluster-policies"
DISPLAY_LABEL_STRIP_PREFIX=""
DISPLAY_LABEL_PREFIX_PATH=""
DISPLAY_LABEL_PREFIX_TARGET=""

read_kustomize_resources() {
  local dir="$1"
  local file="${dir}/kustomization.yaml"

  awk '
    $1 == "resources:" { in_resources = 1; next }
    in_resources && $1 == "-" {
      print $2
      next
    }
    in_resources && $1 !~ /^-/ { in_resources = 0 }
  ' "${file}"
}

normalize_path() {
  local path="$1"
  local dir
  local base

  if [[ -d "${path}" ]]; then
    (cd "${path}" && pwd -P)
    return
  fi

  dir="$(cd "$(dirname "${path}")" && pwd -P)"
  base="$(basename "${path}")"
  printf '%s/%s\n' "${dir}" "${base}"
}

collect_overlay_files() {
  local dir="$1"
  local resource
  local full_path

  while IFS= read -r resource; do
    [[ -n "${resource}" ]] || continue
    full_path="$(normalize_path "${dir}/${resource}")"
    if [[ -d "${full_path}" ]]; then
      collect_overlay_files "${full_path}"
    else
      printf '%s\n' "${full_path}"
    fi
  done < <(read_kustomize_resources "${dir}")
}

split_yaml_documents() {
  local file="$1"

  awk '
    BEGIN { doc = "" }
    /^[[:space:]]*---[[:space:]]*$/ {
      if (doc != "") {
        printf "%s%c", doc, 0
        doc = ""
      }
      next
    }
    { doc = doc $0 ORS }
    END {
      if (doc != "") {
        printf "%s%c", doc, 0
      }
    }
  ' "${file}"
}

extract_document_identity() {
  local document="$1"

  awk '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }

    /^[[:space:]]*kind:[[:space:]]*/ && kind == "" {
      value = $0
      sub(/^[[:space:]]*kind:[[:space:]]*/, "", value)
      kind = trim(value)
      next
    }

    /^[[:space:]]*metadata:[[:space:]]*$/ {
      in_metadata = 1
      next
    }

    in_metadata && /^[[:space:]]+name:[[:space:]]*/ && name == "" {
      value = $0
      sub(/^[[:space:]]*name:[[:space:]]*/, "", value)
      name = trim(value)
      gsub(/["'\'']/, "", name)
      print kind "|" name
      exit
    }

    in_metadata && /^[^[:space:]-]/ {
      in_metadata = 0
    }
  ' <<< "${document}"
}

matches_direction() {
  local document="$1"

  case "${DIRECTION}" in
    all)
      return 0
      ;;
    ingress)
      grep -Eiq '^[[:space:]]*(ingress|ingressDeny):' <<< "${document}"
      ;;
    egress)
      grep -Eiq '^[[:space:]]*(egress|egressDeny):' <<< "${document}"
      ;;
  esac
}

matches_terms() {
  local haystack="$1"
  local term

  for term in "${LABEL_TERMS[@]:-}"; do
    [[ -n "${term}" ]] || continue
    if ! grep -Fqi -- "${term}" <<< "${haystack}"; then
      return 1
    fi
  done

  return 0
}

collect_target_records() {
  local dir="$1"
  local overlay_name
  local full_path
  local relative_path
  local document
  local identity
  local kind
  local name
  local haystack

  while IFS= read -r overlay_name <&3; do
    [[ -n "${overlay_name}" ]] || continue
    if [[ "${NAMESPACE}" != "all" && "${NAMESPACE}" != "${overlay_name}" ]]; then
      continue
    fi

    while IFS= read -r full_path <&4; do
      [[ -n "${full_path}" ]] || continue
      relative_path="${full_path#"${REPO_ROOT}/"}"

      while IFS= read -r -d '' document <&5; do
        identity="$(extract_document_identity "${document}")"
        [[ -n "${identity}" ]] || continue

        if ! matches_direction "${document}"; then
          continue
        fi

        kind="${identity%%|*}"
        name="${identity#*|}"
        haystack="${overlay_name}
${relative_path}
${kind}
${name}
${document}"

        if ! matches_terms "${haystack}"; then
          continue
        fi

        printf '%s\t%s\t%s\t%s\n' "${overlay_name}" "${relative_path}" "${kind}" "${name}"
      done 5< <(split_yaml_documents "${full_path}")
    done 4< <(collect_overlay_files "${dir}/${overlay_name}")
  done 3< <(read_kustomize_resources "${dir}")
}

build_top_rows_from_records() {
  local records="$1"

  if [[ -z "${records}" ]]; then
    return 0
  fi

  printf '%s\n' "${records}" | awk -F '\t' -v listsep="${LIST_SEP}" '
    function has_entry(list, value,    parts, count, i) {
      if (list == "") {
        return 0
      }

      count = split(list, parts, listsep)
      for (i = 1; i <= count; i++) {
        if (parts[i] == value) {
          return 1
        }
      }

      return 0
    }

    function add_source(key, value) {
      if (sources[key] == "") {
        sources[key] = value
      } else if (!has_entry(sources[key], value)) {
        sources[key] = sources[key] listsep value
      }
    }

    NF == 4 {
      key = $3 "\t" $4
      if (!(key in seen)) {
        seen[key] = 1
      }
      add_source(key, $2)
    }

    END {
      for (key in seen) {
        split(key, parts, /\t/)
        printf "%s\t%s\t%s\n", parts[1], parts[2], sources[key]
      }
    }
  ' | sort -t "$(printf '\t')" -k1,1 -k2,2
}

build_overlay_rows_from_records() {
  local overlay_name="$1"
  local records="$2"

  if [[ -z "${records}" ]]; then
    return 0
  fi

  printf '%s\n' "${records}" | awk -F '\t' -v overlay="${overlay_name}" -v listsep="${LIST_SEP}" '
    function has_entry(list, value,    parts, count, i) {
      if (list == "") {
        return 0
      }

      count = split(list, parts, listsep)
      for (i = 1; i <= count; i++) {
        if (parts[i] == value) {
          return 1
        }
      }

      return 0
    }

    function add_source(key, value) {
      if (sources[key] == "") {
        sources[key] = value
      } else if (!has_entry(sources[key], value)) {
        sources[key] = sources[key] listsep value
      }
    }

    NF == 4 && $1 == overlay {
      key = $3 "\t" $4
      names[key] = 1
      add_source(key, $2)
    }

    END {
      for (key in names) {
        split(key, parts, /\t/)
        printf "%s\t%s\t%s\n", parts[1], parts[2], sources[key]
      }
    }
  ' | sort -t "$(printf '\t')" -k1,1 -k2,2
}

source_link_target() {
  local path="$1"

  printf './%s' "${path#terraform/kubernetes/cluster-policies/}"
}

display_source_label() {
  local path="$1"

  if [[ -n "${DISPLAY_LABEL_STRIP_PREFIX}" && "${path}" == "${DISPLAY_LABEL_STRIP_PREFIX}"* ]]; then
    printf '%s' "${path#"${DISPLAY_LABEL_STRIP_PREFIX}"}"
    return
  fi

  printf '%s' "${path}"
}

format_source_links() {
  local paths="$1"
  local path
  local label
  local first=1
  local expanded_paths

  expanded_paths="${paths//${LIST_SEP}/$'\n'}"

  while IFS= read -r path; do
    [[ -n "${path}" ]] || continue
    label="$(display_source_label "${path}")"

    if [[ "${FORMAT}" == "markdown" ]]; then
      if [[ "${first}" -eq 0 ]]; then
        printf '<br />'
      fi
      printf "[\`%s\`](%s)" "${label}" "$(source_link_target "${path}")"
    else
      printf '      source: %s\n' "${label}"
    fi

    first=0
  done <<< "${expanded_paths}"
}

print_name_source_row() {
  local name="$1"
  local sources="$2"

  case "${FORMAT}" in
    markdown)
      printf "| \`%s\` | " "${name}"
      if [[ -n "${sources}" ]]; then
        format_source_links "${sources}"
      else
        printf '_none_'
      fi
      printf ' |\n'
      ;;
    text)
      printf '  - %s\n' "${name}"
      if [[ -n "${sources}" ]]; then
        format_source_links "${sources}"
      fi
      ;;
  esac
}

print_rendered_section() {
  local title="$1"
  local resource_rows="$2"
  local kind
  local name
  local sources
  local current_kind=""
  local had_rows=0

  case "${FORMAT}" in
    markdown)
      printf '### %s\n\n' "${title}"
      ;;
    text)
      printf '%s\n' "${title}"
      ;;
  esac

  while IFS=$'\t' read -r kind name sources; do
    [[ -n "${kind}" ]] || continue
    had_rows=1

    if [[ "${kind}" != "${current_kind}" ]]; then
      if [[ -n "${current_kind}" ]]; then
        printf '\n'
      fi

      case "${FORMAT}" in
        markdown)
          printf '#### %s\n\n' "${kind}"
          printf '| Name | Source |\n'
          printf '| --- | --- |\n'
          ;;
        text)
          printf '  %s\n' "${kind}"
          ;;
      esac

      current_kind="${kind}"
    fi

    print_name_source_row "${name}" "${sources}"
  done <<< "${resource_rows}"

  if [[ "${had_rows}" -eq 0 ]]; then
    case "${FORMAT}" in
      markdown)
        printf '_none_\n'
        ;;
      text)
        printf '  - none\n'
        ;;
    esac
  fi

  printf '\n'
}

print_overlay_section() {
  local title="$1"
  local rows="$2"

  print_rendered_section "${title}" "${rows}"
}

print_target() {
  local name="$1"
  local dir="${POLICY_ROOT}/${name}"
  local display_name
  local records
  local top_rows
  local child
  local overlay_rows

  display_name="$(tr '[:lower:]' '[:upper:]' <<< "${name:0:1}")${name:1}"
  DISPLAY_LABEL_STRIP_PREFIX=""
  DISPLAY_LABEL_PREFIX_PATH=""
  DISPLAY_LABEL_PREFIX_TARGET=""

  if [[ "${name}" == "cilium" ]]; then
    DISPLAY_LABEL_STRIP_PREFIX="terraform/kubernetes/cluster-policies/cilium/"
    DISPLAY_LABEL_PREFIX_PATH="terraform/kubernetes/cluster-policies/cilium"
    DISPLAY_LABEL_PREFIX_TARGET="./cilium"
  fi

  case "${FORMAT}" in
    markdown)
      printf '## %s\n\n' "${display_name}"
      printf "Rendered from [\`%s\`](./%s) after filter application.\n\n" \
        "${dir#"${REPO_ROOT}/"}" "${name}"
      if [[ -n "${DISPLAY_LABEL_PREFIX_PATH}" ]]; then
        printf "Displayed policy source paths below are relative to [\`%s\`](%s).\n\n" \
          "${DISPLAY_LABEL_PREFIX_PATH}" "${DISPLAY_LABEL_PREFIX_TARGET}"
      fi
      ;;
    text)
      printf '%s\n\n' "${display_name}"
      printf 'Rendered from %s after filter application.\n\n' "${dir#"${REPO_ROOT}/"}"
      ;;
  esac

  records="$(collect_target_records "${dir}")"
  top_rows="$(build_top_rows_from_records "${records}")"
  print_rendered_section "Top-Level Rendered Set" "${top_rows}"

  while IFS= read -r child; do
    [[ -n "${child}" ]] || continue
    if [[ "${NAMESPACE}" != "all" && "${NAMESPACE}" != "${child}" ]]; then
      continue
    fi
    overlay_rows="$(build_overlay_rows_from_records "${child}" "${records}")"
    print_overlay_section "Overlay: ${child}" "${overlay_rows}"
  done < <(read_kustomize_resources "${dir}")
}

print_header() {
  local label_display

  if (( ${#LABEL_TERMS[@]} > 0 )); then
    label_display="${LABEL_TERMS[*]}"
  else
    label_display="none"
  fi

  cat <<EOF
# Policy Composition

Generated with [\`terraform/kubernetes/scripts/show-policy-composition.sh\`](../scripts/show-policy-composition.sh) using \`--target ${TARGET} --format ${FORMAT}\`.

This view answers three related questions:

- what the current checked-in policy composition includes after filter application
- which source files contribute each rendered resource
- which policies in each overlay survive the active slice

Important notes:

- this is a source-tree composition view, not a shipped stage-default view
- the checked-in sentiment policy set now models only the shipped SST path

Active filters:

- namespace: \`${NAMESPACE}\`
- direction: \`${DIRECTION}\`
- label terms: \`${label_display}\`

EOF
}

if [[ "${FORMAT}" == "markdown" ]]; then
  print_header
fi

if [[ "${TARGET}" == "all" || "${TARGET}" == "cilium" ]]; then
  print_target "cilium"
fi

if [[ "${TARGET}" == "all" || "${TARGET}" == "kyverno" ]]; then
  print_target "kyverno"
fi
