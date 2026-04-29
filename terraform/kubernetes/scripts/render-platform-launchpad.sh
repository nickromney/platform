#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"
STACK_DIR="${STACK_DIR:-${REPO_ROOT}/terraform/kubernetes}"
INVENTORY_FILE="${INVENTORY_FILE:-${STACK_DIR}/config/platform-launchpad.apps.json}"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

MARKER_START="codex:platform-launchpad:start"
MARKER_END="codex:platform-launchpad:end"

TARGETS=()

usage() {
  cat <<'EOF' | sed "1s|@SCRIPT_NAME@|${0##*/}|"
Usage: @SCRIPT_NAME@ [--target <path>]...

Renders the Platform Launchpad dashboard JSON from a small tile inventory and
replaces the generated block in target files between marker comments.

Markers required in each target:
  # codex:platform-launchpad:start
  ...
  # codex:platform-launchpad:end

Environment variables:
  STACK_DIR         Stack root (default: inferred from script path)
  INVENTORY_FILE    Launchpad inventory JSON file
  ENABLE_SSO
  ENABLE_HEADLAMP
  ENABLE_APP_REPO_SENTIMENT
  ENABLE_APP_REPO_SUBNETCALC
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

is_true() {
  case "${1:-}" in
    true|TRUE|1|yes|YES|y|Y) return 0 ;;
    *) return 1 ;;
  esac
}

