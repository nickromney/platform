#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "MCP GitOps manifests expose machine and SSO console lanes" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import json
import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])


def load_docs(relative_path: str) -> list[dict]:
    path = repo_root / relative_path
    assert path.exists(), relative_path
    return [doc for doc in yaml.safe_load_all(path.read_text(encoding="utf-8")) if doc]


def by_kind_name(docs: list[dict], kind: str, name: str) -> dict:
    matches = [doc for doc in docs if doc.get("kind") == kind and doc.get("metadata", {}).get("name") == name]
    assert len(matches) == 1, (kind, name, matches)
    return matches[0]


def labels_for(workload: dict) -> dict:
    return workload["spec"]["template"]["metadata"]["labels"]


required_labels = {
    "app",
    "app.kubernetes.io/name",
    "app.kubernetes.io/component",
    "team",
    "tier",
}

mcp_docs = load_docs("terraform/kubernetes/apps/mcp/all.yaml")
namespace = by_kind_name(mcp_docs, "Namespace", "mcp")
assert namespace["metadata"]["labels"]["platform.publiccloudexperiments.net/namespace-role"] == "shared"

for name, app, component, tier, port in (
    ("platform-mcp", "platform-mcp", "mcp-server", "backend", 8080),
    ("mcp-inspector", "mcp-inspector", "inspector", "tooling", 6274),
):
    deployment = by_kind_name(mcp_docs, "Deployment", name)
    labels = labels_for(deployment)
    assert required_labels <= labels.keys(), (name, labels)
    assert labels["app"] == app
    assert labels["app.kubernetes.io/name"] == app
    assert labels["app.kubernetes.io/component"] == component
    assert labels["team"] == "platform"
    assert labels["tier"] == tier
    container = deployment["spec"]["template"]["spec"]["containers"][0]
    assert container["securityContext"]["readOnlyRootFilesystem"] is True
    assert "ALL" in container["securityContext"]["capabilities"]["drop"]

    service = by_kind_name(mcp_docs, "Service", name)
    assert service["metadata"]["labels"]["app"] == app
    assert service["spec"]["ports"][0]["port"] == port

inspector = by_kind_name(mcp_docs, "Deployment", "mcp-inspector")
inspector_env = {
    item["name"]: item["value"]
    for item in inspector["spec"]["template"]["spec"]["containers"][0].get("env", [])
    if "value" in item
}
assert inspector_env["MCP_AUTO_OPEN_ENABLED"] == "false"
assert inspector_env["HOST"] == "0.0.0.0"
assert inspector_env["MCP_PROXY_AUTH_TOKEN"] == ""

apim = by_kind_name(load_docs("terraform/kubernetes/apps/apim/all.yaml"), "ConfigMap", "subnetcalc-apim-simulator-config")
apim_config = json.loads(apim["data"]["config.json"])
mcp_routes = [route for route in apim_config["routes"] if route["name"] == "platform-mcp"]
assert len(mcp_routes) == 1
assert mcp_routes[0]["host_match"] == ["mcp.127.0.0.1.sslip.io"]
assert mcp_routes[0]["path_prefix"] == "/mcp"
assert mcp_routes[0]["upstream_base_url"] == "http://platform-mcp.mcp.svc.cluster.local:8080"
assert apim_config["allow_anonymous"] is False
assert apim_config["oidc"]["audience"] == "apim-simulator"

routes = []
for relative_path in (
    "terraform/kubernetes/apps/platform-gateway-routes-sso/httproute-mcp.yaml",
    "terraform/kubernetes/apps/platform-gateway-routes-sso/httproute-mcp-console.yaml",
):
    routes.extend(load_docs(relative_path))

