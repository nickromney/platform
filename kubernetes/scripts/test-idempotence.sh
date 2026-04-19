#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
  cat <<'EOF'
Usage: test-idempotence.sh [options]

Purpose:
  Run apply/apply/plan idempotence checks for a Kubernetes stack and capture the
  logs plus any changed resource addresses under an ignored .run directory.

Options:
  --stack-name NAME             Logical stack name (for example: kind, lima, slicer)
  --stack-dir PATH              Directory that owns the stack Makefile
  --stage N                     Stage to exercise
  --allowlist-file PATH         Optional TSV allowlist of accepted changes
  --results-dir PATH            Optional output directory (default: <repo>/.run/idempotence/<stack>/stage<stage>/<timestamp>)
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

fail() {
  printf 'test-idempotence: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required binary: $1"
}

stack_name=""
stack_dir=""
stage=""
allowlist_file="${REPO_ROOT}/kubernetes/idempotence-allowlist.tsv"
results_dir=""

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --stack-name)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--stack-name"
        exit 1
      }
      stack_name="${2:-}"
      shift 2
      ;;
    --stack-dir)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--stack-dir"
        exit 1
      }
      stack_dir="${2:-}"
      shift 2
      ;;
    --stage)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--stage"
        exit 1
      }
      stage="${2:-}"
      shift 2
      ;;
    --allowlist-file)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--allowlist-file"
        exit 1
      }
      allowlist_file="${2:-}"
      shift 2
      ;;
    --results-dir)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--results-dir"
        exit 1
      }
      results_dir="${2:-}"
      shift 2
      ;;
    *)
      shell_cli_unknown_flag "$(shell_cli_script_name)" "$1"
      exit 1
      ;;
  esac
done

dry_run_summary="would run apply/apply/plan idempotence checks for a Kubernetes stack"
if [[ -n "${stack_name}" || -n "${stage}" ]]; then
  if [[ -n "${stack_name}" && -n "${stage}" ]]; then
    dry_run_summary="would run apply/apply/plan idempotence checks for stack '${stack_name}' at stage ${stage}"
  elif [[ -n "${stack_name}" ]]; then
    dry_run_summary="would run apply/apply/plan idempotence checks for stack '${stack_name}'"
  else
    dry_run_summary="would run apply/apply/plan idempotence checks at stage ${stage}"
  fi
fi

shell_cli_maybe_execute_or_preview_summary usage "${dry_run_summary}"

[[ -n "${stack_name}" ]] || fail "--stack-name is required"
[[ -n "${stack_dir}" ]] || fail "--stack-dir is required"
[[ -n "${stage}" ]] || fail "--stage is required"
[[ "${stage}" =~ ^[0-9]+$ ]] || fail "--stage must be numeric"
[[ -d "${stack_dir}" ]] || fail "stack directory not found: ${stack_dir}"

require_cmd make
require_cmd jq
require_cmd tofu

stack_dir="$(cd "${stack_dir}" && pwd)"

timestamp_utc() {
  date -u +"%Y%m%d-%H%M%SZ"
}

results_root="${results_dir:-${REPO_ROOT}/.run/idempotence/${stack_name}/stage${stage}}"
run_dir="${results_root%/}/$(timestamp_utc)"
mkdir -p "${run_dir}"

apply_flags="-no-color"
if [[ -n "${TG_APPLY_FLAGS:-}" ]]; then
  apply_flags="${TG_APPLY_FLAGS} ${apply_flags}"
fi

plan_file="${run_dir}/final.plan"
plan_json="${run_dir}/final.plan.json"
plan_flags="-detailed-exitcode -no-color -out=${plan_file}"
if [[ -n "${TG_PLAN_FLAGS:-}" ]]; then
  plan_flags="${TG_PLAN_FLAGS} ${plan_flags}"
fi

last_log_file=""

run_logged_step() {
  local step_name="$1"
  shift
  local log_file="${run_dir}/${step_name}.log"
  local rc=0

  if "$@" >"${log_file}" 2>&1; then
    rc=0
  else
    rc=$?
  fi

  last_log_file="${log_file}"
  printf '%s\t%s\t%s\n' "${step_name}" "${rc}" "${log_file}" >>"${run_dir}/steps.tsv"
  return "${rc}"
}

second_apply_is_noop() {
  local log_file="$1"
  grep -Eq 'No changes\.|Resources: 0 added, 0 changed, 0 destroyed\.' "${log_file}"
}

extract_apply_addresses() {
  local log_file="$1"
  sed -n -E 's/^[[:space:]]*# ([^[:space:]]+) .*/\1/p' "${log_file}" | LC_ALL=C sort -u
}

