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

create_minimal_policy_stack() {
  local stack_dir="$1"
  mkdir -p \
    "${stack_dir}/scripts" \
    "${stack_dir}/cluster-policies" \
    "${stack_dir}/apps/argocd-apps" \
    "${stack_dir}/apps/agentgateway-ai-gateway" \
    "${stack_dir}/apps/idp" \
    "${stack_dir}/apps/platform-gateway" \
    "${stack_dir}/apps/platform-gateway-routes" \
    "${stack_dir}/apps/platform-gateway-routes-sso"

  cat >"${stack_dir}/scripts/gitea-local-access.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
gitea_local_access_setup() { return 0; }
gitea_local_access_reset() { return 0; }
gitea_local_access_cleanup() { return 0; }
EOF

  cat >"${stack_dir}/apps/argocd-apps/95-grafana.application.yaml" <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: grafana
spec:
  source:
    repoURL: https://grafana.github.io/helm-charts
    chart: grafana
    targetRevision: 9.4.5
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
  cat >"${stack_dir}/apps/argocd-apps/73-agentgateway-ai-gateway.application.yaml" <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: agentgateway-ai-gateway
spec:
  source:
    path: apps/agentgateway-ai-gateway
EOF
  cat >"${stack_dir}/apps/argocd-apps/68-agentgateway-crds.application.yaml" <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: agentgateway-crds
spec:
  source:
    repoURL: ghcr.io/kgateway-dev/charts
    chart: agentgateway-crds
    targetRevision: v2.2.1
EOF
  cat >"${stack_dir}/apps/argocd-apps/69-agentgateway.application.yaml" <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: agentgateway
spec:
  source:
    repoURL: ghcr.io/kgateway-dev/charts
    chart: agentgateway
    targetRevision: v2.2.1
EOF

  cat >"${stack_dir}/apps/agentgateway-ai-gateway/all.yaml" <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: agentgateway-ai-gateway
spec:
  gatewayClassName: agentgateway
  infrastructure:
    parametersRef:
      group: agentgateway.dev
      kind: AgentgatewayParameters
      name: agentgateway-ai-gateway
---
apiVersion: agentgateway.dev/v1alpha1
kind: AgentgatewayParameters
metadata:
  name: agentgateway-ai-gateway
spec:
  deployment:
    spec:
      template:
        spec:
          securityContext:
            seccompProfile:
              type: RuntimeDefault
          containers:
            - name: agentgateway
              securityContext:
                seccompProfile:
                  type: RuntimeDefault
---
apiVersion: agentgateway.dev/v1alpha1
kind: AgentgatewayBackend
metadata:
  name: local-openai-compatible
spec:
  static:
    host: host.docker.internal
    port: 8000
  policies:
    auth:
      secretRef:
        name: omlx-secret
EOF

  cat >"${stack_dir}/apps/idp/all.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: idp-core
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: backstage
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backstage
---
apiVersion: v1
kind: Service
metadata:
  name: backstage
EOF

  cat >"${stack_dir}/apps/platform-gateway-routes/kustomization.yaml" <<'EOF'
resources:
  - httproute-gitea.yaml
  - httproute-agentgateway-ai-gateway.yaml
  - httproute-hubble.yaml
  - referencegrant-agentgateway-ai-gateway.yaml
  - referencegrant-hubble.yaml
EOF
  cat >"${stack_dir}/apps/platform-gateway-routes/httproute-gitea.yaml" <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: gitea
spec:
  hostnames:
    - gitea.admin.127.0.0.1.sslip.io
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - group: ""
          kind: Service
          name: oauth2-proxy-gitea
          namespace: sso
          port: 4180
          weight: 1
EOF
  cat >"${stack_dir}/apps/platform-gateway-routes/httproute-agentgateway-ai-gateway.yaml" <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: agentgateway-ai-gateway
spec:
  hostnames:
    - llm.127.0.0.1.sslip.io
EOF
  cat >"${stack_dir}/apps/platform-gateway-routes/referencegrant-agentgateway-ai-gateway.yaml" <<'EOF'
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: allow-gateway-routes-agentgateway-ai-gateway
EOF
  touch \
    "${stack_dir}/apps/platform-gateway-routes/httproute-hubble.yaml" \
    "${stack_dir}/apps/platform-gateway-routes/referencegrant-hubble.yaml"

  cat >"${stack_dir}/apps/platform-gateway-routes-sso/kustomization.yaml" <<'EOF'
resources:
  - httproute-portal.yaml
  - httproute-portal-api.yaml
  - httproute-hubble.yaml
  - httproute-grafana.yaml
  - httproute-agentgateway-ai-gateway.yaml
  - httproute-sentiment-dev.yaml
  - httproute-subnetcalc-dev.yaml
  - referencegrant-sso.yaml
  - referencegrant-agentgateway-ai-gateway.yaml
  - referencegrant-hubble.yaml
EOF
  touch \
    "${stack_dir}/apps/platform-gateway-routes-sso/httproute-portal.yaml" \
    "${stack_dir}/apps/platform-gateway-routes-sso/httproute-portal-api.yaml" \
    "${stack_dir}/apps/platform-gateway-routes-sso/httproute-hubble.yaml" \
    "${stack_dir}/apps/platform-gateway-routes-sso/httproute-grafana.yaml" \
    "${stack_dir}/apps/platform-gateway-routes-sso/httproute-sentiment-dev.yaml" \
    "${stack_dir}/apps/platform-gateway-routes-sso/httproute-subnetcalc-dev.yaml" \
    "${stack_dir}/apps/platform-gateway-routes-sso/referencegrant-hubble.yaml" \
  cp "${stack_dir}/apps/platform-gateway-routes/httproute-agentgateway-ai-gateway.yaml" \
    "${stack_dir}/apps/platform-gateway-routes-sso/httproute-agentgateway-ai-gateway.yaml"
  cp "${stack_dir}/apps/platform-gateway-routes/referencegrant-agentgateway-ai-gateway.yaml" \
    "${stack_dir}/apps/platform-gateway-routes-sso/referencegrant-agentgateway-ai-gateway.yaml"
  cat >"${stack_dir}/apps/platform-gateway-routes-sso/referencegrant-sso.yaml" <<'EOF'
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
spec:
  to:
    - group: ""
      kind: Service
      name: oauth2-proxy-backstage
    - group: ""
      kind: Service
      name: oauth2-proxy-hubble
    - group: ""
      kind: Service
      name: oauth2-proxy-idp-core
EOF
  cat >"${stack_dir}/apps/platform-gateway-routes-sso/observabilitypolicy-tracing.yaml" <<'EOF'
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: hubble
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: portal-api
EOF
}

copy_policy_render_fixture_stack() {
  local stack_dir="$1"
  local fixture_root="${REPO_ROOT}/kubernetes/kind/tests/fixtures/policy-render/source-stack"

  rm -rf "${stack_dir}"
  mkdir -p "$(dirname "${stack_dir}")"
  cp -R "${fixture_root}" "${stack_dir}"
}

