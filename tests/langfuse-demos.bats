#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "Langfuse demo apps expose trace chat, tool agent, and eval runner surfaces" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
manifest_path = repo_root / "terraform/kubernetes/apps/langfuse-demos/all.yaml"
assert manifest_path.exists(), "langfuse demo manifest missing"
docs = [doc for doc in yaml.safe_load_all(manifest_path.read_text(encoding="utf-8")) if doc]

deployments = {
    doc["metadata"]["name"]: doc
    for doc in docs
    if doc.get("kind") == "Deployment"
}
services = {
    doc["metadata"]["name"]: doc
    for doc in docs
    if doc.get("kind") == "Service"
}
expected = {
    "langfuse-trace-chat": "trace-chat",
    "langfuse-tool-agent": "tool-agent",
    "langfuse-eval-runner": "eval-runner",
}
assert expected.keys() <= deployments.keys(), deployments.keys()
assert expected.keys() <= services.keys(), services.keys()

for name, role in expected.items():
    deployment = deployments[name]
    template = deployment["spec"]["template"]
    annotations = template["metadata"]["annotations"]
    labels = template["metadata"]["labels"]
    container = template["spec"]["containers"][0]
    env = {item["name"]: item["value"] for item in container["env"] if "value" in item}
    assert labels["app.kubernetes.io/part-of"] == "langfuse-demos", name
    assert labels["app.kubernetes.io/name"] == name, name
    assert annotations["prometheus.io/scrape"] == "true", name
    assert annotations["prometheus.io/path"] == "/metrics", name
    assert annotations["prometheus.io/port"] == "8080", name
    assert env["DEMO_ROLE"] == role, name
    assert env["LANGFUSE_HOST"] == "http://langfuse-web.langfuse.svc.cluster.local:3000", name
    assert env["OPENAI_BASE_URL"] == "http://agentgateway-ai-gateway.agentgateway-system.svc.cluster.local/v1", name
    assert env["OPENAI_MODEL"] == "auto", name
    assert int(env["LLM_TIMEOUT_SECONDS"]) >= 10, name
    assert int(env["LANGFUSE_TIMEOUT_SECONDS"]) >= 10, name
    assert "langfuse-demos" in container["image"], name
    assert container["imagePullPolicy"] == "Always", name

network_policy = next(
    doc
    for doc in docs
    if doc.get("kind") == "NetworkPolicy" and doc["metadata"]["name"] == "langfuse-demos-runtime"
)
policy_text = yaml.safe_dump(network_policy)
for text in (
    "namespace: dev",
    "kubernetes.io/metadata.name: langfuse",
    "kubernetes.io/metadata.name: agentgateway-system",
    "kubernetes.io/metadata.name: observability",
    "app.kubernetes.io/name: prometheus",
    "port: 3000",
    "port: 80",
    "port: 8080",
):
    assert text in policy_text, text

print("validated Langfuse demo app manifests")
PY

  if [ "${status}" -ne 0 ]; then
    printf '%s\n' "${output}"
  fi
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated Langfuse demo app manifests"* ]]
}

@test "Langfuse demos have explicit Cilium runtime egress to Langfuse and agentgateway" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
rendered = yaml.safe_load_all(
    os.popen(f"kubectl kustomize {repo_root / 'terraform/kubernetes/cluster-policies/cilium/dev'}").read()
)
policies = {
    doc["metadata"]["name"]: doc
    for doc in rendered
    if doc and doc.get("kind") == "CiliumNetworkPolicy"
}
policy = policies.get("langfuse-demos-runtime")
assert policy is not None, "langfuse-demos-runtime CiliumNetworkPolicy missing"
spec = policy["spec"]
selector = spec["endpointSelector"]["matchLabels"]
assert selector["k8s:app.kubernetes.io/part-of"] == "langfuse-demos"
policy_text = yaml.safe_dump(policy)
for expected in (
    "k8s:app.kubernetes.io/component: authentication-proxy",
    "k8s:io.cilium.k8s.namespace.labels.platform.publiccloudexperiments.net/namespace-role: shared",
    "k8s:io.kubernetes.pod.namespace: kube-system",
    "k8s:k8s-app: kube-dns",
    "k8s:io.kubernetes.pod.namespace: langfuse",
    "k8s:app.kubernetes.io/component: web",
    "k8s:io.kubernetes.pod.namespace: agentgateway-system",
    "k8s:app.kubernetes.io/name: agentgateway-ai-gateway",
    "k8s:io.kubernetes.pod.namespace: observability",
    "k8s:app.kubernetes.io/name: prometheus",
):
    assert expected in policy_text, expected
