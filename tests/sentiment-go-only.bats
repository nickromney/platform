#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "sentiment app tree contains only the canonical Go app surface" {
  run bash -lc "cd '${REPO_ROOT}' && ls -A apps/sentiment | sort"

  [ "${status}" -eq 0 ]
  expected=$'.gitea\nMODEL_CARD.md\nMakefile\nREADME.md\napp-go\ncatalog-info.yaml\ncompose.apim-ai-gateway.yml\ncompose.tls.yml\ncompose.yml\ndata\ndocs\nedge\nevaluation.jsonl\nkeycloak\nmkdocs.yml\npki\ntests\ntls-proxy\nupdate-sentiment-image-tags.sh'
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
    assert build.get("context") == "apps/sentiment/app-go", image
    assert build.get("dockerfile") == "Dockerfile", image
    assert not any(path in json.dumps(image) for path in retired_paths), image
PY

  [ "${status}" -eq 0 ]
}