assert_policy_render_tree_matches_golden() {
  local case_name="$1"
  local fixture_root="${REPO_ROOT}/kubernetes/kind/tests/fixtures/policy-render"
  local stack_dir="${BATS_TEST_TMPDIR}/stack-${case_name}"
  local actual_root="${BATS_TEST_TMPDIR}/render-${case_name}"
  local expected_repo="${fixture_root}/expected/${case_name}/repo"
  local contract_file="${fixture_root}/contracts/${case_name}.json"

  copy_policy_render_fixture_stack "${stack_dir}"

  run bash -lc "export STACK_DIR='${stack_dir}' GITOPS_RENDER_CONTRACT_FILE='${contract_file}'; source '${SCRIPT}'; render_policy_repo_tree '${actual_root}' >/dev/null"
  [ "${status}" -eq 0 ]

  run bash -lc "diff -ruN '${expected_repo}/apps' '${actual_root}/repo/apps' && diff -ruN '${expected_repo}/cluster-policies' '${actual_root}/repo/cluster-policies'"
  [ "${status}" -eq 0 ]
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

@test "post_repo_deploy_key sends normalized SSH public key identity" {
  capture_file="${BATS_TEST_TMPDIR}/deploy-key-payload.json"

  cat >"${TEST_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
while [[ $# -gt 0 ]]; do
  case "${1}" in
    -d)
      printf '%s' "${2}" >"${CAPTURE_FILE:?}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
printf '201'
EOF
  chmod +x "${TEST_BIN}/curl"

  run bash -lc "export PATH='${TEST_BIN}':\"\$PATH\" CAPTURE_FILE='${capture_file}' DEPLOY_PUBLIC_KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey local-comment'; source '${SCRIPT}'; post_repo_deploy_key; printf '\n'; jq -r '.key' '${capture_file}'"

  [ "${status}" -eq 0 ]
  [ "${lines[0]}" = "201" ]
  [ "${lines[1]}" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey" ]
}

@test "render_policy_repo_tree is callable without Gitea push runtime env" {
  stack_dir="${BATS_TEST_TMPDIR}/stack-render-only"
  create_minimal_policy_stack "${stack_dir}"

  run bash -lc "unset GITEA_ADMIN_USERNAME GITEA_ADMIN_PWD GITEA_SSH_USERNAME GITEA_REPO_OWNER GITEA_REPO_NAME DEPLOY_KEY_TITLE DEPLOY_PUBLIC_KEY SSH_PRIVATE_KEY_PATH GITEA_HTTP_BASE GITEA_SSH_HOST GITEA_SSH_PORT; export STACK_DIR='${stack_dir}' ENABLE_BACKSTAGE=true ENABLE_HUBBLE=false ENABLE_POLICIES=false ENABLE_GATEWAY_TLS=true ENABLE_HEADLAMP=false ENABLE_GRAFANA=false ENABLE_APP_REPO_SENTIMENT=false ENABLE_APP_REPO_SUBNETCALC=false ENABLE_PROMETHEUS=false; source '${SCRIPT}'; render_policy_repo_tree '${BATS_TEST_TMPDIR}/render-only' >/dev/null; test -f '${BATS_TEST_TMPDIR}/render-only/repo/apps/platform-gateway-routes/httproute-gitea.yaml'; declare -f render_policy_repo_tree"

  [ "${status}" -eq 0 ]
  [[ "${output}" != *"push_rendered_repo"* ]]
  [[ "${output}" != *"wait_for_gitea"* ]]
  [[ "${output}" != *"refresh_gitea_git_access"* ]]
}

@test "render_policy_repo_tree exposes APIM console on admin host behind SSO when APIM is enabled" {
  run bash -lc "export STACK_DIR='${REPO_ROOT}/terraform/kubernetes' ENABLE_BACKSTAGE=false ENABLE_HUBBLE=false ENABLE_POLICIES=false ENABLE_GATEWAY_TLS=true ENABLE_HEADLAMP=false ENABLE_GRAFANA=false ENABLE_APP_REPO_SENTIMENT=false ENABLE_APP_REPO_SUBNETCALC=false ENABLE_APIM_SIMULATOR=true ENABLE_AGENTGATEWAY_AI_GATEWAY=false ENABLE_PROMETHEUS=false ENABLE_VICTORIA_LOGS=false ENABLE_OTEL_GATEWAY=false ENABLE_OBSERVABILITY_AGENT=false ENABLE_SSO=true; source '${SCRIPT}'; render_policy_repo_tree '${BATS_TEST_TMPDIR}/render-apim-admin' >/dev/null; cat '${BATS_TEST_TMPDIR}/render-apim-admin/repo/apps/platform-gateway-routes-sso/httproute-apim.yaml'; printf '%s\n' '---GRANT---'; cat '${BATS_TEST_TMPDIR}/render-apim-admin/repo/apps/platform-gateway-routes-sso/referencegrant-sso.yaml'"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"apim.admin.127.0.0.1.sslip.io"* ]]
  [[ "${output}" == *"name: oauth2-proxy-apim"* ]]
}

@test "render_policy_repo_tree prunes APIM console route and SSO grant when APIM is disabled" {
  run bash -lc "export STACK_DIR='${REPO_ROOT}/terraform/kubernetes' ENABLE_BACKSTAGE=false ENABLE_HUBBLE=false ENABLE_POLICIES=false ENABLE_GATEWAY_TLS=true ENABLE_HEADLAMP=false ENABLE_GRAFANA=false ENABLE_APP_REPO_SENTIMENT=false ENABLE_APP_REPO_SUBNETCALC=false ENABLE_APIM_SIMULATOR=false ENABLE_AGENTGATEWAY_AI_GATEWAY=false ENABLE_PROMETHEUS=false ENABLE_VICTORIA_LOGS=false ENABLE_OTEL_GATEWAY=false ENABLE_OBSERVABILITY_AGENT=false ENABLE_SSO=true; source '${SCRIPT}'; render_policy_repo_tree '${BATS_TEST_TMPDIR}/render-apim-disabled' >/dev/null; test ! -f '${BATS_TEST_TMPDIR}/render-apim-disabled/repo/apps/platform-gateway-routes-sso/httproute-apim.yaml'; ! grep -Fq 'oauth2-proxy-apim' '${BATS_TEST_TMPDIR}/render-apim-disabled/repo/apps/platform-gateway-routes-sso/referencegrant-sso.yaml'"

  [ "${status}" -eq 0 ]
}

@test "render_policy_repo_tree includes lightweight Langfuse without Bitnami legacy images when enabled" {
  run bash -lc "export STACK_DIR='${REPO_ROOT}/terraform/kubernetes' ENABLE_BACKSTAGE=false ENABLE_HUBBLE=false ENABLE_POLICIES=false ENABLE_GATEWAY_TLS=true ENABLE_HEADLAMP=false ENABLE_GRAFANA=false ENABLE_APP_REPO_SENTIMENT=false ENABLE_APP_REPO_SUBNETCALC=false ENABLE_APIM_SIMULATOR=false ENABLE_AGENTGATEWAY_AI_GATEWAY=false ENABLE_LANGFUSE=true ENABLE_PROMETHEUS=false ENABLE_VICTORIA_LOGS=false ENABLE_OTEL_GATEWAY=false ENABLE_OBSERVABILITY_AGENT=false ENABLE_SSO=true; source '${SCRIPT}'; render_policy_repo_tree '${BATS_TEST_TMPDIR}/render-langfuse' >/dev/null; cat '${BATS_TEST_TMPDIR}/render-langfuse/repo/apps/argocd-apps/81-langfuse.application.yaml' '${BATS_TEST_TMPDIR}/render-langfuse/repo/apps/langfuse/all.yaml' '${BATS_TEST_TMPDIR}/render-langfuse/repo/apps/platform-gateway-routes-sso/httproute-langfuse.yaml' '${BATS_TEST_TMPDIR}/render-langfuse/repo/apps/platform-gateway-routes-sso/referencegrant-sso.yaml'"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"path: apps/langfuse"* ]]
  [[ "${output}" == *"ignoreDifferences:"* ]]
  [[ "${output}" == *".spec.volumeClaimTemplates[].status"* ]]
  [[ "${output}" == *"RespectIgnoreDifferences=true"* ]]
  [[ "${output}" == *"image: docker.io/langfuse/langfuse:3"* ]]
  [[ "${output}" == *"image: docker.io/langfuse/langfuse-worker:3"* ]]
  [[ "${output}" == *"image: docker.io/postgres:17.6-alpine"* ]]
  [[ "${output}" == *"image: docker.io/redis:8.2.7-alpine"* ]]
  [[ "${output}" == *"image: docker.io/clickhouse/clickhouse-server:25.5.11"* ]]
  [[ "${output}" == *"image: cgr.dev/chainguard/minio:latest"* ]]
  [[ "${output}" == *'encryption-key: "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"'* ]]
  [[ "${output}" == *"langfuse.admin.127.0.0.1.sslip.io"* ]]
  [[ "${output}" == *"name: oauth2-proxy-langfuse"* ]]
  [[ "${output}" != *"dhi.io/langfuse"* ]]
  [[ "${output}" != *"dhi.io/postgres"* ]]
  [[ "${output}" != *"dhi.io/redis"* ]]
  [[ "${output}" != *"bitnami"* ]]
  [[ "${output}" != *"bitnamilegacy"* ]]
}

