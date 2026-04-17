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
  local expected_cutoff
  expected_cutoff="$(awk -F'\"' '/^exclude-newer = \"/ { print $2; exit }' "${REPO_ROOT}/apps/subnet-calculator/apim-simulator/uv.lock")"

  run bash -lc "export CHECK_VERSION_LIB_ONLY=1; source '${SCRIPT}'; printf '%s\n' \
    \"\$(js_dependency_cooldown_seconds '${REPO_ROOT}/apps/subnet-calculator')\" \
    \"\$(bun_lock_resolved_version '${REPO_ROOT}/apps/subnet-calculator/bun.lock' '@azure/static-web-apps-cli')\" \
    \"\$(python_dependency_cooldown_cutoff '${REPO_ROOT}/apps/subnet-calculator/apim-simulator')\" \
    \"\$(uv_lock_resolved_version '${REPO_ROOT}/apps/subnet-calculator/apim-simulator/uv.lock' 'anyio')\""

  [ "${status}" -eq 0 ]
  [ "${output}" = "$(printf '604800\n2.0.8\n%s\n4.12.1' "${expected_cutoff}")" ]
}

@test "check-version collects only project dependencies from pyproject arrays" {
  run bash -lc "
    tmp_root='${BATS_TEST_TMPDIR}/repo'
    mkdir -p \"\${tmp_root}/apps/with-comments\" \"\${tmp_root}/apps/empty-inline\"

    cat >\"\${tmp_root}/apps/with-comments/pyproject.toml\" <<'EOF'
[project]
name = \"with-comments\"
version = \"0.1.0\"
dependencies = [
    \"fastapi[standard]>=0.118.0\",  # inline comment
    \"httpx>=0.28.1\",
]

[project.optional-dependencies]
dev = [
    \"pytest>=8.0.0\",
]
EOF

    cat >\"\${tmp_root}/apps/empty-inline/pyproject.toml\" <<'EOF'
[project]
name = \"empty-inline\"
version = \"0.1.0\"
dependencies = []

[dependency-groups]
dev = [
    \"playwright>=1.55.0\",
]
EOF

    export CHECK_VERSION_LIB_ONLY=1
    source '${SCRIPT}'
    REPO_ROOT=\"\${tmp_root}\"
    collect_python_dependency_names | LC_ALL=C sort -u
  "

  [ "${status}" -eq 0 ]
  [ "${output}" = "$(printf 'fastapi\nhttpx')" ]
}

@test "check-version classifies internal image refs and docker hub repositories" {
  run bash -lc "export CHECK_VERSION_LIB_ONLY=1; source '${SCRIPT}'; \
    if image_ref_is_internal 'localhost:30090/platform/subnetcalc-api:latest'; then echo internal; else echo external; fi; \
    if image_ref_is_internal 'ghcr.io/nginx/nginx-gateway-fabric:2.5.1'; then echo internal; else echo external; fi; \
    printf '%s\n' \"\$(image_ref_registry 'gitea/act_runner:0.4.0')\" \"\$(image_ref_repository 'gitea/act_runner:0.4.0')\""

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

@test "check-version converts TSV rows into JSON objects without ANSI codes" {
  run bash -lc "export CHECK_VERSION_LIB_ONLY=1; source '${SCRIPT}'; printf '%b\n' \$'argo-cd chart\t9.5.0\t9.5.1\t\033[1;33mupdate available\033[0m' | tsv_rows_to_json_array '[\"component\",\"codebase\",\"latest\",\"status\"]'"

  [ "${status}" -eq 0 ]

  run jq -r '.[0].component + "|" + .[0].status' <<<"${output}"

  [ "${status}" -eq 0 ]
  [ "${output}" = "argo-cd chart|update available" ]
}

@test "check-version hides current-only apps from dependency audit text" {
  run bash -lc "export CHECK_VERSION_LIB_ONLY=1; source '${SCRIPT}'; rows=\$(cat <<'EOF'
apps/sentiment/frontend-react-vite/sentiment-auth-ui\treact\t19.2.5\t19.2.5\t19.2.5\tcurrent
apps/sentiment/frontend-react-vite/sentiment-auth-ui\treact-dom\t19.2.5\t19.2.5\t19.2.5\tcurrent
apps/subnet-calculator/frontend-react\tleft-pad\t1.0.0\t1.0.1\t1.0.1\tupdate available
EOF
); render_dependency_audit_text \"\${rows}\""

  [ "${status}" -eq 0 ]
  [[ ! "${output}" =~ apps/sentiment/frontend-react-vite/sentiment-auth-ui ]]
  [[ "${output}" =~ apps/subnet-calculator/frontend-react ]]
  [[ "${output}" =~ hidden\ current-only\ apps:\ 1\ \(dependencies\ hidden:\ 2\) ]]
}