mcp_route = by_kind_name(routes, "HTTPRoute", "mcp")
assert mcp_route["spec"]["hostnames"] == ["mcp.127.0.0.1.sslip.io"]
assert mcp_route["spec"]["rules"][0]["matches"][0]["path"]["value"] == "/mcp"
assert mcp_route["spec"]["rules"][0]["backendRefs"][0]["name"] == "subnetcalc-apim-simulator"
assert mcp_route["spec"]["rules"][0]["backendRefs"][0]["namespace"] == "apim"

console_route = by_kind_name(routes, "HTTPRoute", "mcp-console")
assert console_route["spec"]["hostnames"] == ["mcp-console.127.0.0.1.sslip.io"]
assert console_route["spec"]["rules"][0]["backendRefs"][0]["name"] == "oauth2-proxy-mcp-console"
assert console_route["spec"]["rules"][0]["backendRefs"][0]["namespace"] == "sso"

reference_grant = by_kind_name(
    load_docs("terraform/kubernetes/apps/platform-gateway-routes-sso/referencegrant-sso.yaml"),
    "ReferenceGrant",
    "allow-gateway-routes",
)
allowed_services = [item["name"] for item in reference_grant["spec"]["to"] if item.get("kind") == "Service"]
assert "oauth2-proxy-mcp-console" in allowed_services

reference_grant_apim = by_kind_name(
    load_docs("terraform/kubernetes/apps/platform-gateway-routes-sso/referencegrant-apim.yaml"),
    "ReferenceGrant",
    "allow-gateway-routes-apim",
)
allowed_apim_services = [item["name"] for item in reference_grant_apim["spec"]["to"] if item.get("kind") == "Service"]
assert "subnetcalc-apim-simulator" in allowed_apim_services

kustomization = yaml.safe_load(
    (repo_root / "terraform/kubernetes/apps/platform-gateway-routes-sso/kustomization.yaml").read_text(encoding="utf-8")
)
for resource in ("httproute-mcp.yaml", "httproute-mcp-console.yaml", "referencegrant-apim.yaml"):
    assert resource in kustomization["resources"], resource

print("validated MCP GitOps manifests")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated MCP GitOps manifests"* ]]
}

@test "MCP Cilium policies only bridge APIM and SSO to MCP workloads" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])


def load_docs(relative_path: str) -> list[dict]:
    path = repo_root / relative_path
    assert path.exists(), relative_path
    return [doc for doc in yaml.safe_load_all(path.read_text(encoding="utf-8")) if doc]


def one_policy(relative_path: str, name: str) -> dict:
    matches = [doc for doc in load_docs(relative_path) if doc.get("metadata", {}).get("name") == name]
    assert len(matches) == 1, (relative_path, name, matches)
    return matches[0]


platform_policy = one_policy("terraform/kubernetes/cluster-policies/cilium/shared/mcp-hardened.yaml", "platform-mcp-hardened")
selector = platform_policy["spec"]["endpointSelector"]["matchLabels"]
assert selector["k8s:io.kubernetes.pod.namespace"] == "mcp"
assert selector["k8s:app.kubernetes.io/name"] == "platform-mcp"

inspector_policy = one_policy("terraform/kubernetes/cluster-policies/cilium/shared/mcp-hardened.yaml", "mcp-inspector-hardened")
inspector_selector = inspector_policy["spec"]["endpointSelector"]["matchLabels"]
assert inspector_selector["k8s:io.kubernetes.pod.namespace"] == "mcp"
assert inspector_selector["k8s:app.kubernetes.io/name"] == "mcp-inspector"

ingress = platform_policy["spec"]["ingress"] + inspector_policy["spec"]["ingress"]
source_names = {
    source["matchLabels"].get("k8s:app.kubernetes.io/name")
    for rule in ingress
    for source in rule.get("fromEndpoints", [])
    if source["matchLabels"].get("k8s:app.kubernetes.io/name")
}
assert source_names == {"subnetcalc-apim-simulator", "oauth2-proxy"}
source_namespaces = {
    source["matchLabels"].get("k8s:io.kubernetes.pod.namespace")
    for rule in ingress
    for source in rule.get("fromEndpoints", [])
}
assert source_namespaces == {"apim", "sso", "observability"}
assert any(rule["toPorts"][0]["ports"][0]["port"] == "8080" for rule in ingress)
assert any(rule["toPorts"][0]["ports"][0]["port"] == "6274" for rule in ingress)
assert any(rule["toPorts"][0]["ports"][0]["port"] == "9090" for rule in ingress)

