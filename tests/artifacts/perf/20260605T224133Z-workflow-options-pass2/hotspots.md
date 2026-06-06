# Workflow Options Optimization Pass 2

Scenario: workflow option-contract rendering through both the direct renderer and public `scripts/platform-workflow.sh options` command.

Commands:

```bash
kubernetes/workflow/render-options.sh --execute
scripts/platform-workflow.sh options --execute --output json
```

Baseline: 10 hyperfine runs after 3 warmups. Direct renderer mean 17.9ms, sigma 2.7ms. Public options command mean 65.1ms, sigma 8.8ms. Artifact: `baseline-hyperfine.json`.

Profile: jq wrapper showed the public options command performed preview/apply setup before printing options: default variant path validation, default action/stage validation, registry host lookup, and command construction. It made 10 jq invocations for a static options response. Artifact: `jq-counts.txt`.

Opportunity matrix:

| Hotspot | Impact | Confidence | Effort | Score |
| --- | ---: | ---: | ---: | ---: |
| Fast-path `options --execute` before preview command setup | 3 | 5 | 1 | 15.0 |

Change: after flag parsing, `options` now exits through `print_options` before validating preview-only fields, priming registry caches, or constructing Make command args.

Result: public options command mean 35.3ms, sigma 4.4ms. jq invocations dropped from 10 to 2, and registry lookups dropped to 0. Artifact: `post-pass2-hyperfine.json`.

Isomorphism proof:

- Ordering preserved: yes, `print_options` still owns both text and JSON output order.
- Tie-breaking unchanged: yes, the source options JSON is still rendered before command dispatch.
- Floating-point: N/A.
- RNG seeds: N/A.
- Golden outputs: `shasum -a 256 -c golden_checksums.txt` passed after the change.
