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

  run env KUBECONFIG="${KIND_KUBECONFIG}" timeout 300 "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" =~ gitea\ chart[[:space:]]+${expected_gitea}[[:space:]]+${expected_gitea} ]]
  [[ "${output}" =~ policy-reporter[[:space:]]+${expected_policy_reporter}[[:space:]]+${expected_policy_reporter} ]]
  [[ "${output}" =~ prometheus\ chart[[:space:]]+${expected_prometheus}[[:space:]]+${expected_prometheus} ]]
  [[ ! "${output}" =~ gitea\ chart[[:space:]]+${expected_gitea}[[:space:]]+$ ]]
  [[ ! "${output}" =~ policy-reporter[[:space:]]+${expected_policy_reporter}[[:space:]]+$ ]]
  [[ ! "${output}" =~ prometheus\ chart[[:space:]]+${expected_prometheus}[[:space:]]+$ ]]
}

@test "check-version reports kind release and node tag status" {
  if ! command -v kind >/dev/null 2>&1; then
    skip "kind is required"
  fi

  run env KUBECONFIG="${KIND_KUBECONFIG}" timeout 300 "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" =~ Kind\ versions ]]
  [[ "${output}" =~ kind\ release\ tag[[:space:]]+v?[0-9]+\.[0-9]+\.[0-9]+ ]]
  [[ "${output}" =~ kind\ node\ tag[[:space:]]+v[0-9]+\.[0-9]+\.[0-9]+ ]]
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

@test "check-version parses app cooldown policies and locked dependency versions" {
  run bash -lc "export CHECK_VERSION_LIB_ONLY=1; source '${SCRIPT}'; printf '%s\n' \
    \"\$(js_dependency_cooldown_seconds '${REPO_ROOT}/apps/subnet-calculator')\" \
    \"\$(bun_lock_resolved_version '${REPO_ROOT}/apps/subnet-calculator/bun.lock' '@azure/static-web-apps-cli')\" \
    \"\$(python_dependency_cooldown_cutoff '${REPO_ROOT}/apps/subnet-calculator/apim-simulator')\" \
    \"\$(uv_lock_resolved_version '${REPO_ROOT}/apps/subnet-calculator/apim-simulator/uv.lock' 'anyio')\""

  [ "${status}" -eq 0 ]
  [ "${output}" = "$(printf '604800\n2.0.8\n2026-04-04T13:01:24.862941Z\n4.12.1')" ]
}

@test "check-version classifies internal image refs and docker hub repositories" {
  run bash -lc "export CHECK_VERSION_LIB_ONLY=1; source '${SCRIPT}'; \
    if image_ref_is_internal 'localhost:30090/platform/subnetcalc-api:latest'; then echo internal; else echo external; fi; \
    if image_ref_is_internal 'ghcr.io/nginx/nginx-gateway-fabric:2.4.1'; then echo internal; else echo external; fi; \
    printf '%s\n' \"\$(image_ref_registry 'gitea/act_runner:0.2.13')\" \"\$(image_ref_repository 'gitea/act_runner:0.2.13')\""

  [ "${status}" -eq 0 ]
  [ "${output}" = "$(printf 'internal\nexternal\ndocker.io\ngitea/act_runner')" ]
}

@test "check-version reports not deployed current components as current" {
  run bash -lc "export CHECK_VERSION_LIB_ONLY=1; source '${SCRIPT}'; CLUSTER_OK=1; print_row 'signoz chart' '' '0.118.0' '0.118.0' '' 'v0.118.0' '' 'v0.118.0' '0'"

  [ "${status}" -eq 0 ]
  [[ "${output}" =~ not\ deployed\;\ codebase\ ==\ latest\ \(0\.118\.0\) ]]
  [[ ! "${output}" =~ not\ deployed\;\ latest\ ==\ 0\.118\.0 ]]
}

@test "check-version renders long tags with aligned spacing" {
  run bash -lc "export CHECK_VERSION_LIB_ONLY=1; source '${SCRIPT}'; printf '%s\n' \$'Component\tDeployTag\tCodeTag\tStatus' \$'---------\t---------\t-------\t------' \$'argo-cd chart\t3.3.6-debian13\tv3.3.6\tok' \$'cert-manager\tv1.20.1\tv1.20.1\tok' | render_tsv_table"

  [ "${status}" -eq 0 ]
  [[ "${output}" =~ argo-cd\ chart[[:space:]]+3\.3\.6-debian13[[:space:]][[:space:]]+v3\.3\.6[[:space:]][[:space:]]+ok ]]
}
