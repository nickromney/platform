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
  --bats tests/shell-cli-lib.bats --execute
```

Naming it matters more than it looks. The default glob for
`shell-cli.sh` is `tests/shell-cli*.bats`, which also matches
`tests/shell-cli-posix-lib.bats` -- a suite for a different library that
cannot kill a single one of its mutants. Left to the default, those runs
carry a second suite for nothing. Name the oracle explicitly for both
`shell-cli.sh` and `shell-cli-posix.sh`.

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
| `mutation.sh` | 30 | 29 | 1 | 97% (1 accepted equivalent) | `tests/mutation-lib.bats` |
| `host-port-listeners.sh` | 50 | 48 | 2 | 96% (2 accepted equivalents) | `tests/host-port-listeners.bats` |
| `parallel.sh` | 9 | 9 | 0 | 100% | `tests/parallel.bats` |
| `timeout.sh` | 6 | 2 | 4 | 33% (4 accepted equivalents) | `tests/timeout-lib.bats` |
| `shell-cli.sh` | 16 | 16 | 0 | 100% | `tests/shell-cli-lib.bats` |
| `shell-cli-posix.sh` | 9 | 9 | 0 | 100% | `tests/shell-cli-posix-lib.bats` |
| `compose-cli.sh` | 12 | 12 | 0 | 100% | `tests/compose-cli-lib.bats` |

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
- `host-port-listeners.sh:26` — the `|| true` on the loopback `grep`. `grep -E`
  exits nonzero exactly when nothing matched, and nothing matched is exactly
  when `body` is empty, so the next line returns 1 either way. The guard cannot
  change a status or a byte of output; it only keeps an errexit caller from
  aborting one line earlier than it already does.
- `mutation.sh:22` — the `-lt` bound on the `mutation_strip_comment` scan loop.
  Under `-le` the loop runs one extra iteration at `i == len`, where
  `${line:len:1}` is unavoidably the empty string. An empty `ch` matches no arm
  of the `case`, and the only early return is the `'#'` arm, so the extra pass
  can neither print nor return; it increments `i` past the bound and exits. A
  differential run over 1583 inputs -- every hand-picked end state
  (unterminated quote, trailing backslash, trailing hash) plus every string up
  to length four over the six characters that drive each branch -- found no
  difference in stdout or exit status.

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
- **`|| true` on a command substitution is rarely an equivalent.** The eight
  guards around `lsof` and `ss` in `host-port-listeners.sh` read like noise
  until a stub exits nonzero *while still printing listeners*, which is what
  real `lsof` does when it cannot examine every socket. Under `set -e` the
  mutant aborts before printing and a busy port reports as free. The guards
  that really are equivalent are the ones whose command's exit status is fully
  determined by whether its output was empty, as at `:26` above.

## Attack order, and how each file closed out

1. `http-fetch.sh` — done; 15% -> 85%.
2. `timeout.sh` — done; the boundary mutant is killed and the rest are
   documented equivalents.
3. `parallel.sh` — done; 55% -> 100%.
4. `host-port-listeners.sh` — done; 56% -> 96%.
5. `shell-cli.sh` — done; 44% -> 100%. The gain was mostly the oracle: swapping
   the audit suite for `tests/shell-cli-lib.bats` took the run from minutes to
   32s, and a unit suite can drive the error paths an audit run never reaches.
6. `compose-cli.sh`, `shell-cli-posix.sh` — done; both went from no oracle to
   100% on their first suite. Neither needs a container runtime: every backend
   probe is driven through a PATH holding nothing but stubs.
7. `mutation.sh` — done; 63% -> 97%, with the one survivor a documented
   equivalent. Keep it here as operators evolve; it gates itself.

Per file: strengthen assertions until the score plateaus, only then split
functions toward do-one-thing, and re-mutate to confirm no behaviour drifted.

## Open question: cache-dir substitution

`http_cache_dir_ensure` silently substitutes a fresh mktemp dir when
`HTTP_FETCH_CACHE_DIR` is set but missing, and the substitution happens per
call inside subshells — consecutive calls can resolve different directories,
orphaning entries written earlier. The primed-hit test pins current semantics;
whether production should instead fail fast or create the configured directory
is an unresolved product decision, recorded here so the suite's shape is not
mistaken for an endorsement.

## Roadmap

Every script in `scripts/lib/` now has an oracle and a score. What is left:

1. Resolve the cache-dir substitution question above.
2. Hold the line: a new function in `scripts/lib/` arrives with its own suite,
   and a re-mutation is what proves the suite is worth having.