apim_policy = one_policy("terraform/kubernetes/cluster-policies/cilium/shared/apim-baseline.yaml", "apim-baseline")
apim_ingress_namespaces = {
    endpoint["matchLabels"].get("k8s:io.kubernetes.pod.namespace")
    for rule in apim_policy["spec"]["ingress"]
    for endpoint in rule.get("fromEndpoints", [])
}
assert "platform-gateway" in apim_ingress_namespaces
apim_egress_names = {
    endpoint["matchLabels"].get("k8s:app.kubernetes.io/name")
    for rule in apim_policy["spec"]["egress"]
    for endpoint in rule.get("toEndpoints", [])
}
assert "platform-mcp" in apim_egress_names

gateway_policy = one_policy(
    "terraform/kubernetes/cluster-policies/cilium/shared/platform-gateway-hardened.yaml",
    "platform-gateway-hardened",
)
gateway_egress_names = {
    endpoint["matchLabels"].get("k8s:app.kubernetes.io/name")
    for rule in gateway_policy["spec"]["egress"]
    for endpoint in rule.get("toEndpoints", [])
}
assert "subnetcalc-apim-simulator" in gateway_egress_names

sso_policy = one_policy("terraform/kubernetes/cluster-policies/cilium/shared/sso-hardened.yaml", "sso-hardened")
sso_egress_names = {
    endpoint["matchLabels"].get("k8s:app.kubernetes.io/name")
    for rule in sso_policy["spec"]["egress"]
    for endpoint in rule.get("toEndpoints", [])
}
assert "mcp-inspector" in sso_egress_names

kustomization = yaml.safe_load(
    (repo_root / "terraform/kubernetes/cluster-policies/cilium/shared/kustomization.yaml").read_text(encoding="utf-8")
)
assert "mcp-hardened.yaml" in kustomization["resources"]

print("validated MCP Cilium policies")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated MCP Cilium policies"* ]]
}

@test "MCP Argo and SSO registration is wired for direct and app-of-apps modes" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])

locals_tf = (repo_root / "terraform/kubernetes/locals.tf").read_text(encoding="utf-8")
workload_apps_tf = (repo_root / "terraform/kubernetes/workload-apps.tf").read_text(encoding="utf-8")
sso_tf = (repo_root / "terraform/kubernetes/sso.tf").read_text(encoding="utf-8")

assert 'mcp_public_host' in locals_tf
assert 'mcp_console_public_host' in locals_tf
assert '"oauth2-proxy-mcp-console"' in locals_tf
assert '["mcp"]' in locals_tf
assert '["oauth2-proxy-mcp-console"]' in locals_tf
assert '"mcp"] : []' in locals_tf

assert 'resource "kubectl_manifest" "namespace_mcp"' in workload_apps_tf
assert 'resource "kubectl_manifest" "argocd_app_mcp"' in workload_apps_tf
assert 'name: mcp' in workload_apps_tf
assert 'path: apps/mcp' in workload_apps_tf

assert 'local.sso_mcp_console_proxy_apps' in sso_tf
assert 'upstream: ${each.value.upstream}' in sso_tf

app_of_apps = repo_root / "terraform/kubernetes/apps/argocd-apps/79-mcp.application.yaml"
assert app_of_apps.exists()
assert "path: apps/mcp" in app_of_apps.read_text(encoding="utf-8")

print("validated MCP Argo and SSO registration")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated MCP Argo and SSO registration"* ]]
}

@test "MCP observability is wired for Prometheus, Victoria Logs, and Grafana" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])


