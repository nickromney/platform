#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export CATALOG="${REPO_ROOT}/catalog/platform-apps.json"
}

@test "IDP catalog declares app ownership environments RBAC secrets and deployment evidence" {
  [ -f "${CATALOG}" ]

  run jq -e '
    .schema_version == "platform.idp/v1" and
    (.applications | length) >= 3 and
    any(.applications[]; .name == "chatgpt-sim" and .owner == "platform" and any(.environments[]; .name == "dev" and .namespace == "dev")) and
    any(.applications[]; .name == "subnetcalc" and any(.environments[]; .name == "dev" and .rbac.group == "app-subnetcalc-dev")) and
    any(.applications[]; .name == "sentiment" and any(.environments[]; .name == "uat" and .rbac.group == "app-sentiment-uat")) and
    all(.applications[]; has("deployment") and has("secrets") and has("scorecard"))
  ' "${CATALOG}"

  [ "${status}" -eq 0 ]
}

@test "IDP deployment shell read model includes catalog deployment evidence" {
  fixture_catalog="${BATS_TEST_TMPDIR}/platform-apps.json"
  cat >"${fixture_catalog}" <<'JSON'
{
  "applications": [
    {
      "name": "fixture-service",
      "owner": "team-platform",
      "health": "/readyz",
      "deployment": {
        "controller": "argocd",
        "strategy": "gitops",
        "image": "registry.local/fixture:base",
        "sync": "automated"
      },
      "environments": [
        {
          "name": "dev",
          "namespace": "dev",
          "route": "https://fixture.dev.example.test",
          "rbac": {"group": "app-fixture-dev"},
          "deployment": {"image": "registry.local/fixture:dev"}
        }
      ]
    }
  ]
}
JSON

  run env PLATFORM_APP_CATALOG="${fixture_catalog}" \
    "${REPO_ROOT}/terraform/kubernetes/scripts/idp-deployments.sh" --execute --format json

  [ "${status}" -eq 0 ]
  run jq -e '
    .schema_version == "platform.idp.deployment-read-model/v1" and
    all(.deployments[]; has("app") and has("environment") and has("image") and has("health") and has("sync")) and
    any(.deployments[]; .app == "fixture-service" and .environment == "dev" and .image == "registry.local/fixture:dev" and .health == "/readyz" and .sync == "automated")
  ' <<<"${output}"

  [ "${status}" -eq 0 ]
}

@test "identity and access edge contract exposes OIDC RBAC and API audience facts" {
  jq_path="$(command -v jq)"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  ln -sf "${jq_path}" "${BATS_TEST_TMPDIR}/bin/jq"

  run env PATH="${BATS_TEST_TMPDIR}/bin:/usr/bin:/bin" \
    /bin/bash "${REPO_ROOT}/terraform/kubernetes/scripts/check-sso.sh" \
    --execute \
    --contract \
    --host-port 443

  [ "${status}" -eq 0 ]
  identity_contract="${output}"

  run jq -e '
    .schema_version == "platform.identity-access-edge/v1" and
    .oidc_provider.provider == "keycloak" and
    .oidc_provider.groups_claim == "groups" and
    .oidc_provider.issuer_url == "https://keycloak.127.0.0.1.sslip.io/realms/platform" and
    .access_groups.admin == "platform-admins" and
    .access_groups.viewer == "platform-viewers" and
    .resource_servers.apim.audience == "apim-simulator" and
    any(.browser_edges[]; .name == "gitea" and (.allowed_groups | index("platform-admins"))) and
    .kubernetes_rbac.token_client_id == "headlamp"
  ' <<<"${identity_contract}"

  [ "${status}" -eq 0 ]
}

