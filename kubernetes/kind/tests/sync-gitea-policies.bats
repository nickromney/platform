#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/terraform/kubernetes/scripts/sync-gitea-policies.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN}"
  export PATH="${TEST_BIN}:${PATH}"

  cat >"${TEST_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/curl"

  cat >"${TEST_BIN}/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/git"

  cat >"${TEST_BIN}/helm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cmd="${1:-}"
shift || true
case "${cmd}" in
  repo)
    exit 0
    ;;
  pull)
    ref="${1:?missing chart ref}"
    shift
    chart="${ref##*/}"
    untardir=""
    version=""
    while [[ $# -gt 0 ]]; do
      case "${1}" in
        --version)
          version="${2}"
          shift 2
          ;;
        --untar)
          shift
          ;;
        --untardir)
          untardir="${2}"
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    mkdir -p "${untardir}/${chart}"
    cat >"${untardir}/${chart}/Chart.yaml" <<OUT
apiVersion: v2
name: ${chart}
version: ${version}
OUT
    if [[ "${chart}" == "headlamp" ]]; then
      mkdir -p "${untardir}/${chart}/templates"
      cat >"${untardir}/${chart}/templates/deployment.yaml" <<'OUT'
{{- if hasKey .Values.config "sessionTTL" }}
            - "-session-ttl={{ .Values.config.sessionTTL }}"
            {{- end }}
OUT
      cat >"${untardir}/${chart}/values.schema.json" <<'OUT'
{
  "properties": {
    "config": {
      "properties": {
        "sessionTTL": {
          "type": "integer",
          "description": "The time in seconds for the session to be valid",
          "default": 86400,
          "minimum": 1,
          "maximum": 31536000
        }
      }
    }
  }
}
OUT
    fi
    exit 0
    ;;
esac
exit 0
EOF
  chmod +x "${TEST_BIN}/helm"

  export STACK_DIR="${BATS_TEST_TMPDIR}/stack"
  mkdir -p "${STACK_DIR}/scripts"
  cat >"${STACK_DIR}/scripts/gitea-local-access.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

gitea_local_access_setup() {
  return 0
}

gitea_local_access_reset() {
  return 0
}

gitea_local_access_cleanup() {
  return 0
}
EOF
  chmod +x "${STACK_DIR}/scripts/gitea-local-access.sh"
  export GITEA_HTTP_BASE="http://127.0.0.1:30090"
  export GITEA_ADMIN_USERNAME="gitea-admin"
  export GITEA_ADMIN_PWD="test-admin-password"
  export GITEA_SSH_USERNAME="git"
  export GITEA_SSH_HOST="127.0.0.1"
  export GITEA_SSH_PORT="30022"
  export GITEA_REPO_OWNER="platform"
  export GITEA_REPO_NAME="policies"
  export DEPLOY_KEY_TITLE="argocd-policies-repo-key"
  export DEPLOY_PUBLIC_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey"
  export SSH_PRIVATE_KEY_PATH="${BATS_TEST_TMPDIR}/id_ed25519"
  export POLICIES_REPO_URL_CLUSTER="ssh://git@gitea-ssh.gitea.svc.cluster.local:22/platform/policies.git"
  touch "${SSH_PRIVATE_KEY_PATH}"
}

@test "rewrite_external_argocd_apps_to_vendored_charts vendors and rewrites external chart apps" {
  apps_dir="${BATS_TEST_TMPDIR}/apps"
  vendor_root="${BATS_TEST_TMPDIR}/vendor"
  mkdir -p "${apps_dir}"

  cat >"${apps_dir}/001-cert-manager.application.yaml" <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cert-manager
spec:
  source:
    repoURL: https://charts.jetstack.io
    chart: cert-manager
    targetRevision: v1.20.2
    helm:
      releaseName: cert-manager
EOF

  run bash -lc "source '${SCRIPT}'; rewrite_external_argocd_apps_to_vendored_charts '${apps_dir}' '${vendor_root}'"

  [ "${status}" -eq 0 ]
  [ -f "${vendor_root}/cert-manager/Chart.yaml" ]
  grep -Fq "repoURL: ${POLICIES_REPO_URL_CLUSTER}" "${apps_dir}/001-cert-manager.application.yaml"
  grep -Fq "targetRevision: main" "${apps_dir}/001-cert-manager.application.yaml"
  grep -Fq "path: apps/vendor/charts/cert-manager" "${apps_dir}/001-cert-manager.application.yaml"
  ! grep -Fq "chart: cert-manager" "${apps_dir}/001-cert-manager.application.yaml"
}

