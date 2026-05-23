#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "sentiment app tree contains only the canonical Go app surface" {
  run bash -lc "cd '${REPO_ROOT}' && ls -A apps/sentiment | sort"

  [ "${status}" -eq 0 ]
  expected=$'.gitea\nMODEL_CARD.md\nMakefile\nREADME.md\napp\ncatalog-info.yaml\ncompose.tls.yml\ncompose.yml\ndata\ndocs\nedge\nevaluation.jsonl\nmkdocs.yml\npki\ntests\ntls-proxy\nupdate-sentiment-image-tags.sh'
  [ "${output}" = "${expected}" ]
}

@test "sentiment image catalog builds only Go sentiment images" {
  run python3 - <<PY
import json
from pathlib import Path

repo = Path("${REPO_ROOT}")
catalog = json.loads((repo / "kubernetes/workflow/image-catalog.json").read_text(encoding="utf-8"))
sentiment = [image for image in catalog["workload_images"] if image["id"].startswith("sentiment-")]
retired_paths = ("api-sentiment", "frontend-react-vite", "frontend-typescript-vite")

assert {image["id"] for image in sentiment} == {"sentiment-api", "sentiment-auth-ui"}, sentiment
for image in sentiment:
    build = image.get("build", {})
    assert build.get("context") == "apps/sentiment/app", image
    assert build.get("dockerfile") == "Dockerfile", image
    assert not any(path in json.dumps(image) for path in retired_paths), image
PY

  [ "${status}" -eq 0 ]
}

@test "sentiment repo tooling does not point to retired Python or React app paths" {
  run rg -n 'apps/sentiment/(api-sentiment|frontend-react-vite|frontend-typescript-vite)|sentiment/(api-sentiment|frontend-react-vite|frontend-typescript-vite)' \
    "${REPO_ROOT}/scripts" \
    "${REPO_ROOT}/kubernetes" \
    "${REPO_ROOT}/terraform" \
    "${REPO_ROOT}/apps/sentiment" \
    --glob '!terraform/kubernetes/.terragrunt-cache/**'

  [ "${status}" -eq 1 ]
}

@test "current sentiment docs describe the shipped Go lexicon classifier path" {
  run rg -n "SST|sst|model endpoint|model-backed" \
    "${REPO_ROOT}/apps/sentiment/docs" \
    "${REPO_ROOT}/kubernetes/kind/docs" \
    "${REPO_ROOT}/terraform/kubernetes/cluster-policies/COMPOSITION.md" \
    "${REPO_ROOT}/terraform/kubernetes/cluster-policies/AUDIT.md" \
    --glob '!**/*.svg'

  [ "${status}" -eq 1 ]

  run rg -n "Go lexicon classifier|deterministic lexicon classifier" \
    "${REPO_ROOT}/apps/sentiment/docs" \
    "${REPO_ROOT}/kubernetes/kind/docs" \
    "${REPO_ROOT}/terraform/kubernetes/cluster-policies/COMPOSITION.md" \
    "${REPO_ROOT}/terraform/kubernetes/cluster-policies/AUDIT.md"

  [ "${status}" -eq 0 ]
}
