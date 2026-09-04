#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
}

@test "Argo CD Applications defined for both GitOps modes agree on sync policy" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import glob
import json
import os
import re
from pathlib import Path

import yaml

# Most Argo CD Applications are written twice. With enable_app_of_apps=false
# Terraform applies an inline manifest; with it true the same app is synced from
# apps/argocd-apps/. Both settings ship: the kind stages from 500 up enable it,
# the Lima stages and the local identity profile do not. Nothing keeps the two
# definitions in step, so an app can reconcile differently depending on which
# mode brought it up, and nothing says so.
#
# Chart source, revision and path are deliberately different and are not
# compared: the renderer rewrites the checked-in upstream chart references into
# vendored paths on the way into the GitOps repo. Helm values are skipped for
# the same reason. destination.namespace is skipped because the Terraform side
# interpolates it from a resource attribute this test cannot resolve. A sync
# wave is only compared when both sides declare one, because ordering in direct
# Terraform mode comes from depends_on rather than from waves.
MIN_COMPARABLE_APPS = 27

TF_RETRY = {"limit": 5, "backoff": {"duration": "10s", "factor": 2, "maxDuration": "3m"}}
SYNC_BASE = ["CreateNamespace=true", "ServerSideApply=true", "SkipDryRunOnMissingResource=true"]

# Divergences that exist today, recorded so they are visible rather than
# invisible. Each entry is [terraform_value, checked_in_value]. Resolving one
# means deleting its entry; introducing a new one means fixing it or adding it
# here deliberately.
KNOWN_DIVERGENCES = {
    # Seven workload apps retry in direct Terraform mode and not under
    # app-of-apps, so a transient sync failure is retried in one mode only.
    "agentgateway-ai-gateway": {"retry": [TF_RETRY, None]},
    "apim": {"retry": [TF_RETRY, None]},
    "idp": {"retry": [TF_RETRY, None]},
    "langfuse-demos": {"retry": [TF_RETRY, None]},
    "mcp": {"retry": [TF_RETRY, None]},
    "uat": {"retry": [TF_RETRY, None]},
    "dev": {
        "retry": [TF_RETRY, None],
        "syncOptions": [SYNC_BASE, SYNC_BASE + ["RespectIgnoreDifferences=true"]],
    },
    # eso-demo is the one app that retries under app-of-apps and not in
    # Terraform, and with a longer budget than any other app uses.
    "eso-demo": {
        "retry": [None, {"limit": 20, "backoff": {"duration": "15s", "factor": 2, "maxDuration": "5m"}}]
    },
    # argo-rollouts creates its own namespace in one mode and not the other.
    "argo-rollouts": {
        "wave": ["86", "87"],
        "syncOptions": [
            SYNC_BASE[:1] + SYNC_BASE[1:] + ["RespectIgnoreDifferences=true"],
            ["CreateNamespace=false"] + SYNC_BASE[1:] + ["RespectIgnoreDifferences=true"],
        ],
    },
    # kyverno-policies applies client-side in Terraform mode and server-side
    # under app-of-apps.
    "kyverno-policies": {"syncOptions": [["CreateNamespace=true"], SYNC_BASE]},
    "cert-manager-config": {"wave": ["5", "10"]},
    "platform-gateway-routes": {"wave": ["20", "50"]},
}


def strip_block_scalars(text: str) -> str:
    """Drop block scalars. They hold Helm values and render placeholders that
    are not valid YAML on their own, and nothing here compares them."""
    kept: list[str] = []
    skip_indent: int | None = None
    for line in text.split("\n"):
        if skip_indent is not None:
            if line.strip() and (len(line) - len(line.lstrip())) <= skip_indent:
                skip_indent = None
            else:
                continue
        opener = re.match(r"^(\s*)[\w.\"'-]+: \|-?\s*$", line)
        if opener:
            skip_indent = len(opener.group(1))
            continue
        kept.append(line)
    return "\n".join(kept)


def parse(text):
    try:
        doc = yaml.safe_load(strip_block_scalars(text))
    except yaml.YAMLError:
        return None
    if isinstance(doc, dict) and doc.get("kind") == "Application":
        return doc
    return None


repo_root = Path(os.environ["REPO_ROOT"])
stack = repo_root / "terraform" / "kubernetes"

terraform_apps = {}
for path in sorted(glob.glob(str(stack / "*.tf"))):
    for match in re.finditer(
        r"yaml_body = <<__YAML__\n(.*?)\n__YAML__", Path(path).read_text(encoding="utf-8"), re.S
    ):
        if "kind: Application" not in match.group(1):
            continue
        doc = parse(match.group(1))
        if doc:
            terraform_apps[doc["metadata"]["name"]] = doc

checked_in_apps = {}
for path in sorted(glob.glob(str(stack / "apps" / "argocd-apps" / "*.application.yaml"))):
    doc = parse(Path(path).read_text(encoding="utf-8"))
    if doc:
        checked_in_apps[doc["metadata"]["name"]] = doc

shared = sorted(set(terraform_apps) & set(checked_in_apps))
assert len(shared) >= MIN_COMPARABLE_APPS, (
    f"only {len(shared)} Applications could be compared, expected at least "
    f"{MIN_COMPARABLE_APPS}; a manifest may have stopped parsing and is now "
    "silently unguarded"
)


def facets(doc):
    policy = doc.get("spec", {}).get("syncPolicy") or {}
    return {
        "project": doc.get("spec", {}).get("project"),
        "automated": policy.get("automated"),
        "syncOptions": policy.get("syncOptions"),
        "retry": policy.get("retry"),
        "wave": (doc.get("metadata", {}).get("annotations") or {}).get(
            "argocd.argoproj.io/sync-wave"
        ),
    }


actual = {}
for name in shared:
    left, right = facets(terraform_apps[name]), facets(checked_in_apps[name])
    differences = {}
    for field in left:
        if field == "wave" and (left[field] is None or right[field] is None):
            continue
        if left[field] != right[field]:
            differences[field] = [left[field], right[field]]
    if differences:
        actual[name] = differences

expected = json.loads(json.dumps(KNOWN_DIVERGENCES))
if actual != expected:
    lines = []
    for name in sorted(set(actual) | set(expected)):
        got, want = actual.get(name, {}), expected.get(name, {})
        if got == want:
            continue
        for field in sorted(set(got) | set(want)):
            if got.get(field) == want.get(field):
                continue
            if field not in want:
                lines.append(
                    f"  {name}.{field}: new divergence between the two GitOps modes\n"
                    f"      terraform={json.dumps(got[field][0])}\n"
                    f"      checked-in={json.dumps(got[field][1])}"
                )
            elif field not in got:
                lines.append(
                    f"  {name}.{field}: recorded divergence is resolved; "
                    "delete it from KNOWN_DIVERGENCES"
                )
            else:
                lines.append(
                    f"  {name}.{field}: recorded divergence changed\n"
                    f"      recorded={json.dumps(want[field])}\n"
                    f"      actual={json.dumps(got[field])}"
                )
    raise AssertionError(
        "Argo CD Applications disagree between the direct Terraform path and "
        "the app-of-apps path:\n" + "\n".join(lines)
    )

print(f"compared {len(shared)} Argo CD Applications across both GitOps modes")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"across both GitOps modes"* ]]
}