@test "check-version honors npm cooldown timestamps with fractional seconds" {
  local stub_bin="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${stub_bin}"

  cat >"${stub_bin}/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"dist-tags":{"latest":"1.1.0"},"time":{"created":"2026-04-01T00:00:00.000Z","modified":"2026-04-17T00:00:00.000Z","1.0.0":"2026-04-01T00:00:00.000Z","1.1.0":"2026-04-15T00:00:00.000Z"}}'
EOF
  chmod +x "${stub_bin}/curl"

  run bash -lc "export CHECK_VERSION_LIB_ONLY=1 PATH='${stub_bin}:'\"\$PATH\"; source '${SCRIPT}'; printf '%s\n' \"\$(npm_latest_eligible_version example 604800)\" \"\$(dependency_update_status 1.0.0 \"\$(npm_latest_eligible_version example 604800)\" \"\$(npm_latest_overall_version example)\")\""

  [ "${status}" -eq 0 ]
  [ "${output}" = "$(printf '1.0.0\ncooldown active')" ]
}

@test "check-version help advertises prerelease channel toggles as opt-in" {
  run bash "${SCRIPT}" --help

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"CHECK_VERSION_INCLUDE_CANARY=1"* ]]
  [[ "${output}" == *"CHECK_VERSION_INCLUDE_ALPHA=1"* ]]
  [[ "${output}" == *"CHECK_VERSION_INCLUDE_PRERELEASE=1"* ]]
  [[ "${output}" == *"All prerelease channels default to off"* ]]
}

@test "check-version keeps npm alpha releases disabled unless alpha is explicitly enabled" {
  local stub_bin="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${stub_bin}"

  cat >"${stub_bin}/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"dist-tags":{"latest":"1.0.0"},"time":{"created":"2026-04-01T00:00:00.000Z","modified":"2026-04-17T00:00:00.000Z","1.0.0":"2026-04-01T00:00:00.000Z","1.1.0-alpha.1":"2026-04-05T00:00:00.000Z"}}'
EOF
  chmod +x "${stub_bin}/curl"

  run bash -lc "export CHECK_VERSION_LIB_ONLY=1 PATH='${stub_bin}:'\"\$PATH\"; source '${SCRIPT}'; printf '%s\n' \"\$(npm_latest_eligible_version example 604800)\" \"\$(CHECK_VERSION_INCLUDE_PRERELEASE=1 npm_latest_eligible_version example 604800)\" \"\$(CHECK_VERSION_INCLUDE_ALPHA=1 npm_latest_eligible_version example 604800)\""

  [ "${status}" -eq 0 ]
  [ "${output}" = "$(printf '1.0.0\n1.0.0\n1.1.0-alpha.1')" ]
}

@test "check-version keeps npm canary releases disabled unless canary is explicitly enabled" {
  local stub_bin="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${stub_bin}"

  cat >"${stub_bin}/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"dist-tags":{"latest":"19.2.5"},"time":{"created":"2026-04-01T00:00:00.000Z","modified":"2026-04-17T00:00:00.000Z","19.2.5":"2026-04-01T00:00:00.000Z","19.3.0-canary-fd524fe0-20251121":"2026-04-10T00:00:00.000Z"}}'
EOF
  chmod +x "${stub_bin}/curl"

  run bash -lc "export CHECK_VERSION_LIB_ONLY=1 PATH='${stub_bin}:'\"\$PATH\"; source '${SCRIPT}'; printf '%s\n' \"\$(npm_latest_eligible_version example 604800)\" \"\$(CHECK_VERSION_INCLUDE_PRERELEASE=1 npm_latest_eligible_version example 604800)\" \"\$(CHECK_VERSION_INCLUDE_CANARY=1 npm_latest_eligible_version example 604800)\""

  [ "${status}" -eq 0 ]
  [ "${output}" = "$(printf '19.2.5\n19.2.5\n19.3.0-canary-fd524fe0-20251121')" ]
}

