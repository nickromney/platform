#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/kind-kind-local.yaml}"
  export KUBECTX="${KUBECTX:-kind-kind-local}"
}

@test "SSO oauth2-proxy cookie names are app-scoped and versioned" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
import re
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])
texts = [
    (repo_root / "terraform/kubernetes/sso.tf").read_text(encoding="utf-8"),
    (repo_root / "terraform/kubernetes/locals.tf").read_text(encoding="utf-8"),
]
cookie_names: list[str] = []
for text in texts:
    cookie_names.extend(re.findall(r"cookieName:\s+(kind-[^\s]+)", text))
    cookie_names.extend(re.findall(r'cookie_name\s+=\s+"(kind-[^"]+)"', text))

assert cookie_names, "no oauth2-proxy cookie names found"
assert all(name.startswith("kind-v2-sso-") for name in cookie_names), cookie_names
assert len(cookie_names) == len(set(cookie_names)), cookie_names
assert "kind-sso-admin" not in "\n".join(texts)
assert "kind-sso-dev" not in "\n".join(texts)
assert "kind-sso-uat" not in "\n".join(texts)

print("validated app-scoped SSO cookie names")
PY

  if [ "${status}" -ne 0 ]; then
    printf '%s\n' "${output}"
  fi
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated app-scoped SSO cookie names"* ]]
}

@test "Gitea policy sync preserves VictoriaLogs GitOps inputs" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])
sync = (repo_root / "terraform/kubernetes/scripts/sync-gitea.sh").read_text(encoding="utf-8")
delegate = (repo_root / "terraform/kubernetes/scripts/sync-gitea-policies.sh").read_text(encoding="utf-8")

assert "export_resolved_bool ENABLE_VICTORIA_LOGS enable_victoria_logs true" in sync
assert "export_resolved_string VICTORIA_LOGS_CHART_VERSION victoria_logs_chart_version" in sync
assert "if ! is_true \"${ENABLE_VICTORIA_LOGS}\"" in delegate
assert "victoria-logs-single) printf '%s\\n' \"${VICTORIA_LOGS_CHART_VERSION}\"" in delegate

print("validated VictoriaLogs policy sync inputs")
PY

  if [ "${status}" -ne 0 ]; then
    printf '%s\n' "${output}"
  fi
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated VictoriaLogs policy sync inputs"* ]]
}

@test "VictoriaLogs has no recent non-allowlisted platform errors" {
  command -v kubectl >/dev/null || skip "kubectl is required"
  command -v curl >/dev/null || skip "curl is required"
  kubectl --kubeconfig "${KUBECONFIG}" --context "${KUBECTX}" -n observability get pod victoria-logs-victoria-logs-single-server-0 >/dev/null 2>&1 || skip "VictoriaLogs is not running"

  local port="19429"
  kubectl --kubeconfig "${KUBECONFIG}" --context "${KUBECTX}" -n observability port-forward pod/victoria-logs-victoria-logs-single-server-0 "${port}:9428" >/tmp/platform-victorialogs-port-forward.log 2>&1 &
  local pf_pid="$!"
  trap 'kill "${pf_pid}" >/dev/null 2>&1 || true' RETURN

  for _ in {1..40}; do
    if curl -fsS "http://127.0.0.1:${port}/health" >/dev/null 2>&1 || curl -fsS "http://127.0.0.1:${port}/" >/dev/null 2>&1; then
      break
    fi
    sleep 0.25
  done

  run uv run --isolated python - <<'PY'
from __future__ import annotations

import datetime as dt
import json
import os
import re
import urllib.parse
import urllib.request

port = os.environ.get("VICTORIALOGS_TEST_PORT", "19429")
base_url = f"http://127.0.0.1:{port}/select/logsql/query"
query = 'error'
url = f"{base_url}?{urllib.parse.urlencode({'query': query, 'limit': '1000'})}"

with urllib.request.urlopen(url, timeout=20) as response:
    rows = [json.loads(line) for line in response.read().decode("utf-8").splitlines() if line.strip()]

window_minutes = int(os.environ.get("VICTORIALOGS_ERROR_WINDOW_MINUTES", "1"))
cutoff = dt.datetime.now(dt.UTC) - dt.timedelta(minutes=window_minutes)
allowlist = [
    # Gitea logs SSH port probes as warning text containing "error"; this is noisy but not a platform failure.
    re.compile(r"sshConnectionFailed\(\).*\\[W\\].*(EOF|Failed authentication attempt)"),
    # Argo repo-server logs rendered Helm values at info level; values can contain strings such as show-debug-on-error.
    re.compile(r'level=info msg="manifest cache (hit|miss):'),
    # Grafana logs transient sqlite lock retries at info level during dashboard provisioning/startup.
    re.compile(r'level=info msg="Database locked, sleeping then retrying" error="database is locked"'),
]
violations: list[str] = []
for row in rows:
    raw_time = row.get("_time", "")
    try:
        logged_at = dt.datetime.fromisoformat(raw_time.replace("Z", "+00:00"))
    except ValueError:
        continue
    if logged_at < cutoff:
        continue

    msg = row.get("_msg", "")
    deployment = row.get("k8s.deployment.name", row.get("service.name", "<unknown>"))
    if any(pattern.search(msg) for pattern in allowlist):
        continue
    violations.append(f"{raw_time} {deployment}: {msg[:500]}")

assert not violations, "non-allowlisted recent error logs:\n" + "\n".join(violations[:20])
print("validated recent VictoriaLogs error quality")
PY

  if [ "${status}" -ne 0 ]; then
    printf '%s\n' "${output}"
    printf '%s\n' "--- port-forward log ---"
    cat /tmp/platform-victorialogs-port-forward.log
  fi
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated recent VictoriaLogs error quality"* ]]
}
