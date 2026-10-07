#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
}

@test "every workflow pins its actions by commit SHA with a readable version" {
  # Asserts the rule, not the values. An earlier version of this test listed
  # the exact SHA each action was expected to carry, which made every
  # Dependabot bump a gate failure: #210 moved astral-sh/setup-uv to v10.0.1
  # and left main red, because the workflow and the test each stated the
  # version and only one of them was updated.
  #
  # The property worth protecting is that no action resolves to a mutable tag.
  # A SHA plus a `# vX.Y.Z` comment gives an immutable reference a human can
  # still read, and Dependabot rewrites both together, so this stays green
  # across bumps while still failing on an unpinned action.
  #
  # Covers every workflow, not just version-audit.yml. A supply-chain rule that
  # only holds in the file that audits supply chains is the wrong shape.
  run uv run --locked --project "${REPO_ROOT}" python "${REPO_ROOT}/tests/lib/workflow-pin-check.py" \
    "${REPO_ROOT}/.github/workflows"

  [ "${status}" -eq 0 ]
}

@test "the pin rule rejects a tag, a short sha, and a missing version comment" {
  # Without this, the rule above passes vacuously if its regex stops matching.
  # Each fixture violates exactly one clause.
  local dir="${BATS_TEST_TMPDIR}/wf"
  mkdir -p "${dir}"

  printf 'jobs:\n  a:\n    steps:\n      - uses: actions/checkout@v4\n' >"${dir}/tag.yml"
  run uv run --locked --project "${REPO_ROOT}" python "${REPO_ROOT}/tests/lib/workflow-pin-check.py" "${dir}"
  [ "${status}" -ne 0 ]

  rm -f "${dir}/tag.yml"
  printf 'jobs:\n  a:\n    steps:\n      - uses: actions/checkout@3d3c42e  # v7.0.1\n' >"${dir}/short.yml"
  run uv run --locked --project "${REPO_ROOT}" python "${REPO_ROOT}/tests/lib/workflow-pin-check.py" "${dir}"
  [ "${status}" -ne 0 ]

  rm -f "${dir}/short.yml"
  printf 'jobs:\n  a:\n    steps:\n      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1\n' >"${dir}/nocomment.yml"
  run uv run --locked --project "${REPO_ROOT}" python "${REPO_ROOT}/tests/lib/workflow-pin-check.py" "${dir}"
  [ "${status}" -ne 0 ]

  rm -f "${dir}/nocomment.yml"
  printf 'jobs:\n  a:\n    steps:\n      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1\n' >"${dir}/good.yml"
  run uv run --locked --project "${REPO_ROOT}" python "${REPO_ROOT}/tests/lib/workflow-pin-check.py" "${dir}"
  [ "${status}" -eq 0 ]
}

@test "version audits are explicit local commands rather than hosted verification" {
  [ ! -e "${REPO_ROOT}/.github/workflows/version-audit.yml" ]
  [ -x "${REPO_ROOT}/scripts/check-repo-version.sh" ]
  [ -x "${REPO_ROOT}/terraform/kubernetes/scripts/check-provider-version.sh" ]
  [ -x "${REPO_ROOT}/terraform/kubernetes/scripts/check-component-version.sh" ]
  grep -Fq 'check-version:' "${REPO_ROOT}/Makefile"
}