ports = {
    port["port"]
    for rule in spec.get("egress", [])
    for port_block in rule.get("toPorts", [])
    for port in port_block.get("ports", [])
}
assert {"53", "3000", "80"} <= ports, ports
protocols_for_53 = {
    port.get("protocol")
    for rule in spec.get("egress", [])
    for port_block in rule.get("toPorts", [])
    for port in port_block.get("ports", [])
    if port.get("port") == "53"
}
assert {"TCP", "UDP"} <= protocols_for_53, protocols_for_53

print("validated Langfuse demo Cilium runtime policy")
PY

  if [ "${status}" -ne 0 ]; then
    printf '%s\n' "${output}"
  fi
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated Langfuse demo Cilium runtime policy"* ]]
}

@test "Observability policy permits Prometheus to scrape Langfuse demo metrics" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
policy = yaml.safe_load(
    (repo_root / "terraform/kubernetes/cluster-policies/cilium/shared/observability-hardened.yaml").read_text(encoding="utf-8")
)
allowed = False
for rule in policy["spec"].get("egress", []):
    ports = {
        port.get("port")
        for port_block in rule.get("toPorts", [])
        for port in port_block.get("ports", [])
    }
    for endpoint in rule.get("toEndpoints", []):
        labels = endpoint.get("matchLabels", {})
        if (
            labels.get("k8s:io.kubernetes.pod.namespace") == "dev"
            and labels.get("k8s:app.kubernetes.io/part-of") == "langfuse-demos"
            and "8080" in ports
        ):
            allowed = True
assert allowed, "observability-hardened must allow Prometheus egress to dev/langfuse-demos on 8080"

print("validated observability egress for Langfuse demo scraping")
PY

  if [ "${status}" -ne 0 ]; then
    printf '%s\n' "${output}"
  fi
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated observability egress for Langfuse demo scraping"* ]]
}

@test "Agentgateway policy permits Langfuse and demos to call the local LLM route" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
policy = yaml.safe_load(
    (repo_root / "terraform/kubernetes/cluster-policies/cilium/shared/agentgateway-ai-gateway-hardened.yaml").read_text(encoding="utf-8")
)
allowed_demos = False
allowed_langfuse = False
for rule in policy["spec"].get("ingress", []):
    ports = {
        port.get("port")
        for port_block in rule.get("toPorts", [])
        for port in port_block.get("ports", [])
    }
    for endpoint in rule.get("fromEndpoints", []):
        labels = endpoint.get("matchLabels", {})
        if (
            labels.get("k8s:io.kubernetes.pod.namespace") == "dev"
            and labels.get("k8s:app.kubernetes.io/part-of") == "langfuse-demos"
            and {"80", "8080"} <= ports
        ):
            allowed_demos = True
        if (
            labels.get("k8s:io.kubernetes.pod.namespace") == "langfuse"
            and labels.get("k8s:app.kubernetes.io/name") == "langfuse"
            and {"80", "8080"} <= ports
        ):
            allowed_langfuse = True
assert allowed_demos, "agentgateway ingress must allow dev/langfuse-demos on the OpenAI-compatible ports"
assert allowed_langfuse, "agentgateway ingress must allow Langfuse web/bootstrap on the OpenAI-compatible ports"

print("validated agentgateway ingress for Langfuse and demo LLM calls")
PY

  if [ "${status}" -ne 0 ]; then
    printf '%s\n' "${output}"
  fi
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated agentgateway ingress for Langfuse and demo LLM calls"* ]]
}

