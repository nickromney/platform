"""Check actual Kustomize output for optional feature references."""

import json
import sys
from pathlib import Path

import yaml

root = Path(sys.argv[1])
results = []
for case in sorted(root.glob("stage*-headlamp*-observability*")):
    enabled = "headlamptrue" in case.name
    observability = "observabilitytrue" in case.name
    for rendered in sorted(case.glob("platform-gateway-routes*.yaml")):
        resources = list(yaml.safe_load_all(rendered.read_text()))
        assert resources, f"{rendered}: no rendered resources"
        refs = []
        headlamp_routes = []
        for resource in resources:
            if not isinstance(resource, dict):
                continue
            kind = resource.get("kind")
            metadata = resource.get("metadata", {})
            text = json.dumps(resource)
            assert "signoz" not in text.lower(), f"{rendered}: retired SigNoz resource reference"
            if kind == "HTTPRoute":
                for rule in resource.get("spec", {}).get("rules", []):
                    for backend in rule.get("backendRefs", []):
                        refs.append(backend.get("namespace", metadata.get("namespace")))
                if "headlamp" in metadata.get("name", ""):
                    headlamp_routes.append(metadata["name"])
            if kind == "ReferenceGrant":
                refs.append(metadata.get("namespace"))
                refs.extend(x.get("namespace") for x in resource.get("spec", {}).get("from", []))
        if enabled:
            assert headlamp_routes, f"{rendered}: enabled Headlamp lost route"
        else:
            assert not headlamp_routes and "headlamp" not in refs, (
                f"{rendered}: disabled Headlamp has dangling route/grant"
            )
            assert "headlamp" not in rendered.read_text().lower(), (
                f"{rendered}: disabled Headlamp has residual reference"
            )
        grafana_routes = [
            r
            for r in resources
            if isinstance(r, dict)
            and r.get("kind") == "HTTPRoute"
            and "grafana" in r.get("metadata", {}).get("name", "")
        ]
        if observability:
            # Current source exposes Grafana only through the SSO proxy.
            if rendered.name == "platform-gateway-routes-sso.yaml":
                assert grafana_routes, f"{rendered}: enabled Grafana lost route"
        else:
            assert "observability" not in refs, f"{rendered}: disabled observability namespace referenced"
            assert not grafana_routes, f"{rendered}: disabled Grafana route"
        results.append({"case": case.name, "rendered": rendered.name, "resources": len(resources), "status": "passed"})
    application = case / "repo/apps/argocd-apps/85-headlamp.application.yaml"
    assert application.exists() == enabled, f"{case}: Headlamp Application mismatch"
    namespace = case / "repo/apps/argocd-apps/80-observability.namespace.yaml"
    assert namespace.exists() == observability, f"{case}: observability Namespace mismatch"
assert len(results) == 16, f"Expected 16 route renders, got {len(results)}"
(root / "matrix-result.json").write_text(json.dumps(results, indent=2) + "\n")
print(f"PASS: {len(results)} actual route renders; optional namespace/route/grant checks")
