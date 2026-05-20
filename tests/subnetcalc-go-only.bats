#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "subnetcalc app tree contains only the canonical Go app surface" {
  run bash -lc "cd '${REPO_ROOT}' && for path in apps/subnetcalc/* apps/subnetcalc/.[!.]*; do [ -e \"\${path}\" ] && basename \"\${path}\"; done | sort"

  [ "${status}" -eq 0 ]
  expected=$'.dockerignore\n.gitea\n.gitignore\nMakefile\nREADME.md\napp\ncatalog-info.yaml\ncompose.yml\nmkdocs.yml\ntests'
  [ "${output}" = "${expected}" ]
}

@test "subnetcalc makefile exposes only Go and default compose workflows" {
  run make -C "${REPO_ROOT}/apps/subnetcalc" help

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"app-test"* ]]
  [[ "${output}" != *"app-go-test"* ]]
  [[ "${output}" == *"up"* ]]
  [[ "${output}" == *"down"* ]]
  [[ "${output}" != *"frontend-react"* ]]
  [[ "${output}" != *"frontend-typescript-vite"* ]]
  [[ "${output}" != *"frontend-python-flask"* ]]
  [[ "${output}" != *"api-fastapi"* ]]
  [[ "${output}" != *"bruno"* ]]
}

@test "subnetcalc image catalog builds only Go subnetcalc images" {
  run python3 - <<PY
import json
from pathlib import Path

repo = Path("${REPO_ROOT}")
catalog = json.loads((repo / "kubernetes/workflow/image-catalog.json").read_text(encoding="utf-8"))
subnetcalc = [image for image in catalog["workload_images"] if image["id"].startswith("subnetcalc-")]
retired_ids = {"subnetcalc-frontend-react"}
actual_ids = {image["id"] for image in subnetcalc}

assert retired_ids.isdisjoint(actual_ids), actual_ids
for image in subnetcalc:
    build = image.get("build", {})
    context = build.get("context", "")
    dockerfile = build.get("dockerfile", "")
    if image["id"] in {"subnetcalc-api", "subnetcalc-frontend"}:
        assert context == "apps/subnetcalc/app", image
        assert dockerfile == "Dockerfile", image
PY

  [ "${status}" -eq 0 ]
}
