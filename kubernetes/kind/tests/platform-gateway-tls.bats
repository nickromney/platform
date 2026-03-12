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
  grep -Fq "ssl_protocols TLSv1.3;" "${hardening_manifest}"
  grep -Fq "ssl_conf_command Ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256;" "${hardening_manifest}"
  grep -Fq "ssl_session_tickets off;" "${hardening_manifest}"
  grep -Fq 'add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;' "${hardening_manifest}"
  grep -Fq 'add_header X-Content-Type-Options "nosniff" always;' "${hardening_manifest}"
}

@test "check-security verifies rendered platform gateway nginx directives" {
  script="${REPO_ROOT}/terraform/kubernetes/scripts/check-security.sh"

  grep -Fq "expected_platform_gateway_tls_directives" "${script}"
  grep -Fq "live_platform_gateway_nginx_conf" "${script}"
  grep -Fq "Rendered NGINX config includes:" "${script}"
  grep -Fq "Rendered NGINX config missing expected directive:" "${script}"
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
