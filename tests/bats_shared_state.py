"""Find Bats files that write into the real repo tree instead of BATS_TEST_TMPDIR.

Why this exists
---------------
`scripts/run-bats-suite.sh` keeps a hand-maintained `SERIAL_ONLY_FILES` list. The
criterion is stated in a comment there -- a test writing outside its own
BATS_TEST_TMPDIR -- but nothing enforced it, so the list only grew when a race
surfaced in a gate run and someone went looking. Every entry on it so far was
added after it bit. This turns that criterion into something checkable.

What it covers, and what it does not
------------------------------------
This finds filesystem writes spelled out *in the .bats file itself*: redirects,
mkdir, rm, touch, sed -i, cp/mv/ln destinations, whose target is a path under
the real checkout.

It deliberately does not try to follow `make -C <real dir>` or a script invoked
with `--execute`. Those can write anywhere, and deciding statically whether they
do is not tractable -- the cilium renderer entry on the serial list is exactly
that shape: the .bats file writes nothing, and `render-category.sh --execute`
rewrites checked-in policy files underneath it. So a clean result here means
"no test writes to the tree in its own source", not "no test writes to the
tree". Treat it as a floor, not a guarantee.
"""

from __future__ import annotations

import re
from pathlib import Path

# A path expression rooted at the real checkout. Tests that stay inside their
# sandbox reference BATS_TEST_TMPDIR or a variable derived from it instead.
_REAL_TREE = re.compile(r'"?\$\{?REPO_ROOT\}?/')

# Commands where every path argument is written to.
_WRITES_ALL_ARGS = ("mkdir", "rm", "rmdir", "touch", "truncate")

# Commands where only the final argument is the destination; the earlier ones
# are sources, which is how the sandboxing tests legitimately read the tree
# (cp "${REPO_ROOT}/Makefile" "${sandbox}/Makefile").
_WRITES_LAST_ARG = ("cp", "mv", "ln", "install")


# foo="${REPO_ROOT}/apps/x", with or without export/local/readonly in front.
_REAL_TREE_ASSIGNMENT = re.compile(
    r'^(?:export|local|readonly|declare)?\s*([A-Za-z_][A-Za-z0-9_]*)=("?\$\{?REPO_ROOT\}?/[^\s;]*)'
)


def _strip_quotes(token: str) -> str:
    return token.strip().strip('"').strip("'")


def _real_tree_aliases(lines: list[str]) -> set[str]:
    """Variables a file assigns a path under the real checkout.

    Writing through a name is the more idiomatic spelling -- idp-core-components
    sets PLATFORM_IDP_RUN_DIR="${REPO_ROOT}/.run/..." and then removes
    "${PLATFORM_IDP_RUN_DIR}" -- so matching only the literal ${REPO_ROOT}/
    would miss the majority of real cases.
    """
    aliases: set[str] = set()

    for raw_line in lines:
        match = _REAL_TREE_ASSIGNMENT.match(raw_line.strip())
        if match is not None:
            aliases.add(match.group(1))

    return aliases


def _is_real_tree(token: str, aliases: frozenset[str] = frozenset()) -> bool:
    if _REAL_TREE.search(token):
        return True

    return any(re.search(r"\$\{?" + re.escape(alias) + r"\}?(/|\b)", token) for alias in aliases)


def _redirect_targets(line: str, aliases: frozenset[str]) -> list[str]:
    """Targets of > and >> redirections, ignoring >&2 and 2>/dev/null."""
    targets = [m.group(1) for m in re.finditer(r'>>?\s*("?[^\s;)|&]+"?)', line)]
    return [t for t in targets if _is_real_tree(t, aliases)]