@test "chatgpt-sim is deployed in dev with the chatgpt.dev route" {
  for path in \
    terraform/kubernetes/apps/chatgpt-sim/all.yaml \
    terraform/kubernetes/apps/chatgpt-sim/kustomization.yaml \
    terraform/kubernetes/apps/argocd-apps/80-chatgpt-sim.application.yaml \
    terraform/kubernetes/apps/platform-gateway-routes-sso/httproute-chatgpt-sim.yaml \
    terraform/kubernetes/cluster-policies/cilium/shared/chatgpt-sim-hardened.yaml
  do
    [ -f "${REPO_ROOT}/${path}" ]
  done

  run rg -n 'namespace: dev|PUBLIC_BASE_URL|https://chatgpt.dev.127.0.0.1.sslip.io' \
    "${REPO_ROOT}/terraform/kubernetes/apps/chatgpt-sim/all.yaml"
  [ "${status}" -eq 0 ]

  run rg -n 'LLM_URL|http://agentgateway-ai-gateway\.agentgateway-system\.svc\.cluster\.local/v1/chat/completions|MCP_INTERNAL_URL|http://subnetcalc-apim-simulator\.apim\.svc\.cluster\.local:8000/mcp' \
    "${REPO_ROOT}/terraform/kubernetes/apps/chatgpt-sim/all.yaml"
  [ "${status}" -eq 0 ]

  run rg -n 'httproute-chatgpt-sim.yaml' \
    "${REPO_ROOT}/terraform/kubernetes/apps/platform-gateway-routes-sso/kustomization.yaml"
  [ "${status}" -eq 0 ]

  run rg -n 'repoURL: ssh://git@gitea-ssh\.gitea\.svc\.cluster\.local:22/platform/policies\.git' \
    "${REPO_ROOT}/terraform/kubernetes/apps/argocd-apps/80-chatgpt-sim.application.yaml"
  [ "${status}" -eq 0 ]

  run rg -n 'repoURL: http://gitea-http\.gitea\.svc\.cluster\.local:3000/platform/platform-policies\.git' \
    "${REPO_ROOT}/terraform/kubernetes/apps/argocd-apps/80-chatgpt-sim.application.yaml"
  [ "${status}" -ne 0 ]

  run rg -n '"k8s:io.kubernetes.pod.namespace": chatgpt' \
    "${REPO_ROOT}/terraform/kubernetes/cluster-policies/cilium"
  [ "${status}" -ne 0 ]

  run rg -n '"k8s:io.kubernetes.pod.namespace": dev[[:space:]]*$' \
    "${REPO_ROOT}/terraform/kubernetes/cluster-policies/cilium/shared/apim-baseline.yaml" \
    "${REPO_ROOT}/terraform/kubernetes/cluster-policies/cilium/shared/agentgateway-ai-gateway-hardened.yaml"
  [ "${status}" -eq 0 ]

  run rg -n '"k8s:app.kubernetes.io/name": agentgateway-ai-gateway|port: "80"' \
    "${REPO_ROOT}/terraform/kubernetes/cluster-policies/cilium/shared/chatgpt-sim-hardened.yaml"
  [ "${status}" -eq 0 ]
}

@test "chatgpt-sim SSO route is permitted by the sso namespace ReferenceGrant" {
  grant="${REPO_ROOT}/terraform/kubernetes/apps/platform-gateway-routes-sso/referencegrant-sso.yaml"

  run rg -n 'name: oauth2-proxy-chatgpt-sim' "${grant}"
  [ "${status}" -eq 0 ]
}

@test "developer portal and API have public portal gateway routes" {
  for path in \
    terraform/kubernetes/apps/platform-gateway-routes-sso/httproute-portal.yaml \
    terraform/kubernetes/apps/platform-gateway-routes-sso/httproute-portal-api.yaml
  do
    [ -f "${REPO_ROOT}/${path}" ]
  done

  run rg -n 'httproute-portal.yaml|httproute-portal-api.yaml' \
    "${REPO_ROOT}/terraform/kubernetes/apps/platform-gateway-routes-sso/kustomization.yaml"
  [ "${status}" -eq 0 ]

  run rg -n 'portal\.127\.0\.0\.1\.sslip\.io' \
    "${REPO_ROOT}/terraform/kubernetes/apps/platform-gateway-routes-sso/httproute-portal.yaml"
  [ "${status}" -eq 0 ]

  run rg -n 'portal-api\.127\.0\.0\.1\.sslip\.io' \
    "${REPO_ROOT}/terraform/kubernetes/apps/platform-gateway-routes-sso/httproute-portal-api.yaml"
  [ "${status}" -eq 0 ]
}

@test "developer portal gateway routes are permitted by the sso namespace ReferenceGrant" {
  grant="${REPO_ROOT}/terraform/kubernetes/apps/platform-gateway-routes-sso/referencegrant-sso.yaml"

  for service in \
    oauth2-proxy-backstage \
    oauth2-proxy-idp-core
  do
    run rg -n "name: ${service}" "${grant}"
    [ "${status}" -eq 0 ]
  done
}

