#!/usr/bin/env bats

# Memory requests are reservations, not caps. Every assertion here is about a
# request; the matching limit is asserted unchanged alongside it, because a pass
# that quietly lowers a limit would be capping a workload rather than
# right-sizing its scheduler footprint.

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
}

@test "gitea valkey resources land on the chart's primary key rather than the inert master key" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
import re
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
gitea_tf = (repo_root / "terraform/kubernetes/gitea.tf").read_text(encoding="utf-8")

# The vendored valkey subchart (gitea 12.7.0) exposes primary.*, replica.*,
# and sentinel.* only. A master: block renders nothing and lets the chart's
# resourcesPreset: nano win, which is how the running pod ended up reserving
# 128Mi for a process measured at ~6Mi.
valkey_block = re.search(
    r"^        valkey:\n(?P<body>(?:^ {10}.*\n|^\n)+)",
    gitea_tf,
    re.M,
)
assert valkey_block, "valkey values block not found in gitea.tf"
body = valkey_block.group("body")

assert not re.search(r"^ {10}master:", body, re.M), (
    "valkey.master is not a key in the chart; use valkey.primary or the block is inert"
)
assert re.search(r"^ {10}primary:", body, re.M), "valkey.primary block missing"

values = yaml.safe_load("valkey:\n" + body)["valkey"]
resources = values["primary"]["resources"]

# Reservation moves down to ~10x the measured ~6Mi steady state.
assert resources["requests"]["memory"] == "64Mi", resources
assert resources["requests"]["cpu"] == "25m", resources
# Limits pinned to the chart's nano preset so nothing is capped more tightly
# than it is today.
assert resources["limits"]["memory"] == "192Mi", resources
assert resources["limits"]["cpu"] == "150m", resources
assert resources["limits"]["ephemeral-storage"] == "2Gi", resources
assert resources["requests"]["ephemeral-storage"] == "50Mi", resources
PY

  [ "${status}" -eq 0 ]
}

@test "platform-mcp reserves for its measured footprint while the inspector beside it is untouched" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
docs = [
    doc
    for doc in yaml.safe_load_all(
        (repo_root / "terraform/kubernetes/apps/mcp/all.yaml").read_text(encoding="utf-8")
    )
    if doc
]


def container(name: str) -> dict:
    matches = [
        doc
        for doc in docs
        if doc.get("kind") == "Deployment" and doc["metadata"]["name"] == name
    ]
    assert len(matches) == 1, (name, len(matches))
    containers = matches[0]["spec"]["template"]["spec"]["containers"]
    assert len(containers) == 1, (name, containers)
    return containers[0]


mcp = container("platform-mcp")["resources"]
# Measured steady state ~10Mi; 48Mi keeps ~5x headroom.
assert mcp["requests"]["memory"] == "48Mi", mcp
# The burst boundary is unchanged: this is a reservation cut, not a cap.
assert mcp["limits"]["memory"] == "512Mi", mcp

inspector = container("mcp-inspector")["resources"]
# The inspector measures ~98Mi against its 128Mi request. It is deliberately
# left alone; a blanket cut across the namespace would have squeezed it.
assert inspector["requests"]["memory"] == "128Mi", inspector
assert inspector["limits"]["memory"] == "512Mi", inspector
PY

  [ "${status}" -eq 0 ]
}

@test "memory request tunables default to the measured local-cluster reservations" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
import re
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])
variables_tf = (repo_root / "terraform/kubernetes/variables.tf").read_text(encoding="utf-8")

expected_defaults = {
    "metrics_server_memory_request": "100Mi",
    "oauth2_proxy_memory_request": "24Mi",
    "oauth2_proxy_cpu_request": "25m",
    "oauth2_proxy_session_store_memory_request": "24Mi",
}

for name, default in expected_defaults.items():
    block = re.search(
        rf'^variable "{name}" \{{\n(?:.*\n)*?^\}}$', variables_tf, re.M
    )
    assert block, f"{name} is not declared in variables.tf"
    assert f'default     = "{default}"' in block.group(0), (
        f"{name} default moved off the measured local-cluster reservation"
    )

# The tunables have to actually reach the manifests, or the preset overlay is
# a no-op that still passes the declared-variable check.
metrics_tf = (repo_root / "terraform/kubernetes/metrics-server.tf").read_text(encoding="utf-8")
assert "memory: ${var.metrics_server_memory_request}" in metrics_tf
assert "memory: 300Mi" in metrics_tf, "metrics-server limit must stay put"

sso_tf = (repo_root / "terraform/kubernetes/sso.tf").read_text(encoding="utf-8")
assert "memory: ${var.oauth2_proxy_session_store_memory_request}" in sso_tf
PY

  [ "${status}" -eq 0 ]
}

@test "the local-8gb overlay does not restate request tunables that already match the default" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import json
import os
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])
options = json.loads(
    (repo_root / "kubernetes/workflow/options.json").read_text(encoding="utf-8")
)

overlay = next(
    preset["overlay"]
    for preset in options["presets"]
    if preset["id"] == "local-8gb" and preset["group"] == "resource_profile"
)

# Request tunables now default to the measured local-cluster reservations.
# local-8gb must not re-state them: a profile may only reduce, and repeating
# the default would fail the "overlay < default" contract.
for key in (
    "oauth2_proxy_memory_request",
    "oauth2_proxy_cpu_request",
    "oauth2_proxy_session_store_memory_request",
    "metrics_server_memory_request",
):
    assert key not in overlay, key
PY

  [ "${status}" -eq 0 ]
}
