# Platform compose verification map

This directory is the maintained source for verifying the user-facing behaviour of the Docker Compose dev platform. Read this index, then use the matching feature file.

## Baseline preconditions

- `control.sh --execute launch` printed `ready` and `doctor` prints `OK services=…` with all 7 dev services.
- Repo-root `.env` has `OAUTH2_PROXY_COOKIE_SECRET`, and mkcert's CA is trusted.
- No other `compose` project or :8443 listener existed before launch.

## Driving conventions

- Every browser action goes through Dex via `control.sh --execute drive …`, in each of chromium, firefox and webkit (`VERIFY_BROWSERS` narrows it; evidence is per browser).
- Use the documented demo users only.
- Collect service logs with `control.sh --execute logs` after a drive that claims a backend effect.

## Proof and skip reporting

- UI proof is the screenshot and text per step, with hosts recorded in `steps.jsonl`.
- APIM-hop proof is the `apim request … status=200` line for the call the UI made.
- UAT, the Backstage portal and the kind/Lima stacks are not covered. Name them as skipped.

## Feature entry contract

Each feature file has an H1, one paragraph, and then `Sub-features`, `How to get to it (user POV)`, `Driving it with control.sh` and `Gotchas`.

## Features

- [SSO sign-in](./sso-sign-in.md): oauth2-proxy → Dex → app. **Driven 2026-10-10 as the first half of `drive lookup`; `drive login` alone not separately run.**
- [Subnet lookup through APIM](./subnet-lookup.md): the lookup form and the APIM hop. **Driven 2026-10-10.**
- [Provider range check](./provider-check.md): `#provider-form`. Not yet driven.