@test "clone_remote_repo disables ssh agents and prompts" {
  capture_file="${BATS_TEST_TMPDIR}/clone-ssh-command"
  export CAPTURE_FILE="${capture_file}"

  cat >"${TEST_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '200'
EOF
  chmod +x "${TEST_BIN}/curl"

  cat >"${TEST_BIN}/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cmd="${1:-}"
shift || true
case "${cmd}" in
  clone)
    printf '%s\n' "${GIT_SSH_COMMAND:-}" >"${CAPTURE_FILE:?}"
    dest="${@: -1}"
    mkdir -p "${dest}"
    exit 0
    ;;
esac
exit 0
EOF
  chmod +x "${TEST_BIN}/git"

  run bash -lc "export PATH='${TEST_BIN}':\"\$PATH\"; source '${SCRIPT}'; clone_remote_repo '${BATS_TEST_TMPDIR}/remote'; cat '${capture_file}'"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"-o IdentityAgent=none"* ]]
  [[ "${output}" == *"-o BatchMode=yes"* ]]
  [[ "${output}" == *"-o ConnectTimeout=5"* ]]
}

@test "push_rendered_repo disables ssh agents and prompts" {
  capture_file="${BATS_TEST_TMPDIR}/push-ssh-command"
  rendered_dir="${BATS_TEST_TMPDIR}/rendered"
  mkdir -p "${rendered_dir}"
  echo "policy: true" >"${rendered_dir}/policy.yaml"
  export CAPTURE_FILE="${capture_file}"

  cat >"${TEST_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '200'
EOF
  chmod +x "${TEST_BIN}/curl"

  cat >"${TEST_BIN}/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cmd="${1:-}"
shift || true
case "${cmd}" in
  init|config|add|commit|branch)
    exit 0
    ;;
  diff)
    exit 1
    ;;
  remote)
    subcmd="${1:-}"
    case "${subcmd}" in
      get-url)
        exit 1
        ;;
      add|set-url)
        exit 0
        ;;
    esac
    ;;
  push)
    printf '%s\n' "${GIT_SSH_COMMAND:-}" >"${CAPTURE_FILE:?}"
    exit 0
    ;;
esac
exit 0
EOF
  chmod +x "${TEST_BIN}/git"

  run bash -lc "export PATH='${TEST_BIN}':\"\$PATH\"; source '${SCRIPT}'; push_rendered_repo '${rendered_dir}'; cat '${capture_file}'"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"-o IdentityAgent=none"* ]]
  [[ "${output}" == *"-o BatchMode=yes"* ]]
  [[ "${output}" == *"-o ConnectTimeout=5"* ]]
}

@test "rewrite_external_argocd_apps_to_vendored_charts rejects unpinned external chart versions" {
  apps_dir="${BATS_TEST_TMPDIR}/apps"
  vendor_root="${BATS_TEST_TMPDIR}/vendor"
  mkdir -p "${apps_dir}"

  cat >"${apps_dir}/999-custom.application.yaml" <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: custom
spec:
  source:
    repoURL: https://example.invalid/charts
    chart: custom
    targetRevision: "*"
EOF

  run bash -lc "source '${SCRIPT}'; rewrite_external_argocd_apps_to_vendored_charts '${apps_dir}' '${vendor_root}'"

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"must use a pinned version"* ]]
}

