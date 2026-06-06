# Version Audit Pass 5

Target:

```sh
CHECK_VERSION_SKIP_UPSTREAM=1 scripts/check-repo-version.sh --execute
```

Baseline:

- Mean: 1.523s
- Sigma: 0.024s
- `uv run --isolated python - ...` calls: 9
- Workflow parser `uv` calls: 4

Change:

- Batched all workflow action-reference parsing into one Python startup.
- Kept network-backed selector resolution and all reporting in the shell loop.

Result:

- Mean: 1.423s
- Sigma: 0.027s
- `uv run --isolated python - ...` calls: 6
- Workflow parser `uv` calls: 1

Isomorphism proof:

- `CHECK_VERSION_SKIP_UPSTREAM=1` output SHA-256 stayed `4a5012aa3535f60431c4721c168c04be44c98c36efb8d76af4175158f2510e59`.
- Workflow-file ordering still comes from `workflow_files`.
- Action-ref ordering and per-file duplicate suppression remain local to each workflow file.
