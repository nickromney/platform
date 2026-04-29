#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/kind-kind-local.yaml}"
  export KUBECTX="${KUBECTX:-kind-kind-local}"
}

@test "Grafana namespace health dashboard does not rely on empty pod scrape series" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])
for relative_path in (
    "terraform/kubernetes/observability.tf",
    "terraform/kubernetes/apps/argocd-apps/95-grafana.application.yaml",
):
    text = (repo_root / relative_path).read_text(encoding="utf-8")
    assert "Platform Namespace Health" in text, relative_path
    assert "Scraped pods up" in text, relative_path
    assert 'up{job=\\"kubernetes-pods\\",namespace=~\\"dev|uat\\"}' in text, relative_path
    assert "kube_namespace_status_phase" in text, relative_path
    assert "or on(namespace)" in text, relative_path

print("validated namespace health scrape fallback")
PY

  if [ "${status}" -ne 0 ]; then
    printf '%s\n' "${output}"
  fi
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated namespace health scrape fallback"* ]]
}

@test "live Grafana namespace health Prometheus queries return series" {
  command -v kubectl >/dev/null || skip "kubectl is required"
  command -v curl >/dev/null || skip "curl is required"
  kubectl --kubeconfig "${KUBECONFIG}" --context "${KUBECTX}" get ns observability >/dev/null 2>&1 || skip "kind observability namespace is not running"

  local port="19091"
  kubectl --kubeconfig "${KUBECONFIG}" --context "${KUBECTX}" -n observability port-forward svc/prometheus-server "${port}:80" >/tmp/platform-prometheus-port-forward.log 2>&1 &
  local pf_pid="$!"
  trap 'kill "${pf_pid}" >/dev/null 2>&1 || true' RETURN

  for _ in {1..40}; do
    if curl -fsS "http://127.0.0.1:${port}/-/ready" >/dev/null 2>&1; then
      break
    fi
    sleep 0.25
  done

  run uv run --isolated python - <<'PY'
from __future__ import annotations

import json
import os
import subprocess
import urllib.parse
import urllib.request

port = os.environ.get("PROMETHEUS_TEST_PORT", "19091")
base_url = f"http://127.0.0.1:{port}/api/v1/query"
raw_dashboard = subprocess.check_output(
    [
        "kubectl",
        "--kubeconfig",
        os.environ["KUBECONFIG"],
        "--context",
        os.environ["KUBECTX"],
        "-n",
        "observability",
        "get",
        "cm",
        "grafana-dashboards-default",
        "-o",
        "jsonpath={.data.platform-namespace-health\\.json}",
    ],
    text=True,
)
dashboard = json.loads(raw_dashboard)
failures: list[str] = []
checked = 0
for panel in dashboard["panels"]:
    title = panel["title"]
    for target in panel.get("targets", []):
        query = target.get("expr")
        if not query:
            continue
        checked += 1
        url = f"{base_url}?{urllib.parse.urlencode({'query': query})}"
        with urllib.request.urlopen(url, timeout=10) as response:
            payload = json.loads(response.read())
        result = payload.get("data", {}).get("result", [])
        namespaces = {item.get("metric", {}).get("namespace") for item in result}
        if not result:
            failures.append(f"{title}: query returned no series: {query}")
        elif not {"dev", "uat"} <= namespaces:
            failures.append(f"{title}: expected dev and uat series, got {sorted(namespaces)}")

if checked != 5:
    failures.append(f"expected to check 5 Prometheus targets, checked {checked}")

if failures:
    raise AssertionError("\n".join(failures))

print("validated live namespace health dashboard queries")
PY

  if [ "${status}" -ne 0 ]; then
    printf '%s\n' "${output}"
    printf '%s\n' "--- port-forward log ---"
    cat /tmp/platform-prometheus-port-forward.log
  fi
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated live namespace health dashboard queries"* ]]
}

