#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "app repo source projection excludes generated working directories" {
  local source_dir target_dir
  source_dir="${BATS_TEST_TMPDIR}/source"
  target_dir="${BATS_TEST_TMPDIR}/target"

  mkdir -p \
    "${source_dir}/app/internal" \
    "${source_dir}/app/.run/build" \
    "${source_dir}/apim-simulator/.run/cache" \
    "${source_dir}/frontend/node_modules/pkg" \
    "${source_dir}/api/.venv/lib" \
    "${source_dir}/api/.pytest_cache" \
    "${source_dir}/api/.ruff_cache" \
    "${source_dir}/.git/objects"

  printf 'package app\n' >"${source_dir}/app/internal/app.go"
  printf 'generated\n' >"${source_dir}/app/.run/build/output"
  printf 'generated\n' >"${source_dir}/apim-simulator/.run/cache/blob"
  printf 'dependency\n' >"${source_dir}/frontend/node_modules/pkg/index.js"
  printf 'dependency\n' >"${source_dir}/api/.venv/lib/site.py"
  printf 'cache\n' >"${source_dir}/api/.pytest_cache/CACHEDIR.TAG"
  printf 'cache\n' >"${source_dir}/api/.ruff_cache/CACHEDIR.TAG"
  printf 'git\n' >"${source_dir}/.git/objects/blob"

  # shellcheck source=/dev/null
  source "${REPO_ROOT}/terraform/kubernetes/scripts/sync-gitea-app-repo.sh"

  copy_app_repo_source_dir "${source_dir}" "${target_dir}"

  [ -f "${target_dir}/app/internal/app.go" ]
  [ ! -e "${target_dir}/app/.run" ]
  [ ! -e "${target_dir}/apim-simulator/.run" ]
  [ ! -e "${target_dir}/frontend/node_modules" ]
  [ ! -e "${target_dir}/api/.venv" ]
  [ ! -e "${target_dir}/api/.pytest_cache" ]
  [ ! -e "${target_dir}/api/.ruff_cache" ]
  [ ! -e "${target_dir}/.git" ]
}

@test "app repo content hashes ignore generated working directories" {
  run rg -n \
    'app_repo_sync_excluded_path_segments|setintersection\(toset\(split\("/", f\)\), local\.app_repo_sync_excluded_path_segments\)' \
    "${REPO_ROOT}/terraform/kubernetes/locals.tf"

  [ "${status}" -eq 0 ]
}
