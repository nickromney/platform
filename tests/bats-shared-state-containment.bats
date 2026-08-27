#!/usr/bin/env bats
#
# The parallel Bats phase is only safe while every test that writes to the real
# checkout is named in SERIAL_ONLY_FILES in scripts/run-bats-suite.sh. That list
# was hand-maintained and the criterion lived only in a comment beside it, so it
# grew one entry at a time, each added after a race had already surfaced in a
# gate run. This asserts the criterion instead of restating it.
#
# The detector is a floor, not a guarantee: it reads writes spelled out in the
# .bats source and cannot follow `make -C <real dir>` or a script invoked with
# --execute. cilium-module-renderers is on the serial list for exactly that
# reason and this check cannot see why. So the invariant runs one way only --
# a detected writer must be contained -- and never the reverse.

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
}

@test "every Bats file writing to the real tree is contained in SERIAL_ONLY_FILES" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
import subprocess
from pathlib import Path

from tests.bats_shared_state import bats_files_writing_real_tree, exempt_files, serial_only_files

repo_root = Path(os.environ["REPO_ROOT"])
tracked = tuple(
    subprocess.run(
        ["git", "-C", str(repo_root), "ls-files", "*.bats"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.split()
)

offenders = bats_files_writing_real_tree(repo_root, tracked)
contained = set(serial_only_files(repo_root)) | set(exempt_files(repo_root))
uncontained = {name: lines for name, lines in offenders.items() if name not in contained}

if uncontained:
    for name, lines in sorted(uncontained.items()):
        print(f"{name} writes outside BATS_TEST_TMPDIR:")
        for line in lines:
            print(f"    {line}")
    print(
        "\nKeep the writes inside BATS_TEST_TMPDIR, which is the real fix;"
        "\nor add the file to SERIAL_ONLY_FILES in scripts/run-bats-suite.sh,"
        "\nwhich only removes the concurrency; or, if no other test can observe"
        "\nthe write, record it with its reason in"
        "\ntests/bats-shared-state-exemptions.txt."
    )

assert not uncontained, sorted(uncontained)
print(f"checked {len(tracked)} Bats files; {len(offenders)} write to the tree, all contained")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"all contained"* ]]
}

@test "SERIAL_ONLY_FILES names only files that exist" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.bats_shared_state import serial_only_files

repo_root = Path(os.environ["REPO_ROOT"])
listed = serial_only_files(repo_root)
assert listed, "SERIAL_ONLY_FILES parsed as empty, which would silence the check above"

missing = [name for name in listed if not (repo_root / name).is_file()]
assert not missing, missing
print(f"validated {len(listed)} serial-only entr(ies)")
PY

  [ "${status}" -eq 0 ]
}

@test "exemptions name files that exist and still write to the tree" {
  # A stale exemption is worse than none, because it silently permits a future
  # write. Both halves have to hold for the entry to still be honest.
  run uv run --isolated python - <<'PYEOF'
from __future__ import annotations

import os
from pathlib import Path

from tests.bats_shared_state import exempt_files, real_tree_writes

repo_root = Path(os.environ["REPO_ROOT"])
listed = exempt_files(repo_root)

missing = [name for name in listed if not (repo_root / name).is_file()]
assert not missing, f"exempted but absent from disk: {missing}"

stale = [name for name in listed if not real_tree_writes(repo_root / name)]
assert not stale, f"exempted but no longer writes to the tree, drop the entry: {stale}"

print(f"validated {len(listed)} exemption(s)")
PYEOF

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated"* ]]
}

@test "the detector reports writes to the tree and ignores reads of it" {
  # Both directions. A detector that never fires would keep this file green
  # while enforcing nothing, which is the failure mode worth guarding against.
  local sandbox="${BATS_TEST_TMPDIR}/probe"
  mkdir -p "${sandbox}"

  # Writes: literal, through a variable, and via a redirect.
  cat >"${sandbox}/writer.bats" <<'EOF'
@test "plants a fixture" {
  rm -rf "${REPO_ROOT}/apps/zz-probe"
  mkdir -p "${REPO_ROOT}/apps/zz-probe"
}
EOF
  cat >"${sandbox}/aliased.bats" <<'EOF'
setup() {
  export RUN_DIR="${REPO_ROOT}/.run/probe"
}
@test "writes through a name" {
  rm -rf "${RUN_DIR}"
}
EOF
  cat >"${sandbox}/redirect.bats" <<'EOF'
@test "redirects into the tree" {
  printf 'x\n' >"${REPO_ROOT}/apps/zz-probe.txt"
}
EOF

  # Reads: the sandboxing idiom, where REPO_ROOT is the source and the
  # destination is the test's own tmpdir. These must not be flagged.
  cat >"${sandbox}/reader.bats" <<'EOF'
@test "copies out of the tree into a sandbox" {
  cp "${REPO_ROOT}/Makefile" "${BATS_TEST_TMPDIR}/Makefile"
  cp -R "${REPO_ROOT}/scripts/hooks" "${BATS_TEST_TMPDIR}/hooks"
  ln -s "${REPO_ROOT}/scripts/lib/shell-cli.sh" "${BATS_TEST_TMPDIR}/shell-cli.sh"
  run grep -n 'thing' "${REPO_ROOT}/Makefile"
  echo "checked ${REPO_ROOT}/Makefile" >&2
}
EOF

  run env PROBE_DIR="${sandbox}" uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.bats_shared_state import real_tree_writes

probe = Path(os.environ["PROBE_DIR"])

for name in ("writer.bats", "aliased.bats", "redirect.bats"):
    found = real_tree_writes(probe / name)
    assert found, f"{name} writes to the tree but was not reported"

reads = real_tree_writes(probe / "reader.bats")
assert not reads, f"reader.bats only reads the tree but was reported: {reads}"

print("detector reports writes and ignores reads")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"detector reports writes and ignores reads"* ]]
}