@test "vendor_direct_tf_only_charts vendors dex headlamp and oauth2-proxy" {
  vendor_root="${BATS_TEST_TMPDIR}/vendor"

  run bash -lc "source '${SCRIPT}'; vendor_direct_tf_only_charts '${vendor_root}'"

  [ "${status}" -eq 0 ]
  [ -f "${vendor_root}/dex/Chart.yaml" ]
  [ -f "${vendor_root}/headlamp/Chart.yaml" ]
  [ -f "${vendor_root}/oauth2-proxy/Chart.yaml" ]
  grep -Fq '{{- with .Values.config.sessionTTL }}' "${vendor_root}/headlamp/templates/deployment.yaml"
  grep -Fq -- '- "-session-ttl={{ . }}"' "${vendor_root}/headlamp/templates/deployment.yaml"
  grep -Fq '"minimum": 0' "${vendor_root}/headlamp/values.schema.json"
}

@test "render_otel_gateway_manifest prefers VictoriaLogs when enabled and Loki is off" {
  apps_dir="${BATS_TEST_TMPDIR}/apps"
  mkdir -p "${apps_dir}"

  run bash -lc "export ENABLE_PROMETHEUS=true ENABLE_GRAFANA=true ENABLE_VICTORIA_LOGS=true ENABLE_LOKI=false ENABLE_TEMPO=false ENABLE_SIGNOZ=false ENABLE_OTEL_GATEWAY=false OPENTELEMETRY_COLLECTOR_CHART_VERSION=0.152.0; source '${SCRIPT}'; render_otel_gateway_manifest '${apps_dir}'; cat '${apps_dir}/96-otel-collector-prometheus.application.yaml'"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"otlphttp/victoria-logs"* ]]
  [[ "${output}" == *"/insert/opentelemetry/v1/logs"* ]]
  [[ "${output}" != *"otlphttp/loki"* ]]
}

@test "prune_argocd_app_manifests keeps cert-manager when gateway TLS is disabled but cert-manager stays enabled" {
  apps_dir="${BATS_TEST_TMPDIR}/apps"
  mkdir -p "${apps_dir}"

  cat >"${apps_dir}/001-cert-manager.application.yaml" <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cert-manager
EOF

  cat >"${apps_dir}/002-nginx-gateway-fabric.application.yaml" <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nginx-gateway-fabric
EOF

  run bash -lc "export ENABLE_CERT_MANAGER=true ENABLE_GATEWAY_TLS=false; source '${SCRIPT}'; prune_argocd_app_manifests '${apps_dir}'"

  [ "${status}" -eq 0 ]
  [ -f "${apps_dir}/001-cert-manager.application.yaml" ]
  [ ! -f "${apps_dir}/002-nginx-gateway-fabric.application.yaml" ]
}

@test "apply_external_platform_images rewrites signoz auth proxy when explicitly enabled" {
  repo_dir="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${repo_dir}/apps/platform-gateway-routes-sso"

  cat >"${repo_dir}/apps/platform-gateway-routes-sso/signoz-auth-proxy-deployment.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: signoz-auth-proxy
spec:
  template:
    spec:
      containers:
        - name: signoz-auth-proxy
          image: ghcr.io/scolastico-dev/s.containers/signoz-auth-proxy:latest
EOF

  run bash -lc "export PREFER_EXTERNAL_PLATFORM_IMAGES=true EXTERNAL_PLATFORM_IMAGE_SIGNOZ_AUTH_PROXY='host.docker.internal:5002/platform/signoz-auth-proxy:dev'; source '${SCRIPT}'; apply_external_platform_images '${repo_dir}'"

  [ "${status}" -eq 0 ]
  grep -Fq "image: host.docker.internal:5002/platform/signoz-auth-proxy:dev" "${repo_dir}/apps/platform-gateway-routes-sso/signoz-auth-proxy-deployment.yaml"
}

