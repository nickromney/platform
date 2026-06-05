# Workflow Preview Optimization Pass 1

Scenario: preset-heavy operator preview command for `scripts/platform-workflow.sh`, matching the command-generation path used by workflow UI surfaces.

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

Baseline: 10 hyperfine runs after 3 warmups, mean 196.3ms, sigma 20.4ms. Artifact: `baseline-hyperfine.json`.

Profile: jq wrapper showed 36 jq invocations. The top remaining repeated pure lookup was `.variant_contract | .registry.runtime_host`, called 3 times for the same target. Artifact: `jq-counts.txt`.

Opportunity matrix:

| Hotspot | Impact | Confidence | Effort | Score |
| --- | ---: | ---: | ---: | ---: |
| Memoize variant registry host lookups for one workflow invocation | 1 | 4 | 1 | 4.0 |

Change: cache `registry.runtime_host` and `registry.push_host` after target validation, before command construction and tfvars rendering.

Result: 10 hyperfine runs after 3 warmups, mean 176.3ms, sigma 11.7ms. Artifact: `post-pass1-hyperfine.json`. jq wrapper count dropped from 36 to 34, and runtime-host contract lookups dropped from 3 to 1.

Isomorphism proof:

- Ordering preserved: yes, command args and generated tfvars are rendered in the same functions and order.
- Tie-breaking unchanged: yes, variant contract source stays `.run/workflow/options.json`.
- Floating-point: N/A.
- RNG seeds: N/A.
- Golden outputs: `shasum -a 256 -c golden_checksums.txt` passed after the change.
