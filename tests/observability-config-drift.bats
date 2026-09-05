#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
  export REPO_ROOT
}

@test "both Prometheus paths size the server the same way" {
  # enable_app_of_apps picks which Application deploys Prometheus, and the two
  # had drifted to different memory limits and retention windows. Selecting a
  # profile should not silently select a different Prometheus.
  run uv run --isolated python - <<'PY'
import os
import re
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])
sources = {
    "terraform": repo_root / "terraform/kubernetes/observability.tf",
    "app-of-apps": repo_root / "terraform/kubernetes/apps/argocd-apps/90-prometheus.application.yaml",
}

def server_settings(text: str) -> dict[str, str]:
    server = text.split("        server:", 1)[1]
    server = server.split("        serverFiles:", 1)[0]
    found = {}
    for field in ("cpu", "memory"):
        values = re.findall(rf"^\s+{field}: (\S+)$", server, re.M)
        assert len(values) == 2, f"expected a request and a limit for {field}, found {values}"
        found[f"{field}_request"], found[f"{field}_limit"] = values
    retention = re.search(r"^\s+retention: (\S+)$", server, re.M)
    assert retention, "no retention setting found"
    found["retention"] = retention.group(1)
    return found

settings = {label: server_settings(path.read_text(encoding="utf-8")) for label, path in sources.items()}
terraform, app_of_apps = settings["terraform"], settings["app-of-apps"]
differences = {key: (terraform[key], app_of_apps[key]) for key in terraform if terraform[key] != app_of_apps[key]}
assert not differences, f"Prometheus server drift between the two paths: {differences}"

print(f"validated matching Prometheus server settings: {terraform}")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated matching Prometheus server settings"* ]]
}