@test "Langfuse runtime ingress permits demo pods to ingest traces" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
docs = [
    doc
    for doc in yaml.safe_load_all((repo_root / "terraform/kubernetes/apps/langfuse/all.yaml").read_text(encoding="utf-8"))
    if doc
]
policy = next(
    doc
    for doc in docs
    if doc.get("kind") == "NetworkPolicy" and doc["metadata"]["name"] == "langfuse-runtime"
)
allowed = False
for rule in policy["spec"].get("ingress", []):
    ports = {item.get("port") for item in rule.get("ports", [])}
    for source in rule.get("from", []):
        namespace = source.get("namespaceSelector", {}).get("matchLabels", {})
        pod = source.get("podSelector", {}).get("matchLabels", {})
        if (
            namespace.get("kubernetes.io/metadata.name") == "dev"
            and pod.get("app.kubernetes.io/part-of") == "langfuse-demos"
            and 3000 in ports
        ):
            allowed = True
assert allowed, "Langfuse NetworkPolicy must allow dev/langfuse-demos pods to ingest events on port 3000"

print("validated Langfuse runtime ingress for demo ingestion")
PY

  if [ "${status}" -ne 0 ]; then
    printf '%s\n' "${output}"
  fi
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated Langfuse runtime ingress for demo ingestion"* ]]
}

@test "Langfuse bootstrap seeds the default project, LLM connection, and starter trace" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
docs = [
    doc
    for doc in yaml.safe_load_all((repo_root / "terraform/kubernetes/apps/langfuse/all.yaml").read_text(encoding="utf-8"))
    if doc
]
config = next(doc for doc in docs if doc.get("kind") == "ConfigMap" and doc["metadata"]["name"] == "langfuse-env")
data = config["data"]
for key, value in {
    "LANGFUSE_INIT_ORG_ID": "local-platform",
    "LANGFUSE_INIT_PROJECT_ID": "local-platform-project",
    "LANGFUSE_INIT_PROJECT_PUBLIC_KEY": "pk-lf-local-platform",
    "LANGFUSE_INIT_PROJECT_SECRET_KEY": "sk-lf-local-platform",
    "LANGFUSE_DEFAULT_ORG_ID": "local-platform",
    "LANGFUSE_DEFAULT_ORG_ROLE": "OWNER",
    "LANGFUSE_DEFAULT_PROJECT_ID": "local-platform-project",
    "LANGFUSE_DEFAULT_PROJECT_ROLE": "OWNER",
    "LANGFUSE_LLM_CONNECTION_WHITELISTED_HOST": "agentgateway-ai-gateway.agentgateway-system.svc.cluster.local",
}.items():
    assert data[key] == value, (key, data.get(key))

job = next(doc for doc in docs if doc.get("kind") == "Job" and doc["metadata"]["name"] == "langfuse-bootstrap")
assert job["metadata"]["annotations"]["argocd.argoproj.io/hook"] == "PostSync", job["metadata"]
for name in ("langfuse-web", "langfuse-worker"):
    deployment = next(doc for doc in docs if doc.get("kind") == "Deployment" and doc["metadata"]["name"] == name)
    annotations = deployment["spec"]["template"]["metadata"]["annotations"]
    assert annotations["platform.publiccloudexperiments.net/config-generation"] == "2026-05-22-langfuse-bootstrap", name
pod_spec = job["spec"]["template"]["spec"]
assert pod_spec["automountServiceAccountToken"] is False
container = pod_spec["containers"][0]
assert container["image"] == "docker.io/curlimages/curl:8.19.0", container["image"]
env = {item["name"]: item.get("value") for item in container["env"] if "value" in item}
assert env["LOCAL_LLM_PROVIDER"] == "local-agentgateway"
assert env["LOCAL_LLM_BASE_URL"] == "http://agentgateway-ai-gateway.agentgateway-system.svc.cluster.local/v1"
assert env["LOCAL_LLM_FALLBACK_MODEL"] == "Qwen3.5-9B-MLX-4bit"
command = "\n".join(container["command"])
for expected in (
    "/api/public/llm-connections",
    "/api/public/ingestion",
    "/api/public/traces/platform-langfuse-bootstrap",
    "platform-langfuse-bootstrap",
):
    assert expected in command, expected

