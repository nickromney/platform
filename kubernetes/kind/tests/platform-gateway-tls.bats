#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
}

@test "nginx gateway controller enables snippet support for platform gateway hardening" {
  manifest="${REPO_ROOT}/terraform/kubernetes/apps/nginx-gateway-fabric/deploy.yaml"

  grep -Fq -- "--snippets" "${manifest}"
  grep -Fq "snippetspolicies" "${manifest}"
  grep -Fq "snippetsfilters" "${manifest}"
}

@test "platform gateway manifests declare TLS 1.3 and modern hardening directives" {
  gateway_manifest="${REPO_ROOT}/terraform/kubernetes/apps/platform-gateway/gateway.yaml"
  hardening_manifest="${REPO_ROOT}/terraform/kubernetes/apps/platform-gateway/tls-hardening.yaml"

  grep -Fq "nginx.org/ssl-protocols: TLSv1.3" "${gateway_manifest}"
  grep -Fq 'nginx.org/ssl-prefer-server-ciphers: "off"' "${gateway_manifest}"
  grep -Fq "ssl_conf_command Ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256;" "${hardening_manifest}"
  grep -Fq "ssl_session_tickets off;" "${hardening_manifest}"
  grep -Fq 'add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;' "${hardening_manifest}"
  grep -Fq 'add_header X-Content-Type-Options "nosniff" always;' "${hardening_manifest}"
}

@test "check-security verifies rendered platform gateway nginx directives" {
  script="${REPO_ROOT}/terraform/kubernetes/scripts/check-security.sh"

  grep -Fq "TFVARS_FILES=()" "${script}"
  grep -Fq 'TFVARS_FILES+=("${2:-}")' "${script}"
  grep -Fq "approved_image_prefixes_from_policy" "${script}"
  grep -Fq "restrict-image-registries.yaml" "${script}"
  grep -Fq "expected_platform_gateway_tls_directives" "${script}"
  grep -Fq "live_platform_gateway_nginx_conf" "${script}"
  grep -Fq "Rendered NGINX config includes:" "${script}"
  grep -Fq "Rendered NGINX config missing expected directive:" "${script}"
  grep -Fq "app.kubernetes.io/name=sentiment-api" "${script}"
}

@test "image registry policy no longer blanket-trusts Docker Hub" {
  policy="${REPO_ROOT}/terraform/kubernetes/cluster-policies/kyverno/shared/restrict-image-registries.yaml"

  grep -Fq 'host.docker.internal:5002/*' "${policy}"
  grep -Fq 'docker.io/bitnamilegacy/*' "${policy}"
  grep -Fq 'docker.io/grafana/*' "${policy}"
  grep -Fq 'docker.io/victoriametrics/*' "${policy}"
  ! grep -Fq 'docker.io/*"' "${policy}"
}

@test "oidc bootstrap script performs a controlled nginx gateway restart after kube-apiserver restart" {
  script="${REPO_ROOT}/terraform/kubernetes/scripts/configure-kind-apiserver-oidc.sh"

  grep -Fq "retry_webhook_fail()" "${script}"
  grep -Fq "restart_deployment()" "${script}"
  grep -Fq 'rollout restart "deploy/${deploy_name}"' "${script}"
  grep -Fq 'retry_webhook_fail 12 kubectl -n "${namespace}" rollout restart "deploy/${deploy_name}"' "${script}"
  grep -Fq 'restart_deployment "${NGINX_GATEWAY_NAMESPACE}" "${NGINX_GATEWAY_DEPLOY_NAME}"' "${script}"
  grep -Fq 'wait_for_deployment_rollout "${NGINX_GATEWAY_NAMESPACE}" "${NGINX_GATEWAY_DEPLOY_NAME}" "${GATEWAY_DEPLOY_WAIT_SECONDS}"' "${script}"
  grep -Fq 'wait_for_service_endpoints "${NGINX_GATEWAY_NAMESPACE}" "${NGINX_GATEWAY_SERVICE}" "${GATEWAY_DEPLOY_WAIT_SECONDS}"' "${script}"
}

@test "cluster health script distinguishes gitea gateway reachability from direct api reachability" {
  script="${REPO_ROOT}/terraform/kubernetes/scripts/check-cluster-health.sh"

  grep -Fq "Gitea HTTPS gateway" "${script}"
  grep -Fq "Gitea API NodePort reachable" "${script}"
  grep -Fq "repo/bootstrap automation will fail until it is" "${script}"
}

@test "cluster health script checks both direct and gateway admin surfaces" {
  script="${REPO_ROOT}/terraform/kubernetes/scripts/check-cluster-health.sh"

  grep -Fq "Argo CD direct URL" "${script}"
  grep -Fq "Argo CD admin gateway URL" "${script}"
  grep -Fq "Hubble UI direct URL" "${script}"
  grep -Fq "Hubble admin gateway URL" "${script}"
  grep -Fq "Grafana admin gateway URL" "${script}"
  grep -Fq "Headlamp admin gateway URL" "${script}"
  grep -Fq "Kyverno admin gateway URL" "${script}"
}

@test "gateway stack check supports direct Argo CD mode without app-of-apps" {
  script="${REPO_ROOT}/terraform/kubernetes/scripts/check-gateway-stack.sh"

  grep -Fq "detect_argocd_gitops_mode()" "${script}"
  grep -Fq 'Detected direct Argo CD mode (no app-of-apps parent)' "${script}"
  grep -Fq 'Detected Argo CD app-of-apps mode' "${script}"
}
