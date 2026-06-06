# Shell Audit Pass 6

Target:

```sh
scripts/audit-shell-scripts.sh --execute \
  --path scripts/audit-shell-scripts.sh \
  --path scripts/lib \
  --path scripts/suggest-make-goal.sh \
  --path kubernetes/scripts \
  --path kubernetes/kind/scripts \
  --path terraform/kubernetes/scripts
```

Baseline:

- Mean: 15.581s
- Sigma: 0.228s
- Profiled helper calls: `grep` 1804, `awk` 416, `mktemp` 710, `cat` 710, `rm` 355

Change:

- Replaced interface-output `grep` and `awk` checks with Bash string and line parsing.
- Kept file-content scans and entrypoint probes unchanged.

Result:

- Mean: 13.273s
- Sigma: 0.570s
- Profiled helper calls: `grep` 924, `awk` 96, `mktemp` 710, `cat` 710, `rm` 355

Isomorphism proof:

- Scoped audit output SHA-256 stayed `1bdce3140a7b0389ec10a3afef4d18f1b10d5e1bb3cb07e7d2fa8f198d2142d1`.
- The Usage parser still accepts same-line and next-line entrypoint names.
- File scanning and Bash 3.2 feature checks remain external `grep` scans.