@test "render_policy_repo_tree matches full golden tree for minimal contract" {
  assert_policy_render_tree_matches_golden "minimal"
}

@test "render_policy_repo_tree matches full golden tree for external observability contract" {
  assert_policy_render_tree_matches_golden "external-observability"
}

@test "GitOps feature Terraform test has a bounded runner" {
  runner="${REPO_ROOT}/terraform/kubernetes/scripts/tofu-test-gitops-features.sh"
  content="$(cat "${runner}")"

  [[ "${content}" == *"TOFU_GITOPS_FEATURES_TEST_TIMEOUT_SECONDS"* ]]
  [[ "${content}" == *"tests/gitops_features.tftest.hcl"* ]]
  [[ "${content}" == *"list_tofu_processes"* ]]
  [[ "${content}" == *"kill_process_tree"* ]]
  [[ "${content}" == *"return 124"* ]]

  run "${runner}" --dry-run
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"would run bounded tofu test -filter=tests/gitops_features.tftest.hcl"* ]]
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

@test "vendor_direct_tf_only_charts vendors headlamp and oauth2-proxy" {
  vendor_root="${BATS_TEST_TMPDIR}/vendor"

  run bash -lc "source '${SCRIPT}'; vendor_direct_tf_only_charts '${vendor_root}'"

  [ "${status}" -eq 0 ]
  [ -f "${vendor_root}/headlamp/Chart.yaml" ]
  [ -f "${vendor_root}/oauth2-proxy/Chart.yaml" ]
  grep -Fq '{{- if hasKey .Values.config "sessionTTL" }}' "${vendor_root}/headlamp/templates/deployment.yaml"
  grep -Fq -- '- "-session-ttl={{ .Values.config.sessionTTL }}"' "${vendor_root}/headlamp/templates/deployment.yaml"
  grep -Fq '"minimum": 1' "${vendor_root}/headlamp/values.schema.json"
}

@test "render_otel_gateway_manifest routes logs to VictoriaLogs" {
  apps_dir="${BATS_TEST_TMPDIR}/apps"
  mkdir -p "${apps_dir}"

  run bash -lc "export ENABLE_PROMETHEUS=true ENABLE_GRAFANA=true ENABLE_VICTORIA_LOGS=true ENABLE_OTEL_GATEWAY=false OPENTELEMETRY_COLLECTOR_CHART_VERSION=0.158.1; source '${SCRIPT}'; render_otel_gateway_manifest '${apps_dir}'; cat '${apps_dir}/96-otel-collector-prometheus.application.yaml'"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"otlphttp/victoria-logs"* ]]
  [[ "${output}" == *"/insert/opentelemetry/v1/logs"* ]]
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

@test "Backstage resource gate prunes portal workload route and SSO grant" {
  repo_dir="${BATS_TEST_TMPDIR}/repo"
  idp_manifest="${repo_dir}/apps/idp/all.yaml"
  routes_dir="${repo_dir}/apps/platform-gateway-routes-sso"
  mkdir -p "$(dirname "${idp_manifest}")" "${routes_dir}"

  cat >"${idp_manifest}" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: idp-core
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: backstage
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: backstage-kubernetes-reader
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: backstage-kubernetes-reader
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backstage
---
apiVersion: v1
kind: Service
metadata:
  name: backstage
EOF

  cat >"${routes_dir}/kustomization.yaml" <<'EOF'
resources:
  - httproute-portal.yaml
  - httproute-portal-api.yaml
  - referencegrant-sso.yaml
EOF
  touch "${routes_dir}/httproute-portal.yaml" "${routes_dir}/httproute-portal-api.yaml"
  cat >"${routes_dir}/referencegrant-sso.yaml" <<'EOF'
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
spec:
  to:
    - group: ""
      kind: Service
      name: oauth2-proxy-backstage
    - group: ""
      kind: Service
      name: oauth2-proxy-idp-core
EOF

  run bash -lc "export ENABLE_BACKSTAGE=false; source '${SCRIPT}'; remove_backstage_idp_resources '${idp_manifest}'; prune_gateway_routes_manifests '${routes_dir}'"

  [ "${status}" -eq 0 ]
  grep -Fq "name: idp-core" "${idp_manifest}"
  ! grep -Fq "name: backstage" "${idp_manifest}"
  [ ! -f "${routes_dir}/httproute-portal.yaml" ]
  [ -f "${routes_dir}/httproute-portal-api.yaml" ]
  ! grep -Fq "httproute-portal.yaml" "${routes_dir}/kustomization.yaml"
  ! grep -Fq "oauth2-proxy-backstage" "${routes_dir}/referencegrant-sso.yaml"
  grep -Fq "oauth2-proxy-idp-core" "${routes_dir}/referencegrant-sso.yaml"
}