def load_docs(relative_path: str) -> list[dict]:
    return [
        doc
        for doc in yaml.safe_load_all((repo_root / relative_path).read_text(encoding="utf-8"))
        if doc
    ]


def by_kind_name(docs: list[dict], kind: str, name: str) -> dict:
    matches = [doc for doc in docs if doc.get("kind") == kind and doc.get("metadata", {}).get("name") == name]
    assert len(matches) == 1, (kind, name, matches)
    return matches[0]


mcp_docs = load_docs("terraform/kubernetes/apps/mcp/all.yaml")
deployment = by_kind_name(mcp_docs, "Deployment", "platform-mcp")
template = deployment["spec"]["template"]
annotations = template["metadata"]["annotations"]
assert annotations["prometheus.io/scrape"] == "true"
assert annotations["prometheus.io/path"] == "/metrics"
assert annotations["prometheus.io/port"] == "9090"

container = template["spec"]["containers"][0]
ports = {port["name"]: port["containerPort"] for port in container["ports"]}
assert ports["metrics"] == 9090
env = {item["name"]: item["value"] for item in container["env"] if "value" in item}
assert env["PLATFORM_MCP_LOG_FORMAT"] == "json"
assert env["PLATFORM_MCP_METRICS_ENABLED"] == "true"
assert env["OTEL_SERVICE_NAME"] == "platform-mcp"
assert "k8s.namespace.name=mcp" in env["OTEL_RESOURCE_ATTRIBUTES"]

service = by_kind_name(mcp_docs, "Service", "platform-mcp")
service_ports = {port["name"]: port["port"] for port in service["spec"]["ports"]}
assert service_ports["metrics"] == 9090

policy = by_kind_name(
    load_docs("terraform/kubernetes/cluster-policies/cilium/shared/mcp-hardened.yaml"),
    "CiliumClusterwideNetworkPolicy",
    "platform-mcp-hardened",
)
assert any(
    source["matchLabels"].get("k8s:io.kubernetes.pod.namespace") == "observability"
    and rule["toPorts"][0]["ports"][0]["port"] == "9090"
    for rule in policy["spec"]["ingress"]
    for source in rule.get("fromEndpoints", [])
)

observability_policy = by_kind_name(
    load_docs("terraform/kubernetes/cluster-policies/cilium/shared/observability-hardened.yaml"),
    "CiliumClusterwideNetworkPolicy",
    "observability-hardened",
)
assert any(
    target["matchLabels"].get("k8s:io.kubernetes.pod.namespace") == "mcp"
    and target["matchLabels"].get("k8s:app.kubernetes.io/name") == "platform-mcp"
    and any(port["port"] == "9090" for ports in rule.get("toPorts", []) for port in ports.get("ports", []))
    for rule in observability_policy["spec"]["egress"]
    for target in rule.get("toEndpoints", [])
), "observability namespace must be allowed to scrape platform-mcp metrics"

prometheus = (repo_root / "terraform/kubernetes/observability.tf").read_text(encoding="utf-8")
grafana = (repo_root / "terraform/kubernetes/apps/argocd-apps/95-grafana.application.yaml").read_text(encoding="utf-8")
assert "- job_name: platform-mcp" in prometheus, "missing platform-mcp Prometheus scrape job"
assert "names:\n                    - mcp" in prometheus, "missing mcp namespace in Prometheus scrape job"
assert "platform-mcp-observability" in grafana, "missing MCP Grafana dashboard"
assert "platform_mcp_tool_calls_total" in grafana, "missing MCP tool metrics panel"
assert "How to read this dashboard" in grafana, "MCP dashboard needs operator guidance, not just empty panels"
assert "Prometheus Scrape" in grafana, "MCP dashboard must show whether metrics are being scraped"
assert "Total Tool Calls" in grafana, "MCP dashboard must render zero calls as an explicit value"
assert "Platform MCP" in grafana, "launchpad must include an MCP dashboard tile"
assert "Backstage Observability" in grafana, "launchpad must include a Backstage observability tile"
assert "k8s.namespace.name:mcp" in grafana, "missing MCP Victoria Logs query"

