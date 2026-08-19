#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
  export DOCS_SITE="${REPO_ROOT}/sites/docs"
}

@test "docs site lives under sites/docs with source content" {
  [ -d "${DOCS_SITE}" ]
  [ -f "${DOCS_SITE}/package.json" ]
  [ -f "${DOCS_SITE}/README.md" ]
  [ -d "${DOCS_SITE}/content" ]
  [ -d "${DOCS_SITE}/diagrams/d2" ]
}

@test "docs site import excludes build artifacts and vendored dependencies" {
  # Asks git what was imported, not the filesystem. These paths are all
  # gitignored, so the old on-disk checks failed on any machine that had run
  # `make -C sites/docs build` and passed on a clean CI checkout -- the
  # host-dependence of section 1, pointing at the developer rather than at CI.
  # The claim is about what the import committed, which only git can answer.
  local artifact
  for artifact in .git .next node_modules .run .playwright-mcp tsconfig.tsbuildinfo; do
    run git -C "${REPO_ROOT}" ls-files -- "sites/docs/${artifact}"
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
  done
}

@test "docs site does not carry generated video outputs" {
  run git -C "${REPO_ROOT}" ls-files -- \
    'sites/docs/**/*.mp4' 'sites/docs/**/*.mov' 'sites/docs/**/*.webm'
  [ "${status}" -eq 0 ]
  [ "${output}" = "" ]
}

@test "docs site non-text assets are D2 SVGs or app chrome" {
  # Tracked files only. `find` walked into node_modules, where vendored
  # packages ship their own .png and .gif demo assets, so this failed on any
  # machine with dependencies installed and reported someone else's files.
  run git -C "${REPO_ROOT}" ls-files -- \
    'sites/docs/**/*.png' 'sites/docs/**/*.jpg' \
    'sites/docs/**/*.jpeg' 'sites/docs/**/*.gif'
  [ "${status}" -eq 0 ]
  [ "${output}" = "" ]
}

@test "docs site keeps D2 sources and excludes Remotion source by default" {
  run find "${DOCS_SITE}/diagrams/d2" -type f -name '*.d2' -print
  [ "${status}" -eq 0 ]
  [ -n "${output}" ]

  [ ! -d "${DOCS_SITE}/remotion" ]
  [ ! -f "${DOCS_SITE}/remotion.config.ts" ]
}

@test "docs site has validation scripts for content and diagrams" {
  run grep -E '"(lint:content|test:docs|check:d2|typecheck|build)"' "${DOCS_SITE}/package.json"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'"lint:content"'* ]]
  [[ "${output}" == *'"test:docs"'* ]]
  [[ "${output}" == *'"check:d2"'* ]]
  [[ "${output}" == *'"typecheck"'* ]]
  [[ "${output}" == *'"build"'* ]]
}

@test "docs Makefile build installs dependencies from a clean checkout" {
  # Static on purpose. This used to `rm -rf node_modules` and run
  # `make -C sites/docs build`, which is a real `bun install` over the network
  # followed by a Next.js build -- minutes of work, a network dependency, and
  # it destroyed the developer's installed dependencies on the way past. A test
  # in the hermetic subset cannot do that, and the contract it is checking is
  # the dependency wiring in the Makefile, which is readable without building.
  local makefile="${DOCS_SITE}/Makefile"

  run grep -n '^NODE_MODULES_STAMP := node_modules/\.bun-install\.stamp$' "${makefile}"
  [ "${status}" -eq 0 ]

  # The stamp rebuilds from the manifest and lockfile, which is what makes a
  # clean checkout install before building.
  run grep -n '^\$(NODE_MODULES_STAMP): package\.json bun\.lock$' "${makefile}"
  [ "${status}" -eq 0 ]

  # build depends on the stamp, so it can never run against absent deps.
  run grep -nE '^build: \$\(NODE_MODULES_STAMP\)' "${makefile}"
  [ "${status}" -eq 0 ]

  run bash -c "grep -A 2 '^\\\$(NODE_MODULES_STAMP): package.json bun.lock\$' '${makefile}'"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"bun install"* ]]

  run bash -c "grep -A 1 '^build: ' '${makefile}'"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"bun run build"* ]]
}