@test "platform gateway buffers oauth2-proxy Keycloak session response headers" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
policy_path = repo_root / "terraform/kubernetes/apps/platform-gateway/proxysettingspolicy-oauth-response-buffers.yaml"
kustomization_path = repo_root / "terraform/kubernetes/apps/platform-gateway/kustomization.yaml"

assert policy_path.exists(), "missing platform gateway response-buffer policy"
policy = yaml.safe_load(policy_path.read_text(encoding="utf-8"))
kustomization = yaml.safe_load(kustomization_path.read_text(encoding="utf-8"))

assert "proxysettingspolicy-oauth-response-buffers.yaml" in kustomization["resources"]
assert policy["apiVersion"] == "gateway.nginx.org/v1alpha1"
assert policy["kind"] == "ProxySettingsPolicy"

target_refs = policy["spec"]["targetRefs"]
assert any(ref.get("kind") == "Gateway" and ref.get("name") == "platform-gateway" for ref in target_refs), target_refs

buffering = policy["spec"]["buffering"]
assert buffering["bufferSize"] in {"16k", "32k", "64k"}, buffering
assert buffering["buffers"]["number"] >= 8, buffering
assert buffering["buffers"]["size"] in {"16k", "32k", "64k"}, buffering
assert buffering["busyBuffersSize"] in {"32k", "64k", "128k"}, buffering

print("validated platform gateway response-header buffers for oauth2-proxy sessions")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated platform gateway response-header buffers"* ]]
}

@test "SSO auth proxies may reach developer portal and API upstreams" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
policy = yaml.safe_load((repo_root / "terraform/kubernetes/cluster-policies/cilium/shared/sso-hardened.yaml").read_text(encoding="utf-8"))
idp_policy_path = repo_root / "terraform/kubernetes/cluster-policies/cilium/shared/idp-hardened.yaml"
idp_policy = yaml.safe_load(idp_policy_path.read_text(encoding="utf-8"))
kustomization = yaml.safe_load((repo_root / "terraform/kubernetes/cluster-policies/cilium/shared/kustomization.yaml").read_text(encoding="utf-8"))

idp_egress_rules = [
    rule
    for rule in policy["spec"]["egress"]
    if any(
        endpoint.get("matchLabels", {}).get("k8s:io.kubernetes.pod.namespace") == "idp"
        for endpoint in rule.get("toEndpoints", [])
    )
]

assert idp_egress_rules, "sso-hardened must allow oauth2-proxy upstream traffic to the idp namespace"
ports = {
    port["port"]
    for rule in idp_egress_rules
    for to_port in rule.get("toPorts", [])
    for port in to_port.get("ports", [])
}
assert "8080" in ports, ports
assert "7007" in ports, ports

assert "idp-hardened.yaml" in kustomization["resources"]
assert idp_policy["metadata"]["name"] == "idp-hardened"
assert idp_policy["spec"]["endpointSelector"]["matchLabels"]["k8s:io.kubernetes.pod.namespace"] == "idp"

auth_proxy_ingress = [
    rule
    for rule in idp_policy["spec"]["ingress"]
    if any(
        endpoint.get("matchLabels", {}).get("k8s:io.kubernetes.pod.namespace") == "sso"
        and endpoint.get("matchLabels", {}).get("k8s:app.kubernetes.io/name") == "oauth2-proxy"
        for endpoint in rule.get("fromEndpoints", [])
    )
]
assert auth_proxy_ingress, "idp-hardened must allow SSO oauth2-proxy ingress to IDP services"
ingress_ports = {
    port["port"]
    for rule in auth_proxy_ingress
    for to_port in rule.get("toPorts", [])
    for port in to_port.get("ports", [])
}
assert "8080" in ingress_ports, ingress_ports
assert "7007" in ingress_ports, ingress_ports

print("validated SSO auth proxy ingress and egress for IDP upstreams")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated SSO auth proxy ingress and egress for IDP upstreams"* ]]
}

@test "SSO auth proxies may reach application gateway upstreams" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
policy = yaml.safe_load((repo_root / "terraform/kubernetes/cluster-policies/cilium/shared/sso-hardened.yaml").read_text(encoding="utf-8"))

app_rules = []
for rule in policy["spec"]["egress"]:
    endpoints = rule.get("toEndpoints", [])
    namespaces = {
        endpoint.get("matchLabels", {}).get("k8s:io.kubernetes.pod.namespace")
        for endpoint in endpoints
    }
    if {"dev", "uat"}.issubset(namespaces):
        app_rules.append(rule)

