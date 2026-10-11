# SSO sign-in

An unauthenticated visit to subnetcalc dev is redirected by oauth2-proxy to Dex. After the demo user signs in, the browser returns to the app, which reports healthy API status.

## Sub-features

- `sso-redirect` sends an unauthenticated GET of the app URL to `https://dex.compose.127.0.0.1.sslip.io:8443/dex/auth?...` with a 302.
- `sso-login` covers the Dex local login form and the callback to the app.
- `sso-app-ready` shows `#api-status` "API Status: healthy | Backend: Subnet Calculator API (Go) …".

## How to get to it (user POV)

- Open `https://subnetcalc.dev.compose.127.0.0.1.sslip.io:8443/` and sign in as `demo@dev.test`.

## Driving it with control.sh

Preconditions:

- `doctor` prints `OK`.

- **Sign in.** `control.sh --execute drive login` runs the same sign-in steps that `drive lookup` runs first (on 2026-10-10 only `drive lookup` was run). In `steps.jsonl`, `dex-login-form` has host `dex.compose.127.0.0.1.sslip.io:8443` and `app-signed-in` has host `subnetcalc.dev.compose.127.0.0.1.sslip.io:8443`. The `apiStatus` line starts "API Status: healthy".

## Gotchas

- `demo@uat.test` should be refused on the dev app if per-environment allowlists are configured. That is not yet driven, so check `oauth2-proxy-subnetcalc-dev` config before claiming it.
