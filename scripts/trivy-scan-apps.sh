#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TRIVY_RUNNER="${SCRIPT_DIR}/trivy-run.sh"
REPORT_ROOT="${TRIVY_REPORT_ROOT:-${REPO_ROOT}/.run/apps-security/trivy}"
CLONE_ROOT="${REPORT_ROOT}/gitea-clones"
mode="all"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/shell-cli.sh"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/platform-env.sh"
platform_load_env

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/trivy-common.sh"

TRIVY_SEVERITY="${TRIVY_SEVERITY:-HIGH,CRITICAL}"
TRIVY_FS_SCANNERS="${TRIVY_FS_SCANNERS:-vuln,misconfig,secret}"
TRIVY_IMAGE_SCANNERS="${TRIVY_IMAGE_SCANNERS:-vuln,secret}"
TRIVY_TIMEOUT="${TRIVY_TIMEOUT:-20m}"
TRIVY_IGNORE_UNFIXED="${TRIVY_IGNORE_UNFIXED:-1}"
SCAN_GITEA="${SCAN_GITEA:-0}"
TRIVY_SKIP_DIRS=(
  node_modules
  .venv
  dist
  build
  coverage
  test-results
  playwright-report
)

SOURCE_TARGETS=(
  "apps/sentiment"
  "apps/subnetcalc"
)

# Keep this list aligned with kubernetes/lima/scripts/build-local-workload-images.sh.
IMAGE_SPECS=(
  "platform-security-scan/sentiment-api:scan|apps/sentiment/api-sentiment|apps/sentiment/api-sentiment/Dockerfile|"
  "platform-security-scan/sentiment-auth-ui:scan|apps/sentiment/frontend-react-vite/sentiment-auth-ui|apps/sentiment/frontend-react-vite/sentiment-auth-ui/Dockerfile|"
  "platform-security-scan/subnetcalc-api-fastapi-container-app:scan|apps/subnetcalc/api-fastapi-container-app|apps/subnetcalc/api-fastapi-container-app/Dockerfile|"
  "platform-security-scan/subnetcalc-apim-simulator:scan|apps/subnetcalc/apim-simulator|apps/subnetcalc/apim-simulator/Dockerfile|"
  "platform-security-scan/subnetcalc-frontend-typescript-vite:scan|apps/subnetcalc|apps/subnetcalc/frontend-typescript-vite/Dockerfile|"
  "platform-security-scan/subnetcalc-frontend-react:scan|apps/subnetcalc|apps/subnetcalc/frontend-react/Dockerfile|"
)

scan_failed=0
gate_failed=0
gitea_helper_loaded=0
CLONED_REPO_PATH=""
SUMMARY_REPORT="${REPORT_ROOT}/summary.md"
GATE_SEVERITIES="$(printf '%s' "${TRIVY_SEVERITY}" | tr '[:lower:]' '[:upper:]' | tr -d ' ')"
FINDINGS_TSV=""
REPORT_INDEX_FILE=""

log() {
  printf '%s\n' "$*"
}

fail() {
  printf 'trivy-scan-apps: %s\n' "$*" >&2
  exit 1
}

is_true() {
  case "${1}" in
    1|true|TRUE|yes|YES|y|Y)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

ensure_prereqs() {
  command -v jq >/dev/null 2>&1 || fail "jq not found in PATH"
  command -v git >/dev/null 2>&1 || fail "git not found in PATH"
  [[ -x "${TRIVY_RUNNER}" ]] || fail "missing Trivy runner at ${TRIVY_RUNNER}"
}

ensure_scan_prereqs() {
  ensure_prereqs

  case "$(trivy_local_status)" in
    available:*)
      return 0
      ;;
    unparseable)
      fail "trivy is present in PATH but its version could not be determined"
      ;;
    *)
      fail "trivy is not installed locally; install it if you want to run app scans"
      ;;
  esac
}

load_gitea_helper() {
  if [[ "${gitea_helper_loaded}" == "1" ]]; then
    return 0
  fi

  # shellcheck source=/dev/null
  source "${REPO_ROOT}/terraform/kubernetes/scripts/gitea-local-access.sh"
  gitea_helper_loaded=1
}