@test "sync-gitea-policies can load render inputs from a GitOps render contract" {
  contract_file="${BATS_TEST_TMPDIR}/gitops-render-contract.json"
  cat >"${contract_file}" <<'EOF'
{
  "enable_backstage": false,
  "enable_prometheus": true,
  "enable_grafana": true,
  "enable_app_repo_sentiment": true,
  "prefer_external_images": true,
  "external_sentiment_api": "host.docker.internal:5002/platform/sentiment-api:contract",
  "external_sentiment_ui": "host.docker.internal:5002/platform/sentiment-auth-ui:contract",
  "prefer_external_platform": true,
  "external_platform_backstage": "host.docker.internal:5002/platform/backstage:contract",
  "external_platform_idp_core": "host.docker.internal:5002/platform/idp-core:contract",
  "grafana_image_registry": "host.docker.internal:5002",
  "grafana_image_repository": "platform/grafana-victorialogs",
  "grafana_image_tag": "contract",
  "grafana_victoria_logs_plugin_url": "",
  "grafana_liveness_initial_delay_seconds": 111
}
EOF

  run bash -lc "export GITOPS_RENDER_CONTRACT_FILE='${contract_file}'; source '${SCRIPT}'; printf '%s\n' \"\$ENABLE_BACKSTAGE\" \"\$ENABLE_PROMETHEUS\" \"\$ENABLE_GRAFANA\" \"\$ENABLE_APP_REPO_SENTIMENT\" \"\$PREFER_EXTERNAL_WORKLOAD_IMAGES\" \"\$EXTERNAL_IMAGE_SENTIMENT_API\" \"\$PREFER_EXTERNAL_PLATFORM_IMAGES\" \"\$EXTERNAL_PLATFORM_IMAGE_BACKSTAGE\" \"\$GRAFANA_IMAGE_REPOSITORY\" \"\$GRAFANA_LIVENESS_INITIAL_DELAY_SECONDS\""

  [ "${status}" -eq 0 ]
  [ "${output}" = "$(printf 'false\ntrue\ntrue\ntrue\ntrue\nhost.docker.internal:5002/platform/sentiment-api:contract\ntrue\nhost.docker.internal:5002/platform/backstage:contract\nplatform/grafana-victorialogs\n111')" ]
}

@test "render_prometheus_application_manifest injects alertmanager startup-safe resources" {
  apps_dir="${BATS_TEST_TMPDIR}/argocd-apps"
  mkdir -p "${apps_dir}"
  cat >"${apps_dir}/90-prometheus.application.yaml" <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
spec:
  source:
    helm:
      values: |
        alertmanager:
          enabled: false
        extraScrapeConfigs: |
          - job_name: demo
EOF

  run bash -lc "export ENABLE_ALERTMANAGER=true HARDENED_IMAGE_REGISTRY='registry.example.test/dhi'; source '${SCRIPT}'; render_prometheus_application_manifest '${apps_dir}/90-prometheus.application.yaml'; cat '${apps_dir}/90-prometheus.application.yaml'"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"repository: registry.example.test/dhi/alertmanager"* ]]
  [[ "${output}" == *$'resources:\n            requests:\n              cpu: 25m\n              memory: 64Mi\n            limits:\n              cpu: 200m\n              memory: 256Mi'* ]]
  [[ "${output}" != *"cpu: 40m"* ]]
  [[ "${output}" != *"memory: 96Mi"* ]]
}

@test "sync-gitea-policies contract renders external image tree changes" {
  repo_dir="${BATS_TEST_TMPDIR}/repo"
  workload_file="${repo_dir}/apps/sentiment/dev/all.yaml"
  idp_manifest="${repo_dir}/apps/idp/all.yaml"
  mcp_manifest="${repo_dir}/apps/mcp/all.yaml"
  chatgpt_manifest="${repo_dir}/apps/chatgpt-sim/all.yaml"
  contract_file="${BATS_TEST_TMPDIR}/gitops-render-contract.json"
  mkdir -p "$(dirname "${workload_file}")" "$(dirname "${idp_manifest}")" "$(dirname "${mcp_manifest}")" "$(dirname "${chatgpt_manifest}")"

  cat >"${workload_file}" <<'EOF'
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
        - name: sentiment-api
          image: platform/sentiment-api:latest
EOF
  cat >"${idp_manifest}" <<'EOF'
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
        - name: idp-core
          image: platform/idp-core:latest
        - name: backstage
          image: platform/backstage:latest
EOF
  cat >"${mcp_manifest}" <<'EOF'
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
        - name: platform-mcp
          image: localhost:30090/platform/platform-mcp:latest
EOF
  cat >"${chatgpt_manifest}" <<'EOF'
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
        - name: chatgpt-sim
          image: localhost:30090/platform/chatgpt-sim:latest
EOF

  cat >"${contract_file}" <<'EOF'
{
  "prefer_external_images": true,
  "external_sentiment_api": "host.docker.internal:5002/platform/sentiment-api:golden",
  "external_platform_mcp": "host.docker.internal:5002/platform/platform-mcp:golden",
  "external_platform_chatgpt_sim": "host.docker.internal:5002/platform/chatgpt-sim:golden",
  "prefer_external_platform": true,
  "external_platform_idp_core": "host.docker.internal:5002/platform/idp-core:golden",
  "external_platform_backstage": "host.docker.internal:5002/platform/backstage:golden"
}
EOF

  run bash -lc "export GITOPS_RENDER_CONTRACT_FILE='${contract_file}'; source '${SCRIPT}'; apply_external_workload_images '${workload_file}'; apply_external_platform_images '${repo_dir}'; cat '${workload_file}' '${idp_manifest}' '${mcp_manifest}' '${chatgpt_manifest}'"

  [ "${status}" -eq 0 ]
  [ "${output}" = "$(cat <<'EOF'
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
        - name: sentiment-api
          image: host.docker.internal:5002/platform/sentiment-api:golden
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
        - name: idp-core
          image: host.docker.internal:5002/platform/idp-core:golden
        - name: backstage
          image: host.docker.internal:5002/platform/backstage:golden
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
        - name: platform-mcp
          image: host.docker.internal:5002/platform/platform-mcp:golden
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
        - name: chatgpt-sim
          image: host.docker.internal:5002/platform/chatgpt-sim:golden
EOF
)" ]
}