allowlist_match() {
  local phase="$1"
  local address="$2"
  local line_stack=""
  local line_stage=""
  local line_phase=""
  local line_pattern=""
  local line_reason=""

  [[ -f "${allowlist_file}" ]] || return 1

  while IFS=$'\t' read -r line_stack line_stage line_phase line_pattern line_reason; do
    [[ -n "${line_stack}" ]] || continue
    [[ "${line_stack}" == \#* ]] && continue
    [[ "${line_stack}" == "stack" ]] && continue
    [[ "${line_stack}" == "*" || "${line_stack}" == "${stack_name}" ]] || continue
    [[ "${line_stage}" == "*" || "${line_stage}" == "${stage}" ]] || continue
    [[ "${line_phase}" == "*" || "${line_phase}" == "${phase}" ]] || continue
    [[ -n "${line_pattern}" ]] || continue
    case "${address}" in
      ${line_pattern})
        return 0
        ;;
    esac
  done <"${allowlist_file}"

  return 1
}

check_addresses_against_allowlist() {
  local phase="$1"
  shift
  local address=""
  local unknown=()

  for address in "$@"; do
    [[ -n "${address}" ]] || continue
    if ! allowlist_match "${phase}" "${address}"; then
      unknown+=("${address}")
    fi
  done

  if [[ "${#unknown[@]}" -gt 0 ]]; then
    printf '%s\n' "${unknown[@]}" >"${run_dir}/${phase}-unexpected.txt"
    return 1
  fi

  return 0
}

collect_plan_addresses() {
  local file="$1"
  local out_file="$2"

  jq -r '
    .resource_changes[]?
    | select(any(.change.actions[]?; . != "no-op"))
    | .address
  ' "${file}" | LC_ALL=C sort -u >"${out_file}"
}

{
  printf 'stack=%s\n' "${stack_name}"
  printf 'stack_dir=%s\n' "${stack_dir}"
  printf 'stage=%s\n' "${stage}"
  printf 'allowlist_file=%s\n' "${allowlist_file}"
  printf 'run_dir=%s\n' "${run_dir}"
} >"${run_dir}/metadata.env"
printf 'step\texit_code\tlog_file\n' >"${run_dir}/steps.tsv"

printf '==> %s stage %s: first apply\n' "${stack_name}" "${stage}"
if ! run_logged_step "apply-first" env TG_APPLY_FLAGS="${apply_flags}" make -C "${stack_dir}" apply STAGE="${stage}" AUTO_APPROVE=1; then
  fail "first apply failed; see ${last_log_file}"
fi

printf '==> %s stage %s: second apply\n' "${stack_name}" "${stage}"
if ! run_logged_step "apply-second" env TG_APPLY_FLAGS="${apply_flags}" make -C "${stack_dir}" apply STAGE="${stage}" AUTO_APPROVE=1; then
  fail "second apply failed; see ${last_log_file}"
fi
second_apply_log="${last_log_file}"

if second_apply_is_noop "${second_apply_log}"; then
  printf 'second_apply=noop\n' >>"${run_dir}/summary.env"
else
  mapfile_addresses=()
  while IFS= read -r address; do
    [[ -n "${address}" ]] || continue
    mapfile_addresses+=("${address}")
  done < <(extract_apply_addresses "${second_apply_log}")

  if [[ "${#mapfile_addresses[@]}" -eq 0 ]]; then
    fail "second apply reported changes but no resource addresses were extracted; see ${second_apply_log}"
  fi

  printf '%s\n' "${mapfile_addresses[@]}" >"${run_dir}/apply-addresses.txt"
  if ! check_addresses_against_allowlist "apply" "${mapfile_addresses[@]}"; then
    fail "second apply changed non-allowlisted resources; see ${run_dir}/apply-unexpected.txt"
  fi
  printf 'second_apply=allowlisted\n' >>"${run_dir}/summary.env"
fi

printf '==> %s stage %s: final plan\n' "${stack_name}" "${stage}"
set +e
run_logged_step "plan-final" env TG_PLAN_FLAGS="${plan_flags}" make -C "${stack_dir}" plan STAGE="${stage}"
plan_rc=$?
set -e
final_plan_log="${last_log_file}"

case "${plan_rc}" in
  0)
    printf 'final_plan=noop\n' >>"${run_dir}/summary.env"
    ;;
  2)
    tofu show -json "${plan_file}" >"${plan_json}"
    collect_plan_addresses "${plan_json}" "${run_dir}/plan-addresses.txt"

    plan_addresses=()
    while IFS= read -r address; do
      [[ -n "${address}" ]] || continue
      plan_addresses+=("${address}")
    done <"${run_dir}/plan-addresses.txt"

    if [[ "${#plan_addresses[@]}" -eq 0 ]]; then
      fail "final plan returned drift but no changed addresses were recorded; see ${final_plan_log}"
    fi

    if ! check_addresses_against_allowlist "plan" "${plan_addresses[@]}"; then
      fail "final plan reported non-allowlisted drift; see ${run_dir}/plan-unexpected.txt"
    fi
    printf 'final_plan=allowlisted\n' >>"${run_dir}/summary.env"
    ;;
  *)
    fail "final plan failed with exit code ${plan_rc}; see ${final_plan_log}"
    ;;
esac

printf 'OK   idempotence harness passed (%s stage %s)\n' "${stack_name}" "${stage}"
printf 'OK   results: %s\n' "${run_dir}"
