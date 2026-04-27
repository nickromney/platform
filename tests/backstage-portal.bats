#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "Backstage is the deployed developer portal behind the portal route" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
manifest = repo_root / "terraform/kubernetes/apps/idp/all.yaml"
docs = list(yaml.safe_load_all(manifest.read_text(encoding="utf-8")))

deployments = {
    doc["metadata"]["name"]: doc
    for doc in docs
    if doc and doc.get("kind") == "Deployment"
}
services = {
    doc["metadata"]["name"]: doc
    for doc in docs
    if doc and doc.get("kind") == "Service"
}
service_accounts = {
    doc["metadata"]["name"]: doc
    for doc in docs
    if doc and doc.get("kind") == "ServiceAccount"
}
cluster_roles = {
    doc["metadata"]["name"]: doc
    for doc in docs
    if doc and doc.get("kind") == "ClusterRole"
}
cluster_role_bindings = {
    doc["metadata"]["name"]: doc
    for doc in docs
    if doc and doc.get("kind") == "ClusterRoleBinding"
}

assert "backstage" in deployments, "idp app must deploy Backstage"
assert "backstage" in services, "idp app must expose a Backstage service"
assert "backstage" in service_accounts, "Backstage needs a dedicated service account for Kubernetes catalog lookups"
assert "backstage-kubernetes-reader" in cluster_roles
assert "backstage-kubernetes-reader" in cluster_role_bindings

container = deployments["backstage"]["spec"]["template"]["spec"]["containers"][0]
pod_spec = deployments["backstage"]["spec"]["template"]["spec"]
pod_security = deployments["backstage"]["spec"]["template"]["spec"]["securityContext"]
assert container["image"] == "localhost:30090/platform/backstage:latest"
assert container["ports"][0]["containerPort"] == 7007
assert pod_spec["serviceAccountName"] == "backstage"
assert pod_spec["automountServiceAccountToken"] is True
assert pod_security["runAsNonRoot"] is True
assert pod_security["runAsUser"] == 1000
assert pod_security["runAsGroup"] == 1000
assert pod_security["fsGroup"] == 1000
assert container["securityContext"]["allowPrivilegeEscalation"] is False
assert container["securityContext"]["readOnlyRootFilesystem"] is True
assert container["securityContext"]["capabilities"]["drop"] == ["ALL"]
assert container["resources"]["requests"]["memory"] in {"512Mi", "768Mi"}
assert container["resources"]["limits"]["memory"] in {"1Gi", "1536Mi", "2Gi"}
assert any(mount["mountPath"] == "/tmp" for mount in container["volumeMounts"])

service_port = services["backstage"]["spec"]["ports"][0]
assert service_port["port"] == 7007
assert service_port["targetPort"] == "http"
assert service_port["appProtocol"] == "http"

rules = cluster_roles["backstage-kubernetes-reader"]["rules"]
assert any("pods" in rule["resources"] and "services" in rule["resources"] for rule in rules)
assert any("deployments" in rule["resources"] and "replicasets" in rule["resources"] for rule in rules)

print("validated Backstage replaces the deployed developer portal")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated Backstage replaces the deployed developer portal"* ]]
}

@test "portal SSO proxy and catalog point at Backstage" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import json
import os
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])
locals_tf = (repo_root / "terraform/kubernetes/locals.tf").read_text(encoding="utf-8")
catalog = json.loads((repo_root / "catalog/platform-apps.json").read_text(encoding="utf-8"))

assert 'upstream         = "http://backstage.idp.svc.cluster.local:7007"' in locals_tf
assert 'name             = "oauth2-proxy-backstage"' in locals_tf
assert 'public_url       = local.idp_portal_public_url' in locals_tf

apps = {app["name"]: app for app in catalog["applications"]}
assert "backstage" in apps
assert any(env["route"] == "https://portal.127.0.0.1.sslip.io" for env in apps["backstage"]["environments"])

print("validated portal SSO and catalog point at Backstage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated portal SSO and catalog point at Backstage"* ]]
}