assert app_rules, "sso-hardened must allow oauth2-proxy egress to application upstream namespaces"
ports = {
    port["port"]
    for rule in app_rules
    for to_port in rule.get("toPorts", [])
    for port in to_port.get("ports", [])
}
assert "8080" in ports, ports

for rule in app_rules:
    for endpoint in rule.get("toEndpoints", []):
        expressions = endpoint.get("matchExpressions", [])
        tier_expression = next((expr for expr in expressions if expr.get("key") == "k8s:tier"), {})
        assert tier_expression.get("operator") == "In", tier_expression
        assert {"frontend", "gateway"}.issubset(set(tier_expression.get("values", []))), tier_expression

print("validated SSO auth proxy egress for application upstreams")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated SSO auth proxy egress for application upstreams"* ]]
}

@test "developer portal and API proxies use scoped browser SSO cookies" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
import re
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])
locals_tf = (repo_root / "terraform/kubernetes/locals.tf").read_text(encoding="utf-8")

block_match = re.search(r"sso_idp_proxy_apps = merge\((?P<body>.*?)\n  \)", locals_tf, re.S)
assert block_match, "sso_idp_proxy_apps local not found"
body = block_match.group("body")

cookie_names = dict(re.findall(r"(portal|api) = \{.*?cookie_name\s+=\s+\"([^\"]+)\"", body, re.S))
cookie_domains = dict(re.findall(r"(portal|api) = \{.*?cookie_domain\s+=\s+([^\n]+)", body, re.S))

assert cookie_names.get("portal") == "kind-v2-sso-portal", cookie_names
assert cookie_names.get("api") == "kind-v2-sso-portal-api", cookie_names
assert cookie_domains.get("portal", "").strip() == "local.portal_cookie_domain", cookie_domains
assert cookie_domains.get("api", "").strip() == "local.portal_cookie_domain", cookie_domains

print("validated scoped portal/API SSO cookies")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated scoped portal/API SSO cookies"* ]]
}

@test "app and environment authorization uses Keycloak groups instead of email-domain shortcuts" {
  for group in \
    app-subnetcalc-dev \
    app-subnetcalc-uat \
    app-sentiment-dev \
    app-sentiment-uat
  do
    run rg -n "${group}" "${REPO_ROOT}/terraform/kubernetes/sso.tf" "${REPO_ROOT}/terraform/kubernetes/locals.tf"
    [ "${status}" -eq 0 ]
  done

  run rg -n -- '--allowed-group=app-(subnetcalc|sentiment)-(dev|uat)' "${REPO_ROOT}/terraform/kubernetes/sso.tf"
  [ "${status}" -eq 0 ]

  run rg -n -- '--allowed-group=\$\{each\.value\.group\}' "${REPO_ROOT}/terraform/kubernetes/sso.tf"
  [ "${status}" -eq 0 ]

  run rg -n -- '--allowed-group=\$\{local\.sso_admin_group\}' "${REPO_ROOT}/terraform/kubernetes/sso.tf"
  [ "${status}" -eq 0 ]

  run rg -n 'email-domain: "(dev|uat)\\.test"' "${REPO_ROOT}/terraform/kubernetes/sso.tf"
  [ "${status}" -ne 0 ]
}

@test "HTTP services expose named appProtocol and target ports" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
paths = [
    "terraform/kubernetes/apps/workloads/base/all.yaml",
    "terraform/kubernetes/apps/chatgpt-sim/all.yaml",
    "terraform/kubernetes/apps/idp/all.yaml",
]

services = {}
for rel in paths:
    for doc in yaml.safe_load_all((repo_root / rel).read_text(encoding="utf-8")):
        if doc and doc.get("kind") == "Service":
            services[doc["metadata"]["name"]] = doc

expected = {
    "sentiment-api",
    "sentiment-auth-ui",
    "sentiment-router",
    "subnetcalc-api",
    "subnetcalc-frontend",
    "subnetcalc-router",
    "chatgpt-sim",
    "idp-core",
    "backstage",
}

for name in sorted(expected):
    port = services[name]["spec"]["ports"][0]
    assert port["name"] == "http", name
    assert port["appProtocol"] == "http", name
    assert port["targetPort"] == "http", name

