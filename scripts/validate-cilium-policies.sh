#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
POLICY_ROOT="${CILIUM_POLICY_ROOT:-${REPO_ROOT}/terraform/kubernetes/cluster-policies/cilium}"
RENDER_SCRIPT="${RENDER_CILIUM_POLICY_VALUES_SCRIPT:-${REPO_ROOT}/terraform/kubernetes/scripts/render-cilium-policy-values.sh}"
INSTALL_HINTS_SCRIPT="${INSTALL_HINTS_SCRIPT:-${REPO_ROOT}/scripts/install-tool-hints.sh}"
KUBECTL_BIN="${KUBECTL_BIN:-kubectl}"
CILIUM_IMAGE_VERSION_FILE="${CILIUM_IMAGE_VERSION_FILE:-${REPO_ROOT}/terraform/kubernetes/variables.tf}"
LIVE_VALIDATION_TMP_KUBECONFIG=""
mode="${1:-static}"

usage() {
  cat <<'EOF'
Usage: validate-cilium-policies.sh [static|live]

static
    Validate the repo's checked-in Cilium policy sources and kustomize overlays.

live
    Run Cilium's live cluster validator via cilium-dbg preflight validate-cnp
    using the current kubeconfig context.
EOF
}

fail() {
  echo "FAIL $*" >&2
  exit 1
}

require_cmd() {
  local tool="$1"

  if command -v "${tool}" >/dev/null 2>&1; then
    return 0
  fi

  echo "FAIL ${tool} not found in PATH" >&2
  if [[ -x "${INSTALL_HINTS_SCRIPT}" ]]; then
    echo "" >&2
    echo "Install hints:" >&2
    "${INSTALL_HINTS_SCRIPT}" --plain "${tool}" | sed 's/^/  /' >&2 || true
  fi
  exit 1
}

find_running_cilium_pod() {
  local kubeconfig="$1"
  local selector pod
  local selectors=(
    "k8s-app=cilium"
    "app.kubernetes.io/name=cilium-agent"
    "app.kubernetes.io/part-of=cilium"
  )

  for selector in "${selectors[@]}"; do
    pod="$(
      "${KUBECTL_BIN}" --kubeconfig "${kubeconfig}" -n kube-system get pods \
        -l "${selector}" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
    )"
    if [[ -n "${pod}" ]]; then
      printf '%s\n' "${pod}"
      return 0
    fi
  done

  return 1
}

resolve_cilium_version() {
  local version

  version="$(
    sed -n '/variable "cilium_version"/,/^}/p' "${CILIUM_IMAGE_VERSION_FILE}" \
      | sed -n 's/^[[:space:]]*default[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' \
      | head -n 1
  )"
  [[ -n "${version}" ]] || fail "could not resolve cilium_version from ${CILIUM_IMAGE_VERSION_FILE}"
  printf '%s\n' "${version}"
}

list_cilium_policy_files() {
  find "${POLICY_ROOT}" -type f \( -name '*.yaml' -o -name '*.yml' \) ! -name 'kustomization.yaml' | LC_ALL=C sort
}

list_kustomize_dirs() {
  find "${POLICY_ROOT}" -type f -name 'kustomization.yaml' -print \
    | while IFS= read -r file; do
        dirname "${file}"
      done \
    | LC_ALL=C sort -u
}

run_static_validation() {
  local file kind validated_files rendered_dirs

  [[ -d "${POLICY_ROOT}" ]] || fail "missing Cilium policy root: ${POLICY_ROOT}"
  [[ -x "${RENDER_SCRIPT}" ]] || fail "render script is not executable: ${RENDER_SCRIPT}"

  require_cmd "${KUBECTL_BIN}"
  require_cmd yq
  require_cmd jq

  validated_files=0
  while IFS= read -r file; do
    [[ -n "${file}" ]] || continue
    kind="$(yq eval 'select(documentIndex == 0) | .kind // ""' "${file}" 2>/dev/null || true)"
    case "${kind}" in
      CiliumNetworkPolicy|CiliumClusterwideNetworkPolicy)
        "${RENDER_SCRIPT}" "${file}" >/dev/null
        validated_files=$((validated_files + 1))
        ;;
    esac
  done < <(list_cilium_policy_files)

  rendered_dirs=0
  while IFS= read -r dir; do
    [[ -n "${dir}" ]] || continue
    "${KUBECTL_BIN}" kustomize "${dir}" >/dev/null
    rendered_dirs=$((rendered_dirs + 1))
  done < <(list_kustomize_dirs)

  echo "OK   validated ${validated_files} Cilium policy manifest file(s)"
  echo "OK   rendered ${rendered_dirs} Cilium kustomize overlay(s)"
}

run_live_validation() {
  local kubeconfig_input kubeconfig_rendered cilium_version image cilium_pod
  local -a runner

  require_cmd "${KUBECTL_BIN}"

  kubeconfig_input="${KUBECONFIG:-${HOME}/.kube/config}"
  kubeconfig_rendered="$(mktemp "${TMPDIR:-/tmp}/cilium-kubeconfig.XXXXXX")"
  LIVE_VALIDATION_TMP_KUBECONFIG="${kubeconfig_rendered}"
  trap 'rm -f "${LIVE_VALIDATION_TMP_KUBECONFIG:-}"' EXIT

  KUBECONFIG="${kubeconfig_input}" "${KUBECTL_BIN}" config view --raw >"${kubeconfig_rendered}"
  "${KUBECTL_BIN}" --kubeconfig "${kubeconfig_rendered}" cluster-info >/dev/null

  if command -v cilium-dbg >/dev/null 2>&1; then
    runner=(cilium-dbg preflight validate-cnp --k8s-kubeconfig-path "${kubeconfig_rendered}")
    echo "INFO using local cilium-dbg"
  elif cilium_pod="$(find_running_cilium_pod "${kubeconfig_rendered}")"; then
    runner=(
      "${KUBECTL_BIN}" --kubeconfig "${kubeconfig_rendered}"
      -n kube-system
      exec "${cilium_pod}"
      --
      cilium-dbg preflight validate-cnp
    )
    echo "INFO using in-cluster ${cilium_pod}"
  else
    require_cmd docker
    if ! docker info >/dev/null 2>&1; then
      fail "docker daemon not reachable; required for containerized cilium-dbg validation"
    fi
    cilium_version="$(resolve_cilium_version)"
    image="quay.io/cilium/cilium:v${cilium_version}"
    runner=(
      docker run --rm
      -v "${kubeconfig_rendered}:${kubeconfig_rendered}:ro"
      "${image}"
      cilium-dbg preflight validate-cnp
      --k8s-kubeconfig-path "${kubeconfig_rendered}"
    )
    echo "INFO using ${image}"
  fi

  "${runner[@]}"
  echo "OK   cilium live policy validation"
  rm -f "${kubeconfig_rendered}"
  LIVE_VALIDATION_TMP_KUBECONFIG=""
  trap - EXIT
}

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
