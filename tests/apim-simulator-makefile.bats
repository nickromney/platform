#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
  export APIM_ROOT="${REPO_ROOT}/apps/apim-simulator"
}

@test "apim simulator make help exposes Go app workflow" {
  run make -C "${APIM_ROOT}" help

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"App:"* ]]
  [[ "${output}" == *"update"* ]]
  [[ "${output}" == *"No dependency locks are managed at this wrapper level"* ]]
}

@test "apim simulator update is a Go-only no-op" {
  run make -n -C "${APIM_ROOT}" update

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"apim-simulator: Go-only app; no package-manager locks to update"* ]]
}

@test "apim simulator app js-check uses Biome and Deno without npm manifests" {
  # Static on purpose. This used to run `make app-js-check`, which executes
  # biome -- a tool the repo pins nowhere, does not install in CI, and which is
  # absent from this host. Executing it can only ever pass on a machine that
  # happens to have it, which is the non-hermetic class section 1 documents.
  # The contract worth guarding is which tools the recipe uses and which assets
  # it covers, and that is readable without running anything.
  #
  # It also expected internal/app/web/style.css, which does not exist and is not
  # in GO_APP_WEB_ASSETS. That went unnoticed because the file never ran.
  app_makefile="${APIM_ROOT}/app/Makefile"
  core_makefile="${REPO_ROOT}/mk/go-app-core.mk"

  run grep -n '^GO_APP_WEB_ASSETS := internal/app/web/app.js internal/app/web/api-types.d.ts internal/app/web/index.html$' "${app_makefile}"
  [ "${status}" -eq 0 ]

  run grep -n '^	biome check \$(GO_APP_WEB_ASSETS)$' "${core_makefile}"
  [ "${status}" -eq 0 ]

  run grep -n '^	deno check --check-js internal/app/web/app.js$' "${core_makefile}"
  [ "${status}" -eq 0 ]

  # Every asset named must actually exist, which is what the stale style.css
  # entry would have failed.
  for asset in app.js api-types.d.ts index.html; do
    [ -f "${APIM_ROOT}/app/internal/app/web/${asset}" ]
  done

  [ ! -e "${APIM_ROOT}/app/package.json" ]
  [ ! -e "${APIM_ROOT}/app/internal/app/web/package.json" ]
}