@test "check-version ignores PyPI prereleases by default during cooldown selection" {
  local stub_bin="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${stub_bin}"

  cat >"${stub_bin}/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"info":{"version":"0.28.1"},"releases":{"0.28.1":[{"upload_time_iso_8601":"2026-04-01T00:00:00.000Z"}],"1.0.dev3":[{"upload_time_iso_8601":"2026-04-05T00:00:00.000Z"}]}}'
EOF
  chmod +x "${stub_bin}/curl"

  run bash -lc "export CHECK_VERSION_LIB_ONLY=1 PATH='${stub_bin}:'\"\$PATH\"; source '${SCRIPT}'; printf '%s\n' \"\$(pypi_latest_eligible_version example 2026-04-10T00:00:00.000Z)\" \"\$(CHECK_VERSION_INCLUDE_PRERELEASE=1 pypi_latest_eligible_version example 2026-04-10T00:00:00.000Z)\""

  [ "${status}" -eq 0 ]
  [ "${output}" = "$(printf '0.28.1\n1.0.dev3')" ]
}

@test "check-version treats current prereleases ahead of stable as current" {
  run bash -lc "export CHECK_VERSION_LIB_ONLY=1; source '${SCRIPT}'; dependency_update_status '19.3.0-canary-fd524fe0-20251121' '19.2.5' '19.2.5'"

  [ "${status}" -eq 0 ]
  [ "${output}" = "current" ]
}

@test "check-version caches Docker Hub tag listings by repository" {
  local stub_bin="${BATS_TEST_TMPDIR}/bin"
  local call_counter="${BATS_TEST_TMPDIR}/curl-count"
  local cache_dir="${BATS_TEST_TMPDIR}/cache"
  mkdir -p "${stub_bin}" "${cache_dir}"

  cat >"${stub_bin}/curl" <<'EOF'
#!/usr/bin/env bash
count_file="${CHECK_VERSION_TEST_CURL_COUNT_FILE:?}"
count=0
if [ -f "${count_file}" ]; then
  count="$(cat "${count_file}")"
fi
printf '%s\n' "$((count + 1))" >"${count_file}"
printf '%s\n' '{"results":[{"name":"1.2.3"},{"name":"latest"}],"next":null}'
EOF
  chmod +x "${stub_bin}/curl"

  run bash -lc "export CHECK_VERSION_LIB_ONLY=1 CHECK_VERSION_CACHE_DIR='${cache_dir}' CHECK_VERSION_TEST_CURL_COUNT_FILE='${call_counter}' PATH='${stub_bin}:'\"\$PATH\"; source '${SCRIPT}'; printf '%s\n--\n%s\n' \"\$(docker_hub_repo_tags 'library' 'curl')\" \"\$(docker_hub_repo_tags 'library' 'curl')\""

  [ "${status}" -eq 0 ]
  [ "$(cat "${call_counter}")" = "1" ]
  [ "${output}" = "$(printf '1.2.3\nlatest\n--\n1.2.3\nlatest')" ]
}