@test "platform-mcp can render from platform image refs without workload shortcuts" {
  repo_dir="${BATS_TEST_TMPDIR}/repo"
  mcp_manifest="${repo_dir}/apps/mcp/all.yaml"
  contract_file="${BATS_TEST_TMPDIR}/gitops-render-contract.json"
  mkdir -p "$(dirname "${mcp_manifest}")"
  cat >"${mcp_manifest}" <<'EOF'
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
        - name: platform-mcp
          image: localhost:30090/platform/platform-mcp:latest
EOF
  cat >"${contract_file}" <<'EOF'
{
  "prefer_external_images": false,
  "prefer_external_platform": true,
  "external_platform_mcp": "host.docker.internal:5002/platform/platform-mcp:0.1.0"
}
EOF

  run bash -lc "export GITOPS_RENDER_CONTRACT_FILE='${contract_file}'; source '${SCRIPT}'; apply_external_workload_images '${mcp_manifest}'; apply_external_platform_images '${repo_dir}'; cat '${mcp_manifest}'"

  [ "${status}" -eq 0 ]
  grep -Fq "image: host.docker.internal:5002/platform/platform-mcp:0.1.0" <<<"${output}"
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

  run bash -lc "export PREFER_EXTERNAL_PLATFORM_IMAGES=true EXTERNAL_PLATFORM_IMAGE_GRAFANA='host.docker.internal:5002/platform/grafana-victorialogs:12.3.1-v0.28.0'; source '${SCRIPT}'; apply_external_platform_images '${repo_dir}'; render_grafana_application_manifest '${app_file}'"

  [ "${status}" -eq 0 ]
  grep -Fq "registry: host.docker.internal:5002" "${app_file}"
  grep -Fq "repository: platform/grafana-victorialogs" "${app_file}"
  grep -Fq "tag: 12.3.1-v0.28.0" "${app_file}"
  grep -Fq "plugins: []" "${app_file}"
}

@test "external image render-input module maps contract defaults and manifest replacements" {
  run bash -lc "source '${SCRIPT}'; render_external_image_inputs"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"workload|EXTERNAL_IMAGE_SENTIMENT_API|external_sentiment_api|sentiment-api"* ]]
  [[ "${output}" == *"workload|EXTERNAL_IMAGE_SUBNETCALC_FRONTEND|external_subnetcalc_frontend|subnetcalc-frontend"* ]]
  [[ "${output}" == *"platform|EXTERNAL_PLATFORM_IMAGE_PLATFORM_MCP|external_platform_mcp|platform-mcp"* ]]
  [[ "${output}" == *"platform|EXTERNAL_PLATFORM_IMAGE_IDP_CORE|external_platform_idp_core|idp-core"* ]]
}

@test "GitOps render-input module maps enablement and host contract defaults" {
  run bash -lc "source '${SCRIPT}'; render_gitops_render_inputs"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"bool|ENABLE_HUBBLE|enable_hubble|true"* ]]
  [[ "${output}" == *"bool|ENABLE_APP_REPO_SUBNETCALC|enable_app_repo_subnetcalc|false"* ]]
  [[ "${output}" == *"bool|ENABLE_PROGRESSIVE_DELIVERY|enable_progressive_delivery|false"* ]]
  [[ "${output}" == *"string|PLATFORM_BASE_DOMAIN|platform_base_domain|127.0.0.1.sslip.io"* ]]
  [[ "${output}" == *"string|ARGOCD_PUBLIC_HOST|argocd_public_host|"* ]]
  [[ "${output}" == *"string|SSO_PUBLIC_URL|sso_public_url|"* ]]
  [[ "${output}" == *"string|POLICIES_REPO_URL_CLUSTER|policies_repo_url_cluster|"* ]]
  [[ "${output}" == *"string|MCP_PUBLIC_HOST|mcp_public_host|"* ]]
  [[ "${output}" == *"bool|ENABLE_APIM_SIMULATOR|enable_apim_simulator|false"* ]]
  [[ "${output}" == *"bool|ENABLE_AGENTGATEWAY_AI_GATEWAY|enable_agentgateway_ai_gateway|false"* ]]
  [[ "${output}" == *"string|AGENTGATEWAY_AI_GATEWAY_PUBLIC_HOST|agentgateway_ai_gateway_public_host|"* ]]
  [[ "${output}" == *"string|AGENTGATEWAY_AI_GATEWAY_MODEL|agentgateway_ai_gateway_model|"* ]]
  [[ "${output}" == *"chart|AGENTGATEWAY_CHART_VERSION|agentgateway_chart_version|agentgateway_chart_version"* ]]
  [[ "${output}" == *"chart|GRAFANA_CHART_VERSION|grafana_chart_version|grafana_chart_version"* ]]
}

@test "progressive delivery render adds dev-only subnetcalc rollout overlay" {
  repo_dir="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${repo_dir}/apps/dev"
  printf '%s\n' \
    'namespace: dev' \
    'resources:' \
    '  - ../workloads/base' \
    'patches:' \
    '  - path: subnetcalc-router-gateway-canary-patch.yaml' \
    >"${repo_dir}/apps/dev/kustomization.yaml"

  run bash -lc "export ENABLE_PROGRESSIVE_DELIVERY=true ENABLE_APP_REPO_SUBNETCALC=true; source '${SCRIPT}'; configure_progressive_delivery '${repo_dir}'"

  [ "${status}" -eq 0 ]
  grep -Fq '  - subnetcalc-frontend-canary-service.yaml' "${repo_dir}/apps/dev/kustomization.yaml"
  grep -Fq 'path: subnetcalc-router-gateway-canary-patch.yaml' "${repo_dir}/apps/dev/kustomization.yaml"
  grep -Fq 'path: subnetcalc-frontend-rollout-patch.yaml' "${repo_dir}/apps/dev/kustomization.yaml"
  grep -Fq 'name: subnetcalc-frontend' "${repo_dir}/apps/dev/kustomization.yaml"
  [ "$(grep -c '^patches:' "${repo_dir}/apps/dev/kustomization.yaml")" -eq 1 ]
}

@test "policy repo render vendors subnetcalc frontend canary route and dev ReferenceGrant" {
  run bash -lc "export STACK_DIR='${REPO_ROOT}/terraform/kubernetes' ENABLE_BACKSTAGE=false ENABLE_HUBBLE=false ENABLE_POLICIES=false ENABLE_GATEWAY_TLS=true ENABLE_HEADLAMP=false ENABLE_GRAFANA=false ENABLE_APP_REPO_SENTIMENT=false ENABLE_APP_REPO_SUBNETCALC=true ENABLE_APIM_SIMULATOR=true ENABLE_AGENTGATEWAY_AI_GATEWAY=false ENABLE_PROMETHEUS=false ENABLE_VICTORIA_LOGS=false ENABLE_OTEL_GATEWAY=false ENABLE_OBSERVABILITY_AGENT=false ENABLE_SSO=true ENABLE_PROGRESSIVE_DELIVERY=true; source '${SCRIPT}'; render_policy_repo_tree '${BATS_TEST_TMPDIR}/render-canary-route' >/dev/null; test -f '${BATS_TEST_TMPDIR}/render-canary-route/repo/apps/platform-gateway-routes-sso/httproute-subnetcalc-frontend-dev.yaml'; test -f '${BATS_TEST_TMPDIR}/render-canary-route/repo/apps/platform-gateway-routes-sso/referencegrant-dev-subnetcalc-frontend.yaml'; grep -Fq 'subnetcalc-frontend-canary' '${BATS_TEST_TMPDIR}/render-canary-route/repo/apps/platform-gateway-routes-sso/httproute-subnetcalc-frontend-dev.yaml'; grep -Fq 'referencegrant-dev-subnetcalc-frontend.yaml' '${BATS_TEST_TMPDIR}/render-canary-route/repo/apps/platform-gateway-routes-sso/kustomization.yaml'; grep -Fq 'subnetcalc-router-gateway-canary-patch.yaml' '${BATS_TEST_TMPDIR}/render-canary-route/repo/apps/dev/kustomization.yaml'"

  [ "${status}" -eq 0 ]
}

