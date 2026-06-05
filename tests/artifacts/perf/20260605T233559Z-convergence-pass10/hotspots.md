# Pass 10 - Optimization convergence

## Convergence Sweep
- Scoped shell audit: 13.898s +/- 0.437s
- Image catalog operator overrides: 3.268s +/- 0.073s
- Platform inventory: 3.441s +/- 0.051s
- Docker optimization contracts: 3.981s +/- 0.075s
- Kind help: 135.7ms +/- 9.9ms

## Remaining Lever Selected
- The scoped shell audit still had a high-confidence helper-process hotspot from interface probes.
- Before this pass, each probe allocated stdout/stderr temp files, read them back with `cat`, and removed them immediately.
- Pass 6 already reduced `grep`/`awk`; this pass removed the repeated `mktemp`/`cat`/`rm` capture churn while preserving separate stdout/stderr files for diagnostics.

## Change
- Allocate the stdout/stderr capture files lazily once per audit process.
- Truncate and reuse those files for each interface probe.
- Read first-line errors and successful output with Bash builtins instead of `head` and `cat`.
- Remove the shared capture files with a single `EXIT` trap.

## Result
- Scoped shell audit post-change: 10.738s +/- 0.544s
- Runtime delta: -3.159s (-22.7%) from the pass-10 convergence baseline.
- Output SHA-256 stayed `1bdce3140a7b0389ec10a3afef4d18f1b10d5e1bb3cb07e7d2fa8f198d2142d1`.

## Remaining Surfaces
- Image catalog, inventory, Docker contracts, and kind help were at their post-pass baselines in the convergence sweep.
- No additional scoped lever was implemented after the shell-audit capture reuse pass.

## Verification
- `bats --filter "shell audit reuses interface capture|shell audit validates interface output without grep" tests/audit-shell-scripts.bats`
- `bash -n scripts/audit-shell-scripts.sh`
- `shasum -a 256 -c tests/artifacts/perf/20260605T233559Z-convergence-pass10/golden_checksums.txt`
