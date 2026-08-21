# Bash Mutation Testing

Bats suites tell you a function was executed. They do not tell you the
assertions would notice if the function stopped working. Mutation testing
answers the second question: change one operator in the script, run the suite,
and see whether anything fails.

A mutant that makes the suite fail is *killed*. A mutant the suite still passes
*survived*, and points at an assertion gap on that exact line.

## Running it

```bash
make mutation SCRIPT=scripts/lib/semver.sh
```

That plans only: it generates the mutants, reports how many are valid, and
touches nothing. To run the cycle:

```bash
make mutation-execute SCRIPT=scripts/lib/semver.sh
```

`mutation-execute` exits non-zero when mutants survive. Add
`MUTATION_ARGS=--no-fail` while triaging, which is how the baseline below was
measured.

The runner is [`scripts/mutation-test.sh`](../scripts/mutation-test.sh); the
generation and parsing engine is
[`scripts/lib/mutation.sh`](../scripts/lib/mutation.sh), covered by
[`tests/mutation-lib.bats`](../tests/mutation-lib.bats).

### Choosing the oracle

By default the runner uses `tests/<script-stem>*.bats`. When the suite is named
after something else, name it explicitly:

```bash
scripts/mutation-test.sh --script scripts/lib/shell-cli.sh \
  --bats tests/audit-shell-scripts.bats --execute --no-fail
```

### Safety

Mutants are applied to the working-tree file one at a time and restored after
each run, under an `EXIT`/`INT`/`TERM` trap, so an interrupted run cannot leave
a mutated script behind. The run refuses to start if the suite does not already
pass on the unmutated script. Reports land in `.run/mutation/<stem>/`, which is
git-ignored.

## Operators

| Operator | Mutation |
|---|---|
| `LOGICAL_AND_OR` | `&&` <-> `\|\|` |
| `NUMERIC_COMPARE` | `-eq` <-> `-ne` |
| `BOUNDARY_CHECK` | `-lt` <-> `-le`, `-gt` <-> `-ge` |
| `STRING_COMPARE` | `==` <-> `!=` |
| `BOOLEAN_LITERAL` | `true` <-> `false` |
| `RETURN_CODE` | `return 0` <-> `return 1` |
| `NEGATION_DROP` | standalone `!` removed |
| `ARITH_STEP` | `++` <-> `--` |

Comments, heredoc bodies, and identifiers that merely contain a keyword are not
mutated. Mutants that fail `bash -n` are excluded from the score rather than
counted as killed.

## Baseline for `scripts/lib/`

Score = killed / (killed + survived). Timeouts count as killed.

| Script | Valid mutants | Killed | Survived | Score | Oracle |
|---|---|---|---|---|---|
| `semver.sh` | 3 | 3 | 0 | 100% | `tests/semver-lib.bats` |
| `http-fetch.sh` | 13 | 11 | 2 | 85% (2 accepted equivalents) | `tests/http-fetch.bats` |
| `mutation.sh` | 30 | 19 | 11 | 63% | `tests/mutation-lib.bats` |
| `host-port-listeners.sh` | 50 | 28 | 22 | 56% | `tests/host-port-listeners.bats` |
| `parallel.sh` | 9 | 5 | 4 | 55% | `tests/parallel.bats` |
| `timeout.sh` | 6 | 2 | 4 | 33% (4 accepted equivalents) | `tests/timeout-lib.bats` |
| `shell-cli.sh` | 16 | 7 | 9 | 44% | `tests/audit-shell-scripts.bats` |
| `shell-cli-posix.sh` | — | — | — | untested | none |
| `compose-cli.sh` | — | — | — | untested | none |

## Accepted equivalents

Some mutants change the source without changing any behaviour an honest test
could observe. Those are recorded next to the tests that would otherwise be
expected to kill them, never silently dropped from the score.

- `timeout.sh:41-42` — the `|| true` guards on `kill` and `wait` in the expiry
  branch. Both are builtins, so PATH shims cannot reach them, and manufacturing
  their failure needs a race whose failure mode hangs the unmutated code too.
- `http-fetch.sh:118` — `shift || true` in `http_status_code`. Bash exempts the
  left of an `&&` list from errexit, and every real caller reads the value back
  through `"$(...)"`, where errexit does not apply either. The survivors are
  really saying the guard covers a case callers cannot reach.

## What the survivors keep saying

- **`RETURN_CODE` flips dominate.** Early-return and error paths get executed by
  the suites but their exit status is never asserted. The usual cause is a bats
  line like `helper out; test "${out}" = x`, where only the trailing `test`
  decides the status. Chaining with `&&` instead of `;` killed seven mutants in
  `http-fetch.sh` alone.
- **`LOGICAL_AND_OR` survives in guard clauses** whose bail-out branch no test
  ever drives.
- **`BOUNDARY_CHECK` needs an exact-boundary input.** `timeout.sh`'s fallback
  `-ge` was only killed once a stubbed clock landed a poll on
  `elapsed == seconds` exactly; anything else passes under both `-ge` and `-gt`.

## Attack order for the remaining gaps

1. `http-fetch.sh` — done; 15% -> 85%.
2. `timeout.sh` — done; the boundary mutant is killed and the rest are
   documented equivalents.
3. `parallel.sh` and `host-port-listeners.sh` — mid scores, mostly guard
   branches that are never driven to bail out.
4. `shell-cli.sh` — the oracle is an audit suite rather than a unit suite, which
   is why the score is low and the runs are slow.
5. `compose-cli.sh`, `shell-cli-posix.sh` — write a first bats suite before any
   refactoring. Mutation testing says nothing without an oracle.
6. `mutation.sh` — keep at or above 63% as operators evolve; it gates itself.

Per file: strengthen assertions until the score plateaus, only then split
functions toward do-one-thing, and re-mutate to confirm no behaviour drifted.
