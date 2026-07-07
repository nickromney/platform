# Vanilla JavaScript Type-Checking Plan

<!-- markdownlint-disable MD013 -->

- Status: Draft
- Date: 2026-05-20
- Scope: `apps/subnetcalc`, `apps/sentiment`, and the other lightweight Go apps
- Source process: `improve-codebase-architecture`

## Purpose

This plan records how the lightweight Go apps should get TypeScript-style
type safety without adopting a JavaScript package-manager ecosystem or adding
runtime dependencies.

The intended default is still vanilla HTML, CSS, and JavaScript emitted or
served by Go. The improvement is checked JavaScript:

```js
// @ts-check

/** @typedef {import("./api-types").RuntimeConfig} RuntimeConfig */
/** @typedef {import("./api-types").ApiDiagnostics} ApiDiagnostics */
```

The app runtime remains a Go binary with embedded static assets. Type checking
is a build/test concern only.

## Decision

Use `// @ts-check` JavaScript plus `.d.ts` declarations for the current
lightweight apps.

Do not start with `.ts -> bundled .js` for subnetcalc, sentiment, chatgpt-sim,
idp-core, or platform-mcp browser surfaces. Transpilation and bundling are
available later if a UI becomes large enough to need modules, but they should
not be the default.

## Why This Fits

The problem is not types. The problem is the package-manager ecosystem and
runtime/build sprawl that usually arrives with frontend tooling.

Checked JavaScript gives us:

- Type-checked API payloads.
- Type-checked runtime configuration.
- Better editor navigation.
- Safer DOM querying and UI state updates.
- No generated browser bundle.
- No package root per app.
- No Node, npm, Yarn, pnpm, Bun, Vite, React, or TypeScript runtime in app
  containers.

## Type Checker Shape

To enforce the checks in CI and local tests, the repo needs one explicit
checker path. That checker is a tool, not an app runtime dependency.

Current dependency posture:

- Do not write a repo-local type checker.
- Do not use TSLint; it is deprecated.
- Do not use npm, npx, Yarn, pnpm, or Bun for the lightweight app default path.
- Biome is the selected checker for linting and formatting checked browser
  JavaScript.
- Deno is the selected semantic checker for `// @ts-check` JavaScript via
  `deno check --check-js`.
- Biome and Deno are installed or preloaded as standalone binaries/tool images,
  not through npm.
- App Makefiles call the wrapper; app containers do not contain it.

Possible implementation options, in preference order:

1. Use Biome standalone for lint/format.
2. Use Deno standalone for semantic type checking.
3. Use a pinned tool container that contains Node plus the TypeScript compiler
   only if the team explicitly accepts npm-originated TypeScript artifacts.

Do not use open-ended `npm install`, `npx`, or per-app `package.json` files for
the lightweight apps.

## Contract Source Direction

The browser types should describe the Go HTTP contract, not invent a parallel
frontend model.

For small apps:

- Define stable Go response structs for runtime config, auth/user state, API
  results, and diagnostics.
- Generate or maintain matching `api-types.d.ts` declarations beside the
  static JavaScript.
- Add tests that fail when handlers stop emitting fields the browser contract
  expects.

For APIM Simulator later:

- Prefer generated declarations from Go management response types or the
  Go-emitted OpenAPI contract.
- Keep the browser UI as an adapter over the management API.

Do not make browser JavaScript the source of truth for API semantics.

## Shared Typed Frontend Concepts

Every lightweight app should converge on a small shared vocabulary:

```ts
export interface RuntimeConfig {
  appName: string;
  environment: string;
  apiBasePath: string;
  backendURL?: string;
  gatewayURL?: string;
  networkHops: NetworkHop[];
  user?: LoggedInUser;
  theme: ThemeMode;
}

export interface LoggedInUser {
  subject: string;
  username?: string;
  email?: string;
  displayName?: string;
  groups?: string[];
}

export type ThemeMode = "light" | "dark" | "system";

export interface NetworkHop {
  name: string;
  url?: string;
  role: "browser" | "gateway" | "frontend" | "backend" | "identity" | "observer";
}

export interface ApiDiagnostics {
  traceId?: string;
  correlationId?: string;
  requestStartedAt: string;
  responseEndedAt: string;
  durationMs: number;
  requestURL: string;
  reachedURL?: string;
  gatewayURL?: string;
  backendURL?: string;
  status: number;
  networkHops: NetworkHop[];
  serverTiming?: string;
}
```

The exact declarations can live per app at first. Extract a shared declaration
module only after two or more apps need the same typed contract and the
extraction passes the deletion test.

## Canonical App Order

### 1. Subnetcalc

Subnetcalc should become the canonical checked-JS implementation.

Red tests:

- Add a failing `js-check` target for `apps/subnetcalc/app`.
- Add a failing contract test proving `api-types.d.ts` exists and the main JS
  file starts with `// @ts-check`.
- Add a failing browser/API contract test for runtime config, logged-in user,
  theme mode, logout/cookie clearing hooks, and diagnostics.