def _command_write_targets(line: str, aliases: frozenset[str]) -> list[str]:
    targets: list[str] = []
    # Split on shell separators so `mkdir -p x && cp a b` is two commands.
    for segment in re.split(r"&&|\|\||;|\|", line):
        tokens = segment.split()
        if not tokens:
            continue

        # Step past `run`, `env FOO=bar`, and sudo-style prefixes.
        index = 0
        while index < len(tokens) and (
            tokens[index] in ("run", "env", "!", "time") or "=" in tokens[index].split("/")[0]
        ):
            index += 1
        if index >= len(tokens):
            continue

        command = Path(_strip_quotes(tokens[index])).name
        arguments = [token for token in tokens[index + 1 :] if not token.startswith("-")]
        if not arguments:
            continue

        # sed only writes with -i; without it the file is a source.
        edits_in_place = command == "sed" and any(token.startswith("-i") for token in tokens[index + 1 :])
        writes_every_argument = command in _WRITES_ALL_ARGS or command == "tee" or edits_in_place

        if writes_every_argument:
            targets.extend(argument for argument in arguments if _is_real_tree(argument, aliases))
        elif command in _WRITES_LAST_ARG and _is_real_tree(arguments[-1], aliases):
            targets.append(arguments[-1])

    return targets


_HEREDOC_OPEN = re.compile(r"<<-?\s*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?")


def real_tree_writes(path: Path) -> tuple[str, ...]:
    """Lines in one .bats file that write to the real checkout, as "line:text".

    Heredoc bodies are payload, not commands the test runs, so they are skipped.
    The write is the redirection on the opening line -- `cat >"${target}" <<EOF`
    is caught there -- while the body is the bytes being written. Reading bodies
    as code misreads any test that embeds an example: this module's own test
    file writes fixture .bats content containing `mkdir -p "${REPO_ROOT}/..."`
    into a sandbox, and scanning it as code reported the checker itself.
    """
    findings: list[str] = []

    lines = path.read_text(encoding="utf-8").splitlines()
    aliases = frozenset(_real_tree_aliases(lines))
    delimiter: str | None = None

    for line_no, raw_line in enumerate(lines, start=1):
        if delimiter is not None:
            if raw_line.strip() == delimiter:
                delimiter = None
            continue

        line = raw_line.strip()
        opened = _HEREDOC_OPEN.search(line)
        if opened is not None:
            delimiter = opened.group(1)

        if not line or line.startswith("#"):
            continue

        targets = _redirect_targets(line, aliases) + _command_write_targets(line, aliases)
        if targets:
            findings.append(f"{line_no}:{line}")

    return tuple(findings)


def bats_files_writing_real_tree(repo_root: Path, bats_files: tuple[str, ...]) -> dict[str, tuple[str, ...]]:
    """Map each given .bats file that writes to the checkout to the offending lines."""
    offenders: dict[str, tuple[str, ...]] = {}

    for relative in bats_files:
        path = repo_root / relative
        if not path.is_file():
            continue
        writes = real_tree_writes(path)
        if writes:
            offenders[relative] = writes

    return offenders


def exempt_files(repo_root: Path) -> tuple[str, ...]:
    """Files acknowledged in tests/bats-shared-state-exemptions.txt.

    Writing outside BATS_TEST_TMPDIR is a proxy for the real question, which is
    whether another test can observe the write. Entries here are the cases where
    that answer is no and the reason is written down.
    """
    listing = repo_root / "tests" / "bats-shared-state-exemptions.txt"
    if not listing.is_file():
        return ()

    return tuple(
        line.strip()
        for line in listing.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    )


def serial_only_files(repo_root: Path) -> tuple[str, ...]:
    """The SERIAL_ONLY_FILES list as run-bats-suite.sh defines it."""
    script = (repo_root / "scripts" / "run-bats-suite.sh").read_text(encoding="utf-8")
    match = re.search(r'SERIAL_ONLY_FILES="\$\{BATS_SERIAL_ONLY_FILES:-(.*?)\}"', script, re.DOTALL)
    if match is None:
        raise AssertionError("could not find SERIAL_ONLY_FILES in scripts/run-bats-suite.sh")

    return tuple(line.strip() for line in match.group(1).splitlines() if line.strip())
