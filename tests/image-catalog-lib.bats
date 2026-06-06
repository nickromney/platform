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

@test "source tags cache repeated equivalent fingerprint sources" {
  source_dir="${BATS_TEST_TMPDIR}/sources"
  test_bin="${BATS_TEST_TMPDIR}/bin"
  find_log="${BATS_TEST_TMPDIR}/find.log"
  catalog="${BATS_TEST_TMPDIR}/image-catalog.json"
  real_find="$(command -v find)"
  mkdir -p "${source_dir}" "${test_bin}"
  printf 'same input\n' >"${source_dir}/file.txt"

  cat >"${catalog}" <<JSON
{
  "namespace": "platform",
  "platform_images": [
    {
      "id": "first",
      "image_name": "first",
      "default_tag": "0.1.0",
      "fingerprint_sources": ["${source_dir}"]
    },
    {
      "id": "second",
      "image_name": "second",
      "default_tag": "0.1.0",
      "fingerprint_sources": ["${source_dir}"]
    }
  ],
  "workload_images": []
}
JSON

  cat >"${test_bin}/find" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >>"${find_log}"
exec "${real_find}" "\$@"
EOF
  chmod +x "${test_bin}/find"

  run bash -lc "
    set -euo pipefail
    export REPO_ROOT='${REPO_ROOT}'
    export IMAGE_CATALOG_FILE='${catalog}'
    export PATH='${test_bin}:'\"\${PATH}\"
    source '${REPO_ROOT}/kubernetes/workflow/image-catalog-lib.sh'
    first_tag=\"\$(image_catalog_source_tag platform first)\"
    second_tag=\"\$(image_catalog_source_tag platform second)\"
    [ \"\${first_tag}\" = \"\${second_tag}\" ]
  "

  [ "${status}" -eq 0 ]
  find_calls="$(wc -l <"${find_log}" | tr -d ' ')"
  [ "${find_calls}" -eq 1 ]
}
