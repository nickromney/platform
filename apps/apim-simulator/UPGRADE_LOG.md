# Dependency Upgrade Log

**Date:** 2026-04-14
**Project:** apim-simulator

## Summary

- Updated the UI Vite stack to patched 7.x releases.
- Rolled the Astro example forward to `astro@6.1.6` after suspending the example-level npm age gate.
- Verified the final tree with lint, tests, frontend build checks, and npm audit.

## Updates

### `ui`

- `vite`: `^7.2.0` -> `^7.3.2`
- `@vitejs/plugin-react`: `^5.1.0` -> `^5.2.0`
- Result: `npm audit` reports 0 vulnerabilities.
- Tests: `make frontend-check` passed.

### `examples/todo-app/frontend-astro`

- `astro`: `^6.1.4` -> `^6.1.6`
- `@astrojs/check`: `^0.9.4` -> `^0.9.8`
- `overrides.vite`: `7.3.2`
- `overrides.yaml`: `2.8.3`
- `overrides.yaml-language-server`: `1.21.0`
- Notes:
  - `astro@6.1.6` was published too recently for the repo's seven-day npm age gate at roll-forward time, so `examples/todo-app/frontend-astro/.npmrc` was temporarily set to `min-release-age=0` and restored to `min-release-age=7` afterward.
  - The override set was required to keep `astro check` working and to clear the audit findings.
- Tests: `make frontend-check` passed.

## Verification

- `make lint-check`
- `make test-python`
- `make frontend-check`
- `npm --prefix ui audit --json`
- `npm --prefix examples/todo-app/frontend-astro audit --json`

## Notes

- UBS still reports one critical taint finding in `app/main.py` on the upstream Flask response sink, even after cache-response and upstream-status normalization. The current assessment is that it is still a false positive.