network_policy = next(doc for doc in docs if doc.get("kind") == "NetworkPolicy" and doc["metadata"]["name"] == "langfuse-runtime")
egress_to_agentgateway = False
for rule in network_policy["spec"].get("egress", []):
    ports = {item.get("port") for item in rule.get("ports", [])}
    for peer in rule.get("to", []):
        namespace = peer.get("namespaceSelector", {}).get("matchLabels", {})
        pod = peer.get("podSelector", {}).get("matchLabels", {})
        if (
            namespace.get("kubernetes.io/metadata.name") == "agentgateway-system"
            and pod.get("app.kubernetes.io/name") == "agentgateway-ai-gateway"
            and 80 in ports
        ):
            egress_to_agentgateway = True
assert egress_to_agentgateway, "Langfuse bootstrap/playground needs egress to agentgateway"

print("validated Langfuse bootstrap defaults and starter trace")
PY

  if [ "${status}" -ne 0 ]; then
    printf '%s\n' "${output}"
  fi
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated Langfuse bootstrap defaults and starter trace"* ]]
}

@test "Langfuse demo app is a lightweight Go-only app with unit tests" {
  run bash -lc "cd '${REPO_ROOT}/apps/langfuse-demos/app' && test -f go.mod && test -f Dockerfile && test -f Makefile && ! find . -maxdepth 3 \\( -name package.json -o -name package-lock.json -o -name yarn.lock -o -name pnpm-lock.yaml -o -name bun.lock -o -name node_modules \\) -print | grep . && make test"

  if [ "${status}" -ne 0 ]; then
    printf '%s\n' "${output}"
  fi
  [ "${status}" -eq 0 ]
}

@test "Langfuse demo app prereqs call out the host oMLX server step" {
  run make -C "${REPO_ROOT}/apps/langfuse-demos/app" prereqs LOCAL_OPENAI_BASE_URL=http://127.0.0.1:9/v1

  if [ "${status}" -ne 0 ]; then
    printf '%s\n' "${output}"
  fi
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"http://127.0.0.1:9/v1"* ]]
  [[ "${output}" == *"host.docker.internal:8000"* ]]
  [[ "${output}" == *"start the oMLX OpenAI-compatible server"* ]]
}

@test "Langfuse demo app prereqs distinguish auth-protected oMLX from a stopped server" {
  tmpdir="$(mktemp -d)"
  port_file="${tmpdir}/port"
  python3 - "${port_file}" <<'PY' &
from __future__ import annotations

import http.server
import pathlib
import sys


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        self.send_response(401)
        self.end_headers()

    def log_message(self, *_args: object) -> None:
        return


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
pathlib.Path(sys.argv[1]).write_text(str(server.server_port), encoding="utf-8")
server.serve_forever()
PY
  server_pid="$!"
  for _ in {1..50}; do
    [ -s "${port_file}" ] && break
    sleep 0.1
  done
  port="$(cat "${port_file}")"

  run make -C "${REPO_ROOT}/apps/langfuse-demos/app" prereqs LOCAL_OPENAI_BASE_URL="http://127.0.0.1:${port}/v1"
  kill "${server_pid}" 2>/dev/null || true
  rm -rf "${tmpdir}"

  if [ "${status}" -ne 0 ]; then
    printf '%s\n' "${output}"
  fi
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"HTTP 401"* ]]
  [[ "${output}" != *"is unreachable"* ]]
}

@test "Langfuse demos are enabled by stage 920 and visible from GitOps, SSO, Grafana, and image build surfaces" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import json
import os
import re
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])
checks = {
    "stage": repo_root / "kubernetes/kind/stages/920-langfuse.tfvars",
    "variables": repo_root / "terraform/kubernetes/variables.tf",
    "locals": repo_root / "terraform/kubernetes/locals.tf",
    "workload_apps": repo_root / "terraform/kubernetes/workload-apps.tf",
    "app_of_apps": repo_root / "terraform/kubernetes/apps/argocd-apps/82-langfuse-demos.application.yaml",
    "routes_kustomization": repo_root / "terraform/kubernetes/apps/platform-gateway-routes-sso/kustomization.yaml",
    "referencegrant": repo_root / "terraform/kubernetes/apps/platform-gateway-routes-sso/referencegrant-sso.yaml",
    "demo_referencegrant": repo_root / "terraform/kubernetes/apps/platform-gateway-routes-sso/referencegrant-sso-langfuse-demos.yaml",
    "prometheus": repo_root / "terraform/kubernetes/apps/argocd-apps/90-prometheus.application.yaml",
    "grafana": repo_root / "terraform/kubernetes/apps/argocd-apps/95-grafana.application.yaml",
    "image_catalog": repo_root / "kubernetes/workflow/image-catalog.json",
    "image_builder": repo_root / "kubernetes/kind/scripts/build-local-platform-images.sh",
    "sync_script": repo_root / "terraform/kubernetes/scripts/sync-gitea-policies.sh",
}
texts = {name: path.read_text(encoding="utf-8") for name, path in checks.items()}

