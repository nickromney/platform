# Pass 9 - Make target surfaces

## Target
- `make`
- `make -C apps help`
- `make -C docker/compose help`
- `make -C kubernetes/kind help`
- `make -C kubernetes/lima help`
- `make -C kubernetes/slicer help`

## Baseline
- Root help: 37.9ms +/- 3.8ms
- Apps help: 129.1ms +/- 24.2ms
- Compose help: 319.2ms +/- 23.7ms
- Kind help: 138.9ms +/- 10.0ms
- Lima help: 118.7ms +/- 8.4ms
- Slicer help: 118.0ms +/- 7.1ms

## Hotspots
- `apps/Makefile` eagerly scanned wrapper Makefiles with `grep` four times while parsing, even for static `help`.
- `docker/compose/Makefile` eagerly expanded `COMPOSE := $(COMPOSE_CMD) -f compose.yml`, which resolved the compose backend before `help`.
- `apps/sentiment/Makefile` had the same eager compose command expansion pattern for app-local help.

## Change
- Make app wrapper directory variables recursive so wrapper discovery runs only when delegation targets expand them.
- Make compose command wrappers recursive so backend detection runs for execute targets, not help rendering.

## Result
- Apps help: 9.0ms +/- 0.3ms, down 120.1ms (-93.0%)
- Compose help: 12.7ms +/- 6.7ms, down 306.4ms (-96.0%)
- Root help stayed flat: 38.4ms +/- 4.2ms
- Kubernetes help surfaces were not changed; post-run variance was noise on the same output contract.

## Isomorphism Proof
- Measured help outputs are byte-identical before and after according to `golden_checksums.txt`.
- Execute-mode compose backend resolution is still covered by `tests/makefile.bats`.
- App wrapper delegation still expands the wrapper directory scans for `test` and `js-check`.

## Verification
- `bats --filter "docker compose help does not resolve|docker compose test resolves" tests/makefile.bats`
- `bats --filter "apps make help does not scan|apps test delegates|apps js-check delegates" tests/apps-makefile.bats`
- `bats --filter "sentiment make help does not resolve" tests/sentiment-makefile.bats`
- `shasum -a 256 -c tests/artifacts/perf/20260605T233115Z-make-surfaces-pass9/golden_checksums.txt`