@test "Terraform policies sync leaves chart and observability render values in GitOps contract" {
  gitops_tf="${REPO_ROOT}/terraform/kubernetes/gitops.tf"
  sync_block="$(sed -n '/resource \"null_resource\" \"sync_gitea_policies_repo\"/,/^}/p' "${gitops_tf}")"

  [[ "${sync_block}" == *"GITOPS_RENDER_CONTRACT_FILE"* ]]
  for env_name in \
    ENABLE_HUBBLE \
    ENABLE_POLICIES \
    ENABLE_GATEWAY_TLS \
    GATEWAY_HTTPS_HOST_PORT \
    PLATFORM_BASE_DOMAIN \
    PLATFORM_ADMIN_BASE_DOMAIN \
    ARGOCD_PUBLIC_HOST \
    SSO_PUBLIC_URL \
    GITEA_PUBLIC_HOST \
    GRAFANA_PUBLIC_HOST \
    HEADLAMP_PUBLIC_HOST \
    HUBBLE_PUBLIC_HOST \
    KYVERNO_PUBLIC_HOST \
    SENTIMENT_DEV_PUBLIC_HOST \
    SENTIMENT_UAT_PUBLIC_HOST \
    SUBNETCALC_DEV_PUBLIC_HOST \
    SUBNETCALC_UAT_PUBLIC_HOST \
    MCP_PUBLIC_HOST \
    MCP_CONSOLE_PUBLIC_HOST \
    ADMIN_ROUTE_ALLOWLIST_CIDRS \
    GATEWAY_TRUSTED_PROXY_CIDRS \
    ENABLE_CERT_MANAGER \
    ENABLE_ACTIONS_RUNNER \
    ENABLE_APP_REPO_SENTIMENT \
    ENABLE_APP_REPO_SUBNETCALC \
    ENABLE_APIM_SIMULATOR \
    ENABLE_AGENTGATEWAY_AI_GATEWAY \
    AGENTGATEWAY_AI_GATEWAY_PUBLIC_HOST \
    AGENTGATEWAY_AI_GATEWAY_MODEL \
    AGENTGATEWAY_CHART_VERSION \
    ENABLE_PROMETHEUS \
    ENABLE_GRAFANA \
    ENABLE_VICTORIA_LOGS \
    ENABLE_OTEL_GATEWAY \
    ENABLE_HEADLAMP \
    ENABLE_BACKSTAGE \
    ENABLE_OBSERVABILITY_AGENT \
    HARDENED_IMAGE_REGISTRY \
    POLICIES_REPO_URL_CLUSTER \
    CERT_MANAGER_CHART_VERSION \
    GRAFANA_CHART_VERSION \
    GRAFANA_IMAGE_REGISTRY \
    GRAFANA_IMAGE_REPOSITORY \
    GRAFANA_IMAGE_TAG \
    GRAFANA_SIDECAR_IMAGE_REGISTRY \
    GRAFANA_SIDECAR_IMAGE_REPOSITORY \
    GRAFANA_SIDECAR_IMAGE_TAG \
    GRAFANA_VICTORIA_LOGS_PLUGIN_URL \
    GRAFANA_LIVENESS_INITIAL_DELAY_SECONDS \
    HEADLAMP_CHART_VERSION \
    KYVERNO_CHART_VERSION \
    OAUTH2_PROXY_CHART_VERSION \
    OPENTELEMETRY_COLLECTOR_CHART_VERSION \
    POLICY_REPORTER_CHART_VERSION \
    PROMETHEUS_CHART_VERSION \
    VICTORIA_LOGS_CHART_VERSION; do
    [[ "${sync_block}" != *"${env_name}"* ]]
  done
}

@test "Terraform policies sync waits for workload registry secrets before app-of-apps reconciliation" {
  gitops_tf="${REPO_ROOT}/terraform/kubernetes/gitops.tf"
  sync_block="$(awk '/resource \"null_resource\" \"sync_gitea_policies_repo\"/{capture=1} capture{print} /^# -----------------------------------------------------------------------------/{if (capture) exit}' "${gitops_tf}")"
  gitea_tf="${REPO_ROOT}/terraform/kubernetes/gitea.tf"
  registry_secret_block="$(awk '/resource \"kubernetes_secret_v1\" \"gitea_registry_creds\"/{capture=1} capture{print} /^resource \"kubectl_manifest\" \"argocd_app_gitea\"/{if (capture) exit}' "${gitea_tf}")"

  [[ "${sync_block}" == *"kubernetes_secret_v1.gitea_registry_creds"* ]]
  [[ "${registry_secret_block}" == *"kubernetes_namespace_v1.dev"* ]]
  [[ "${registry_secret_block}" == *"kubernetes_namespace_v1.uat"* ]]
  [[ "${registry_secret_block}" == *"kubernetes_namespace_v1.apim"* ]]
  [[ "${registry_secret_block}" == *"kubectl_manifest.namespace_mcp"* ]]
}

@test "Terraform policies sync waits for app-of-apps workload support secrets" {
  gitops_tf="${REPO_ROOT}/terraform/kubernetes/gitops.tf"
  sync_block="$(awk '/resource \"null_resource\" \"sync_gitea_policies_repo\"/{capture=1} capture{print} /^# -----------------------------------------------------------------------------/{if (capture) exit}' "${gitops_tf}")"

  [[ "${sync_block}" == *"kubernetes_secret_v1.backstage_gitea_credentials"* ]]
  [[ "${sync_block}" == *"kubernetes_secret_v1.headlamp_mkcert_ca"* ]]
}

@test "Terraform refreshes repo-backed child apps in app-of-apps mode" {
  locals_tf="${REPO_ROOT}/terraform/kubernetes/locals.tf"
  app_names_block="$(awk '/argocd_gitops_repo_app_names = compact/{capture=1} capture{print} /^  \\)\\)/{if (capture) exit}' "${locals_tf}")"

  [[ "${app_names_block}" == *'["app-of-apps"]'* ]]
  [[ "${app_names_block}" == *'["cilium-policies"]'* ]]
  [[ "${app_names_block}" == *'"platform-gateway-routes"'* ]]
  [[ "${app_names_block}" != *'!var.enable_app_of_apps ? ["cilium-policies"]'* ]]
  [[ "${app_names_block}" != *'!var.enable_app_of_apps ? ["platform-gateway-routes"]'* ]]
}

