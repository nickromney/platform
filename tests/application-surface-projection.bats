#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "platform catalog projects application surfaces into Backstage, launchpad, and observability metrics" {
  run uv run --project "${REPO_ROOT}/apps/idp-core" --with pyyaml python - <<'PY'
from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

import yaml

from app.catalog import application_surface_records, load_catalog

repo_root = Path(os.environ["REPO_ROOT"])
catalog = load_catalog(repo_root / "catalog/platform-apps.json")
surfaces = {
    (record.app, record.environment): record
    for record in application_surface_records(catalog)
}

catalog_files = [
    repo_root / "apps/backstage/catalog/entities.yaml",
    repo_root / "apps/backstage/catalog/apps/platform-mcp/catalog-info.yaml",
    repo_root / "apps/backstage/catalog/apps/subnetcalc/catalog-info.yaml",
    repo_root / "apps/backstage/catalog/apps/apim-simulator/catalog-info.yaml",
    repo_root / "apps/backstage/catalog/apps/sentiment/catalog-info.yaml",
]
docs = []
for catalog_file in catalog_files:
    docs.extend(yaml.safe_load_all(catalog_file.read_text(encoding="utf-8")))
components = {
    doc["metadata"]["name"]: doc
    for doc in docs
    if doc and doc.get("kind") == "Component"
}
launchpad = json.loads(
    (repo_root / "terraform/kubernetes/config/platform-launchpad.apps.json").read_text(encoding="utf-8")
)
tiles = launchpad["tiles"]

for app, environment in [
    ("backstage", "local"),
    ("idp-core", "local"),
    ("sentiment", "dev"),
    ("subnetcalc", "uat"),
]:
    surface = surfaces[(app, environment)]
    component = components[app]
    annotations = component["metadata"]["annotations"]
    links = {link["url"]: link for link in component["metadata"].get("links", [])}

    assert component["metadata"]["title"] == surface.display_name
    assert component["spec"]["owner"] == f"group:default/{surface.owner}"
    assert annotations["backstage.io/kubernetes-label-selector"] == surface.kubernetes_label_selector
    assert surface.route in links, f"{app}/{environment} route missing from Backstage catalog links"

    route_tile = next(
        tile
        for tile in tiles
        if tile.get("service") == app
        and tile.get("environment") == environment
        and tile["url"] == surface.route
    )
    assert route_tile["owner"] == surface.owner
    assert route_tile.get("rbac_group") == surface.rbac_group

backstage_surface = surfaces[("backstage", "local")]
backstage_observability = next(tile for tile in tiles if tile["title"] == "Backstage Observability")
assert backstage_observability["service"] == backstage_surface.app
assert backstage_observability["owner"] == backstage_surface.owner
assert backstage_observability["environment"] == backstage_surface.environment
assert any(
    link["title"] == backstage_observability["title"]
    and link["url"] == backstage_observability["url"]
    for link in components["backstage"]["metadata"].get("links", [])
)

metrics_script = r"""
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');

const repoRoot = process.env.REPO_ROOT;
const modulePath = path.join(repoRoot, 'apps/backstage/packages/backend/src/modules/catalogMetrics.ts');
const ts = require(path.join(repoRoot, 'apps/backstage/node_modules/typescript'));
const source = fs.readFileSync(modulePath, 'utf8');
const js = ts.transpileModule(source, {
  compilerOptions: {
    esModuleInterop: true,
    module: ts.ModuleKind.CommonJS,
    target: ts.ScriptTarget.ES2020,
  },
}).outputText;

const compiled = new Module(modulePath);
compiled.filename = modulePath;
compiled.paths = Module._nodeModulePaths(path.join(repoRoot, 'apps/backstage/packages/backend'));
compiled._compile(js, modulePath);

process.env.BACKSTAGE_CATALOG_METRICS_ROOT = path.join(repoRoot, 'apps/backstage');
process.stdout.write(compiled.exports.renderCatalogMetrics());
"""
metrics = subprocess.run(
    ["node", "-e", metrics_script],
    check=True,
    cwd=repo_root,
    env=os.environ.copy(),
    text=True,
    capture_output=True,
).stdout

assert 'backstage_catalog_component_locality_total{component="backstage",owner="group:default/platform",lifecycle="platform",system="local-idp",type="website"} 1' in metrics
assert 'backstage_catalog_component_locality_total{component="idp-core",owner="group:default/platform",lifecycle="platform",system="local-idp",type="service"} 1' in metrics
assert 'backstage_catalog_component_links_total{component="backstage",kind="observability"} 1' in metrics

print("validated platform application surface projection locality")
PY

  if [ "${status}" -ne 0 ]; then
    printf '%s\n' "${output}"
  fi
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated platform application surface projection locality"* ]]
}
