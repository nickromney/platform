# Image Catalog Projection Optimization Pass 3

Scenario: registry-mode kind operator override rendering, which computes image catalog source fingerprints and projects external platform/workload image refs without mutating a cluster.

Command:

```bash
KIND_OPERATOR_OVERRIDES_FILE=/tmp/operator-overrides.tfvars \
KIND_IMAGE_DISTRIBUTION_MODE=registry \
KIND_ENABLE_BACKSTAGE=on \
kubernetes/kind/scripts/render-operator-overrides.sh --execute
```

Baseline: 10 hyperfine runs after 3 warmups, mean 4.186s, sigma 0.218s. Artifact: `baseline-hyperfine.json`.

Profile: wrappers around `find`, `shasum`, and `jq` showed 10 source-tree scans and 409 `shasum` calls. Two workload image pairs use identical fingerprint source lists, so equivalent source digests were recomputed in sibling command substitutions. Artifacts: `subprocess-summary-before.txt`, `find-summary-before.txt`.

Opportunity matrix:

| Hotspot | Impact | Confidence | Effort | Score |
| --- | ---: | ---: | ---: | ---: |
| Cache source fingerprint tags by ordered source list for one script invocation | 4 | 5 | 2 | 10.0 |

Change: `image-catalog-lib.sh` now keeps a per-script temp-file cache for source fingerprint tags. The file cache is shared across command substitutions, unlike shell variable caches.

Result: 10 hyperfine runs after 3 warmups, mean 3.327s, sigma 0.106s. `find` scans dropped from 10 to 8 and `shasum` calls from 409 to 330. Artifact: `post-pass3-hyperfine.json`.

Isomorphism proof:

- Ordering preserved: yes, image refs are still emitted by the same rendering functions in the same order.
- Tie-breaking unchanged: yes, the cache key is the exact ordered fingerprint source list.
- Floating-point: N/A.
- RNG seeds: N/A.
- Golden outputs: `shasum -a 256 -c golden_checksums.txt` passed after the change.
