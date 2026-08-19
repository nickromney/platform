#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
  export SCRIPT="${REPO_ROOT}/scripts/check-bash32-compat.sh"
}

@test "check-bash32-compat passes a Bash 3.2-compatible script" {
  candidate="${BATS_TEST_TMPDIR}/ok.sh"

  cat >"${candidate}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

values=()
values+=("ok")
printf '%s\n' "${values[@]}"
EOF

  run /bin/bash "${SCRIPT}" --execute "${candidate}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"OK   Bash 3.2 compatibility"* ]]
}

@test "check-bash32-compat reports Bash 4-only constructs" {
  candidate="${BATS_TEST_TMPDIR}/bad.sh"

  cat >"${candidate}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

local -A seen=()
mapfile -t values < <(printf '%s\n' one two)
EOF

  run /bin/bash "${SCRIPT}" --execute "${candidate}"

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"FAIL Bash 3.2 compatibility"* ]]
  [[ "${output}" == *"bad.sh:4:local -A seen=()"* ]]
  [[ "${output}" == *"bad.sh:5:mapfile -t values"* ]]
}

@test "check-bash32-compat scans makefiles, not just shell scripts" {
  # mk/common.mk and mk/go-app-core.mk pin SHELL := /bin/bash, so recipes in
  # every Makefile that includes them are Bash under test -- 5.x on Arch, 3.2 on
  # macOS. Scanning only *.sh meant a Bash 4-only recipe would pass every Linux
  # check and break on the Mac, which is the exact class this check exists for.
  #
  # The path passed below is a DIRECTORY, and that is the whole point. An
  # explicit *file* path bypasses the glob entirely -- append_scan_path appends
  # it verbatim -- so a file-path version of this test passes against the old
  # *.sh-only script too, and proves nothing. Only the directory walk exercises
  # the name filter that this change widened. Verified by running both scripts
  # against both forms.
  scan_dir="${BATS_TEST_TMPDIR}/tree"
  mkdir -p "${scan_dir}"
  candidate="${scan_dir}/Makefile"

  cat >"${candidate}" <<'EOF'
SHELL := /bin/bash

.PHONY: demo
demo:
	@set -euo pipefail; \
	mapfile -t names < <(printf '%s\n' one two); \
	printf '%s\n' "${names[@]}"
EOF

  run /bin/bash "${SCRIPT}" --execute "${scan_dir}"

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"mapfile"* ]]
  [[ "${output}" == *"Makefile"* ]]
}

@test "check-bash32-compat includes tracked makefiles in the default scan set" {
  # Asserts the default set actually grew, so narrowing build_tracked_shell_script_list
  # back to '*.sh' fails here rather than silently restoring the blind spot.
  sh_count="$(git -C "${REPO_ROOT}" ls-files -- '*.sh' | wc -l | tr -d ' ')"
  mk_count="$(git -C "${REPO_ROOT}" ls-files -- 'Makefile' '*/Makefile' '*.mk' | wc -l | tr -d ' ')"

  [ "${mk_count}" -gt 0 ]

  run /bin/bash "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"$((sh_count + mk_count)) script(s) scanned"* ]]
}