cleanup() {
  if [[ "${gitea_helper_loaded}" == "1" ]]; then
    gitea_local_access_cleanup || true
  fi
  if [[ -n "${FINDINGS_TSV}" && -f "${FINDINGS_TSV}" ]]; then
    rm -f "${FINDINGS_TSV}"
  fi
  if [[ -n "${REPORT_INDEX_FILE}" && -f "${REPORT_INDEX_FILE}" ]]; then
    rm -f "${REPORT_INDEX_FILE}"
  fi
}
trap cleanup EXIT

trivy_common_args() {
  local scanners="$1"
  local args=(
    --quiet
    --timeout "${TRIVY_TIMEOUT}"
    --severity "${TRIVY_SEVERITY}"
    --scanners "${scanners}"
  )

  if is_true "${TRIVY_IGNORE_UNFIXED}"; then
    args+=(--ignore-unfixed)
  fi

  printf '%s\n' "${args[@]}"
}

init_run_state() {
  FINDINGS_TSV="$(mktemp "${TMPDIR:-/tmp}/trivy-findings.XXXXXX")"
  REPORT_INDEX_FILE="$(mktemp "${TMPDIR:-/tmp}/trivy-reports.XXXXXX")"
}

append_report_findings() {
  local label="$1"
  local report="$2"

  printf '%s\t%s\n' "${label}" "${report}" >> "${REPORT_INDEX_FILE}"
  jq -r --arg report "${label}" '
    .Results[]? as $result
    | (
        ($result.Vulnerabilities // [])[]?
        | [
            $report,
            "vulnerability",
            ($result.Target // "unknown"),
            (.Severity // "UNKNOWN"),
            (.VulnerabilityID // .PkgName // "unknown"),
            (.PkgName // ""),
            (.InstalledVersion // ""),
            (.FixedVersion // ""),
            (.Title // .Description // "")
          ]
      ),
      (
        ($result.Misconfigurations // [])[]?
        | [
            $report,
            "misconfiguration",
            ($result.Target // "unknown"),
            (.Severity // "UNKNOWN"),
            (.ID // "unknown"),
            "",
            "",
            "",
            (.Title // .Message // "")
          ]
      ),
      (
        ($result.Secrets // [])[]?
        | [
            $report,
            "secret",
            ($result.Target // "unknown"),
            (.Severity // "UNKNOWN"),
            (.RuleID // "secret"),
            "",
            "",
            "",
            (.Title // "Secret finding")
          ]
      ),
      (
        ($result.Licenses // [])[]?
        | [
            $report,
            "license",
            ($result.Target // "unknown"),
            (.Severity // "UNKNOWN"),
            (.Name // "license"),
            "",
            "",
            "",
            (.Category // "License finding")
          ]
      )
    | @tsv
  ' "${report}" >> "${FINDINGS_TSV}"
}

report_summary() {
  local label="$1"
  awk -F '\t' -v report="${label}" -v gate="${GATE_SEVERITIES}" '
    BEGIN {
      split(gate, parts, ",")
      for (i in parts) {
        if (parts[i] != "") {
          gated[parts[i]] = 1
        }
      }
      order[1] = "CRITICAL"
      order[2] = "HIGH"
      order[3] = "MEDIUM"
      order[4] = "LOW"
      order[5] = "UNKNOWN"
    }
    $1 == report {
      total++
      kind[$2]++
      severity[$4]++
      if ($4 in gated) {
        gated_total++
      } else {
        advisory_total++
      }
    }
    END {
      printf "gate=%d advisory=%d total=%d types[vulns=%d misconfig=%d secrets=%d licenses=%d]",
        gated_total + 0,
        advisory_total + 0,
        total + 0,
        kind["vulnerability"] + 0,
        kind["misconfiguration"] + 0,
        kind["secret"] + 0,
        kind["license"] + 0
      first = 1
      for (i = 1; i <= 5; i++) {
        sev = order[i]
        if (severity[sev] > 0) {
          if (first) {
            printf " severities["
            first = 0
          } else {
            printf " "
          }
          printf "%s=%d", sev, severity[sev]
        }
      }
      if (!first) {
        printf "]"
      }
      printf "\n"
    }
  ' "${FINDINGS_TSV}"
}

report_gate_count() {
  local label="$1"
  awk -F '\t' -v report="${label}" -v gate="${GATE_SEVERITIES}" '
    BEGIN {
      split(gate, parts, ",")
      for (i in parts) {
        if (parts[i] != "") {
          gated[parts[i]] = 1
        }
      }
    }
    $1 == report && ($4 in gated) {
      count++
    }
    END {
      print count + 0
    }
  ' "${FINDINGS_TSV}"
}

total_counts() {
  awk -F '\t' -v gate="${GATE_SEVERITIES}" '
    BEGIN {
      split(gate, parts, ",")
      for (i in parts) {
        if (parts[i] != "") {
          gated[parts[i]] = 1
        }
      }
      order[1] = "CRITICAL"
      order[2] = "HIGH"
      order[3] = "MEDIUM"
      order[4] = "LOW"
      order[5] = "UNKNOWN"
    }
    {
      total++
      severity[$4]++
      if ($4 in gated) {
        gated_total++
      } else {
        advisory_total++
      }
    }
    END {
      printf "gate=%d advisory=%d total=%d", gated_total + 0, advisory_total + 0, total + 0
      first = 1
      for (i = 1; i <= 5; i++) {
        sev = order[i]
        if (severity[sev] > 0) {
          if (first) {
            printf " severities["
            first = 0
          } else {
            printf " "
          }
          printf "%s=%d", sev, severity[sev]
        }
      }
      if (!first) {
        printf "]"
      }
      printf "\n"
    }
  ' "${FINDINGS_TSV}"
}

write_terminal_summary() {
  local label report
  local display_label
  local gate advisory total vulns misconfig secrets licenses
  local total_gate=0
  local total_advisory=0
  local total_findings=0
  local total_vulns=0
  local total_misconfig=0
  local total_secrets=0
  local total_licenses=0
  local target_width=52

  printf 'Summary Table\n'
  printf '%-52s %6s %9s %7s %7s %11s %8s %9s\n' "Target" "Gate" "Advisory" "Total" "Vulns" "Misconfig" "Secrets" "Licenses"
  printf '%-52s %6s %9s %7s %7s %11s %8s %9s\n' "------" "----" "--------" "-----" "-----" "----------" "-------" "--------"

  while IFS=$'\t' read -r label report; do
    IFS=$'\t' read -r gate advisory total vulns misconfig secrets licenses <<EOF
$(awk -F '\t' -v report="${label}" -v gate="${GATE_SEVERITIES}" '
  BEGIN {
    split(gate, parts, ",")
    for (i in parts) {
      if (parts[i] != "") {
        gated[parts[i]] = 1
      }
    }
  }
  $1 == report {
    total++
    kind[$2]++
    if ($4 in gated) {
      gated_total++
    } else {
      advisory_total++
    }
  }
  END {
    printf "%d\t%d\t%d\t%d\t%d\t%d\t%d\n",
      gated_total + 0,
      advisory_total + 0,
      total + 0,
      kind["vulnerability"] + 0,
      kind["misconfiguration"] + 0,
      kind["secret"] + 0,
      kind["license"] + 0
  }
' "${FINDINGS_TSV}")
EOF
    display_label="${label}"
    if [[ "${#display_label}" -gt "${target_width}" ]]; then
      display_label="...${display_label:$((${#display_label} - (target_width - 3)))}"
    fi
    printf '%-52s %6d %9d %7d %7d %11d %8d %9d\n' "${display_label}" "${gate}" "${advisory}" "${total}" "${vulns}" "${misconfig}" "${secrets}" "${licenses}"
    total_gate=$((total_gate + gate))
    total_advisory=$((total_advisory + advisory))
    total_findings=$((total_findings + total))
    total_vulns=$((total_vulns + vulns))
    total_misconfig=$((total_misconfig + misconfig))
    total_secrets=$((total_secrets + secrets))
    total_licenses=$((total_licenses + licenses))
  done < "${REPORT_INDEX_FILE}"

  printf '%-52s %6s %9s %7s %7s %11s %8s %9s\n' "------" "----" "--------" "-----" "-----" "----------" "-------" "--------"
  printf '%-52s %6d %9d %7d %7d %11d %8d %9d\n' "Totals" "${total_gate}" "${total_advisory}" "${total_findings}" "${total_vulns}" "${total_misconfig}" "${total_secrets}" "${total_licenses}"
}

write_summary_report() {
  {
    printf '# Trivy Summary\n\n'
    printf -- "- Generated: \`%s\`\n" "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    printf -- "- Gate severities: \`%s\`\n" "${GATE_SEVERITIES}"
    printf -- "- Reports directory: \`%s\`\n" "${REPORT_ROOT}"
    printf '\n## Reports\n\n'
    while IFS=$'\t' read -r label report; do
      printf -- "- \`%s\`: %s\n" "${label}" "$(report_summary "${label}")"
      printf "  Report: \`%s\`\n" "${report}"
    done < "${REPORT_INDEX_FILE}"

    printf '\n## Gate Findings\n\n'
    if awk -F '\t' -v gate="${GATE_SEVERITIES}" '
      BEGIN {
        split(gate, parts, ",")
        for (i in parts) {
          if (parts[i] != "") {
            gated[parts[i]] = 1
          }
        }
      }
      ($4 in gated) {
        found = 1
      }
      END {
        exit(found ? 0 : 1)
      }
    ' "${FINDINGS_TSV}"; then
      awk -F '\t' -v gate="${GATE_SEVERITIES}" '
        BEGIN {
          split(gate, parts, ",")
          for (i in parts) {
            if (parts[i] != "") {
              gated[parts[i]] = 1
            }
          }
        }
        ($4 in gated) {
          title = $9
          gsub(/\\n/, " ", title)
          printf -- "- `%s` `%s` `%s` `%s` on `%s`", $1, $4, $2, $5, $3
          if ($6 != "") {
            printf " package `%s` `%s`", $6, $7
          }
          if ($8 != "") {
            printf " -> `%s`", $8
          }
          if (title != "") {
            printf ": %s", title
          }
          printf "\n"
        }
      ' "${FINDINGS_TSV}"
    else
      printf '_None._\n'
    fi

    printf '\n## Advisory Findings Outside Gate\n\n'
    if awk -F '\t' -v gate="${GATE_SEVERITIES}" '
      BEGIN {
        split(gate, parts, ",")
        for (i in parts) {
          if (parts[i] != "") {
            gated[parts[i]] = 1
          }
        }
      }
      !($4 in gated) {
        found = 1
      }
      END {
        exit(found ? 0 : 1)
      }
    ' "${FINDINGS_TSV}"; then
      awk -F '\t' -v gate="${GATE_SEVERITIES}" '
        BEGIN {
          split(gate, parts, ",")
          for (i in parts) {
            if (parts[i] != "") {
              gated[parts[i]] = 1
            }
          }
        }
        !($4 in gated) {
          title = $9
          gsub(/\\n/, " ", title)
          printf -- "- `%s` `%s` `%s` `%s` on `%s`", $1, $4, $2, $5, $3
          if ($6 != "") {
            printf " package `%s` `%s`", $6, $7
          }
          if ($8 != "") {
            printf " -> `%s`", $8
          }
          if (title != "") {
            printf ": %s", title
          }
          printf "\n"
        }
      ' "${FINDINGS_TSV}"
    else
      printf '_None._\n'
    fi
  } > "${SUMMARY_REPORT}"
}

to_repo_rel() {
  local path="$1"
  case "${path}" in
    "${REPO_ROOT}/"*)
      printf '%s\n' "${path#"${REPO_ROOT}/"}"
      ;;
    *)
      printf '%s\n' "${path}"
      ;;
  esac
}

run_fs_scan() {
  local label="$1"
  local target="$2"
  local report="$3"
  local runner_report
  local status=0
  local args=()
  local skip_dir

  mkdir -p "$(dirname "${report}")"
  runner_report="$(to_repo_rel "${report}")"
  args=(
    fs
    --format json
    --output "${runner_report}"
    --exit-code 0
  )
  while IFS= read -r arg; do
    args+=("${arg}")
  done < <(trivy_common_args "${TRIVY_FS_SCANNERS}")
  for skip_dir in "${TRIVY_SKIP_DIRS[@]}"; do
    args+=(--skip-dirs "${skip_dir}")
  done
  args+=("${target}")

  log "SCAN ${label}"
  if (cd "${REPO_ROOT}" && "${TRIVY_RUNNER}" "${args[@]}"); then
    status=0
  else
    status=$?
    scan_failed=1
  fi

  if [[ -f "${report}" ]]; then
    append_report_findings "${label}" "${report}"
    log "  ${label}: $(report_summary "${label}")"
    if [[ "$(report_gate_count "${label}")" -gt 0 ]]; then
      gate_failed=1
    fi
  else
    log "  ${label}: no report written"
    scan_failed=1
  fi

  return "${status}"
}

docker_build() {
  if docker buildx version >/dev/null 2>&1; then
    docker buildx build --load --provenance=false "$@"
    return
  fi

  DOCKER_BUILDKIT=1 docker build "$@"
}

build_image() {
  local image_ref="$1"
  local context_dir="$2"
  local dockerfile="$3"
  shift 3

  log "BUILD ${image_ref}"
  (
    cd "${REPO_ROOT}"
    docker_build -t "${image_ref}" -f "${dockerfile}" "$@" "${context_dir}"
  )
}

run_image_scan() {
  local image_ref="$1"
  local report="$2"
  local runner_report
  local status=0
  local args=()

  mkdir -p "$(dirname "${report}")"
  runner_report="$(to_repo_rel "${report}")"
  args=(
    image
    --format json
    --output "${runner_report}"
    --exit-code 0
  )
  while IFS= read -r arg; do
    args+=("${arg}")
  done < <(trivy_common_args "${TRIVY_IMAGE_SCANNERS}")
  args+=("${image_ref}")

  log "SCAN ${image_ref}"
  if (cd "${REPO_ROOT}" && "${TRIVY_RUNNER}" "${args[@]}"); then
    status=0
  else
    status=$?
    scan_failed=1
  fi

  if [[ -f "${report}" ]]; then
    append_report_findings "${image_ref}" "${report}"
    log "  ${image_ref}: $(report_summary "${image_ref}")"
    if [[ "$(report_gate_count "${image_ref}")" -gt 0 ]]; then
      gate_failed=1
    fi
  else
    log "  ${image_ref}: no report written"
    scan_failed=1
  fi

  return "${status}"
}

scan_source_tree() {
  local target
  for target in "${SOURCE_TARGETS[@]}"; do
    run_fs_scan "${target}" "${target}" "${REPORT_ROOT}/fs/$(basename "${target}").json" || true
  done
}

scan_images() {
  local spec
  local image_ref context_dir dockerfile extra_args report label
  local -a extra_args_arr=()

  ensure_prereqs
  command -v docker >/dev/null 2>&1 || fail "docker not found in PATH"
  docker info >/dev/null 2>&1 || fail "docker daemon not reachable"

  while IFS= read -r spec; do
    [[ -n "${spec}" ]] || continue
    IFS='|' read -r image_ref context_dir dockerfile extra_args <<<"${spec}"
    label="$(basename "${image_ref%%:*}")"
    if [[ -n "${extra_args}" ]]; then
      IFS=' ' read -r -a extra_args_arr <<<"${extra_args}"
      build_image "${image_ref}" "${context_dir}" "${dockerfile}" "${extra_args_arr[@]}"
    else
      build_image "${image_ref}" "${context_dir}" "${dockerfile}"
    fi
    report="${REPORT_ROOT}/images/${label}.json"
    run_image_scan "${image_ref}" "${report}" || true
  done <<<"$(printf '%s\n' "${IMAGE_SPECS[@]}")"
}

clone_gitea_repo() {
  local repo_name="$1"
  local dest_rel=".run/apps-security/trivy/gitea-clones/${repo_name}"
  local dest_abs="${REPO_ROOT}/${dest_rel}"
  local remote_url auth_header
  local admin_user="${GITEA_ADMIN_USERNAME:-gitea-admin}"
  local admin_pwd="${GITEA_ADMIN_PWD:-${PLATFORM_ADMIN_PASSWORD:-}}"

  if [[ -z "${admin_pwd}" ]]; then
    platform_require_vars PLATFORM_ADMIN_PASSWORD || exit 1
    admin_pwd="${PLATFORM_ADMIN_PASSWORD}"
  fi

  rm -rf "${dest_abs}"
  mkdir -p "$(dirname "${dest_abs}")"

  remote_url="${GITEA_HTTP_BASE%/}/${GITEA_REPO_OWNER:-platform}/${repo_name}.git"
  auth_header="Authorization: Basic $(printf '%s' "${admin_user}:${admin_pwd}" | base64)"

  printf 'CLONE %s\n' "${remote_url}" >&2
  git -c "http.extraHeader=${auth_header}" clone -q --depth 1 "${remote_url}" "${dest_abs}"
  CLONED_REPO_PATH="${dest_rel}"
}

gitea_repo_exists() {
  local repo_name="$1"
  local admin_user="${GITEA_ADMIN_USERNAME:-gitea-admin}"
  local admin_pwd="${GITEA_ADMIN_PWD:-${PLATFORM_ADMIN_PASSWORD:-}}"
  local code

  if [[ -z "${admin_pwd}" ]]; then
    platform_require_vars PLATFORM_ADMIN_PASSWORD || exit 1
    admin_pwd="${PLATFORM_ADMIN_PASSWORD}"
  fi

  code="$(
    curl -s -o /dev/null -w '%{http_code}' \
      -u "${admin_user}:${admin_pwd}" \
      "${GITEA_HTTP_BASE%/}/api/v1/repos/${GITEA_REPO_OWNER:-platform}/${repo_name}" || true
  )"
  [[ "${code}" == "200" ]]
}

scan_gitea_repos() {
  local repo_name

  if ! is_true "${SCAN_GITEA}"; then
    log "SKIP Gitea repo scan (set SCAN_GITEA=1 or use make -C apps trivy-scan-gitea)"
    return 0
  fi

  load_gitea_helper
  gitea_local_access_setup http

  for repo_name in sentiment subnetcalc; do
    if ! gitea_repo_exists "${repo_name}"; then
      log "SKIP gitea/${repo_name} mirror missing at ${GITEA_REPO_OWNER:-platform}/${repo_name}"
      continue
    fi
    if ! clone_gitea_repo "${repo_name}"; then
      scan_failed=1
      continue
    fi
    run_fs_scan "gitea/${repo_name}" "${CLONED_REPO_PATH}" "${REPORT_ROOT}/gitea/${repo_name}.json" || true
  done
}

print_final_status() {
  write_summary_report
  log ""
  write_terminal_summary
  log ""
  log "Reports: ${REPORT_ROOT}"
  log "Summary: ${SUMMARY_REPORT}"
  if [[ "${scan_failed}" -ne 0 ]]; then
    log "Result: scan execution failed; inspect the logs, JSON reports, and ${SUMMARY_REPORT}"
    return 1
  fi

  log "Totals: $(total_counts)"
  if [[ "${gate_failed}" -eq 0 ]]; then
    log "Result: no ${GATE_SEVERITIES} findings in the scanned targets"
    return 0
  fi

  log "Result: ${GATE_SEVERITIES} findings detected; inspect ${SUMMARY_REPORT}"
  return 1
}

usage() {
  cat <<'EOF'
Usage: trivy-scan-apps.sh [--mode prereqs|fs|images|gitea|all] [--dry-run] [--execute]

Environment:
  SCAN_GITEA=1            Also clone and scan the seeded private app repos from Gitea.
  TRIVY_SEVERITY=...      Severity filter passed to Trivy (default: HIGH,CRITICAL).
  TRIVY_IGNORE_UNFIXED=1  Ignore unfixed vulnerabilities (default: enabled).

Options:
  --mode MODE  Select the Trivy scan mode
  --dry-run    Show the selected scan mode and exit before side effects
  --execute    Execute the scan
  -h, --help   Show this message
EOF
}

main() {
  mkdir -p "${REPORT_ROOT}" "${CLONE_ROOT}"
  init_run_state

  case "${mode}" in
    prereqs)
      local local_status=""
      ensure_prereqs
      local_status="$(trivy_local_status)"
      log "Trivy runner: ${TRIVY_RUNNER}"
      case "${local_status}" in
        available:*)
          log "Runner mode: local trivy binary (${local_status#available:})"
          ;;
        unparseable)
          log "Runner mode: unavailable"
          log "Local trivy version: unavailable (binary present, version could not be determined)"
          ;;
        *)
          log "Runner mode: unavailable"
          log "Local trivy: not installed"
          log "Scanning is optional. Install trivy locally if you want to run make -C apps trivy-scan."
          ;;
      esac
      log "Reports: ${REPORT_ROOT}"
      ;;
    fs)
      ensure_scan_prereqs
      scan_source_tree
      print_final_status
      ;;
    images)
      ensure_scan_prereqs
      scan_images
      print_final_status
      ;;
    gitea)
      ensure_scan_prereqs
      scan_gitea_repos
      print_final_status
      ;;
    all)
      ensure_scan_prereqs
      scan_source_tree
      scan_images
      scan_gitea_repos
      print_final_status
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
}

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --mode)
      shift
      [[ $# -gt 0 ]] || { shell_cli_missing_value "$(shell_cli_script_name)" "--mode" >&2; exit 1; }
      mode="$1"
      ;;
    --)
      shift
      break
      ;;
    -*)
      shell_cli_unknown_flag "$(shell_cli_script_name)" "$1"
      exit 2
      ;;
    *)
      mode="$1"
      ;;
  esac
  shift
done

shell_cli_maybe_execute_or_preview_summary usage \
  "would run Trivy app scan in ${mode} mode"

main