@test "app-of-apps render prunes SSO children when SSO is disabled" {
  apps_dir="${BATS_TEST_TMPDIR}/argocd-apps"
  mkdir -p "${apps_dir}"
  touch \
    "${apps_dir}/78-idp.application.yaml" \
    "${apps_dir}/79-mcp.application.yaml" \
    "${apps_dir}/80-chatgpt-sim.application.yaml"

  run bash -lc "export ENABLE_SSO=false ENABLE_HEADLAMP=false ENABLE_POLICIES=false ENABLE_CERT_MANAGER=false ENABLE_GATEWAY_TLS=false ENABLE_ACTIONS_RUNNER=false ENABLE_APP_REPO_SENTIMENT=false ENABLE_APP_REPO_SUBNETCALC=false ENABLE_APIM_SIMULATOR=false ENABLE_AGENTGATEWAY_AI_GATEWAY=false ENABLE_PROMETHEUS=false ENABLE_GRAFANA=false ENABLE_VICTORIA_LOGS=false ENABLE_OTEL_GATEWAY=false ENABLE_OBSERVABILITY_AGENT=false; source '${SCRIPT}'; prune_argocd_app_manifests '${apps_dir}'; find '${apps_dir}' -maxdepth 1 -type f -print"

  [ "${status}" -eq 0 ]
  [[ "${output}" != *"78-idp.application.yaml"* ]]
  [[ "${output}" != *"79-mcp.application.yaml"* ]]
  [[ "${output}" != *"80-chatgpt-sim.application.yaml"* ]]
}

@test "app-of-apps render creates Headlamp child application when enabled" {
  apps_dir="${BATS_TEST_TMPDIR}/argocd-apps"
  mkdir -p "${apps_dir}"

  run bash -lc "export POLICIES_REPO_URL_CLUSTER='ssh://git@gitea-ssh.gitea.svc.cluster.local:22/platform/policies.git' ENABLE_HEADLAMP=true ENABLE_SSO=false HEADLAMP_CLUSTER_ROLE_BINDING_CREATE=true; source '${SCRIPT}'; render_headlamp_application_manifest '${apps_dir}'; cat '${apps_dir}/85-headlamp.application.yaml'"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"name: headlamp"* ]]
  [[ "${output}" == *"path: apps/vendor/charts/headlamp"* ]]
  [[ "${output}" != *"sessionTTL:"* ]]
  [[ "${output}" == *"probes:"* ]]
  [[ "${output}" == *"initialDelaySeconds: 20"* ]]
  [[ "${output}" == *"initialDelaySeconds: 10"* ]]
  [[ "${output}" == *"CreateNamespace=false"* ]]
}

@test "app-of-apps render wires Headlamp OIDC to provider-aware SSO issuer" {
  apps_dir="${BATS_TEST_TMPDIR}/argocd-apps"
  mkdir -p "${apps_dir}"

  run bash -lc "export POLICIES_REPO_URL_CLUSTER='ssh://git@gitea-ssh.gitea.svc.cluster.local:22/platform/policies.git' ENABLE_HEADLAMP=true ENABLE_SSO=true SSO_PUBLIC_URL='https://keycloak.127.0.0.1.sslip.io/realms/platform' HEADLAMP_PUBLIC_HOST='headlamp.admin.127.0.0.1.sslip.io' HEADLAMP_OIDC_CLIENT_SECRET='secret' HEADLAMP_CLUSTER_ROLE_BINDING_CREATE=true HEADLAMP_OIDC_SKIP_TLS_VERIFY=true; source '${SCRIPT}'; render_headlamp_application_manifest '${apps_dir}'; cat '${apps_dir}/85-headlamp.application.yaml'"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"issuerURL: https://keycloak.127.0.0.1.sslip.io/realms/platform"* ]]
}

@test "app-of-apps render uses direct gateway routes before SSO" {
  apps_dir="${BATS_TEST_TMPDIR}/argocd-apps"
  mkdir -p "${apps_dir}"
  cat >"${apps_dir}/50-platform-gateway-routes.application.yaml" <<'EOF'
spec:
  source:
    path: apps/platform-gateway-routes-sso
EOF

  run bash -lc "export ENABLE_SSO=false; source '${SCRIPT}'; render_platform_gateway_routes_application_manifest '${apps_dir}'; cat '${apps_dir}/50-platform-gateway-routes.application.yaml'"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"path: apps/platform-gateway-routes"* ]]
  [[ "${output}" != *"path: apps/platform-gateway-routes-sso"* ]]
}

@test "app-of-apps render uses SSO gateway routes when SSO is enabled" {
  apps_dir="${BATS_TEST_TMPDIR}/argocd-apps"
  mkdir -p "${apps_dir}"
  cat >"${apps_dir}/50-platform-gateway-routes.application.yaml" <<'EOF'
spec:
  source:
    path: apps/platform-gateway-routes
EOF

  run bash -lc "export ENABLE_SSO=true; source '${SCRIPT}'; render_platform_gateway_routes_application_manifest '${apps_dir}'; cat '${apps_dir}/50-platform-gateway-routes.application.yaml'"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"path: apps/platform-gateway-routes-sso"* ]]
}

@test "render_repo golden renders gateway route host, forwarded headers, and admin allowlist" {
  stack_dir="${BATS_TEST_TMPDIR}/stack-render"
  create_minimal_policy_stack "${stack_dir}"

  run bash -lc "export STACK_DIR='${stack_dir}' PLATFORM_BASE_DOMAIN='apps.example.test' PLATFORM_ADMIN_BASE_DOMAIN='admin.example.test' GATEWAY_HTTPS_HOST_PORT='8443' ADMIN_ROUTE_ALLOWLIST_CIDRS='10.0.0.0/8, 192.168.0.0/16' ENABLE_HUBBLE=true ENABLE_POLICIES=true ENABLE_GATEWAY_TLS=true ENABLE_HEADLAMP=false ENABLE_GRAFANA=true ENABLE_APP_REPO_SENTIMENT=false ENABLE_APP_REPO_SUBNETCALC=false ENABLE_BACKSTAGE=true ENABLE_PROMETHEUS=true; source '${SCRIPT}'; render_repo '${BATS_TEST_TMPDIR}/render-out' >/dev/null; cat '${BATS_TEST_TMPDIR}/render-out/repo/apps/platform-gateway-routes/httproute-gitea.yaml'; printf '%s\n' '---ALLOWLIST---'; cat '${BATS_TEST_TMPDIR}/render-out/repo/apps/platform-gateway-routes/snippetsfilter-admin-allowlist.yaml'"

  [ "${status}" -eq 0 ]
  [ "${output}" = "$(cat <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: gitea
spec:
  hostnames:
    - gitea.admin.apps.example.test
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      filters:
        - type: RequestHeaderModifier
          requestHeaderModifier:
            set:
              - name: X-Forwarded-Host
                value: gitea.admin.apps.example.test:8443
              - name: X-Forwarded-Port
                value: "8443"
              - name: X-Forwarded-Proto
                value: https
      backendRefs:
        - group: ""
          kind: Service
          name: oauth2-proxy-gitea
          namespace: sso
          port: 4180
          weight: 1
---ALLOWLIST---
apiVersion: gateway.nginx.org/v1alpha1
kind: SnippetsFilter
metadata:
  name: admin-allowlist
  namespace: gateway-routes
spec:
  snippets:
    - context: http.server.location
      value: |
        allow 10.0.0.0/8;
        allow 192.168.0.0/16;
        deny all;
EOF
)" ]
}