parse_args() {
  shell_cli_init_standard_flags
  while [[ $# -gt 0 ]]; do
    if shell_cli_handle_standard_flag usage "$1"; then
      shift
      continue
    fi

    case "$1" in
      --target)
        [[ $# -ge 2 ]] || { echo "missing value for --target" >&2; exit 1; }
        TARGETS+=("$2")
        shift 2
        ;;
      *)
        echo "unknown flag: $1" >&2
        usage
        exit 1
        ;;
    esac
  done
}

build_toggles_json() {
  local enable_sso=false
  local enable_headlamp=false
  local enable_sentiment=false
  local enable_subnetcalc=false

  if is_true "${ENABLE_SSO:-true}"; then enable_sso=true; fi
  if is_true "${ENABLE_HEADLAMP:-true}"; then enable_headlamp=true; fi
  if is_true "${ENABLE_APP_REPO_SENTIMENT:-true}"; then enable_sentiment=true; fi
  if is_true "${ENABLE_APP_REPO_SUBNETCALC:-true}"; then enable_subnetcalc=true; fi

  jq -cn \
    --argjson sso "${enable_sso}" \
    --argjson headlamp "${enable_headlamp}" \
    --argjson sentiment "${enable_sentiment}" \
    --argjson subnetcalc "${enable_subnetcalc}" \
    '{
      ENABLE_SSO: $sso,
      ENABLE_HEADLAMP: $headlamp,
      ENABLE_APP_REPO_SENTIMENT: $sentiment,
      ENABLE_APP_REPO_SUBNETCALC: $subnetcalc
    }'
}

generate_dashboard_json() {
  local toggles_json="$1"
  jq \
    --argjson toggles "${toggles_json}" \
    '
    def x_of($idx): ($idx % 4) * 6;
    def y_of($idx): 3 + ((($idx / 4) | floor) * 5);
    def stat_panel($tile; $idx):
      {
        datasource: "Prometheus",
        description: $tile.url,
        fieldConfig: {
          defaults: {
            color: {mode: "thresholds"},
            mappings: [
              {
                options: {
                  "0": {text: "Down"},
                  "1": {text: "Healthy"}
                },
                type: "value"
              }
            ],
            max: 1,
            min: 0,
            thresholds: {
              mode: "absolute",
              steps: [
                {color: "red", value: 0},
                {color: "green", value: 1}
              ]
            },
            unit: "short"
          }
        },
        gridPos: {h: 5, w: 6, x: x_of($idx), y: y_of($idx)},
        id: ($idx + 2),
        links: [
          {targetBlank: true, title: ("Open " + $tile.title), url: $tile.url}
        ],
        options: {colorMode: "background", graphMode: "none"},
        targets: [{expr: $tile.expr, refId: "A"}],
        title: $tile.title,
        type: "stat"
      };

    {
      annotations: {list: []},
      editable: true,
      graphTooltip: 0,
      panels:
        ([
          {
            gridPos: {h: 3, w: 24, x: 0, y: 0},
            id: 1,
            options: {
              content: "## Platform Launchpad\nClick a tile to open the app or dashboard URL. Health uses deployment readiness with Argo CD fallback where possible.",
              mode: "markdown"
            },
            title: "Entry Points",
            type: "text"
          }
        ] +
        (
          [
            .tiles[]
            | select(((.requires // []) | all($toggles[.] == true)))
          ]
          | sort_by(.sort_key)
          | to_entries
          | map(stat_panel(.value; .key))
        )),
      refresh: "30s",
      schemaVersion: 39,
      tags: ["platform", "launchpad", "entrypoints"],
      templating: {
        list: [
          {
            name: "prometheus",
            type: "datasource",
            query: "prometheus",
            current: {selected: false, value: "Prometheus"}
          }
        ]
      },
      time: {from: "now-15m", to: "now"},
      title: "Platform Launchpad",
      uid: "platform-launchpad"
    }
    ' \
    "${INVENTORY_FILE}"
}

build_section() {
  local dashboard_json="$1"
  cat <<EOF
            # ${MARKER_START}
            platform-launchpad:
              json: |
$(printf '%s\n' "${dashboard_json}" | sed 's/^/                /')
            # ${MARKER_END}
EOF
}

replace_marked_section() {
  local file="$1"
  local rendered_section="$2"
  local start_line
  local end_line
  local tmp_file

  [[ -f "${file}" ]] || { echo "target not found: ${file}" >&2; return 1; }

  start_line="$(grep -n "${MARKER_START}" "${file}" | head -n1 | cut -d: -f1 || true)"
  end_line="$(grep -n "${MARKER_END}" "${file}" | head -n1 | cut -d: -f1 || true)"

  [[ -n "${start_line}" ]] || { echo "missing marker '${MARKER_START}' in ${file}" >&2; return 1; }
  [[ -n "${end_line}" ]] || { echo "missing marker '${MARKER_END}' in ${file}" >&2; return 1; }
  [[ "${start_line}" -lt "${end_line}" ]] || { echo "invalid marker order in ${file}" >&2; return 1; }

  tmp_file="$(mktemp)"
  if (( start_line > 1 )); then
    head -n "$((start_line - 1))" "${file}" > "${tmp_file}"
  else
    : > "${tmp_file}"
  fi
  printf '%s\n' "${rendered_section}" >> "${tmp_file}"
  tail -n "+$((end_line + 1))" "${file}" >> "${tmp_file}"
  mv "${tmp_file}" "${file}"
}

main() {
  parse_args "$@"

  shell_cli_maybe_execute_or_preview_summary usage \
    "would render the Platform Launchpad dashboard into ${#TARGETS[@]} target file(s)"

  if [[ ! -f "${INVENTORY_FILE}" ]]; then
    echo "inventory file not found: ${INVENTORY_FILE}" >&2
    exit 1
  fi

  if [[ "${#TARGETS[@]}" -eq 0 ]]; then
    TARGETS=(
      "${STACK_DIR}/apps/argocd-apps/95-grafana.application.yaml"
      "${STACK_DIR}/observability.tf"
    )
  fi

  local toggles_json
  local dashboard_json
  local section
  toggles_json="$(build_toggles_json)"
  dashboard_json="$(generate_dashboard_json "${toggles_json}")"
  section="$(build_section "${dashboard_json}")"

  for target in "${TARGETS[@]}"; do
    replace_marked_section "${target}" "${section}"
  done
}

main "$@"