@test "render_grafana_application_manifest injects Grafana image and plugin values" {
  app_file="${BATS_TEST_TMPDIR}/95-grafana.application.yaml"

  cat >"${app_file}" <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
spec:
  source:
    helm:
      values: |
        image:
          registry: __GRAFANA_IMAGE_REGISTRY__
          repository: __GRAFANA_IMAGE_REPOSITORY__
          tag: __GRAFANA_IMAGE_TAG__
        sidecar:
          image:
            registry: __GRAFANA_SIDECAR_IMAGE_REGISTRY__
            repository: __GRAFANA_SIDECAR_IMAGE_REPOSITORY__
            tag: __GRAFANA_SIDECAR_IMAGE_TAG__
__GRAFANA_PLUGINS_VALUES__
        livenessProbe:
          initialDelaySeconds: __GRAFANA_LIVENESS_INITIAL_DELAY_SECONDS__
EOF

  run bash -lc "export GRAFANA_IMAGE_REGISTRY='docker.io' GRAFANA_IMAGE_REPOSITORY='grafana/grafana' GRAFANA_IMAGE_TAG='12.3.1' GRAFANA_SIDECAR_IMAGE_REGISTRY='quay.io' GRAFANA_SIDECAR_IMAGE_REPOSITORY='kiwigrid/k8s-sidecar' GRAFANA_SIDECAR_IMAGE_TAG='2.5.0' GRAFANA_VICTORIA_LOGS_PLUGIN_URL='https://example.test/plugin.zip;victoriametrics-logs-datasource' GRAFANA_LIVENESS_INITIAL_DELAY_SECONDS='120'; source '${SCRIPT}'; render_grafana_application_manifest '${app_file}'"

  [ "${status}" -eq 0 ]
  grep -Fq "registry: docker.io" "${app_file}"
  grep -Fq "repository: grafana/grafana" "${app_file}"
  grep -Fq "tag: 12.3.1" "${app_file}"
  grep -Fq "registry: quay.io" "${app_file}"
  grep -Fq "repository: kiwigrid/k8s-sidecar" "${app_file}"
  grep -Fq "tag: 2.5.0" "${app_file}"
  grep -Fq "https://example.test/plugin.zip;victoriametrics-logs-datasource" "${app_file}"
  grep -Fq "initialDelaySeconds: 120" "${app_file}"
}

@test "apply_external_platform_images can switch Grafana to a prebaked host image" {
  repo_dir="${BATS_TEST_TMPDIR}/repo"
  app_file="${repo_dir}/apps/argocd-apps/95-grafana.application.yaml"
  mkdir -p "${repo_dir}/apps/argocd-apps" "${repo_dir}/apps/platform-gateway-routes-sso"

  cat >"${repo_dir}/apps/platform-gateway-routes-sso/signoz-auth-proxy-deployment.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: signoz-auth-proxy
spec:
  template:
    spec:
      containers:
        - name: signoz-auth-proxy
          image: ghcr.io/scolastico-dev/s.containers/signoz-auth-proxy:latest
EOF

  cat >"${app_file}" <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
spec:
  source:
    helm:
      values: |
        image:
          registry: __GRAFANA_IMAGE_REGISTRY__
          repository: __GRAFANA_IMAGE_REPOSITORY__
          tag: __GRAFANA_IMAGE_TAG__
__GRAFANA_PLUGINS_VALUES__
EOF

  run bash -lc "export PREFER_EXTERNAL_PLATFORM_IMAGES=true EXTERNAL_PLATFORM_IMAGE_GRAFANA='host.docker.internal:5002/platform/grafana-victorialogs:12.3.1-v0.26.3'; source '${SCRIPT}'; apply_external_platform_images '${repo_dir}'; render_grafana_application_manifest '${app_file}'"

  [ "${status}" -eq 0 ]
  grep -Fq "registry: host.docker.internal:5002" "${app_file}"
  grep -Fq "repository: platform/grafana-victorialogs" "${app_file}"
  grep -Fq "tag: 12.3.1-v0.26.3" "${app_file}"
  grep -Fq "plugins: []" "${app_file}"
}