@test "Backstage is governed by a local resource gate instead of being unconditional" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])
variables_tf = (repo_root / "terraform/kubernetes/variables.tf").read_text(encoding="utf-8")
locals_tf = (repo_root / "terraform/kubernetes/locals.tf").read_text(encoding="utf-8")
gitops_tf = (repo_root / "terraform/kubernetes/gitops.tf").read_text(encoding="utf-8")
sync_script = (repo_root / "terraform/kubernetes/scripts/sync-gitea-policies.sh").read_text(encoding="utf-8")
kind_makefile = (repo_root / "kubernetes/kind/Makefile").read_text(encoding="utf-8")
sso_run = (repo_root / "tests/kubernetes/sso/run.sh").read_text(encoding="utf-8")
sso_spec = (repo_root / "tests/kubernetes/sso/tests/sso-smoke.spec.ts").read_text(encoding="utf-8")
build_script = (repo_root / "kubernetes/kind/scripts/build-local-platform-images.sh").read_text(encoding="utf-8")

assert 'variable "enable_backstage"' in variables_tf
assert "enable_backstage_effective" in locals_tf
assert 'local.enable_backstage_effective ? ["oauth2-proxy-backstage"] : []' in locals_tf
assert "ENABLE_BACKSTAGE" in gitops_tf
assert "remove_backstage_idp_resources" in sync_script
assert "httproute-portal.yaml" in sync_script
assert "oauth2-proxy-backstage" in sync_script
assert "KIND_ENABLE_BACKSTAGE ?= auto" in kind_makefile
assert "KIND_BACKSTAGE_MIN_DOCKER_MEMORY_BYTES ?= 10737418240" in kind_makefile
assert "ENABLE_BACKSTAGE" in build_script
assert "SKIP backstage (ENABLE_BACKSTAGE=false)" in build_script
assert "SSO_E2E_ENABLE_BACKSTAGE" in sso_run
assert "INCLUDE_BACKSTAGE" in sso_spec

print("validated Backstage local resource gate")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated Backstage local resource gate"* ]]
}

@test "Backstage app is configured for lightweight local-cluster production runtime" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
app_dir = repo_root / "apps/backstage"
production = yaml.safe_load((app_dir / "app-config.production.yaml").read_text(encoding="utf-8"))
local_config = yaml.safe_load((app_dir / "app-config.yaml").read_text(encoding="utf-8"))
backend = (app_dir / "packages/backend/src/index.ts").read_text(encoding="utf-8")
backend_package = (app_dir / "packages/backend/package.json").read_text(encoding="utf-8")
frontend = (app_dir / "packages/app/src/App.tsx").read_text(encoding="utf-8")
org = list(yaml.safe_load_all((app_dir / "catalog/org.yaml").read_text(encoding="utf-8")))
dockerfile = (app_dir / "Dockerfile").read_text(encoding="utf-8")
backend_package = (app_dir / "packages/backend/package.json").read_text(encoding="utf-8")

assert (app_dir / ".yarn/releases/yarn-4.4.1.cjs").is_file()
assert not (app_dir / "packages/backend/Dockerfile").exists()
assert '"build-image": "docker build ../.. -f ../../Dockerfile --tag backstage"' in backend_package
assert production["app"]["baseUrl"] == "${BACKSTAGE_BASE_URL}"
assert production["backend"]["baseUrl"] == "${BACKSTAGE_BASE_URL}"
assert production["backend"]["database"]["client"] == "better-sqlite3"
assert production["backend"]["database"]["connection"] == {"directory": "/tmp/backstage"}
assert local_config["backend"]["database"]["connection"] == {"directory": "/tmp/backstage"}
assert production["auth"]["environment"] == "production"
assert "guest" not in production["auth"]["providers"]
assert "guest" not in local_config["auth"]["providers"]
assert production["auth"]["providers"]["oauth2Proxy"]["signIn"]["resolvers"] == [
    {"resolver": "emailMatchingUserEntityProfileEmail"}
]
assert local_config["auth"]["providers"]["oauth2Proxy"]["signIn"]["resolvers"] == [
    {"resolver": "emailMatchingUserEntityProfileEmail"}
]
extensions = local_config["app"]["extensions"]
assert {"nav-item:kubernetes": False} in extensions
assert {"page:kubernetes": False} in extensions
assert production["kubernetes"]["clusterLocatorMethods"][0]["clusters"][0]["authProvider"] == "serviceAccount"
assert production["kubernetes"]["clusterLocatorMethods"][0]["clusters"][0]["url"] == "https://kubernetes.default.svc"
assert "POSTGRES_" not in (app_dir / "app-config.production.yaml").read_text(encoding="utf-8")
assert production["techdocs"]["generator"]["runIn"] == "local"