@test "render_repo golden prunes disabled SSO routes and Backstage resources" {
  stack_dir="${BATS_TEST_TMPDIR}/stack-render"
  create_minimal_policy_stack "${stack_dir}"

  run bash -lc "export STACK_DIR='${stack_dir}' ENABLE_BACKSTAGE=false ENABLE_HUBBLE=false ENABLE_POLICIES=false ENABLE_GATEWAY_TLS=true ENABLE_HEADLAMP=false ENABLE_GRAFANA=false ENABLE_APP_REPO_SENTIMENT=false ENABLE_APP_REPO_SUBNETCALC=false ENABLE_PROMETHEUS=false; source '${SCRIPT}'; render_repo '${BATS_TEST_TMPDIR}/render-out' >/dev/null; cat '${BATS_TEST_TMPDIR}/render-out/repo/apps/idp/all.yaml'; printf '%s\n' '---KUSTOMIZATION---'; cat '${BATS_TEST_TMPDIR}/render-out/repo/apps/platform-gateway-routes-sso/kustomization.yaml'; printf '%s\n' '---GRANT---'; cat '${BATS_TEST_TMPDIR}/render-out/repo/apps/platform-gateway-routes-sso/referencegrant-sso.yaml'"

  [ "${status}" -eq 0 ]
  [ "${output}" = "$(cat <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: idp-core
---KUSTOMIZATION---
resources:
  - httproute-portal-api.yaml
  - referencegrant-sso.yaml
---GRANT---
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
spec:
  to:
    - group: ""
      kind: Service
      name: oauth2-proxy-idp-core
EOF
)" ]
}

@test "render_repo prunes disabled agentgateway AI gateway resources" {
  stack_dir="${BATS_TEST_TMPDIR}/stack-render"
  create_minimal_policy_stack "${stack_dir}"

  run bash -lc "export STACK_DIR='${stack_dir}' ENABLE_BACKSTAGE=false ENABLE_HUBBLE=false ENABLE_POLICIES=false ENABLE_GATEWAY_TLS=true ENABLE_HEADLAMP=false ENABLE_GRAFANA=false ENABLE_APP_REPO_SENTIMENT=false ENABLE_APP_REPO_SUBNETCALC=false ENABLE_AGENTGATEWAY_AI_GATEWAY=false ENABLE_PROMETHEUS=false; source '${SCRIPT}'; render_repo '${BATS_TEST_TMPDIR}/render-out' >/dev/null; test ! -e '${BATS_TEST_TMPDIR}/render-out/repo/apps/argocd-apps/68-agentgateway-crds.application.yaml'; test ! -e '${BATS_TEST_TMPDIR}/render-out/repo/apps/argocd-apps/69-agentgateway.application.yaml'; test ! -e '${BATS_TEST_TMPDIR}/render-out/repo/apps/argocd-apps/73-agentgateway-ai-gateway.application.yaml'; test ! -e '${BATS_TEST_TMPDIR}/render-out/repo/apps/platform-gateway-routes/httproute-agentgateway-ai-gateway.yaml'; test ! -e '${BATS_TEST_TMPDIR}/render-out/repo/apps/platform-gateway-routes-sso/httproute-agentgateway-ai-gateway.yaml'; ! grep -R 'agentgateway-ai-gateway' '${BATS_TEST_TMPDIR}/render-out/repo/apps/platform-gateway-routes' '${BATS_TEST_TMPDIR}/render-out/repo/apps/platform-gateway-routes-sso'"

  [ "${status}" -eq 0 ]
}

@test "render_repo renders agentgateway AI gateway route from GitOps contract" {
  stack_dir="${BATS_TEST_TMPDIR}/stack-render"
  contract_file="${BATS_TEST_TMPDIR}/gitops-render-contract.json"
  create_minimal_policy_stack "${stack_dir}"
  cat >"${contract_file}" <<'EOF'
{
  "enable_agentgateway_ai_gateway": true,
  "agentgateway_ai_gateway_public_host": "llm.apps.example.test"
}
EOF

  run bash -lc "export STACK_DIR='${stack_dir}' GITOPS_RENDER_CONTRACT_FILE='${contract_file}'; source '${SCRIPT}'; render_repo '${BATS_TEST_TMPDIR}/render-out' >/dev/null; cat '${BATS_TEST_TMPDIR}/render-out/repo/apps/agentgateway-ai-gateway/all.yaml'; printf '%s\n' '---ROUTE---'; cat '${BATS_TEST_TMPDIR}/render-out/repo/apps/platform-gateway-routes/httproute-agentgateway-ai-gateway.yaml'"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"name: local-openai-compatible"* ]]
  [[ "${output}" == *"host: host.docker.internal"* ]]
  [[ "${output}" == *"port: 8000"* ]]
  [[ "${output}" == *"llm.apps.example.test"* ]]
  [[ "${output}" == *"kind: AgentgatewayParameters"* ]]
  [[ "${output}" == *"parametersRef:"* ]]
  [[ "${output}" == *"seccompProfile:"* ]]
  [[ "${output}" == *"type: RuntimeDefault"* ]]
}

@test "render_repo golden renders Grafana chart values from GitOps contract" {
  stack_dir="${BATS_TEST_TMPDIR}/stack-render"
  contract_file="${BATS_TEST_TMPDIR}/gitops-render-contract.json"
  create_minimal_policy_stack "${stack_dir}"
  cat >"${contract_file}" <<'EOF'
{
  "enable_prometheus": true,
  "enable_grafana": true,
  "grafana_chart_version": "9.9.9",
  "grafana_image_registry": "registry.example.test",
  "grafana_image_repository": "platform/grafana-victorialogs",
  "grafana_image_tag": "12.3.4-contract",
  "grafana_sidecar_image_registry": "sidecar.example.test",
  "grafana_sidecar_image_repository": "platform/k8s-sidecar",
  "grafana_sidecar_image_tag": "2.3.4-contract",
  "grafana_victoria_logs_plugin_url": "",
  "grafana_liveness_initial_delay_seconds": 77
}
EOF

  run bash -lc "export STACK_DIR='${stack_dir}' GITOPS_RENDER_CONTRACT_FILE='${contract_file}'; source '${SCRIPT}'; render_repo '${BATS_TEST_TMPDIR}/render-out' >/dev/null; cat '${BATS_TEST_TMPDIR}/render-out/repo/apps/argocd-apps/95-grafana.application.yaml'"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"repoURL: ${POLICIES_REPO_URL_CLUSTER}"* ]]
  [[ "${output}" == *"targetRevision: main"* ]]
  [[ "${output}" == *"path: apps/vendor/charts/grafana"* ]]
  [[ "${output}" == *"registry: registry.example.test"* ]]
  [[ "${output}" == *"repository: platform/grafana-victorialogs"* ]]
  [[ "${output}" == *"tag: 12.3.4-contract"* ]]
  [[ "${output}" == *"registry: sidecar.example.test"* ]]
  [[ "${output}" == *"repository: platform/k8s-sidecar"* ]]
  [[ "${output}" == *"tag: 2.3.4-contract"* ]]
  [[ "${output}" == *"plugins: []"* ]]
  [[ "${output}" == *"initialDelaySeconds: 77"* ]]
}
