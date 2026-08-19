#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
}

@test "subnetcalc app tree contains only the canonical Go app surface" {
  # LC_ALL=C for the same reason as sentiment-go-only.bats: the expected list is
  # in C collation, and a working en_GB.UTF-8 locale sorts it differently.
  #
  # `edge` and `update-subnetcalc-image-tags.sh` are part of the canonical
  # surface, not drift -- sentiment carries the same pair. They arrived in #111
  # and #113 and were never added here, because this file has never run in CI.
  run bash -lc "cd '${REPO_ROOT}' && ls -A apps/subnetcalc | LC_ALL=C sort"

  [ "${status}" -eq 0 ]
  expected=$'.dockerignore\n.gitea\n.gitignore\nMakefile\nREADME.md\napp\ncatalog-info.yaml\ncompose.yml\nedge\nmkdocs.yml\ntests\nupdate-subnetcalc-image-tags.sh'
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