targets = {loc["target"] for loc in production["catalog"]["locations"]}
assert "./catalog/entities.yaml" in targets
assert "./catalog/templates/platform-service/template.yaml" in targets

assert "@backstage/plugin-scaffolder-backend" in backend
assert "@backstage/plugin-catalog-backend" in backend
assert "@backstage/plugin-auth-backend-module-oauth2-proxy-provider" in backend
assert "@backstage/plugin-auth-backend-module-oauth2-proxy-provider" in backend_package
assert "@backstage/plugin-auth-backend-module-guest-provider" not in backend
assert "@backstage/plugin-auth-backend-module-guest-provider" not in backend_package
assert "@backstage/plugin-search-backend-module-pg" not in backend
assert "@backstage/plugin-search-backend-module-pg" not in backend_package
assert '"pg":' not in backend_package
assert "ProxiedSignInPage" in frontend
assert 'provider="oauth2Proxy"' in frontend

users = {
    doc["metadata"]["name"]: doc["spec"]["profile"]["email"]
    for doc in org
    if doc and doc.get("kind") == "User"
}
assert users["demo-admin"] == "demo@admin.test"
assert users["demo-dev"] == "demo@dev.test"
assert users["demo-uat"] == "demo@uat.test"

assert "FROM node:22-bookworm-slim AS packages" in dockerfile
assert "FROM node:22-bookworm-slim AS deps" in dockerfile
assert "FROM node:22-bookworm-slim AS production-deps" in dockerfile
assert "FROM dhi.io/node:22-debian13 AS runtime" in dockerfile
assert "COPY package.json yarn.lock .yarnrc.yml backstage.json tsconfig.json ./" in dockerfile
assert "find packages -mindepth 2 -maxdepth 2 ! -name package.json" in dockerfile
assert "yarn install --immutable" in dockerfile
assert "yarn tsc" in dockerfile
assert "yarn build:backend" in dockerfile
assert "COPY --from=production-deps /usr/lib/aarch64-linux-gnu/libsqlite3.so.0*" in dockerfile
assert "USER 1000:1000" in dockerfile
assert "EXPOSE 7007" in dockerfile

runtime_stage = dockerfile.split("FROM dhi.io/node:22-debian13 AS runtime", 1)[1]
assert "build-essential" not in runtime_stage
assert "libsqlite3-dev" not in runtime_stage
assert "g++" not in runtime_stage
assert "RUN " not in runtime_stage
assert "COPY --chown=1000:1000 --from=production-deps /app ./" in runtime_stage

print("validated lightweight Backstage runtime configuration")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated lightweight Backstage runtime configuration"* ]]
}

@test "Backstage catalog carries source, Kubernetes, and API relationship metadata" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
docs = list(yaml.safe_load_all((repo_root / "apps/backstage/catalog/entities.yaml").read_text(encoding="utf-8")))
entities = {
    (doc["kind"], doc["metadata"]["name"]): doc
    for doc in docs
    if doc
}

for name, (selector, source_path) in {
    "backstage": ("app=backstage", "apps/backstage/"),
    "idp-core": ("app=idp-core", "apps/idp-core/"),
    "hello-platform": ("app=hello-platform", "apps/hello-platform/"),
    "subnetcalc": ("app=subnetcalc", "apps/subnetcalc/"),
    "sentiment": ("app=sentiment", "apps/sentiment/"),
}.items():
    component = entities[("Component", name)]
    annotations = component["metadata"]["annotations"]
    assert annotations["backstage.io/kubernetes-label-selector"] == selector
    assert annotations["backstage.io/source-location"].endswith(source_path), annotations

