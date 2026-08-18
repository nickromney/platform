# Architecture Reviews

Point-in-time architecture reviews, kept so a later session can tell what was
already found, what was fixed, and what was deliberately left.

Each review is a self-contained HTML file. Open it directly:

```bash
open docs/reviews/architecture-review-20260817.html
```

## 2026-08-17

Scope: what PRs #195–#202 changed, and what they changed *around*. Five parallel
explorations (Make/build surface, shell layer, test-and-gate layer, Terraform,
Go tooling), each finding re-verified against the tree before inclusion.

### Status ledger

Read this before re-doing anything in the report.

| Item | Status |
| --- | --- |
| `make -C kubernetes/lima status` was a bash syntax error, dead since #163 | **Fixed** — restored the line #163 deleted |
| 4 `kubernetes/tests/*.bats` gated by nothing | **Fixed** — added to `CI_BATS_TESTS` |
| Gate-coverage guard blind to `kubernetes/tests/` | **Fixed** — enumerates `git ls-files '*.bats'`, no path shape |
| Candidate 1 — gate enumerates rather than globs | **Done** |
| Candidate 2 — browser UI sent the action as the subcommand | **Fixed**, plus the UI's first Go tests |
| Candidate 4 — 4 copy-pasted oauth2-proxy Applications | **Done**, −286 lines. See correction in the report: the original recommendation was wrong |
| Candidate 6 — 7 of 8 `make lint` targets unguarded | **Done** — `LINTERS` list + `tests/lint-wiring.bats` |
| Go test suites run by nothing (9.5k lines, 17 modules) | **Fixed** — `tests/go-tests.bats` + pinned `actions/setup-go` |
| TUI tests were red (stale `local-idp-12gb` after #135) | **Fixed** — assertions now derive from the contract |
| `lint-markdown.sh` warned-and-passed on missing tool | **Fixed** — hard-fails like its three siblings |
| OpenTofu suite (72 runs) run by nothing | **Fixed** — split into tiers; fast tier (43s) in the gate, full suite on demand |
| Candidate 3 — Terraform has no modules; ~80 edit sites per app | **Not started** — the large one |
| Candidate 5 — every Argo CD Application defined twice | **Withdrawn — do not do it.** The premise is wrong; see below |
| Candidate 7 — widen the shell standard past the flag surface | **Not started** |
| `tests/apps-makefile.bats` flake blocking `BATS_JOBS=auto` | **Still open.** The leaked-fixture hypothesis was tested and **rejected** (17/17 pass with the fixture present) — that candidate is eliminated, the cause is not yet known |
| `tests/locale-independence.bats` — "source fingerprinting is stable across locales" | **Newly observed flake, cause unknown.** Failed once in four full serial gate runs; passes in isolation. Not caused by the changes in this branch — nothing here touches `image-catalog-lib.sh`, `apps/shared/apphttp`, or locale handling. Note `source_fingerprint_tag` uses `find -type f`, so it hashes untracked files too and is sensitive to any churn in the hashed directory. Ruled out: `go test` does not churn that directory (4 files before/during/after) |

### Candidate 5 is withdrawn — read this before reopening it

The report claimed 29 Argo CD Applications are defined twice and one copy should
go. **That is wrong.** The two paths are different chart-sourcing architectures:

- `.tf` heredocs source from `${local.policies_repo_url_cluster}` +
  `apps/vendor/charts/...` at `targetRevision: main` — charts vendored into the
  in-cluster Gitea by `sync-gitea-policies.sh`. This is what makes the
  `airplane` preset work, and what #182 hardened.
- `apps/argocd-apps/*.yaml` source from upstream registries (`ghcr.io`,
  `charts.jetstack.io`, `argoproj.github.io`) at pinned chart versions.

All 30 apps present in both differ, by design. Collapsing them breaks offline
operation. Measured 2026-08-17.

**What is genuine drift** and worth a separate, cluster-aware decision — sync
waves disagree between the two paths: `argo-rollouts` 86/87,
`cert-manager-config` 5/10, `nginx-gateway-fabric` -4/-10,
`platform-gateway-routes` 20/50 (which also points at different paths). These
change deployment ordering, so they were not guessed at.

The same mistake was made in candidate 4: a deliberate architectural difference
read as copy-paste. In that case folding the four oauth2-proxy Applications into
the neighbouring `for_each` would have dropped break-glass admin access, because
map-form `extraArgs` cannot carry two `--allowed-group` values. Measure what
differs before proposing a merge.

### Things a follow-up session should not re-derive

- **The gate is three suites, and only some are enforced.** bats (1114 tests) and
  Go (17 modules) now run in `make test-ci`. The OpenTofu fast tier runs too; the
  full 231s suite does not.
- **`tofu` and `terraform` share `.terraform/` and clobber each other.** Running
  the suite under `terraform` installs `registry.terraform.io` providers and
  leaves `tofu test` failing with `Missing required provider
  registry.opentofu.org/gavinbunney/kubectl`. Fix: `tofu init -backend=false`.
- **The suite passes under both**: OpenTofu 72/72 in 231s, Terraform 72/72 in 321s.
- **`run-opentofu-tests.sh` defaults to a 180s per-command timeout**, which is
  too tight for the full suite on an M4 under load — it kills `tofu test`
  mid-run and reports an interrupt, not a failure. Raise
  `TOFU_TEST_TIMEOUT_SECONDS` when running the full tier.
- **Gate timings are ranking-grade, not regression-grade.** The measured run
  varied 739s → 667s purely on background load (Slicer VMs, `mediaanalysisd`).
  Do not diff run-to-run totals and read them as regressions.
