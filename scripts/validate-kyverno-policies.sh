#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/shell-cli.sh"

POLICY_ROOT="${KYVERNO_POLICY_ROOT:-${REPO_ROOT}/terraform/kubernetes/cluster-policies/kyverno}"
TEST_ROOT="${KYVERNO_TEST_ROOT:-${POLICY_ROOT}}"
INSTALL_HINTS_SCRIPT="${INSTALL_HINTS_SCRIPT:-${REPO_ROOT}/scripts/install-tool-hints.sh}"
KUBECTL_BIN="${KUBECTL_BIN:-kubectl}"
KYVERNO_BIN="${KYVERNO_BIN:-kyverno}"
LIVE_VALIDATION_TMP_KUBECONFIG=""
LIVE_VALIDATION_TMP_POLICIES=""
mode="static"

usage() {
  cat <<'EOF'
Usage: validate-kyverno-policies.sh [--mode static|live] [--dry-run] [--execute]

static
    Render the repo's checked-in Kyverno kustomize overlays and execute the
    checked-in kyverno test suites.

live
    Render the repo's checked-in Kyverno policies and evaluate them against the
    current kubeconfig context with kyverno apply --cluster --policy-report.

Options:
  --mode MODE  Validation mode: static or live
  --dry-run    Show the selected validation mode and exit before side effects
  --execute    Execute the validation
  -h, --help   Show this message
EOF
}

fail() {
  echo "FAIL $*" >&2
  exit 1
}

tool_exists() {
  local tool="$1"

  if [[ "${tool}" == */* ]]; then
    [[ -x "${tool}" ]]
    return
  fi

  command -v "${tool}" >/dev/null 2>&1
}

require_cmd() {
  local tool="$1"
  local tool_label

  if tool_exists "${tool}"; then
    return 0
  fi

  tool_label="$(basename "${tool}")"
  echo "FAIL ${tool_label} not found in PATH" >&2
  if [[ -x "${INSTALL_HINTS_SCRIPT}" ]]; then
    echo "" >&2
    echo "Install hints:" >&2
    "${INSTALL_HINTS_SCRIPT}" --execute --plain "${tool_label}" | sed 's/^/  /' >&2 || true
  fi
  exit 1
}

list_kustomize_dirs() {
  find "${POLICY_ROOT}" -type f -name 'kustomization.yaml' -print \
    | while IFS= read -r file; do
        dirname "${file}"
      done \
    | LC_ALL=C sort -u
}

count_test_suites() {
  find "${TEST_ROOT}" -type f -name 'kyverno-test.yaml' -print | wc -l | tr -d '[:space:]'
}

cleanup_live_validation() {
  rm -f "${LIVE_VALIDATION_TMP_KUBECONFIG:-}" "${LIVE_VALIDATION_TMP_POLICIES:-}"
  LIVE_VALIDATION_TMP_KUBECONFIG=""
  LIVE_VALIDATION_TMP_POLICIES=""
}

run_static_validation() {
  local rendered_dirs suite_count dir

  [[ -d "${POLICY_ROOT}" ]] || fail "missing Kyverno policy root: ${POLICY_ROOT}"
  [[ -d "${TEST_ROOT}" ]] || fail "missing Kyverno test root: ${TEST_ROOT}"

  require_cmd "${KUBECTL_BIN}"
  require_cmd "${KYVERNO_BIN}"

  rendered_dirs=0
  while IFS= read -r dir; do
    [[ -n "${dir}" ]] || continue
    "${KUBECTL_BIN}" kustomize "${dir}" >/dev/null
    rendered_dirs=$((rendered_dirs + 1))
  done < <(list_kustomize_dirs)

  suite_count="$(count_test_suites)"
  [[ "${suite_count}" -gt 0 ]] || fail "no kyverno-test.yaml suites found under ${TEST_ROOT}"

  "${KYVERNO_BIN}" test "${TEST_ROOT}" --require-tests --remove-color

  echo "OK   rendered ${rendered_dirs} Kyverno kustomize overlay(s)"
  echo "OK   executed ${suite_count} Kyverno test suite(s)"
}

run_live_validation() {
  local kubeconfig_input kubeconfig_rendered rendered_policies

  [[ -d "${POLICY_ROOT}" ]] || fail "missing Kyverno policy root: ${POLICY_ROOT}"

  require_cmd "${KUBECTL_BIN}"
  require_cmd "${KYVERNO_BIN}"

  kubeconfig_input="${KUBECONFIG:-${HOME}/.kube/config}"
  kubeconfig_rendered="$(mktemp "${TMPDIR:-/tmp}/kyverno-kubeconfig.XXXXXX")"
  rendered_policies="$(mktemp "${TMPDIR:-/tmp}/kyverno-policies.XXXXXX.yaml")"
  LIVE_VALIDATION_TMP_KUBECONFIG="${kubeconfig_rendered}"
  LIVE_VALIDATION_TMP_POLICIES="${rendered_policies}"
  trap cleanup_live_validation EXIT

  KUBECONFIG="${kubeconfig_input}" "${KUBECTL_BIN}" config view --raw >"${kubeconfig_rendered}"
  "${KUBECTL_BIN}" --kubeconfig "${kubeconfig_rendered}" cluster-info >/dev/null
  "${KUBECTL_BIN}" kustomize "${POLICY_ROOT}" >"${rendered_policies}"

  "${KYVERNO_BIN}" apply "${rendered_policies}" \
    --cluster \
    --policy-report \
    --remove-color \
    --kubeconfig "${kubeconfig_rendered}"

  echo "OK   kyverno live policy validation"
  cleanup_live_validation
  trap - EXIT
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
      exit 1
      ;;
    *)
      mode="$1"
      ;;
  esac
  shift
done

shell_cli_maybe_execute_or_preview_summary usage \
  "would run Kyverno policy validation in ${mode} mode"

case "${mode}" in
  static)
    run_static_validation
    ;;
  live)
    run_live_validation
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    fail "unknown mode: ${mode}"
    ;;
esac
