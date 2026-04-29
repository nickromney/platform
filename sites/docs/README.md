# Platform Docs

Local Nextra documentation site for `~/Developer/personal/platform`.

## Run Locally

```bash
bun install
bun run dev
```

Then open <http://localhost:3000>.

## Production-Local Search

Nextra's local search index is built during the production build. You do not
need a global `next` binary; use the project scripts so Bun resolves
`node_modules/.bin/next` for you.

```bash
bun install
bun run build
bun run serve
```

Or run the build and production server in one command:

```bash
bun run local
```

Then open <http://localhost:3000>. The Next.js production server command is
`next start`; there is no `next run` command.

## Validation

```bash
bun run lint:content
bun run typecheck
bun run build
```

## Visual Assets

D2 source lives under `diagrams/d2/`. Rendered SVGs live under
`public/diagrams/` and are generated from the source files.

```bash
bun run media:d2
bun run check:d2
```

Do not commit generated video outputs or one-off screenshots. Add animation
only when it explains something that static D2 diagrams cannot.

The site is intentionally local for now. Cloudflare publication can be added
later once the docs shape settles.
