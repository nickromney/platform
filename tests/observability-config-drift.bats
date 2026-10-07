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
  run uv run --locked --project "${REPO_ROOT}" python - <<'PY'
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

@test "Gitea keeps a Terraform-owned allow so GitOps can bootstrap itself" {
  # The Cilium allow rules for Gitea arrive through Argo CD, which reads them
  # from Gitea. Without a Terraform-owned allow beside the generated
  # default-deny, an interrupted apply leaves that loop unrecoverable.
  run uv run --locked --project "${REPO_ROOT}" python - <<'PY'
import os
from pathlib import Path

namespaces_tf = (Path(os.environ["REPO_ROOT"]) / "terraform/kubernetes/namespaces.tf").read_text(encoding="utf-8")
for fragment in (
    'resource "kubernetes_network_policy_v1" "gitea_argocd_bootstrap"',
    'name      = "allow-gitea-bootstrap"',
    'port     = "3000"',
    'port     = "2222"',
    'policy_types = ["Ingress", "Egress"]',
    '"k8s-app" = "kube-dns"',
    'port     = "5432"',
):
    assert fragment in namespaces_tf, fragment

# A source selector on the ingress rule would isolate Gitea whenever the
# generated default-deny is absent, cutting off the NodePort Terraform uses to
# create the org. The egress rules do carry selectors, so check only ingress.
ingress_rule = namespaces_tf.split("gitea_argocd_bootstrap", 1)[1].split("ingress {", 1)[1].split("egress {", 1)[0]
assert "from {" not in ingress_rule, ingress_rule

print("validated Gitea GitOps bootstrap allow")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated Gitea GitOps bootstrap allow"* ]]
}
