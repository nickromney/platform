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
    exit 0
    ;;
esac
exit 0
EOF
  chmod +x "${TEST_BIN}/helm"

  export STACK_DIR="${BATS_TEST_TMPDIR}/stack"
  mkdir -p "${STACK_DIR}"
  export GITEA_HTTP_BASE="http://127.0.0.1:30090"
  export GITEA_ADMIN_USERNAME="gitea-admin"
  export GITEA_ADMIN_PWD="ChangeMe123!"
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
    targetRevision: v1.19.4
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
}

@test "determine_llm_gateway_external_cidr uses kind node resolution when host.docker.internal resolves to loopback on the host" {
  cat >"${TEST_BIN}/python3" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
host="${2:-}"
if [[ "${host}" == "host.docker.internal" ]]; then
  printf '127.0.0.1\n'
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/python3"

  cat >"${TEST_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  ps)
    printf 'kind-local-control-plane\n'
    ;;
  exec)
    printf '192.168.65.254\n'
    ;;
  *)
    exit 1
    ;;
esac
EOF
  chmod +x "${TEST_BIN}/docker"

  run bash -lc "export PATH='${TEST_BIN}':\"\$PATH\"; source '${SCRIPT}'; determine_llm_gateway_external_cidr"

  [ "${status}" -eq 0 ]
  [ "${output}" = "192.168.65.254/32" ]
}

@test "determine_llm_gateway_external_cidr prefers explicit CIDR overrides" {
  run bash -lc "export LLM_GATEWAY_EXTERNAL_CIDR='192.168.104.2/32'; source '${SCRIPT}'; determine_llm_gateway_external_cidr"

  [ "${status}" -eq 0 ]
  [ "${output}" = "192.168.104.2/32" ]
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
