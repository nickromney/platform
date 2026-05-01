#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "review environment substrate is provisioned by the platform" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])

namespaces = (repo_root / "terraform/kubernetes/namespaces.tf").read_text(encoding="utf-8")
locals_tf = (repo_root / "terraform/kubernetes/locals.tf").read_text(encoding="utf-8")
gitea_tf = (repo_root / "terraform/kubernetes/gitea.tf").read_text(encoding="utf-8")
cert = yaml.safe_load((repo_root / "terraform/kubernetes/apps/cert-manager-config/platform-gateway-cert.yaml").read_text(encoding="utf-8"))

assert "enable_review_environments" in locals_tf
assert "enable_review_environments           = var.enable_argocd && var.enable_gitea" in locals_tf
assert 'resource "kubernetes_namespace_v1" "review"' in namespaces
assert '"platform.publiccloudexperiments.net/namespace-role"      = "application"' in namespaces
assert '"platform.publiccloudexperiments.net/environment"         = "review"' in namespaces
assert '"platform.publiccloudexperiments.net/environment-purpose" = "branch-preview"' in namespaces
assert 'local.enable_review_environments ? ["review"] : []' in locals_tf
assert "kubernetes_namespace_v1.review" in gitea_tf
assert "*.review.127.0.0.1.sslip.io" in cert["spec"]["dnsNames"]

print("validated review namespace, registry secret, and wildcard TLS substrate")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated review namespace, registry secret, and wildcard TLS substrate"* ]]
}

@test "gitea actions runner has scoped review-environment kubernetes access" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
runner_dir = repo_root / "terraform/kubernetes/apps/gitea-actions-runner"
kustomization = yaml.safe_load((runner_dir / "kustomization.yaml").read_text(encoding="utf-8"))
configmap = yaml.safe_load((runner_dir / "configmap.yaml").read_text(encoding="utf-8"))
deployment = yaml.safe_load((runner_dir / "deployment.yaml").read_text(encoding="utf-8"))
service_account = yaml.safe_load((runner_dir / "serviceaccount.yaml").read_text(encoding="utf-8"))
rbac_docs = list(yaml.safe_load_all((runner_dir / "review-environment-rbac.yaml").read_text(encoding="utf-8")))

assert "serviceaccount.yaml" in kustomization["resources"]
assert "review-environment-rbac.yaml" in kustomization["resources"]
assert service_account["kind"] == "ServiceAccount"
assert service_account["metadata"]["name"] == "act-runner"
assert service_account["automountServiceAccountToken"] is True
runner_config = yaml.safe_load(configmap["data"]["config.yaml"])
assert runner_config["runner"]["labels"] == ["self-hosted", "linux", "arm64", "in-cluster", "review-env"]

pod_spec = deployment["spec"]["template"]["spec"]
assert pod_spec["serviceAccountName"] == "act-runner"
init_by_name = {container["name"]: container for container in pod_spec["initContainers"]}
assert init_by_name["install-kubectl"]["image"] == "kindest/node:v1.35.1"
assert "/tools/kubectl" in "\n".join(init_by_name["install-kubectl"]["command"])
assert pod_spec["containers"][0]["env"][-1]["value"].startswith("/tools:")

roles = {(doc["kind"], doc["metadata"]["namespace"], doc["metadata"]["name"]): doc for doc in rbac_docs}
review_role = roles[("Role", "review", "review-environment-manager")]
route_role = roles[("Role", "gateway-routes", "review-route-manager")]

review_resources = {resource for rule in review_role["rules"] for resource in rule["resources"]}
assert {"deployments", "services", "referencegrants", "ciliumnetworkpolicies"} <= review_resources
route_resources = {resource for rule in route_role["rules"] for resource in rule["resources"]}
assert "httproutes" in route_resources

bindings = [doc for doc in rbac_docs if doc["kind"] == "RoleBinding"]
assert all(binding["subjects"][0]["name"] == "act-runner" for binding in bindings)
assert all(binding["subjects"][0]["namespace"] == "gitea-runner" for binding in bindings)

print("validated gitea runner review RBAC and kubectl tooling")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated gitea runner review RBAC and kubectl tooling"* ]]
}

@test "scaffolded review workflow uses the managed substrate" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
workflow_path = repo_root / "apps/backstage/catalog/templates/platform-service/content/.gitea/workflows/review-environment.yaml"
build_workflow_path = repo_root / "apps/backstage/catalog/templates/platform-service/content/.gitea/workflows/build.yaml"
workflow_text = workflow_path.read_text(encoding="utf-8")
build_workflow_text = build_workflow_path.read_text(encoding="utf-8")
workflow = yaml.safe_load(workflow_text)
build_workflow = yaml.safe_load(build_workflow_text)

assert workflow["jobs"]["review"]["runs-on"] == ["self-hosted", "in-cluster", "review-env"]
assert build_workflow["jobs"]["images"]["runs-on"] == ["self-hosted", "in-cluster"]
assert "ubuntu-latest" not in workflow_text
assert "ubuntu-latest" not in build_workflow_text
assert workflow["jobs"]["review"]["env"]["REVIEW_NAMESPACE"] == "review"
assert "kubectl create namespace" not in workflow_text
assert "delete:" in workflow_text
assert "REVIEW_REF_TYPE" in workflow_text
assert "REGISTRY_HOST must be provided" in workflow_text
assert "docker login" in workflow_text
assert "docker push" in workflow_text
assert "imagePullSecrets" in workflow_text
assert "gitea-registry-creds" in workflow_text
assert "team: ${APP_TEAM}" in workflow_text
assert "platform.local/review-environment" in workflow_text
assert "tier: frontend" in workflow_text
assert "tier: backend" in workflow_text
assert workflow_text.count("kind: CiliumNetworkPolicy") == 2
assert "kind: HTTPRoute" in workflow_text
assert "kind: ReferenceGrant" in workflow_text
assert "Remove deleted branch review environment" in workflow_text
assert "Skipping review environment cleanup for deleted" in workflow_text
assert "kubectl -n \"${REVIEW_NAMESPACE}\" delete deployment,service" in workflow_text
assert "kubectl -n \"${REVIEW_NAMESPACE}\" delete ciliumnetworkpolicy" in workflow_text
assert "kubectl -n \"${REVIEW_NAMESPACE}\" delete referencegrant" in workflow_text
assert "kubectl -n gateway-routes delete httproute" in workflow_text
assert "${APP_NAME}-${slug}.review.127.0.0.1.sslip.io" in workflow_text

print("validated generated review workflow substrate usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated generated review workflow substrate usage"* ]]
}
