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

@test "platform gateway manifests declare compatible modern TLS and hardening directives" {
  gateway_manifest="${REPO_ROOT}/terraform/kubernetes/apps/platform-gateway/gateway.yaml"
  hardening_manifest="${REPO_ROOT}/terraform/kubernetes/apps/platform-gateway/tls-hardening.yaml"

  grep -Fq "nginx.org/ssl-protocols: TLSv1.3" "${gateway_manifest}"
  grep -Fq 'nginx.org/ssl-prefer-server-ciphers: "off"' "${gateway_manifest}"
  grep -Fq "ssl_conf_command Ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256;" "${hardening_manifest}"
  grep -Fq "ssl_session_tickets off;" "${hardening_manifest}"
  grep -Fq 'add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;' "${hardening_manifest}"
  grep -Fq 'add_header X-Content-Type-Options "nosniff" always;' "${hardening_manifest}"
}

@test "platform gateway certificate covers every declared gateway route hostname" {
  run uv run --isolated --with pyyaml python - <<'PY'
from pathlib import Path
import os

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
cert_manifest = repo_root / "terraform/kubernetes/apps/cert-manager-config/platform-gateway-cert.yaml"
route_dirs = [
    repo_root / "terraform/kubernetes/apps/platform-gateway-routes",
    repo_root / "terraform/kubernetes/apps/platform-gateway-routes-sso",
]

certificate = yaml.safe_load(cert_manifest.read_text(encoding="utf-8"))
dns_names = set(certificate["spec"]["dnsNames"])

def covered_by_dns_name(hostname: str, dns_name: str) -> bool:
    if hostname == dns_name:
        return True
    if not dns_name.startswith("*."):
        return False
    suffix = dns_name[1:]
    if not hostname.endswith(suffix):
        return False
    prefix = hostname[: -len(suffix)]
    return prefix and "." not in prefix

missing = []
for route_dir in route_dirs:
    for route_manifest in sorted(route_dir.glob("httproute-*.yaml")):
        route = yaml.safe_load(route_manifest.read_text(encoding="utf-8"))
        for hostname in route["spec"].get("hostnames", []):
            if not any(covered_by_dns_name(hostname, dns_name) for dns_name in dns_names):
                missing.append(f"{hostname} ({route_manifest.relative_to(repo_root)})")

assert not missing, "missing gateway cert SAN coverage:\n" + "\n".join(missing)
print("validated gateway certificate SAN coverage for every HTTPRoute hostname")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated gateway certificate SAN coverage for every HTTPRoute hostname"* ]]
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

@test "oidc post-restart recovery script performs a controlled nginx gateway restart after kube-apiserver restart" {
  script="${REPO_ROOT}/terraform/kubernetes/scripts/recover-kind-cluster-after-apiserver-restart.sh"
  helper="${REPO_ROOT}/terraform/kubernetes/scripts/kind-apiserver-oidc-lib.sh"

  grep -Fq 'KIND_OIDC_RECOVERY_FORCE_RUN="${KIND_OIDC_RECOVERY_FORCE_RUN:-0}"' "${script}"
  grep -Fq 'source "${SCRIPT_DIR}/kind-apiserver-oidc-lib.sh"' "${script}"
  grep -Fq 'if [[ "${KIND_OIDC_RECOVERY_FORCE_RUN}" != "1" ]] && kind_oidc_post_restart_dependencies_healthy; then' "${script}"
  grep -Fq 'ok "forcing the explicit post-restart recovery flow"' "${script}"
  grep -Fq "retry_webhook_fail()" "${helper}"
  grep -Fq "restart_deployment()" "${helper}"
  grep -Fq 'rollout restart "deploy/${deploy_name}"' "${helper}"
  grep -Fq 'retry_webhook_fail 12 kubectl -n "${namespace}" rollout restart "deploy/${deploy_name}"' "${helper}"
  grep -Fq 'restart_deployment "${NGINX_GATEWAY_NAMESPACE}" "${NGINX_GATEWAY_DEPLOY_NAME}"' "${script}"
  grep -Fq 'wait_for_deployment_rollout_with_early_recycle \' "${script}"
  grep -Fq '"nginx gateway control plane (${NGINX_GATEWAY_NAMESPACE}/${NGINX_GATEWAY_DEPLOY_NAME})"' "${script}"
  grep -Fq 'wait_for_service_endpoints "${NGINX_GATEWAY_NAMESPACE}" "${NGINX_GATEWAY_SERVICE}" "${GATEWAY_DEPLOY_WAIT_SECONDS}"' "${script}"
}

@test "oidc apiserver patch script stops at apiserver readiness and leaves recovery to explicit follow-up steps" {
  script="${REPO_ROOT}/terraform/kubernetes/scripts/configure-kind-apiserver-oidc.sh"

  grep -Fq 'wait_for_kube_apiserver_ready 120 3' "${script}"
  ! grep -Fq 'restart_deployment "${NGINX_GATEWAY_NAMESPACE}" "${NGINX_GATEWAY_DEPLOY_NAME}"' "${script}"
  ! grep -Fq 'wait_for_deployment_recovery_after_apiserver_restart \' "${script}"
}

@test "oidc helper library tolerates missing deployment selector lookups after apiserver restart" {
  script="${REPO_ROOT}/terraform/kubernetes/scripts/kind-apiserver-oidc-lib.sh"

  grep -Fq 'deployment_selector()' "${script}"
  grep -Fq 'local selector=""' "${script}"
  grep -Fq 'set +e' "${script}"
  grep -Fq 'status=$?' "${script}"
  grep -Fq 'if [[ "${status}" -ne 0 ]]; then' "${script}"
  grep -Fq "printf '%s' \"\${selector}\"" "${script}"
}

@test "oidc helper library defaults the local Kubernetes SSO provider to Keycloak" {
  script="${REPO_ROOT}/terraform/kubernetes/scripts/kind-apiserver-oidc-lib.sh"
  health_script="${REPO_ROOT}/terraform/kubernetes/scripts/check-cluster-health.sh"

  grep -Fq 'SSO_PROVIDER="${SSO_PROVIDER:-keycloak}"' "${script}"
  grep -Fq 'OIDC_ISSUER_URL="${OIDC_ISSUER_URL:-https://${OIDC_HOST}/realms/${KEYCLOAK_REALM}}"' "${script}"
  grep -Fq 'OIDC_ISSUER_URL="${OIDC_ISSUER_URL:-https://${OIDC_HOST}/dex}"' "${script}"
  grep -Fq '[[ -n "${SSO_PROVIDER}" ]] || SSO_PROVIDER="keycloak"' "${health_script}"
  grep -Fq 'Keycloak admin: https://$(keycloak_host)${port_suffix}/admin/' "${health_script}"
}

@test "oidc helper library repairs node-local cilium when post-restart controllers lose kubernetes service reachability" {
  script="${REPO_ROOT}/terraform/kubernetes/scripts/kind-apiserver-oidc-lib.sh"

  grep -Fq 'recycle_cilium_on_nodes()' "${script}"
  grep -Fq 'kubectl -n kube-system get pods \' "${script}"
  grep -Fq -- '-l "k8s-app=cilium"' "${script}"
  grep -Fq -- '--field-selector "spec.nodeName=${node_name}"' "${script}"
  grep -Fq 'deployment_api_connectivity_failure_nodes()' "${script}"
  grep -Fq 'connect: connection refused' "${script}"
  grep -Fq 'recycling node-local Cilium for transient API connectivity recovery' "${script}"
  grep -Fq 'recycle_cilium_on_nodes "${failed_nodes}"' "${script}"
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

@test "gateway URL check verifies SNI certificate hostname coverage" {
  script="${REPO_ROOT}/terraform/kubernetes/scripts/check-gateway-urls.sh"

  grep -Fq "TLS certificate hostname checks" "${script}"
  grep -Fq "probe_route_certificates()" "${script}"
  grep -Fq 'openssl s_client -connect "${connect_host}:${HOST_PORT}" -servername "${host}"' "${script}"
  grep -Fq 'openssl x509 -noout -checkhost "${host}"' "${script}"
  grep -Fq "TLS certificate hostnames not ready yet" "${script}"
}

@test "cluster health script hard-refreshes stale Argo apps while waiting for them to settle" {
  script="${REPO_ROOT}/terraform/kubernetes/scripts/check-cluster-health.sh"

  grep -Fq 'APP_REFRESH_INTERVAL_SECONDS="${APP_REFRESH_INTERVAL_SECONDS:-30}"' "${script}"
  grep -Fq 'argocd_app_needs_hard_refresh()' "${script}"
  grep -Fq 'argocd_refresh_app()' "${script}"
  grep -Fq 'argocd.argoproj.io/refresh=hard' "${script}"
  grep -Fq 'argocd_refresh_app "${ns}" "${app}"' "${script}"
}

@test "cluster health script only tolerates stale aggregate degraded health when child resources are clean" {
  script="${REPO_ROOT}/terraform/kubernetes/scripts/check-cluster-health.sh"

  grep -Fq 'argocd_app_has_stale_aggregate_health()' "${script}"
  grep -Fq '[[ "${app}" == "platform-gateway-routes" ]] || return 1' "${script}"
  grep -Fq '[[ "${sync}" == "Synced" && "${health}" == "Degraded" ]] || return 1' "${script}"
  grep -Fq '[[ "${op_phase}" == "Succeeded" ]] || return 1' "${script}"
  grep -Fq '[[ -z "${conditions}" ]] || return 1' "${script}"
  grep -Fq '[[ -z "${child_sync_drift}" ]] || return 1' "${script}"
  grep -Fq '[[ -z "${child_bad_health}" ]] || return 1' "${script}"
  grep -Fq 'if argocd_app_has_stale_aggregate_health "${ns}" "${app}"; then' "${script}"
  grep -Fq 'stale aggregate Degraded health' "${script}"
}

@test "deployment health customization avoids Lua string library helpers in Argo health sandbox" {
  file="${REPO_ROOT}/terraform/kubernetes/locals.tf"

  grep -Fq 'Deployment rollout in progress (updated=' "${file}"
  ! grep -Fq 'string.format(' "${file}"
}

@test "gateway stack check supports direct Argo CD mode without app-of-apps" {
  script="${REPO_ROOT}/terraform/kubernetes/scripts/check-gateway-stack.sh"

  grep -Fq "detect_argocd_gitops_mode()" "${script}"
  grep -Fq 'Detected direct Argo CD mode (no app-of-apps parent)' "${script}"
  grep -Fq 'Detected Argo CD app-of-apps mode' "${script}"
}

@test "gateway stack check tolerates split kubeconfigs with no current-context" {
  script="${REPO_ROOT}/terraform/kubernetes/scripts/check-gateway-stack.sh"

  grep -Fq 'ctx="${KUBECONFIG_CONTEXT:-}"' "${script}"
  grep -Fq 'warn "kubectl current-context is empty; continuing"' "${script}"
  grep -Fq 'KUBECTL_CONTEXT_ARGS+=(--context "${KUBECONFIG_CONTEXT}")' "${script}"
}

@test "gateway stack make targets pass split kubeconfig env through to diagnostics" {
  kind_makefile="${REPO_ROOT}/kubernetes/kind/Makefile"
  lima_makefile="${REPO_ROOT}/kubernetes/lima/Makefile"
  slicer_makefile="${REPO_ROOT}/kubernetes/slicer/Makefile"

  grep -Fq 'KUBECONFIG="$(KUBECONFIG_PATH)" KUBECONFIG_CONTEXT="$(KUBECONFIG_CONTEXT)" "$(STACK_DIR)/scripts/check-gateway-stack.sh"' "${kind_makefile}"
  grep -Fq 'KUBECONFIG="$(KUBECONFIG_PATH)" KUBECONFIG_CONTEXT="$(KUBECONFIG_CONTEXT)" "$(STACK_DIR)/scripts/check-gateway-stack.sh"' "${lima_makefile}"
  grep -Fq 'KUBECONFIG="$(KUBECONFIG_PATH)" KUBECONFIG_CONTEXT="$(KUBECONFIG_CONTEXT)" "$(STACK_DIR)/scripts/check-gateway-stack.sh"' "${slicer_makefile}"
}

@test "gateway bootstrap CRD waiter tolerates missing status conditions during early reconciliation" {
  file="${REPO_ROOT}/terraform/kubernetes/gateway-bootstrap.tf"

  grep -Fq 'deadline=$((SECONDS + 180))' "${file}"
  grep -Fq "jq -r '.status.conditions[]? | select(.type==\"Established\") | .status'" "${file}"
  grep -Fq 'established="$(kubectl $${KUBECTL_ARGS} get "crd/$${crd}" -o json 2>/dev/null | jq -r '\''.status.conditions[]? | select(.type=="Established") | .status'\'' | head -n1 || true)"' "${file}"
  grep -Fq 'Timed out waiting for CRD/$${crd} to become Established' "${file}"
  grep -Fq 'kubectl $${KUBECTL_ARGS} wait --for=condition=Established --timeout=10s "crd/$${crd}" >/dev/null' "${file}"
  ! grep -Fq '$$((SECONDS + 180))' "${file}"
  ! grep -Fq '$$(kubectl' "${file}"
}

@test "cert-manager config app retries through webhook warmup before gateway TLS is required" {
  cert_manager_tf="${REPO_ROOT}/terraform/kubernetes/cert-manager.tf"
  app_manifest="${REPO_ROOT}/terraform/kubernetes/apps/argocd-apps/10-cert-manager-config.application.yaml"

  grep -Fq 'retry:' "${cert_manager_tf}"
  grep -Fq 'limit: 20' "${cert_manager_tf}"
  grep -Fq 'backoff:' "${cert_manager_tf}"
  grep -Fq 'duration: 15s' "${cert_manager_tf}"
  grep -Fq 'maxDuration: 5m' "${cert_manager_tf}"
  grep -Fq 'retry:' "${app_manifest}"
  grep -Fq 'limit: 20' "${app_manifest}"
}

@test "kind oidc bootstrap waits for platform gateway TLS readiness instead of racing Argo reconciliation" {
  sso_tf="${REPO_ROOT}/terraform/kubernetes/sso.tf"
  wait_script="${REPO_ROOT}/terraform/kubernetes/scripts/wait-for-platform-gateway-tls.sh"

  grep -Fq 'resource "null_resource" "wait_for_platform_gateway_tls"' "${sso_tf}"
  grep -Fq 'wait-for-platform-gateway-tls.sh' "${sso_tf}"
  grep -Fq 'null_resource.wait_for_platform_gateway_tls' "${sso_tf}"
  grep -Fq 'kubectl_manifest.argocd_app_cert_manager_config' "${sso_tf}"
  grep -Fq 'kubectl_manifest.argocd_app_platform_gateway' "${sso_tf}"
  grep -Fq 'kubectl_manifest.argocd_app_platform_gateway_routes' "${sso_tf}"
  grep -Fq 'argocd.argoproj.io/refresh=hard' "${wait_script}"
  grep -Fq 'CERT_MANAGER_CONFIG_APP="${CERT_MANAGER_CONFIG_APP:-cert-manager-config}"' "${wait_script}"
  grep -Fq 'PLATFORM_GATEWAY_TLS_SECRET="${PLATFORM_GATEWAY_TLS_SECRET:-platform-gateway-tls}"' "${wait_script}"
  grep -Fq 'gateway listener programmed' "${wait_script}"
}
