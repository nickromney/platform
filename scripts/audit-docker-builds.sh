#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUT_ROOT="${DOCKER_AUDIT_OUT_ROOT:-${REPO_ROOT}/.run/docker-build-audit}"
FAIL_ON_WARNINGS="${DOCKER_AUDIT_FAIL_ON_WARNINGS:-1}"
SELECTED_TARGETS=()

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

TARGET_SPECS=(
  "frontend-typescript-vite|${REPO_ROOT}/apps/subnetcalc|${REPO_ROOT}/apps/subnetcalc/frontend-typescript-vite/Dockerfile|platform-docker-audit/subnetcalc-frontend-typescript-vite:audit|"
  "frontend-react|${REPO_ROOT}/apps/subnetcalc|${REPO_ROOT}/apps/subnetcalc/frontend-react/Dockerfile|platform-docker-audit/subnetcalc-frontend-react:audit|"
  "frontend-react-server|${REPO_ROOT}/apps/subnetcalc|${REPO_ROOT}/apps/subnetcalc/frontend-react/Dockerfile.server|platform-docker-audit/subnetcalc-frontend-react-server:audit|"
  "frontend-python-flask|${REPO_ROOT}/apps/subnetcalc/frontend-python-flask|${REPO_ROOT}/apps/subnetcalc/frontend-python-flask/Dockerfile|platform-docker-audit/subnetcalc-frontend-python-flask:audit|"
  "api-fastapi-container-app|${REPO_ROOT}/apps/subnetcalc/api-fastapi-container-app|${REPO_ROOT}/apps/subnetcalc/api-fastapi-container-app/Dockerfile|platform-docker-audit/subnetcalc-api-fastapi-container-app:audit|"
  "api-fastapi-azure-function|${REPO_ROOT}/apps/subnetcalc/api-fastapi-azure-function|${REPO_ROOT}/apps/subnetcalc/api-fastapi-azure-function/Dockerfile|platform-docker-audit/subnetcalc-api-fastapi-azure-function:audit|linux/amd64"
  "api-fastapi-azure-function-uvicorn|${REPO_ROOT}/apps/subnetcalc/api-fastapi-azure-function|${REPO_ROOT}/apps/subnetcalc/api-fastapi-azure-function/Dockerfile.uvicorn|platform-docker-audit/subnetcalc-api-fastapi-azure-function-uvicorn:audit|"
  "apim-simulator|${REPO_ROOT}/apps/apim-simulator|${REPO_ROOT}/apps/apim-simulator/Dockerfile|platform-docker-audit/subnetcalc-apim-simulator:audit|"
)

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute] [target-name ...]

Builds the selected Docker targets with plain progress output, saves the raw logs,
captures image sizes and layer histories, and fails if build logs contain warning
or error lines.
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

preview() {
  local spec name context dockerfile image platform

  shell_cli_print_dry_run_summary "would audit selected Docker builds and write reports under ${OUT_ROOT}"
  printf 'Selected Docker build targets:\n'
  for spec in "${TARGET_SPECS[@]}"; do
    IFS='|' read -r name context dockerfile image platform <<<"${spec}"
    if ! matches_selection "${name}" ${SELECTED_TARGETS[@]+"${SELECTED_TARGETS[@]}"}; then
      continue
    fi
    printf '  %s\n' "${name}"
    printf '    context: %s\n' "${context}"
    printf '    dockerfile: %s\n' "${dockerfile}"
    printf '    image: %s\n' "${image}"
    if [[ -n "${platform}" ]]; then
      printf '    platform: %s\n' "${platform}"
    fi
  done
}

format_bytes() {
  local value="$1"
  if command -v numfmt >/dev/null 2>&1; then
    numfmt --to=iec --suffix=B "${value}"
  else
    printf '%sB\n' "${value}"
  fi
}

matches_selection() {
  local name="$1"
  shift || true

  if [[ "$#" -eq 0 ]]; then
    return 0
  fi

  local selected
  for selected in "$@"; do
    if [[ "${selected}" == "${name}" ]]; then
      return 0
    fi
  done

  return 1
}

main() {
  shell_cli_parse_standard_only usage "$@" || exit 1
  SELECTED_TARGETS=(${SHELL_CLI_ARGS[@]+"${SHELL_CLI_ARGS[@]}"})
  set -- ${SELECTED_TARGETS[@]+"${SELECTED_TARGETS[@]}"}
  shell_cli_maybe_execute_or_preview usage preview

  command -v docker >/dev/null 2>&1 || {
    echo "audit-docker-builds: docker not found in PATH" >&2
    exit 1
  }
  command -v rg >/dev/null 2>&1 || {
    echo "audit-docker-builds: rg not found in PATH" >&2
    exit 1
  }

  mkdir -p "${OUT_ROOT}"
  local summary_file="${OUT_ROOT}/summary.tsv"
  printf 'target\timage\tsize_bytes\tsize_human\twarnings\terrors\tlog_file\thistory_file\n' >"${summary_file}"

  local overall_status=0
  local spec name context dockerfile image platform log_file history_file
  local size_bytes size_human warnings_count errors_count
  local warning_matches error_matches
  local build_cmd

  for spec in "${TARGET_SPECS[@]}"; do
    IFS='|' read -r name context dockerfile image platform <<<"${spec}"

    if ! matches_selection "${name}" "$@"; then
      continue
    fi

    log_file="${OUT_ROOT}/${name}.log"
    history_file="${OUT_ROOT}/${name}.history.tsv"

    echo "==> building ${name}"
    build_cmd=(docker build --progress=plain --file "${dockerfile}" --tag "${image}")
    if [[ -n "${platform}" ]]; then
      build_cmd+=(--platform "${platform}")
    fi
    build_cmd+=("${context}")
    if ! DOCKER_BUILDKIT=1 "${build_cmd[@]}" >"${log_file}" 2>&1; then
      echo "build failed for ${name}; see ${log_file}" >&2
      overall_status=1
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "${name}" "${image}" "0" "0B" "0" "1" "${log_file}" "${history_file}" >>"${summary_file}"
      continue
    fi

    docker history --no-trunc --format '{{.Size}}\t{{.CreatedBy}}' "${image}" >"${history_file}"

    size_bytes="$(docker image inspect "${image}" --format '{{.Size}}')"
    size_human="$(format_bytes "${size_bytes}")"

    warning_matches="$(rg -in '\bwarning\b' "${log_file}" || true)"
    error_matches="$(rg -in '\berror\b' "${log_file}" || true)"
    warnings_count="$(printf '%s' "${warning_matches}" | sed '/^$/d' | wc -l | tr -d ' ')"
    errors_count="$(printf '%s' "${error_matches}" | sed '/^$/d' | wc -l | tr -d ' ')"

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "${name}" "${image}" "${size_bytes}" "${size_human}" "${warnings_count}" "${errors_count}" "${log_file}" "${history_file}" \
      >>"${summary_file}"

    echo "    image size: ${size_human}"
    echo "    log file: ${log_file}"
    echo "    layer history: ${history_file}"

    if [[ -n "${warning_matches}" ]]; then
      echo "    warning lines:"
      printf '%s\n' "${warning_matches}"
      if [[ "${FAIL_ON_WARNINGS}" == "1" ]]; then
        overall_status=1
      fi
    fi

    if [[ -n "${error_matches}" ]]; then
      echo "    error lines:"
      printf '%s\n' "${error_matches}"
      overall_status=1
    fi
  done

  echo
  echo "summary: ${summary_file}"
  cat "${summary_file}"

  return "${overall_status}"
}

main "$@"