@test "check-version external image audit separates updates from skipped references" {
  run bash -lc "export CHECK_VERSION_LIB_ONLY=1; source '${SCRIPT}'; rows=\$(cat <<'EOF'
apps/subnet-calculator/csharp-test/web-app/Dockerfile:10	mcr.microsoft.com/dotnet/aspnet:9.0	9.0	10.0.6	mcr.microsoft.com	update available
terraform/kubernetes/apps/argocd-apps/95-grafana.application.yaml:46	__GRAFANA_IMAGE_REGISTRY__/__GRAFANA_IMAGE_REPOSITORY__:__GRAFANA_IMAGE_TAG__			docker.io	templated image reference
docker/compose/compose.yml:35	dhi.io/dex:2.44.0-debian13			dhi.io	vendor-managed mirror
apps/sentiment/compose.yml:100	quay.io/oauth2-proxy/oauth2-proxy:v7.15.2	v7.15.2	v7.15.2	quay.io	current
EOF
); render_external_image_audit_text \"\${rows}\""

  [ "${status}" -eq 0 ]
  [[ "${output}" =~ updates\ available:\ 1 ]]
  [[ "${output}" =~ non-updatable\ references:\ 2 ]]
  [[ "${output}" =~ current\ hidden:\ 1 ]]
  [[ "${output}" =~ Updates: ]]
  [[ "${output}" =~ Skipped\ /\ non-updatable: ]]
  [[ "${output}" =~ mcr\.microsoft\.com/dotnet/aspnet:9\.0\ \(9\.0\ \-\>\ 10\.0\.6,\ mcr\.microsoft\.com\) ]]
  [[ "${output}" =~ templated\ image\ reference,\ docker\.io ]]
  [[ "${output}" =~ vendor-managed\ mirror,\ dhi\.io ]]
}

@test "check-version does not report older discovered image tags as updates" {
  run bash -lc "export CHECK_VERSION_LIB_ONLY=1; source '${SCRIPT}'; printf '%s\n' \
    \"\$(external_image_update_status '26.6.1' '23.0.4')\" \
    \"\$(external_image_update_status 'v7.15.2' 'v7.14.2')\" \
    \"\$(external_image_update_status '9.0' '10.0.6')\""

  [ "${status}" -eq 0 ]
  [ "${output}" = "$(printf 'current\ncurrent\nupdate available')" ]
}

@test "check-version resolves latest pinned image tags within the current release series" {
  run bash -lc "export CHECK_VERSION_LIB_ONLY=1; source '${SCRIPT}'; \
    docker_hub_repo_tags() { printf '%s\n' '3.14.4-alpine3.23' '3.12.14-alpine3.23' '3.12.13-alpine3.23'; }; \
    oci_registry_repo_tags() { printf '%s\n' '26.7.0' '26.6.2' '26.6.1'; }; \
    printf '%s\n' \
      \"\$(docker_hub_latest_tag_for_ref 'python:3.12.13-alpine3.23')\" \
      \"\$(oci_registry_latest_tag_for_ref 'quay.io/keycloak/keycloak:26.6.1')\""

  [ "${status}" -eq 0 ]
  [ "${output}" = "$(printf '3.12.14-alpine3.23\n26.6.2')" ]
}

@test "check-version treats floating track tags as unresolved rather than actionable updates" {
  run bash -lc "export CHECK_VERSION_LIB_ONLY=1; source '${SCRIPT}'; \
    docker_hub_repo_tags() { printf '%s\n' '10.0.6' '9.0.9' '9.0'; }; \
    oci_registry_repo_tags() { printf '%s\n' '4.1036.0' '4.1035.0'; }; \
    printf '%s\n' \
      \"\$(docker_hub_latest_tag_for_ref 'mcr.microsoft.com/dotnet/aspnet:9.0')\" \
      \"\$(oci_registry_latest_tag_for_ref 'mcr.microsoft.com/azure-functions/python:4-python3.13')\""

  [ "${status}" -eq 0 ]
  [ "${output}" = "$(printf '\n')" ]
}

@test "check-version parallel line mapper runs callbacks with bounded concurrency" {
  run bash -lc "export CHECK_VERSION_LIB_ONLY=1; source '${SCRIPT}'; callback() { sleep 1; printf '%s\n' \"processed:\$1\"; }; input_file='${BATS_TEST_TMPDIR}/items.txt'; output_dir='${BATS_TEST_TMPDIR}/out'; printf 'a\nb\nc\n' >\"\${input_file}\"; start=\$(date +%s); parallel_map_lines 2 callback \"\${input_file}\" \"\${output_dir}\"; elapsed=\$(( \$(date +%s) - start )); printf '__ELAPSED__=%s\n' \"\${elapsed}\""

  [ "${status}" -eq 0 ]
  [[ "${output}" =~ processed:a$'\n'processed:b$'\n'processed:c$'\n'__ELAPSED__= ]]
  [[ "${output}" =~ __ELAPSED__=2|__ELAPSED__=1 ]]
}