catalog = (repo_root / "apps/backstage/catalog/apps/platform-mcp/catalog-info.yaml").read_text(encoding="utf-8")
assert "MCP Observability" in catalog, "missing catalog observability link title"
assert "platform-mcp-observability" in catalog, "missing catalog observability link URL"

print("validated MCP observability wiring")
PY

  if [ "${status}" -ne 0 ]; then
    printf '%s\n' "${output}"
  fi
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated MCP observability wiring"* ]]
}

@test "MCP browser E2E contracts cover SSO console, D2 render export, and observability dashboards" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])
sso_run = (repo_root / "tests/kubernetes/sso/run.sh").read_text(encoding="utf-8")
sso_spec = (repo_root / "tests/kubernetes/sso/tests/sso-smoke.spec.ts").read_text(encoding="utf-8")

assert "SSO_E2E_ENABLE_MCP" in sso_run, "runner must expose an MCP feature toggle"
assert "SSO_E2E_TEST_GREP" in sso_run, "runner must allow focused MCP E2E execution"
assert "--grep" in sso_run, "runner must pass focused test filters to Playwright"
assert "oauth2-proxy-oidc" in sso_run, "runner must discover the oauth2-proxy OIDC secret for bearer-token tests"
assert 'kubectl_args+=(--context "${KUBECONFIG_CONTEXT}")' in sso_run, "runner must honor the selected kubeconfig context"
assert "SSO_E2E_OAUTH2_PROXY_CLIENT_SECRET" in sso_run, "runner must pass the OIDC client secret to Playwright"
kind_makefile = (repo_root / "kubernetes/kind/Makefile").read_text(encoding="utf-8")
assert 'KUBECONFIG="$(KUBECONFIG_PATH)" KUBECONFIG_CONTEXT="$(KUBECONFIG_CONTEXT)" SSO_E2E_ENABLE_BACKSTAGE' in kind_makefile

assert "mcp-console" in sso_spec, "MCP Inspector console target missing"
assert "mcp-inspector-d2-render-export" in sso_spec, "D2 render/export post-login check missing"
assert "MCP_ENDPOINT_URL" in sso_spec and "absolutePlatformUrl('mcp', '/mcp')" in sso_spec
assert "tools/list" in sso_spec and "tools/call" in sso_spec, "MCP protocol calls missing"
assert "d2_render" in sso_spec, "D2 render tool is not exercised"
assert "page.waitForEvent('download')" in sso_spec, "D2 SVG browser export is not asserted"
assert "platform-mcp-d2-e2e.svg" in sso_spec, "D2 SVG export filename is not stable"

assert "grafana-mcp-observability" in sso_spec, "MCP Grafana dashboard target missing"
assert "Platform MCP Observability" in sso_spec, "MCP Grafana dashboard title not asserted"
assert "Total Tool Calls" in sso_spec, "MCP tool-call panel not asserted"
assert "Tool Calls by Tool" in sso_spec, "MCP tool breakdown panel not asserted"
assert "grafana-backstage-observability" in sso_spec, "Backstage Grafana dashboard target missing"
assert "Backstage Observability" in sso_spec, "Backstage Grafana dashboard title not asserted"
assert "Services Missing Kubernetes Selector" in sso_spec, "Backstage catalog quality panel not asserted"
assert "Recent Backstage Logs" in sso_spec, "Backstage Victoria Logs panel not asserted"

sso_readme = (repo_root / "tests/kubernetes/sso/README.md").read_text(encoding="utf-8")
assert 'SSO_E2E_TEST_GREP="mcp-console: load and login" make check-sso-e2e' in sso_readme

print("validated MCP browser E2E contracts")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated MCP browser E2E contracts"* ]]
}