assert entities[("Component", "backstage")]["spec"]["consumesApis"] == ["idp-api"]
assert entities[("Component", "idp-core")]["spec"]["providesApis"] == ["idp-api"]
for name in ["subnetcalc", "sentiment"]:
    component = entities[("Component", name)]
    api_name = f"{name}-api"
    assert component["spec"]["providesApis"] == [api_name]
    assert component["spec"]["consumesApis"] == [api_name]
    assert entities[("API", api_name)]["spec"]["type"] == "openapi"

print("validated Backstage catalog annotations and API relations")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated Backstage catalog annotations and API relations"* ]]
}

@test "local platform image flow builds Backstage instead of the old React portal" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])
build_script = (repo_root / "kubernetes/kind/scripts/build-local-platform-images.sh").read_text(encoding="utf-8")
locals_tf = (repo_root / "terraform/kubernetes/locals.tf").read_text(encoding="utf-8")
variables_tf = (repo_root / "terraform/kubernetes/variables.tf").read_text(encoding="utf-8")
gitops_tf = (repo_root / "terraform/kubernetes/gitops.tf").read_text(encoding="utf-8")
policies_script = (repo_root / "terraform/kubernetes/scripts/sync-gitea-policies.sh").read_text(encoding="utf-8")

assert '"backstage"' in build_script
assert "apps/backstage/Dockerfile" in build_script
assert "backstage_source_tag=" in build_script
assert 'lookup(var.external_platform_image_refs, "backstage", "")' in locals_tf
assert "backstage" in variables_tf
assert 'EXTERNAL_PLATFORM_IMAGE_BACKSTAGE' in gitops_tf
assert 'replace_image_ref "${idp_manifest}" "backstage" "${EXTERNAL_PLATFORM_IMAGE_BACKSTAGE}"' in policies_script

for target, registry_host in {
    "kind": "host.docker.internal:5002",
    "lima": "host.lima.internal:5002",
    "slicer": "192.168.64.1:5002",
}.items():
    tfvars = (repo_root / "kubernetes" / target / "targets" / f"{target}.tfvars").read_text(encoding="utf-8")
    assert f'backstage   = "{registry_host}/platform/backstage:latest"' in tfvars

print("validated Backstage local image flow")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated Backstage local image flow"* ]]
}

@test "Backstage template is a real self-service app factory" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
template_dir = repo_root / "apps/backstage/catalog/templates/platform-service"
template = yaml.safe_load((template_dir / "template.yaml").read_text(encoding="utf-8"))
content_dir = template_dir / "content"

assert template["metadata"]["title"] == "Create a Platform App"
assert "frontend/backend" in template["metadata"]["description"]

step_actions = [step["action"] for step in template["spec"]["steps"]]
assert step_actions == ["fetch:template", "gitea:repo:publish", "debug:log"], step_actions

parameters = template["spec"]["parameters"]
all_properties = {
    name
    for group in parameters
    for name in group.get("properties", {})
}
for required in {"name", "owner", "description", "environments", "frontendPort", "backendPort"}:
    assert required in all_properties, required

expected_files = {
    "README.md",
    "catalog-info.yaml",
    ".gitea/workflows/build.yaml",
    "apps/frontend/Dockerfile",
    "apps/frontend/index.html",
    "apps/frontend/nginx.conf",
    "apps/backend/Dockerfile",
    "apps/backend/package.json",
    "apps/backend/server.js",
    "kubernetes/base/frontend.yaml",
    "kubernetes/base/backend.yaml",
    "kubernetes/base/kustomization.yaml",
    "kubernetes/policies/cilium-frontend-backend.yaml",
    "kubernetes/policies/kyverno-container-baseline.yaml",
    "observability/grafana-dashboard.json",
}
missing = [str(content_dir / path) for path in sorted(expected_files) if not (content_dir / path).is_file()]
assert not missing, missing

