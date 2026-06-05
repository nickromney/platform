#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "source tags explain missing fingerprint sources by catalog entry" {
  catalog="${BATS_TEST_TMPDIR}/image-catalog.json"
  cat >"${catalog}" <<'JSON'
{
  "namespace": "platform",
  "platform_images": [
    {
      "id": "missing-app",
      "image_name": "missing-app",
      "default_tag": "0.1.0",
      "fingerprint_sources": ["missing/source/path"]
    }
  ],
  "workload_images": []
}
JSON

  run bash -lc "
    set -euo pipefail
    export REPO_ROOT='${REPO_ROOT}'
    export IMAGE_CATALOG_FILE='${catalog}'
    source '${REPO_ROOT}/kubernetes/workflow/image-catalog-lib.sh'
    image_catalog_source_tag platform missing-app
  "

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"platform.missing-app fingerprint source not found: missing/source/path"* ]]
}

@test "source tags fail when the catalog image id is unknown" {
  catalog="${BATS_TEST_TMPDIR}/image-catalog.json"
  cat >"${catalog}" <<'JSON'
{
  "namespace": "platform",
  "platform_images": [],
  "workload_images": []
}
JSON

  run bash -lc "
    set -euo pipefail
    export REPO_ROOT='${REPO_ROOT}'
    export IMAGE_CATALOG_FILE='${catalog}'
    source '${REPO_ROOT}/kubernetes/workflow/image-catalog-lib.sh'
    image_catalog_source_tag platform unknown-app
  "

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"platform.unknown-app not found in image catalog"* ]]
}
