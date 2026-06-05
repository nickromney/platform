# Pass 8 - Python contract tests

## Target
- `bats tests/validate-docker-optimization-contracts.bats`

## Baseline
- Command: `hyperfine --warmup 1 --runs 5 'bats tests/validate-docker-optimization-contracts.bats > /tmp/validate-docker-benchmark.txt'`
- Mean: 4.226s
- Sigma: 0.058s
- Golden output SHA-256: `1c54cecead4083347612c9df0cb202bfedb98bf45dbfb6819fcf6e35c880ea3a`

## Hotspot
- The test file spawned `uv run --isolated python` for every Python contract assertion.
- In the sandbox, direct `uv` calls can also fail while initializing `/Users/nickromney/.cache/uv`, making the suite need escalation even though the contracts only need repository-local Python modules and PyYAML.

## Change
- Run the inline Python contract assertions with `python3`.
- The host Python environment already provides PyYAML 6.0.3, which is the only extra package needed by the compose-contract tests.

## Result
- Mean: 3.938s
- Sigma: 0.055s
- Runtime delta: -0.288s (-6.8%)
- `uv run --isolated` call sites in `tests/validate-docker-optimization-contracts.bats`: 0
- Golden output SHA-256: `1c54cecead4083347612c9df0cb202bfedb98bf45dbfb6819fcf6e35c880ea3a`

## Verification
- `bats tests/validate-docker-optimization-contracts.bats`
- `shasum -a 256 tests/artifacts/perf/20260605T232501Z-python-contracts-pass8/validate-docker-golden.txt tests/artifacts/perf/20260605T232501Z-python-contracts-pass8/validate-docker-after.txt`
