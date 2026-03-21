#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/terraform/kubernetes/scripts/check-version.sh"
  export TF_DEFAULTS_SCRIPT="${REPO_ROOT}/terraform/kubernetes/scripts/tf-defaults.sh"
  export KIND_KUBECONFIG="${HOME}/.kube/kind-kind-local.yaml"
}

@test "check-version reports vendored Argo chart apps from live resource labels" {
  if ! command -v kubectl >/dev/null 2>&1; then
    skip "kubectl is required"
  fi

  if ! command -v timeout >/dev/null 2>&1; then
    skip "timeout is required"
  fi

  if [ ! -f "${KIND_KUBECONFIG}" ]; then
    skip "kind kubeconfig not found"
  fi

  if ! KUBECONFIG="${KIND_KUBECONFIG}" kubectl get ns --request-timeout=5s >/dev/null 2>&1; then
    skip "kind cluster is not reachable"
  fi

  local expected_gitea expected_policy_reporter expected_prometheus
  expected_gitea="$(bash -lc "source '${TF_DEFAULTS_SCRIPT}'; tf_default_from_variables gitea_chart_version")"
  expected_policy_reporter="$(bash -lc "source '${TF_DEFAULTS_SCRIPT}'; tf_default_from_variables policy_reporter_chart_version")"
  expected_prometheus="$(bash -lc "source '${TF_DEFAULTS_SCRIPT}'; tf_default_from_variables prometheus_chart_version")"

  run env KUBECONFIG="${KIND_KUBECONFIG}" timeout 300 "${SCRIPT}"

  [ "${status}" -eq 0 ]
  [[ "${output}" =~ gitea\ chart[[:space:]]+${expected_gitea}[[:space:]]+${expected_gitea} ]]
  [[ "${output}" =~ policy-reporter[[:space:]]+${expected_policy_reporter}[[:space:]]+${expected_policy_reporter} ]]
  [[ "${output}" =~ prometheus\ chart[[:space:]]+${expected_prometheus}[[:space:]]+${expected_prometheus} ]]
  [[ ! "${output}" =~ gitea\ chart[[:space:]]+${expected_gitea}[[:space:]]+$ ]]
  [[ ! "${output}" =~ policy-reporter[[:space:]]+${expected_policy_reporter}[[:space:]]+$ ]]
  [[ ! "${output}" =~ prometheus\ chart[[:space:]]+${expected_prometheus}[[:space:]]+$ ]]
}

@test "check-version reports kind tool version status" {
  if ! command -v kind >/dev/null 2>&1; then
    skip "kind is required"
  fi

  run env KUBECONFIG="${KIND_KUBECONFIG}" timeout 300 "${SCRIPT}"

  [ "${status}" -eq 0 ]
  [[ "${output}" =~ Tool\ versions ]]
  [[ "${output}" =~ kind\ cli[[:space:]]+v?[0-9]+\.[0-9]+\.[0-9]+ ]]
}

@test "check-version derives preferred hardened tags from latest appVersion" {
  run bash -lc "export CHECK_VERSION_LIB_ONLY=1; source '${SCRIPT}'; printf '%s\n' \"\$(derive_tag_with_existing_suffix 'v3.3.5' '3.3.4-debian13')\" \"\$(derive_tag_with_existing_suffix '3.3.5' 'v3.3.4-debian13')\""

  [ "${status}" -eq 0 ]
  [ "${output}" = "$(printf '3.3.5-debian13\nv3.3.5-debian13')" ]
}

@test "check-version classifies docker manifest probe results" {
  local stub_bin="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${stub_bin}"

  cat >"${stub_bin}/docker" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "manifest" ] && [ "$2" = "inspect" ]; then
  case "$3" in
    available/image:1) exit 0 ;;
    private/image:1) echo "unauthorized: authentication required" >&2; exit 1 ;;
    missing/image:1) echo "no such manifest" >&2; exit 1 ;;
  esac
fi
exit 2
EOF
  chmod +x "${stub_bin}/docker"

  run bash -lc "export CHECK_VERSION_LIB_ONLY=1 PATH='${stub_bin}:'\"\$PATH\"; source '${SCRIPT}'; printf '%s\n' \"\$(image_ref_availability 'available/image:1')\" \"\$(image_ref_availability 'private/image:1')\" \"\$(image_ref_availability 'missing/image:1')\""

  [ "${status}" -eq 0 ]
  [ "${output}" = "$(printf 'available\nauth-required\nmissing')" ]
}