print("validated HTTP service port metadata")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated HTTP service port metadata"* ]]
}

@test "Keycloak realm bootstrap includes app callbacks and a requestable groups client scope" {
  realm_tf="${REPO_ROOT}/terraform/kubernetes/sso.tf"

  for expected in \
    'clientScopes = [' \
    'name        = local.sso_groups_claim'
  do
    run rg -n -F "${expected}" "${realm_tf}"
    [ "${status}" -eq 0 ]
  done

  run rg -n 'optionalClientScopes\s*=\s*\[local\.sso_groups_claim\]' "${realm_tf}"
  [ "${status}" -eq 0 ]

  for expected in \
    '[for app in values(local.sso_chatgpt_sim_proxy_apps) : "${app.public_url}/oauth2/callback"]' \
    '[for app in values(local.sso_idp_proxy_apps) : "${app.public_url}/oauth2/callback"]'
  do
    run rg -n -F "${expected}" "${REPO_ROOT}/terraform/kubernetes/locals.tf"
    [ "${status}" -eq 0 ]
  done

  run rg -n 'resource "null_resource" "reconcile_keycloak_realm"' "${realm_tf}"
  [ "${status}" -eq 0 ]
}

@test "launchpad and IDP catalog use portal public FQDNs" {
  launchpad="${REPO_ROOT}/terraform/kubernetes/config/platform-launchpad.apps.json"
  catalog="${REPO_ROOT}/catalog/platform-apps.json"

  run jq -e '.tiles[] | select(.title == "Developer Portal") | .url == "https://portal.127.0.0.1.sslip.io"' "${launchpad}"
  [ "${status}" -eq 0 ]

  run jq -e '.tiles[] | select(.title == "Portal API") | .url == "https://portal-api.127.0.0.1.sslip.io"' "${launchpad}"
  [ "${status}" -eq 0 ]

  run jq -e '
    any(.applications[]; .name == "backstage" and any(.environments[]; .route == "https://portal.127.0.0.1.sslip.io")) and
    any(.applications[]; .name == "idp-core" and any(.environments[]; .route == "https://portal-api.127.0.0.1.sslip.io"))
  ' "${catalog}"
  [ "${status}" -eq 0 ]
}

@test "APIM uses a dedicated stage-900 resource audience without owning subnetcalc or compose auth" {
  realm_tf="${REPO_ROOT}/terraform/kubernetes/sso.tf"
  apim_manifest="${REPO_ROOT}/terraform/kubernetes/apps/apim/all.yaml"
  compose_stack="${REPO_ROOT}/docker/compose/compose.yml"
  subnetcalc_compose="${REPO_ROOT}/apps/subnetcalc/compose.yml"
  contracts="${REPO_ROOT}/docs/ddd/contracts.md"
  glossary="${REPO_ROOT}/docs/ddd/ubiquitous-language.md"

  run rg -n 'sso_apim_audience\s*=\s*"apim-simulator"' "${REPO_ROOT}/terraform/kubernetes/locals.tf"
  [ "${status}" -eq 0 ]

  run rg -n 'clientId\s*=\s*local\.sso_apim_audience|included\.client\.audience.*local\.sso_apim_audience' "${realm_tf}"
  [ "${status}" -eq 0 ]

  run rg -n '"audience": "apim-simulator"' "${apim_manifest}"
  [ "${status}" -eq 0 ]

  run rg -n 'oidc-issuer-url=https://dex\.compose\.127\.0\.0\.1\.sslip\.io:8443/dex' "${compose_stack}"
  [ "${status}" -eq 0 ]

  run rg -n 'AUTH_METHOD=none' "${subnetcalc_compose}"
  [ "${status}" -eq 0 ]

  run rg -n 'profiles: \["oidc"\]' "${subnetcalc_compose}"
  [ "${status}" -eq 0 ]

  for term in \
    "resource audience" \
    "portable auth mode" \
    "apim-simulator"
  do
    run rg -n "${term}" "${contracts}" "${glossary}"
    [ "${status}" -eq 0 ]
  done
}

