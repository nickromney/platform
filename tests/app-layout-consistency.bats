#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "in-scope Go apps expose the canonical app layout" {
  run python3 - <<PY
from pathlib import Path

repo = Path("${REPO_ROOT}")
apps = {
    "chatgpt-sim": {"keycloak": False},
    "idp-core": {"keycloak": False},
    "platform-mcp": {"keycloak": False},
    "sentiment": {"keycloak": True},
    "subnetcalc": {"keycloak": False},
}

for name, spec in apps.items():
    root = repo / "apps" / name
    for child in [".gitea", "app", "tests", "compose.yml"]:
        assert (root / child).exists(), f"{name} missing {child}"
    assert not (root / "app-go").exists(), f"{name} still exposes app-go"
    assert (root / "app" / "go.mod").exists(), f"{name} app is not Go"
    assert (root / "app" / "Dockerfile").exists(), f"{name} missing app Dockerfile"
    if spec["keycloak"]:
        assert (root / "keycloak").exists(), f"{name} missing keycloak"

idp = repo / "apps" / "idp-core"
for retired in ["pyproject.toml", "uv.lock"]:
    assert not (idp / retired).exists(), f"idp-core still has {retired}"
for retired in ["__init__.py", "main.py", "models.py"]:
    assert not (idp / "app" / retired).exists(), f"idp-core app still has Python {retired}"

print(f"validated {len(apps)} canonical Go app layout(s)")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated 5 canonical Go app layout(s)"* ]]
}

@test "in-scope Go app image catalog entries point at canonical app directories" {
  run python3 - <<PY
import json
from pathlib import Path

repo = Path("${REPO_ROOT}")
catalog = json.loads((repo / "kubernetes/workflow/image-catalog.json").read_text(encoding="utf-8"))
expected = {
    "chatgpt-sim",
    "idp-core",
    "platform-mcp",
    "sentiment-api",
    "sentiment-auth-ui",
    "subnetcalc-api",
    "subnetcalc-frontend",
}
images = {image["id"]: image for image in catalog["workload_images"] + catalog["platform_images"]}
for image_id in expected:
    image = images[image_id]
    context = image.get("build", {}).get("context", "")
    prebuild = image.get("build", {}).get("prebuild", "")
    if image_id == "idp-core":
        assert context == ".", image
        assert "apps/idp-core/app build-linux" in prebuild, image
    else:
        app_name = image_id
        if image_id.startswith("sentiment-"):
            app_name = "sentiment"
        elif image_id.startswith("subnetcalc-"):
            app_name = "subnetcalc"
        assert context == f"apps/{app_name}/app", image
        assert f"apps/{app_name}/app build-linux" in prebuild, image
    assert "app-go" not in json.dumps(image), image

print(f"validated {len(expected)} canonical image catalog entry(ies)")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated 7 canonical image catalog entry(ies)"* ]]
}
