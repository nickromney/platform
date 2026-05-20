# Subnet Calculator

Subnetcalc is now the minimal Go implementation only. The same binary runs as
either role, selected by container environment:

- `RUNTIME_ROLE=backend` serves the subnet API on port `8080`.
- `RUNTIME_ROLE=frontend` serves embedded HTML/CSS/JavaScript and proxies
  `/api/*` to `BACKEND_URL`.

The frontend has no package manager. The backend is Go with the one intentional
OIDC dependency used for server-side token validation.

## Run

```bash
make -C apps/subnetcalc up
```

Local URLs:

- Frontend: <http://localhost:8003>
- Backend health: <http://localhost:8090/api/v1/health>

## Test

```bash
make -C apps/subnetcalc/app-go test
make -C apps/subnetcalc test
```

`make test` runs the Go unit tests and the compose smoke test for the backend
and frontend roles.

The retired Python, C#, React, Vite, Static Web Apps, Bruno, PKI, and local
hosting experiments were moved to the `subnet-calculator` repository on branch
`chore/20260519-archive-platform-experiments`.