@test "Keycloak admin console lands on the platform realm and uses a permanent admin lifecycle" {
  realm_tf="${REPO_ROOT}/terraform/kubernetes/sso.tf"
  reconcile_script="${REPO_ROOT}/terraform/kubernetes/scripts/reconcile-keycloak-realm.sh"
  launchpad="${REPO_ROOT}/terraform/kubernetes/config/platform-launchpad.apps.json"
  e2e="${REPO_ROOT}/tests/kubernetes/sso/tests/sso-smoke.spec.ts"

  run rg -n 'resource "kubernetes_secret_v1" "keycloak_bootstrap_admin"' "${realm_tf}"
  [ "${status}" -eq 0 ]

  run rg -n 'resource "kubernetes_secret_v1" "keycloak_admin"' "${realm_tf}"
  [ "${status}" -eq 0 ]

  run rg -n 'name: keycloak-bootstrap-admin' "${realm_tf}"
  [ "${status}" -eq 0 ]

  run rg -n 'KEYCLOAK_PERMANENT_ADMIN_SECRET|ensure_master_admin|delete_bootstrap_admins_from_master' "${reconcile_script}"
  [ "${status}" -eq 0 ]

  run rg -n 'ensure_group_client_role "platform-admins" "realm-management" "realm-admin"' "${reconcile_script}"
  [ "${status}" -eq 0 ]

  run rg -n 'defaultClientScopes\s*=\s*\["web-origins", "acr", "profile", "basic", "email"\]' "${realm_tf}"
  [ "${status}" -eq 0 ]

  run rg -n 'reconcile_client_scope_attachments|detach_client_scope_attachment' "${reconcile_script}"
  [ "${status}" -eq 0 ]

  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

script = (Path(os.environ["REPO_ROOT"]) / "terraform/kubernetes/scripts/reconcile-keycloak-realm.sh").read_text(encoding="utf-8")

assert "login_permanent_keycloak_admin()" in script
assert "ensure_master_admin\nlogin_permanent_keycloak_admin" in script

print("validated permanent admin reauthentication before bootstrap admin deletion")
PY
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated permanent admin reauthentication before bootstrap admin deletion"* ]]

  run jq -e '.tiles[] | select(.title == "Keycloak") | .url == "https://keycloak.127.0.0.1.sslip.io/admin/platform/console/#/platform/users"' "${launchpad}"
  [ "${status}" -eq 0 ]

  run rg -n "KEYCLOAK_CONSOLE_ADMIN_LOGIN.*'demo@admin.test'" "${e2e}"
  [ "${status}" -eq 0 ]
}

@test "Keycloak is bounded for local laptop stage-900 runs" {
  realm_tf="${REPO_ROOT}/terraform/kubernetes/sso.tf"

  run rg -n 'name: KC_CACHE' "${realm_tf}"
  [ "${status}" -eq 0 ]

  run rg -n 'value: local' "${realm_tf}"
  [ "${status}" -eq 0 ]

  run rg -n 'name: JAVA_OPTS_KC_HEAP' "${realm_tf}"
  [ "${status}" -eq 0 ]

  run rg -n 'MaxRAMPercentage=40' "${realm_tf}"
  [ "${status}" -eq 0 ]

  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

realm_tf = (Path(os.environ["REPO_ROOT"]) / "terraform/kubernetes/sso.tf").read_text(encoding="utf-8")

for needle in (
    "replicas: 1",
    "app.kubernetes.io/name: keycloak-postgres",
    "memory: 64Mi",
    "memory: 256Mi",
    "value: local",
    "resources:",
    "requests:",
    'cpu: "250m"',
    "memory: 768Mi",
    "limits:",
    'cpu: "750m"',
    "memory: 1280Mi",
):
    assert needle in realm_tf, needle

print("validated bounded Keycloak resource profile")
PY
  [ "${status}" -eq 0 ]
}

@test "Keycloak local targets use an optimized single-pod container image" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])
dockerfile = (repo_root / "apps/keycloak/Dockerfile").read_text(encoding="utf-8")
sso_tf = (repo_root / "terraform/kubernetes/sso.tf").read_text(encoding="utf-8")
build_script = (repo_root / "kubernetes/kind/scripts/build-local-platform-images.sh").read_text(encoding="utf-8")
image_catalog = (repo_root / "kubernetes/workflow/image-catalog.json").read_text(encoding="utf-8")

assert "FROM quay.io/keycloak/keycloak:26.6.1 AS builder" in dockerfile
assert "ENV KC_DB=postgres" in dockerfile
assert "ENV KC_CACHE=local" in dockerfile
assert "RUN /opt/keycloak/bin/kc.sh build" in dockerfile
assert "COPY --from=builder /opt/keycloak/ /opt/keycloak/" in dockerfile
assert 'ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]' in dockerfile
assert "microdnf" not in dockerfile and "dnf " not in dockerfile and "rpm " not in dockerfile