frontend = (content_dir / "apps/frontend/Dockerfile").read_text(encoding="utf-8")
backend = (content_dir / "apps/backend/Dockerfile").read_text(encoding="utf-8")
cilium_docs = list(yaml.safe_load_all((content_dir / "kubernetes/policies/cilium-frontend-backend.yaml").read_text(encoding="utf-8")))
kyverno = yaml.safe_load((content_dir / "kubernetes/policies/kyverno-container-baseline.yaml").read_text(encoding="utf-8"))
dashboard = (content_dir / "observability/grafana-dashboard.json").read_text(encoding="utf-8")
catalog_docs = list(yaml.safe_load_all((content_dir / "catalog-info.yaml").read_text(encoding="utf-8")))
catalog = catalog_docs[0]
catalog_api = catalog_docs[1]

assert "FROM dhi.io/nginx:1.29.5-debian13" in frontend
assert "USER 65532:65532" in frontend
assert "FROM dhi.io/node:22-debian13" in backend
assert "USER 1000:1000" in backend
assert [doc["kind"] for doc in cilium_docs] == ["CiliumNetworkPolicy", "CiliumNetworkPolicy"]
assert {doc["metadata"]["name"] for doc in cilium_docs} == {
    "${{ values.name }}-backend-ingress",
    "${{ values.name }}-frontend-egress",
}
assert kyverno["kind"] == "Policy"
assert "require-drop-all-capabilities" in str(kyverno)
assert "${{ values.name }}-golden-signals" in dashboard
assert any(link["title"] == "Grafana Golden Signals" for link in catalog["metadata"]["links"])
assert catalog["metadata"]["annotations"]["backstage.io/source-location"] == "url:https://gitea.admin.127.0.0.1.sslip.io/platform/${{ values.name }}/"
assert catalog["metadata"]["annotations"]["backstage.io/kubernetes-label-selector"] == "app=${{ values.name }}"
assert catalog["spec"]["providesApis"] == ["${{ values.name }}-api"]
assert catalog["spec"]["consumesApis"] == ["${{ values.name }}-api"]
assert catalog_api["kind"] == "API"
assert catalog_api["metadata"]["name"] == "${{ values.name }}-api"

print("validated Backstage self-service app factory template")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated Backstage self-service app factory template"* ]]
}

@test "Backstage publishes app templates to Gitea with in-cluster credentials" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
backend = (repo_root / "apps/backstage/packages/backend/src/index.ts").read_text(encoding="utf-8")
module = (repo_root / "apps/backstage/packages/backend/src/modules/giteaRepoPublish.ts").read_text(encoding="utf-8")
manifest_docs = list(yaml.safe_load_all((repo_root / "terraform/kubernetes/apps/idp/all.yaml").read_text(encoding="utf-8")))
terraform = "\n".join(
    (repo_root / path).read_text(encoding="utf-8")
    for path in ["terraform/kubernetes/gitea.tf", "terraform/kubernetes/workload-apps.tf"]
)

assert "giteaRepoPublishModule" in backend
assert "createBackendModule" in module
assert "scaffolderActionsExtensionPoint" in module
assert "createTemplateAction" in module
assert "id: 'gitea:repo:publish'" in module
assert "GITEA_BASE_URL" in module
assert "GITEA_USERNAME" in module
assert "GITEA_PASSWORD" in module
assert "/api/v1/orgs/" in module
assert "/api/v1/user/repos" in module
assert "/contents/" in module

deployments = {
    doc["metadata"]["name"]: doc
    for doc in manifest_docs
    if doc and doc.get("kind") == "Deployment"
}
env = deployments["backstage"]["spec"]["template"]["spec"]["containers"][0]["env"]
env_by_name = {item["name"]: item for item in env}
assert env_by_name["GITEA_BASE_URL"]["value"] == "http://gitea-http.gitea.svc.cluster.local:3000"
assert env_by_name["GITEA_OWNER"]["value"] == "platform"
for name, key in {"GITEA_USERNAME": "username", "GITEA_PASSWORD": "password"}.items():
    secret_ref = env_by_name[name]["valueFrom"]["secretKeyRef"]
    assert secret_ref["name"] == "backstage-gitea-credentials"
    assert secret_ref["key"] == key

assert 'name      = "backstage-gitea-credentials"' in terraform
assert "kubernetes_secret_v1.backstage_gitea_credentials" in terraform
assert "kubectl_manifest.namespace_idp" in terraform

print("validated Backstage Gitea publish action wiring")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated Backstage Gitea publish action wiring"* ]]
}
