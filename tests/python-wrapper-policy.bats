#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "tracked host-side code avoids bare python references outside approved exceptions" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
import subprocess
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])
needle = "python" "3"
allowed = {
    ".devcontainer/Dockerfile",
    "apps/subnetcalc/api-fastapi-azure-function/Dockerfile",
    "apps/subnetcalc/frontend-html-static/serve.py",
    "kubernetes/kind/scripts/rewrite-devcontainer-kubeconfig.py",
    "kubernetes/kind/tests/check-version.bats",
    "scripts/audit-shell-scripts.sh",
    "sd-wan/lima/provision/cloud2.sh",
    "sd-wan/lima/provision/common.sh",
    "sd-wan/lima/tests/makefile.bats",
    "terraform/kubernetes/scripts/render-kind-apiserver-oidc-manifest.py",
    "tests/audit-shell-scripts.bats",
}

result = subprocess.run(
    ["git", "-C", str(repo_root), "grep", "-n", needle, "--", "."],
    check=False,
    capture_output=True,
    text=True,
)

unexpected: list[str] = []
for raw_line in result.stdout.splitlines():
    relative_path = raw_line.split(":", 1)[0]
    if relative_path in allowed:
        continue
    unexpected.append(raw_line)

assert not unexpected, "\n".join(unexpected)
print(f"validated {len(allowed)} approved bare-python reference file(s)")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated 11 approved bare-python reference file(s)"* ]]
}