assert "replicas: 1" in sso_tf
assert "image: ${var.keycloak_image}" in sso_tf
assert "- --optimized" in sso_tf

assert "keycloak_source_tag=" in build_script
assert '"id": "keycloak"' in image_catalog
assert '"context": "apps/keycloak"' in image_catalog
assert '"dockerfile": "Dockerfile"' in image_catalog
assert '"default_tag": "26.6.1"' in image_catalog

for target, registry_host in {
    "kind": "host.docker.internal:5002",
    "lima": "host.lima.internal:5002",
    "slicer": "192.168.64.1:5002",
}.items():
    tfvars = (repo_root / "kubernetes" / target / "targets" / f"{target}.tfvars").read_text(encoding="utf-8")
    assert f'keycloak_image = "{registry_host}/platform/keycloak:26.6.1"' in tfvars, (target, tfvars)

print("validated optimized Keycloak container contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated optimized Keycloak container contract"* ]]
}

@test "Headlamp local chart is patched for CPU-bound laptop rollouts" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])
locals_tf = (repo_root / "terraform/kubernetes/locals.tf").read_text(encoding="utf-8")
sync_script = (repo_root / "terraform/kubernetes/scripts/sync-gitea-policies.sh").read_text(encoding="utf-8")

for needle in (
    "watchPlugins = false",
    'limits   = { cpu = "500m", memory = "256Mi" }',
    'requests = { cpu = "100m", memory = "128Mi" }',
):
    assert needle in locals_tf, needle

for needle in (
    "patch_vendored_headlamp_chart",
    "initialDelaySeconds: 20",
    "initialDelaySeconds: 10",
    "timeoutSeconds: 5",
    "failureThreshold: 6",
):
    assert needle in sync_script, needle

print("validated bounded Headlamp runtime and probe patch")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated bounded Headlamp runtime and probe patch"* ]]
}

@test "Keycloak realm reconcile explicitly attaches rendered client scopes" {
  script="${REPO_ROOT}/terraform/kubernetes/scripts/reconcile-keycloak-realm.sh"

  run rg -n 'ensure_client_scope_attachment "\$\{client_uuid\}" "optional" "\$\{scope_name\}"' "${script}"
  [ "${status}" -eq 0 ]
}

@test "Keycloak realm bootstrap defines default OIDC scopes before client attachment" {
  realm_tf="${REPO_ROOT}/terraform/kubernetes/sso.tf"

  for scope in web-origins acr profile basic email; do
    run rg -n 'name\s*=\s*"'"${scope}"'"' "${realm_tf}"
    [ "${status}" -eq 0 ]
  done

  for mapper in oidc-allowed-origins-mapper oidc-acr-mapper oidc-sub-mapper oidc-usermodel-attribute-mapper oidc-full-name-mapper; do
    run rg -n "${mapper}" "${realm_tf}"
    [ "${status}" -eq 0 ]
  done
}

@test "oauth2-proxy uses an internal session store for Keycloak token sessions" {
  realm_tf="${REPO_ROOT}/terraform/kubernetes/sso.tf"

  run rg -n 'resource "kubectl_manifest" "oauth2_proxy_session_store_deployment"' "${realm_tf}"
  [ "${status}" -eq 0 ]

  run rg -n 'session-store-type: redis' "${realm_tf}"
  [ "${status}" -eq 0 ]

  run rg -n 'redis-connection-url: \$\{local\.oauth2_proxy_redis_url\}' "${realm_tf}"
  [ "${status}" -eq 0 ]
}

@test "oauth2-proxy session store image uses the approved preloaded Redis source" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
import re
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])
variables_tf = (repo_root / "terraform/kubernetes/variables.tf").read_text(encoding="utf-8")
policy = (repo_root / "terraform/kubernetes/cluster-policies/kyverno/shared/restrict-image-registries.yaml").read_text(encoding="utf-8")

match = re.search(r'variable "oauth2_proxy_session_store_image" \{(?P<body>.*?)\n\}', variables_tf, re.S)
assert match, "missing oauth2_proxy_session_store_image variable"
default_match = re.search(r'default\s+=\s+"([^"]+)"', match.group("body"))
assert default_match, "missing oauth2_proxy_session_store_image default"

