#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "canonical browser apps use Biome lint-format and Deno semantic checks" {
  run make -C "${REPO_ROOT}/apps/chatgpt-sim/app" js-check
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"biome check internal/app/web/app.js internal/app/web/api-types.d.ts"* ]]
  [[ "${output}" == *"deno check --check-js internal/app/web/app.js"* ]]

  run make -C "${REPO_ROOT}/apps/subnetcalc/app" js-check
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"biome check internal/app/web/app.js internal/app/web/api-types.d.ts"* ]]
  [[ "${output}" == *"deno check --check-js internal/app/web/app.js"* ]]

  run make -C "${REPO_ROOT}/apps/sentiment/app" js-check
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"biome check internal/app/web/app.js internal/app/web/api-types.d.ts"* ]]
  [[ "${output}" == *"deno check --check-js internal/app/web/app.js"* ]]
}

@test "checked JavaScript app roots do not introduce package-manager manifests" {
  run bash -lc "cd '${REPO_ROOT}' && find apps/chatgpt-sim/app apps/subnetcalc/app apps/sentiment/app -maxdepth 2 \\( -name package.json -o -name package-lock.json -o -name yarn.lock -o -name pnpm-lock.yaml -o -name bun.lock -o -name bun.lockb -o -name node_modules \\) -print"

  [ "${status}" -eq 0 ]
  [ "${output}" = "" ]
}

@test "browser JavaScript declares checked source and app-local API types" {
  run bash -lc "cd '${REPO_ROOT}' && for app in chatgpt-sim subnetcalc sentiment; do test \"\$(sed -n '1p' apps/\${app}/app/internal/app/web/app.js)\" = '// @ts-check'; test -f apps/\${app}/app/internal/app/web/api-types.d.ts; done"

  [ "${status}" -eq 0 ]
}

@test "browser apps share the same app-folder color tokens" {
  run bash -lc "cd '${REPO_ROOT}' && for app in chatgpt-sim subnetcalc sentiment; do css=apps/\${app}/app/internal/app/web/style.css; grep -q -- '--page: #f6f8fb;' \"\${css}\"; grep -q -- '--surface: #ffffff;' \"\${css}\"; grep -q -- '--field: #ffffff;' \"\${css}\"; grep -q -- '--border: #cfdae6;' \"\${css}\"; grep -q -- '--field-border: #b9c5d3;' \"\${css}\"; grep -q -- '--text: #17202a;' \"\${css}\"; grep -q -- '--accent: #2459b2;' \"\${css}\"; grep -q -- '--page: #101418;' \"\${css}\"; grep -q -- '--surface: #151b21;' \"\${css}\"; grep -q -- '--field: #0f1419;' \"\${css}\"; grep -q -- '--border: #2d3945;' \"\${css}\"; grep -q -- '--field-border: #3a4855;' \"\${css}\"; grep -q -- '--text: #e8eef4;' \"\${css}\"; grep -q -- '--accent: #2d6cdf;' \"\${css}\"; done"

  [ "${status}" -eq 0 ]
}

@test "browser app headers expose the shared auth and theme controls" {
  run bash -lc "cd '${REPO_ROOT}' && for app in chatgpt-sim subnetcalc sentiment; do html=apps/\${app}/app/internal/app/web/index.html; grep -q 'data-theme=\"system\"' \"\${html}\"; grep -q 'id=\"auth-state\"' \"\${html}\"; grep -q 'id=\"logout-btn\"' \"\${html}\"; grep -q 'id=\"theme-switcher\"' \"\${html}\"; done"

  [ "${status}" -eq 0 ]
}