@test "Grafana app overview dashboard has explicit zero fallbacks for sparse app signals" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])
for relative_path in (
    "terraform/kubernetes/observability.tf",
    "terraform/kubernetes/apps/argocd-apps/95-grafana.application.yaml",
):
    text = (repo_root / relative_path).read_text(encoding="utf-8")
    assert "Platform App Golden Signals" in text, relative_path
    assert ("Error rate (%)" in text or "5xx error ratio" in text), relative_path
    assert "LLM inference p95 (ms)" in text, relative_path
    assert (
        "0 * sum(rate(traces_span_metrics_calls_total" in text
        or "0 * sum(rate(http_server_requests_seconds_count" in text
    ), relative_path
    assert "0 * max by (k8s_namespace_name) (sentiment_comments_created_total" in text, relative_path

print("validated app overview sparse-signal fallbacks")
PY

  if [ "${status}" -ne 0 ]; then
    printf '%s\n' "${output}"
  fi
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated app overview sparse-signal fallbacks"* ]]
}

@test "live Grafana app overview Prometheus queries return series" {
  command -v kubectl >/dev/null || skip "kubectl is required"
  command -v curl >/dev/null || skip "curl is required"
  kubectl --kubeconfig "${KUBECONFIG}" --context "${KUBECTX}" get ns observability >/dev/null 2>&1 || skip "kind observability namespace is not running"

  local port="19092"
  kubectl --kubeconfig "${KUBECONFIG}" --context "${KUBECTX}" -n observability port-forward svc/prometheus-server "${port}:80" >/tmp/platform-prometheus-app-overview-port-forward.log 2>&1 &
  local pf_pid="$!"
  trap 'kill "${pf_pid}" >/dev/null 2>&1 || true' RETURN

  for _ in {1..40}; do
    if curl -fsS "http://127.0.0.1:${port}/-/ready" >/dev/null 2>&1; then
      break
    fi
    sleep 0.25
  done

  run uv run --isolated python - <<'PY'
from __future__ import annotations

import json
import os
import subprocess
import urllib.parse
import urllib.request

port = os.environ.get("PROMETHEUS_APP_OVERVIEW_TEST_PORT", "19092")
base_url = f"http://127.0.0.1:{port}/api/v1/query"
raw_dashboard = subprocess.check_output(
    [
        "kubectl",
        "--kubeconfig",
        os.environ["KUBECONFIG"],
        "--context",
        os.environ["KUBECTX"],
        "-n",
        "observability",
        "get",
        "cm",
        "grafana-dashboards-default",
        "-o",
        "jsonpath={.data.platform-overview\\.json}",
    ],
    text=True,
)
dashboard = json.loads(raw_dashboard)
required_titles = {
    "Request rate (rps)",
    "Error rate (%)",
    "Latency p95 (ms)",
    "Sentiment comments (last 1h)",
    "LLM inference p95 (ms)",
    "Collector scrape availability",
}
failures: list[str] = []
seen: set[str] = set()
for panel in dashboard["panels"]:
    title = panel["title"]
    if title not in required_titles:
        continue
    seen.add(title)
    for target in panel.get("targets", []):
        query = target.get("expr")
        if not query:
            continue
        url = f"{base_url}?{urllib.parse.urlencode({'query': query})}"
        with urllib.request.urlopen(url, timeout=10) as response:
            payload = json.loads(response.read())
        result = payload.get("data", {}).get("result", [])
        if not result:
            failures.append(f"{title}: query returned no series: {query}")

missing = required_titles - seen
if missing:
    failures.append(f"missing expected panels: {sorted(missing)}")

if failures:
    raise AssertionError("\n".join(failures))

print("validated live app overview dashboard queries")
PY

  if [ "${status}" -ne 0 ]; then
    printf '%s\n' "${output}"
    printf '%s\n' "--- port-forward log ---"
    cat /tmp/platform-prometheus-app-overview-port-forward.log
  fi
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated live app overview dashboard queries"* ]]
}