Green implementation:

- Add `api-types.d.ts`.
- Annotate the existing vanilla JS with `// @ts-check`.
- Add typed helper functions for DOM lookup, runtime config, API fetches,
  diagnostics capture, theme handling, login state, and logout.
- Keep emitted/served assets as plain JS, CSS, and HTML.
- Ensure any API calls can route through an APIM-style gateway by using
  `apiBasePath` and optional `gatewayURL`, never hard-coded backend-only URLs.

Focused verification:

```bash
make -C apps/subnetcalc/app test
make -C apps/subnetcalc/app js-check
apps/subnetcalc/tests/compose-smoke.sh --execute
```

### 2. Sentiment

Sentiment should copy the subnetcalc pattern after subnetcalc is green.

Red tests:

- Same `js-check` and checked-JS contract tests.
- Add focused tests for the sentiment API path through the frontend proxy or
  APIM gateway.
- Add diagnostics tests showing backend target, gateway path, timings, user,
  and hop data.

Green implementation:

- Add `api-types.d.ts`.
- Add `// @ts-check` to the browser JS.
- Reuse subnetcalc's typed helper shape where it has proven useful.
- Keep any local differences explicit, such as sentiment-specific payloads and
  result rendering.

Focused verification:

```bash
make -C apps/sentiment/app test
make -C apps/sentiment/app js-check
apps/sentiment/tests/compose-smoke.sh --execute
```

### 3. Other Lightweight Go Apps

Apply the pattern after subnetcalc and sentiment are both green:

- `apps/chatgpt-sim`
- `apps/idp-core`
- `apps/platform-mcp`
- any future lightweight Go app with a browser surface

Each app gets:

- `.gitea`
- `app`
- `keycloak` if required
- `tests`
- `compose.yml`
- optional compose overlays
- Go runtime
- vanilla checked JS where a browser UI exists

## Gateway-Friendly Frontend Rule

Frontend code must treat the API as reachable through a gateway.

Required runtime facts:

- `apiBasePath`: the path the browser should call.
- `gatewayURL`: the gateway or APIM-simulator URL when present.
- `backendURL`: the service behind the frontend or gateway when known.
- `networkHops`: ordered hop descriptions for display and diagnostics.

Required API client behaviour:

- Build URLs from `apiBasePath`.
- Preserve credentials where SSO cookies are expected.
- Record `performance.now()` timings.
- Read trace and correlation headers.
- Record status, reached URL, gateway/backend hints, and server timing.
- Expose these facts in the UI.

Avoid direct backend URLs in browser code except as display-only diagnostics.

## Login, Theme, And Logout Contract

Every lightweight browser app should support:

- Logged-in user display.
- Light, dark, and system theme.
- Logout.
- Cookie clearing for app-local cookies.
- A clear unauthenticated state.

Typed frontend declarations should include:

- `LoggedInUser`
- `ThemeMode`
- `RuntimeConfig`
- `LogoutResult`
- `CookieClearResult`

Go handlers should own the auth and cookie semantics. JavaScript should call the
provided endpoints and update UI state.

## Visual Language Contract

The typed frontend work should not only add types. It should make the apps feel
like the same family:

- Same theme model.
- Same auth/user strip.
- Same diagnostic/hop disclosure pattern.
- Same API timing display.
- Same logout affordance.
- Same APIM/gateway wording where an app calls through a gateway.

Do not introduce a design system dependency. Share vocabulary and small static
CSS patterns only after subnetcalc and sentiment prove the shape.

## TDD Rules

Use red/green TDD for every app:

1. Add the smallest failing test or Make target.
2. Run the focused failing test.
3. Implement the minimum change.
4. Re-run the focused test until green.
5. Run the app's Go tests.
6. Run the app's compose smoke.
7. After the app set is green, run the kind stage-900 apply from a clean local
   runtime state.

Do not move to a shared helper module until two apps have the same need and the
Interface is clear.

## Verification For The Next Session

After Docker is logged in and local runtime conflicts are cleared:

```bash
make -C apps/subnetcalc/app test
make -C apps/sentiment/app test
make -C apps compose-smoke-subnetcalc
make -C apps compose-smoke-sentiment
bats tests/app-layout-consistency.bats
bats tests/validate-app-runtime-surfaces.bats
make -C kubernetes/kind 900 apply AUTO_APPROVE=1
make -C kubernetes/kind check-health
```

If kind, Lima, are already sharing host ports, clear the conflicting
runtime or stop only the conflicting host-forward/proxy process before treating
the app work as failed.

## Non-Goals

- Do not add React, Vue, Svelte, Vite, or a bundler to the lightweight apps.
- Do not add per-app `package.json` files for runtime code.
- Do not ship Node or the TypeScript compiler in app runtime images.
- Do not rewrite working browser code purely for style.
- Do not extract shared frontend modules before subnetcalc and sentiment prove
  the contract.
- Do not bypass the gateway/APIM path in frontend code when an app has an API.
