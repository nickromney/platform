#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
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

@test "Argo Rollouts policy does not allow GitHub plugin download egress" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
policy_path = repo_root / "terraform/kubernetes/cluster-policies/cilium/shared/argo-rollouts-hardened.yaml"
policy = yaml.safe_load(policy_path.read_text())
egress = policy["spec"]["egress"]

assert all("toFQDNs" not in rule for rule in egress), "argo-rollouts must not egress to GitHub FQDNs"
assert "github.com" not in policy_path.read_text()

dns_egress = next(
    rule
    for rule in egress
    if any(
        endpoint.get("matchLabels", {}).get("k8s:io.kubernetes.pod.namespace") == "kube-system"
        and endpoint.get("matchLabels", {}).get("k8s:k8s-app") == "kube-dns"
        for endpoint in rule.get("toEndpoints", [])
    )
)
assert all("rules" not in to_ports for to_ports in dns_egress.get("toPorts", []))

print("validated argo rollouts cilium policy without github egress")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated argo rollouts cilium policy without github egress"* ]]
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
egress_policy = next(doc for doc in docs if doc["metadata"]["name"] == "sentiment-api-egress")
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

keycloak_rules = [
    rule for rule in egress_policy["spec"]["egress"]
    for endpoint in rule.get("toEndpoints", [])
    if endpoint.get("matchLabels", {}).get("k8s:app.kubernetes.io/name") == "keycloak"
]
assert len(keycloak_rules) == 1
assert keycloak_rules[0]["toPorts"][0]["ports"][0]["port"] == "8080"

print("validated sentiment mcp classify ingress and oidc egress")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated sentiment mcp classify ingress and oidc egress"* ]]
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

@test "Cilium gateway ingress policy only selects endpoints another policy already restricts" {
  run uv run --isolated --with pyyaml python - <<'XPY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
policy = repo_root / "terraform/kubernetes/cluster-policies/cilium/shared/cilium-gateway-ingress.yaml"
docs = [d for d in yaml.safe_load_all(policy.read_text()) if d]

# Selecting an endpoint in any Cilium policy switches it from default-allow to
# default-deny for that direction, so an allow rule on an otherwise unselected
# endpoint removes access instead of granting it. hubble-ui and policy-reporter
# are unselected by any other ingress policy; adding them here broke the
# control-plane-to-NodePort path that kind publishes to the host.
forbidden = {"hubble-ui", "policy-reporter"}
violations = []
for doc in docs:
    selector = doc["spec"]["endpointSelector"]["matchLabels"]
    for value in selector.values():
        if value in forbidden:
            violations.append(doc["metadata"]["name"] + " selects " + value)

print("VIOLATIONS " + "; ".join(violations) if violations else "CLEAN")
XPY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"CLEAN"* ]]
}

@test "Cilium gateway ingress policy admits the Envoy identity rather than host" {
  run uv run --isolated --with pyyaml python - <<'XPY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
policy = repo_root / "terraform/kubernetes/cluster-policies/cilium/shared/cilium-gateway-ingress.yaml"
docs = [d for d in yaml.safe_load_all(policy.read_text()) if d]

# Cilium's Gateway API Envoy presents reserved:ingress. A host rule here would
# silently fail to match it and every gateway backend would return 503.
problems = []
for doc in docs:
    entities = set()
    for rule in doc["spec"]["ingress"]:
        entities.update(rule.get("fromEntities", []))
    if entities != {"ingress"}:
        problems.append(doc["metadata"]["name"] + " admits " + ",".join(sorted(entities)))

print("PROBLEMS " + "; ".join(problems) if problems else "CLEAN")
XPY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"CLEAN"* ]]
}
