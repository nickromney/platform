#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
}

@test "platform-service template is a real self-service app factory" {
  run uv run --locked --project "${REPO_ROOT}" python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
content_dir = repo_root / "templates/platform-service/content"

expected_files = {
    "README.md",
    ".gitea/workflows/build.yaml",
    ".gitea/workflows/review-environment.yaml",
    "apps/frontend/Dockerfile",
    "apps/frontend/index.html",
    "apps/frontend/nginx.conf",
    "apps/backend/Dockerfile",
    "apps/backend/package.json",
    "apps/backend/server.js",
    "kubernetes/base/frontend.yaml",
    "kubernetes/base/backend.yaml",
    "kubernetes/base/kustomization.yaml",
    "kubernetes/observability/prometheus-scrape.yaml",
    "kubernetes/policies/cilium-frontend-backend.yaml",
    "kubernetes/policies/kyverno-container-baseline.yaml",
    "observability/grafana-dashboard.json",
}
missing = [str(content_dir / path) for path in sorted(expected_files) if not (content_dir / path).is_file()]
assert not missing, missing

frontend = (content_dir / "apps/frontend/Dockerfile").read_text(encoding="utf-8")
backend = (content_dir / "apps/backend/Dockerfile").read_text(encoding="utf-8")
backend_server = (content_dir / "apps/backend/server.js").read_text(encoding="utf-8")
backend_manifest = yaml.safe_load_all((content_dir / "kubernetes/base/backend.yaml").read_text(encoding="utf-8"))
backend_docs = list(backend_manifest)
prometheus_scrape = yaml.safe_load((content_dir / "kubernetes/observability/prometheus-scrape.yaml").read_text(encoding="utf-8"))
cilium_docs = list(yaml.safe_load_all((content_dir / "kubernetes/policies/cilium-frontend-backend.yaml").read_text(encoding="utf-8")))
kyverno = yaml.safe_load((content_dir / "kubernetes/policies/kyverno-container-baseline.yaml").read_text(encoding="utf-8"))
dashboard = (content_dir / "observability/grafana-dashboard.json").read_text(encoding="utf-8")
review_workflow = (content_dir / ".gitea/workflows/review-environment.yaml").read_text(encoding="utf-8")

assert "FROM dhi.io/nginx:1.29.5-debian13" in frontend
assert "USER 65532:65532" in frontend
assert "FROM dhi.io/node:22.23.4-debian13@sha256:b2191eda91feb8bcc6a8c3a055651216ddfed8239bd29c8c5e9fbcf43227a1bc" in backend
assert "USER 1000:1000" in backend
assert "renderMetrics()" in backend_server
assert "http_requests_total" in backend_server
assert "JSON.stringify" in backend_server
backend_deployment = backend_docs[0]
backend_template = backend_deployment["spec"]["template"]
assert backend_template["metadata"]["annotations"]["prometheus.io/scrape"] == "true"
assert backend_template["metadata"]["annotations"]["prometheus.io/path"] == "/metrics"
assert backend_template["metadata"]["annotations"]["prometheus.io/port"] == "${{ values.backendPort }}"
backend_env = {item["name"]: item["value"] for item in backend_template["spec"]["containers"][0]["env"]}
assert backend_env["OTEL_SERVICE_NAME"] == "${{ values.name }}-backend"
assert backend_env["OTEL_SERVICE_NAMESPACE"] == "${{ values.team }}"
assert backend_env["PORT"] == "${{ values.backendPort }}"
assert "service.version=0.1.0" in backend_env["OTEL_RESOURCE_ATTRIBUTES"]
assert prometheus_scrape["kind"] == "ConfigMap"
assert "job_name: ${{ values.name }}-backend" in prometheus_scrape["data"]["prometheus-additional-scrape.yaml"]
assert [doc["kind"] for doc in cilium_docs] == ["CiliumNetworkPolicy", "CiliumNetworkPolicy"]
assert {doc["metadata"]["name"] for doc in cilium_docs} == {
    "${{ values.name }}-backend-ingress",
    "${{ values.name }}-frontend-egress",
}
assert kyverno["kind"] == "Policy"
assert "require-drop-all-capabilities" in str(kyverno)
assert "${{ values.name }}-golden-signals" in dashboard
assert "victoriametrics-logs-datasource" in dashboard
assert "k8s.namespace.name" in dashboard
assert "http_request_duration_seconds_sum" in dashboard
assert "branches-ignore" in review_workflow
assert "runs-on: [self-hosted, in-cluster, review-env]" in review_workflow
assert "delete:" in review_workflow
assert "REVIEW_REF_TYPE" in review_workflow
assert "REVIEW_NAMESPACE: review" in review_workflow
assert "platform.local/review-environment" in review_workflow
assert "${APP_NAME}-${slug}.review.127.0.0.1.sslip.io" in review_workflow
assert "Remove deleted branch review environment" in review_workflow
assert "Skipping review environment cleanup for deleted" in review_workflow
assert "kubectl -n \"${REVIEW_NAMESPACE}\" delete deployment,service" in review_workflow
assert "kubectl -n gateway-routes delete httproute" in review_workflow
assert "docker push" in review_workflow
assert "imagePullSecrets" in review_workflow
assert "gitea-registry-creds" in review_workflow
assert "kind: CiliumNetworkPolicy" in review_workflow
assert "kind: HTTPRoute" in review_workflow
assert "kind: ReferenceGrant" in review_workflow
assert "kubectl create namespace" not in review_workflow

print("validated platform-service template")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated platform-service template"* ]]
}
