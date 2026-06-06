# Platform Status And Inventory Optimization Pass 4

Scenario: live local platform status, status read-model projection, and guided workflow inventory composition.

Commands:

```bash
scripts/platform-status.sh --execute --output json
scripts/platform-status-read-model.sh --execute --output json
scripts/platform-inventory.sh --execute --variant kind --stage 900 --output json
```

Baseline: 10 hyperfine runs after 2 warmups. Status mean 3.336s, read-model mean 3.306s, inventory mean 6.740s. Artifact: `baseline-hyperfine.json`.

Profile: inventory collected `platform-status` directly, then invoked `platform-status-read-model`, which collected `platform-status` again. The inventory timing was almost exactly two status probes.

Opportunity matrix:

| Hotspot | Impact | Confidence | Effort | Score |
| --- | ---: | ---: | ---: | ---: |
| Reuse inventory's status JSON when building the read model | 5 | 5 | 1 | 25.0 |

Change: `platform-status-read-model.sh` now accepts `PLATFORM_STATUS_READ_MODEL_STATUS_JSON`; `platform-inventory.sh` passes its already-collected status payload through that variable.

Result: inventory mean dropped to 3.427s. Status and standalone read-model timings stayed flat, as expected. Artifact: `post-pass4-hyperfine.json`.

Isomorphism proof:

- Ordering preserved: yes, inventory still builds status, read-model, then workflow JSON in that order.
- Tie-breaking unchanged: yes, the read model receives the exact status JSON inventory already stores as `raw_status`.
- Floating-point: N/A.
- RNG seeds: N/A.
- Golden outputs: recursively normalized `generated_at` fields, then `shasum -a 256 -c golden_checksums.txt` passed.