expected = "ecr-public.aws.com/docker/library/redis:8.2.3-alpine"
image = default_match.group(1)
assert image == expected, image
assert '"ecr-public.aws.com/*"' in policy, "Kyverno policy must approve the ECR Public preload source"

for target in ("docker-desktop", "kind", "lima", "slicer"):
    preload = (repo_root / "kubernetes" / target / "preload-images.txt").read_text(encoding="utf-8")
    assert expected in preload.splitlines(), target

print("validated approved oauth2-proxy Redis session store image")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated approved oauth2-proxy Redis session store image"* ]]
}

@test "admin SSO proxies use org groups rather than admin email-domain shortcuts" {
  run rg -n 'allowed-group: \$\{local\.sso_(admin|viewer)_group\}' "${REPO_ROOT}/terraform/kubernetes/sso.tf"
  [ "${status}" -eq 0 ]

  run rg -n 'email-domain: "admin\\.test"' "${REPO_ROOT}/terraform/kubernetes/sso.tf"
  [ "${status}" -ne 0 ]
}

@test "kind exposes self-service IDP commands as dry-run friendly operator surfaces" {
  run make -C "${REPO_ROOT}/kubernetes/kind" help
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"make idp-catalog"* ]]
  [[ "${output}" == *"make idp-env ACTION=create APP=chatgpt-sim ENV=preview-nr"* ]]
  [[ "${output}" == *"make idp-deployments"* ]]
  [[ "${output}" == *"make idp-secrets"* ]]

  run make -C "${REPO_ROOT}/kubernetes/kind" idp-catalog DRY_RUN=1
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"would inspect the IDP service catalog"* ]]

  run make -C "${REPO_ROOT}/kubernetes/kind" idp-env DRY_RUN=1 ACTION=create APP=chatgpt-sim ENV=preview-nr
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"would create environment preview-nr for chatgpt-sim"* ]]
}

@test "self-service environment requests render a usable workload base reference" {
  export PLATFORM_IDP_RUN_DIR="${REPO_ROOT}/.run/idp-core-components-test"
  rm -rf "${PLATFORM_IDP_RUN_DIR}"

  run make -C "${REPO_ROOT}/kubernetes/kind" idp-env ACTION=create APP=chatgpt-sim ENV=preview-nr
  [ "${status}" -eq 0 ]

  request_dir="${PLATFORM_IDP_RUN_DIR}/chatgpt-sim-preview-nr"
  [ -f "${request_dir}/request.json" ]
  [ -f "${request_dir}/kustomization.yaml" ]

  run sed -n '1,20p' "${request_dir}/kustomization.yaml"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"apps/workloads/chatgpt-sim"* ]]

  run kubectl kustomize "${request_dir}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"name: chatgpt-sim"* ]]

  rm -rf "${PLATFORM_IDP_RUN_DIR}"
}

@test "active SSO route tracing follows Keycloak rather than the old Dex route" {
  run rg -n 'name: keycloak' "${REPO_ROOT}/terraform/kubernetes/apps/platform-gateway-routes-sso/observabilitypolicy-tracing.yaml"
  [ "${status}" -eq 0 ]

  run rg -n 'name: dex' "${REPO_ROOT}/terraform/kubernetes/apps/platform-gateway-routes-sso/observabilitypolicy-tracing.yaml"
  [ "${status}" -ne 0 ]
}

@test "source repo carries concrete closure artifacts claimed by platform-docs" {
  for path in \
    terraform/kubernetes/scripts/gitea-repo-lifecycle-demo.sh \
    terraform/kubernetes/apps/apim/subnetcalc.api-product.yaml.example \
    apps/sentiment/evaluation.jsonl \
    apps/sentiment/MODEL_CARD.md
  do
    [ -f "${REPO_ROOT}/${path}" ]
  done
}

@test "DDD language names the new IDP domain concepts" {
  for term in \
    "service catalog" \
    "application spec" \
    "environment request" \
    "deployment record" \
    "secret binding" \
    "scorecard" \
    "app/environment RBAC" \
    "chatgpt-sim"
  do
    run rg -n "${term}" \
      "${REPO_ROOT}/docs/ddd/ubiquitous-language.md" \
      "${REPO_ROOT}/docs/ddd/context-map.md" \
      "${REPO_ROOT}/docs/ddd/contracts.md"
    [ "${status}" -eq 0 ]
  done
}