assert re.search(r"(?m)^enable_langfuse_demos\s*=\s*true$", texts["stage"])
assert "enable_langfuse_demos" in texts["variables"]
assert "langfuse_trace_chat_public_host" in texts["locals"]
assert "argocd_app_langfuse_demos" in texts["workload_apps"]
assert "path: apps/langfuse-demos" in texts["app_of_apps"]
for name in ("langfuse-trace-chat", "langfuse-tool-agent", "langfuse-eval-runner"):
    assert f"httproute-{name}.yaml" in texts["routes_kustomization"], name
    assert f"oauth2-proxy-{name}" in texts["demo_referencegrant"], name
    assert name in texts["grafana"], name
assert "job_name: langfuse-demos" in texts["prometheus"]
assert "langfuse-demos" in texts["prometheus"]
assert "__meta_kubernetes_pod_annotation_prometheus_io_scrape" in texts["prometheus"]
assert "referencegrant-sso-langfuse-demos.yaml" in texts["routes_kustomization"]
assert "Langfuse Agent Flow" in texts["grafana"]
assert "langfuse_demo_llm_calls_total" in texts["grafana"]
assert 'langfuse_demo_runs_total{job=\\"langfuse-demos\\"}' in texts["grafana"]
assert 'langfuse_demo_langfuse_batches_total{job=\\"langfuse-demos\\"}' in texts["grafana"]
assert '"id": "langfuse-demos"' in texts["image_catalog"]
assert "apps/shared/idpauth" in texts["image_catalog"]
assert "apps/langfuse-demos/app/go.sum" in texts["image_catalog"]
assert "langfuse_demos_source_tag=" in texts["image_builder"]
assert 'image_build_catalog_build_and_push platform langfuse-demos langfuse-demos "${langfuse_demos_source_tag}"' in texts["image_builder"]
assert "EXTERNAL_PLATFORM_IMAGE_LANGFUSE_DEMOS" in texts["sync_script"]

catalog = json.loads(texts["image_catalog"])
ids = {item["id"] for item in catalog["platform_images"]}
assert "langfuse-demos" in ids

print("validated Langfuse demo rollout surfaces")
PY

  if [ "${status}" -ne 0 ]; then
    printf '%s\n' "${output}"
  fi
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated Langfuse demo rollout surfaces"* ]]
}

@test "SSO ReferenceGrants stay under Gateway API target limits while permitting Langfuse demos" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
routes_dir = repo_root / "terraform/kubernetes/apps/platform-gateway-routes-sso"
kustomization = yaml.safe_load((routes_dir / "kustomization.yaml").read_text(encoding="utf-8"))
grant_paths = [
    routes_dir / resource
    for resource in kustomization["resources"]
    if resource.startswith("referencegrant-") and resource.endswith(".yaml")
]

allowed_services: set[str] = set()
for grant_path in grant_paths:
    for doc in yaml.safe_load_all(grant_path.read_text(encoding="utf-8")):
        if not doc or doc.get("kind") != "ReferenceGrant" or doc["metadata"].get("namespace") != "sso":
            continue
        to = doc["spec"].get("to", [])
        assert len(to) <= 16, f"{grant_path.relative_to(repo_root)} has {len(to)} targets"
        allowed_services.update(item["name"] for item in to if item.get("kind") == "Service" and "name" in item)

for service in (
    "oauth2-proxy-langfuse-trace-chat",
    "oauth2-proxy-langfuse-tool-agent",
    "oauth2-proxy-langfuse-eval-runner",
):
    assert service in allowed_services, service

print("validated SSO ReferenceGrant target limits for Langfuse demos")
PY

  if [ "${status}" -ne 0 ]; then
    printf '%s\n' "${output}"
  fi
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated SSO ReferenceGrant target limits for Langfuse demos"* ]]
}
