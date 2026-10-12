---
name: verify-platform
description: Bring up the platform Docker Compose dev stack (TLS edge on :8443, Dex + oauth2-proxy SSO, APIM simulator, subnetcalc dev), sign in through Dex in headless Chromium, Firefox and WebKit, run a subnet lookup that crosses router → APIM → API, and capture screenshots, result text and service logs. Use when you need to prove an edge, SSO, APIM-hop or subnetcalc change on the running compose platform; not for kind/Lima clusters.
---

# Verify the platform (compose dev stack)

The user surface is a browser at
`https://subnetcalc.dev.compose.127.0.0.1.sslip.io:8443/`. oauth2-proxy
redirects to Dex. After sign-in, the subnetcalc frontend calls `/api/v1/*`
through the router and the shared APIM simulator to the API. This is the
smallest stack in the repo that still exercises TLS, SSO and the APIM hop. It
uses about 150 MiB of RAM across 7 containers.

The kind and Lima Kubernetes stacks are out of scope here: they are
heavyweight and covered by `skills/use-platform`. Backstage (the `portal`
profile) is not started either.

Helper: `skills/verify-platform/scripts/control.sh`. It is built on verify-kit:
the shared library (`scripts/verify-lib.sh`), contract tests (`tests/contract.bats`)
and make targets (`verify.mk`) are vendored from
`harnesses-private/nickromney/verify-kit` and pinned by `verify-kit.lock`. Only
the app hooks and `tests/platform.bats` are local. It runs under macOS
`/bin/bash` (Bash 3.2). Nothing runs without `--execute`: a bare call or
`--dry-run` prints usage and the plan. Below, `C` adds `--execute`.

```bash
make verify            # full proven cycle: launch, doctor, drive lookup 10.0.0.0/24, logs, expected-text checks, cleanup
make verify-dry-run    # print what verify would do, change nothing
make verify-test       # shellcheck on the scripts and every BATS file, then the contract and app BATS tests
C() { /bin/bash skills/verify-platform/scripts/control.sh --execute "$@"; }
```

`verify` cleans up on failure too, and it prints `VERIFY PASS` only when every
assertion holds. A failed step exits non-zero without that line.

## Launch

```bash
C launch
```

The steps, in order:

1. Refuse if a compose project named `compose` or a listener on :8443
   already exists. The project name and ports are fixed, so a second instance
   is impossible, and someone else's stack must not be adopted.
2. Run `bun install --frozen-lockfile` in `tests/kubernetes/sso`. That
   provides `playwright-core`, and the driver uses Playwright's own Chromium, Firefox and WebKit builds
   (`VERIFY_BROWSER`, default `chromium`; install with
   `cd tests/kubernetes/sso && bunx playwright install chromium firefox webkit`).
3. Run `make -C docker/compose up-dev`. This needs the repo-root `.env` with
   `OAUTH2_PROXY_COOKIE_SECRET` (see `docker/compose/README.md`) and mkcert.
   Since 2026-10-10, `up-dev` builds the linux/amd64 Go binaries the images
   COPY from `apps/*/app/.run/` through its `binaries` prerequisite. Before
   that, a clean checkout failed with `"/app/.run/apim-simulator": not found`.

It's ready when the app URL 302s to Dex and
`http://localhost:8302/apim/health` returns 200. Building takes a few
minutes cold and about 40 s warm.

## Doctor

```bash
C doctor
```

Read-only. It checks that this run launched the stack, that project
`compose` is running, that `compose-edge-1` publishes :8443, that the app
redirects to Dex, and that APIM is healthy. It lists the running services
and prints the launch revision next to the current HEAD.

## Drive

```bash
C drive login                  # Dex SSO only
C drive lookup 10.0.0.0/24     # SSO, then #lookup-form → #results
C logs                         # apim-simulator / router / api / oauth2-proxy logs
```

Handles:

- Dex form: `#login`, `#password`, `#submit-login`, plus an optional
  "Grant Access" button.
- App: `#lookup-form`, `#ip-address`, `#cloud-mode`, `#lookup-btn`,
  `#results`, `#results-content`, `#api-status`, `#auth-state`, and the
  example buttons `[data-example]`.
- Demo users come from `make -C docker/compose urls`: `demo@dev.test`,
  `demo@uat.test` and `demo@admin.test`, all with password `password123`.
  Override with `VERIFY_DEX_LOGIN` and `VERIFY_DEX_PASSWORD`.

## Evidence

Everything goes under `.run/verify/<run>/evidence/`, which is git-ignored
by `**/.run/`:

- `revision.txt`, `launch.log` and `down.log`.
- One `<HHMMSS-NNN>-<cmd>-<browser>/` per drive (`steps.jsonl` logs the browser name and version), holding `NN-<step>.png`,
  `NN-<step>.txt` and `steps.jsonl`.
- One `<HHMMSS-NNN>-logs/` per `logs` call.

Proof standards:

- The browser goes through the real Dex form. `01-dex-login-form` has the
  Dex host and `02-app-signed-in` has the app host.
- A lookup claim cites `03-lookup-results.txt` and the matching
  `apim request … path=/api/v1/ipv4/subnet-info status=200` line from
  `C logs`. The APIM line is the only proof the request crossed APIM.
- Protected routes are healthy when they return 302/401/403
  unauthenticated. Never treat a 200 from an unauthenticated curl as success.

## Verify

`C verify` (or `make verify`) runs launch, doctor and `drive lookup 10.0.0.0/24`
once in each browser of `VERIFY_BROWSERS` (space or comma separated; default
`chromium firefox webkit`; unknown names exit 2; doctor fails if one is not
installed), then checks four things and fails on any miss:

- `steps.jsonl` of the drive contains `"result":"PASS"`.
- `03-lookup-results.txt` contains `Usable Addresses` and `251`.
- `logs` writes `apim-simulator.log`, which contains
  `path=/api/v1/ipv4/subnet-info status=200`.
- Cleanup runs (only stops the stack if this run launched it).

## Cleanup

```bash
C cleanup
```

Runs `make -C docker/compose down`, but only if this run launched the stack.
It deletes `<run>/state` and keeps the evidence. The built `app/.run/`
binaries and the `tests/kubernetes/sso/node_modules` stay. Both are
git-ignored build outputs.

## Gotchas

- Any new or changed file, untracked ones included, invalidates the pre-push
  `.run/ci-receipt.json`. Re-run `uv run --locked make lint && uv run
  --locked make test-ci` before pushing.
- The images are `linux/amd64` and run under emulation on Apple silicon.
  `docker/compose` builds the binaries with `GOARCH=amd64`, overriding the
  app Makefiles' `arm64` default.
- `#results` first shows "Loading..." The driver waits for real content. A
  capture that only says "Loading..." is not proof.
- On the dev profile, `#auth-state` reads "API authentication is disabled
  for this environment." The SSO gate is at the edge, not in the API.
