#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "IDP Cilium policy explicitly supports Backstage Kubernetes and OTel flows" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
policy = yaml.safe_load((repo_root / "terraform/kubernetes/cluster-policies/cilium/shared/idp-hardened.yaml").read_text())
egress = policy["spec"]["egress"]

assert any("kube-apiserver" in rule.get("toEntities", []) for rule in egress), "idp must reach Kubernetes API for Backstage catalog discovery"
assert any(
    service.get("k8sService", {}).get("namespace") == "default"
    and service.get("k8sService", {}).get("serviceName") == "kubernetes"
    for rule in egress
    for service in rule.get("toServices", [])
), "idp must allow the default/kubernetes service path"

otel_ports = {
    port["port"]
    for rule in egress
    for endpoint in rule.get("toEndpoints", [])
    if endpoint.get("matchLabels", {}).get("k8s:io.kubernetes.pod.namespace") == "observability"
    for port_group in rule.get("toPorts", [])
    for port in port_group.get("ports", [])
}
assert {"4317", "4318"} <= otel_ports, otel_ports

print("validated idp cilium backstage flows")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated idp cilium backstage flows"* ]]
}

@test "MCP Cilium policy keeps tool egress to named platform dependencies" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
docs = [
    doc for doc in yaml.safe_load_all((repo_root / "terraform/kubernetes/cluster-policies/cilium/shared/mcp-hardened.yaml").read_text())
    if doc
]
platform = next(doc for doc in docs if doc["metadata"]["name"] == "platform-mcp-hardened")
egress = platform["spec"]["egress"]

flat = [
    endpoint.get("matchLabels", {})
    for rule in egress
    for endpoint in rule.get("toEndpoints", [])
]

assert any(labels.get("k8s:app.kubernetes.io/name") == "subnetcalc-apim-simulator" for labels in flat)
assert any(labels.get("k8s:app.kubernetes.io/name") == "idp-core" for labels in flat)
assert any(labels.get("k8s:app") == "sentiment" and labels.get("k8s:tier") == "backend" for labels in flat)

assert all("world" not in rule.get("toEntities", []) for rule in egress)
assert all("0.0.0.0/0" not in str(rule) for rule in egress)

print("validated mcp cilium named dependencies")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated mcp cilium named dependencies"* ]]
}

@test "Nginx gateway policy allows Kubernetes API discovery without broad egress" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
policy_path = repo_root / "terraform/kubernetes/cluster-policies/cilium/shared/nginx-gateway-hardened.yaml"
policy = yaml.safe_load(policy_path.read_text())
spec = policy["spec"]
egress = spec["egress"]

selector = spec["endpointSelector"]["matchLabels"]
assert selector["k8s:io.kubernetes.pod.namespace"] == "nginx-gateway"
assert selector["k8s:app.kubernetes.io/name"] == "nginx-gateway"

assert any("kube-apiserver" in rule.get("toEntities", []) for rule in egress), "nginx gateway must reach Kubernetes API"
assert any(
    service.get("k8sService", {}).get("namespace") == "default"
    and service.get("k8sService", {}).get("serviceName") == "kubernetes"
    for rule in egress
    for service in rule.get("toServices", [])
), "nginx gateway must allow the default/kubernetes service path"
assert any(
    endpoint.get("matchLabels", {}).get("k8s:k8s-app") == "kube-dns"
    for rule in egress
    for endpoint in rule.get("toEndpoints", [])
), "nginx gateway should keep DNS egress explicit"

assert all("world" not in rule.get("toEntities", []) for rule in egress)
assert all("0.0.0.0/0" not in str(rule) for rule in egress)

print("validated nginx gateway cilium api egress")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated nginx gateway cilium api egress"* ]]
}

@test "Sentiment backend policy allows MCP classify-only endpoint" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
docs = [
    doc for doc in yaml.safe_load_all((repo_root / "terraform/kubernetes/cluster-policies/cilium/projects/sentiment/sentiment-runtime.yaml").read_text())
    if doc
]
backend = next(doc for doc in docs if doc["metadata"]["name"] == "sentiment-backend-ingress")
ingress = backend["spec"]["ingress"]

mcp_rules = [
    rule for rule in ingress
    for endpoint in rule.get("fromEndpoints", [])
    if endpoint.get("matchLabels", {}).get("k8s:io.kubernetes.pod.namespace") == "mcp"
    and endpoint.get("matchLabels", {}).get("k8s:app.kubernetes.io/name") == "platform-mcp"
]

assert len(mcp_rules) == 1
http_rules = mcp_rules[0]["toPorts"][0]["rules"]["http"]
assert http_rules == [{"method": "POST", "path": "/api/v1/sentiment/classify"}]

print("validated sentiment mcp classify ingress")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated sentiment mcp classify ingress"* ]]
}

@test "Kyverno audits shared namespace runtime hardening and discovery labels" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
shared = repo_root / "terraform/kubernetes/cluster-policies/kyverno/shared"
kustomization = yaml.safe_load((shared / "kustomization.yaml").read_text())
assert "audit-platform-runtime-baseline.yaml" in kustomization["resources"]
assert "audit-platform-workload-labels.yaml" in kustomization["resources"]

runtime = yaml.safe_load((shared / "audit-platform-runtime-baseline.yaml").read_text())
assert runtime["kind"] == "ClusterPolicy"
assert runtime["metadata"]["name"] == "audit-platform-runtime-baseline"
assert runtime["spec"]["validationFailureAction"] == "Audit"
rules = {rule["name"]: rule for rule in runtime["spec"]["rules"]}
for required in (
    "require-drop-all-capabilities",
    "deny-privileged",
    "deny-privilege-escalation",
    "require-read-only-root-filesystem",
    "require-runtime-default-seccomp",
):
    assert required in rules

labels = yaml.safe_load((shared / "audit-platform-workload-labels.yaml").read_text())
assert labels["kind"] == "ClusterPolicy"
assert labels["metadata"]["name"] == "audit-platform-workload-labels"
assert labels["spec"]["validationFailureAction"] == "Audit"
assert "app.kubernetes.io/name" in str(labels)
assert "team" in str(labels)
assert "tier" in str(labels)

tests = yaml.safe_load((shared / "kyverno-test.yaml").read_text())
assert "audit-platform-runtime-baseline.yaml" in tests["policies"]
assert "audit-platform-workload-labels.yaml" in tests["policies"]

print("validated kyverno platform audits")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated kyverno platform audits"* ]]
}
