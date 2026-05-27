# Workflow Preview Profiling

Scenario: preset-heavy operator preview command for `scripts/platform-workflow.sh`, matching the TUI/browser workflow command-generation path without mutating a cluster.

Command:

```bash
scripts/platform-workflow.sh preview --execute --variant kind --stage 900 --action plan \
  --preset resource-profile=local-idp-12gb \
  --preset image-distribution=local-cache \
  --preset observability-stack=lgtm \
  --preset identity-stack=dex \
  --preset app-set=no-reference-apps \
  --set worker_count=2 \
  --app sentiment=off \
  --app subnetcalc=on \
  --output json
```

Baseline: 20 warm-cache hyperfine runs, mean 1.778s, median 1.760s, sigma 0.354s. Artifact: `baseline-hyperfine.json`.

Pass 1 result: batching preset overlay HCL rendering reduced the same 20-run command to mean 286.6ms, sigma 63.6ms. Artifact: `post-pass1-hyperfine.json`.

Decomposition:

| Segment | Mean | Evidence |
| --- | ---: | --- |
| `render-options.sh --execute` | 22.3ms | `decomposition-hyperfine.json` |
| `platform-workflow.sh options --output json` | 89.6ms | `decomposition-hyperfine.json` |
| simple `preview --output json` | 81.2ms | `decomposition-hyperfine.json` |
| preset-heavy `preview --output json` | 1.591s | `decomposition-hyperfine.json` |

## Hotspot Table

| Rank | Location | Metric | Value | Category | Evidence |
| --- | --- | ---: | ---: | --- | --- |
| 1 | `scripts/platform-workflow.sh:render_preset_overlay` -> per-entry `render_assignment_json` | subprocess count | 252 `jq` invocations | CPU/process spawn | `jq-argv-summary.txt` |
| 2 | `scripts/platform-workflow.sh:render_preset_overlay` | repeated overlay scans | 10 full preset overlay scans | CPU/process spawn | `jq-argv-summary.txt` |
| 3 | `scripts/platform-workflow.sh:local_registry_runtime_host` | repeated variant contract lookup | 11 `jq` invocations | CPU/process spawn | `jq-argv-summary.txt` |
| 4 | `scripts/platform-workflow.sh:validate_selected_preset` | preset validation subprocess fanout | 20 `jq` invocations for 5 presets | CPU/process spawn | `jq-argv-summary.txt` |
| 5 | `kubernetes/workflow/render-options.sh` | options rendering | 22.3ms of 1.591s | CPU/process spawn | `decomposition-hyperfine.json` |

## Hypothesis Ledger

- Preset-heavy latency comes from per-assignment `jq` fanout: supports. One run of the preset-heavy command made 311 `jq` calls; 84 entries each paid `.key`, `.value`, and HCL literal rendering.
- Base workflow options rendering dominates: rejects. Rendering options alone is ~22ms; the preset-heavy path is ~1.6s.
- JSON preview object construction dominates: rejects for first pass. It is one large `jq -n` call and simple preview is ~81ms.
- Filesystem writes dominate: rejects. Simple preview and options paths are <100ms; the extra cost appears only when preset overlays are rendered.

## Opportunity Matrix

| Hotspot | Impact | Confidence | Effort | Score |
| --- | ---: | ---: | ---: | ---: |
| Batch HCL rendering for preset overlay entries in one `jq` call per preset | 5 | 5 | 2 | 12.5 |
| Cache `local_registry_runtime_host` for one invocation | 2 | 4 | 1 | 8.0 |
| Batch selected-preset validation | 2 | 3 | 3 | 2.0 |
| Cache rendered workflow options when source mtimes unchanged | 2 | 3 | 4 | 1.5 |

## Pass 1 Isomorphism Proof

- Change: Batch selected preset overlay HCL rendering into one `jq` call.
- Ordering preserved: yes, selected preset groups stay in the original `resource_profile`, `image_distribution`, `observability_stack`, `identity_stack`, `app_set` order, and each overlay still uses `to_entries`.
- Tie-breaking unchanged: N/A, duplicate assignments remain emitted in the same precedence order.
- Floating-point: N/A.
- RNG seeds: N/A.
- Golden outputs: `shasum -a 256 -c golden_checksums.txt` passed after the change.
