"""Assert every GitHub Action in a workflow directory is pinned to a commit SHA.

Extracted so the rule and the tests that police the rule run the same code. A
negative fixture checked by a re-implementation proves nothing about the real
check.

Usage: python workflow-pin-check.py <workflows-dir>
Exits non-zero with a message naming the file and action that violates it.
"""

import re
import sys
from pathlib import Path

USES = re.compile(r"uses:[ \t]*(\S+)(?:[ \t]*#[ \t]*(\S+))?")
SHA = re.compile(r"[0-9a-f]{40}")
VERSION_COMMENT = re.compile(r"v\d[\w.\-]*")


def check(directory: Path) -> int:
    workflows = sorted(directory.glob("*.yml"))
    if not workflows:
        print(f"no workflows found in {directory}", file=sys.stderr)
        return 1

    checked = 0
    for path in workflows:
        for line in path.read_text(encoding="utf-8").splitlines():
            match = USES.search(line)
            if not match:
                continue
            ref, comment = match.group(1), match.group(2)
            # Local composite actions are referenced by path and have no SHA.
            if ref.startswith("./"):
                continue
            checked += 1
            repo, sep, version = ref.partition("@")
            if not sep:
                print(f"{path.name}: {ref} is not pinned at all", file=sys.stderr)
                return 1
            if not SHA.fullmatch(version):
                print(
                    f"{path.name}: {repo} is pinned to {version!r}, "
                    "not a 40-character commit SHA",
                    file=sys.stderr,
                )
                return 1
            if not (comment and VERSION_COMMENT.fullmatch(comment)):
                print(
                    f"{path.name}: {repo} is pinned to a SHA but carries no "
                    "readable # vX.Y.Z comment",
                    file=sys.stderr,
                )
                return 1

    if not checked:
        print("no third-party actions found; the rule would pass vacuously", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(check(Path(sys.argv[1])))
