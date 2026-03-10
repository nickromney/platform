# Hosting & Authentication Matrix

This page summarizes the supported ways to run the Subnet Calculator frontend + backend pair and how authentication flows differ between them. Each scenario is wired into the repo today, so you can switch between them without rewriting code.

## 1. Local Compose (No Auth or JWT)

- **Where**: `subnet-calculator/compose.yml`
- **Frontend**: React + Vite and TypeScript SPA variants (ports 8003/3000) or Flask/static sites.
- **Backend**: FastAPI running either in the Azure Function container (`api-fastapi-azure-function`) or the container-app style service (`api-fastapi-container-app`).
- **Auth**:
  - `AUTH_METHOD=none` when talking to the container-app backend.
  - `AUTH_METHOD=jwt` for the function backend, with credentials injected via `JWT_USERNAME/JWT_PASSWORD`.
- **Usage**: `podman-compose up api-fastapi-container-app frontend-react` (stack 06) keeps the exact “no security” integration for local feature work.

## 2. Azure Static Web Apps + JWT Backend

- **Where**: `make start-stack5` (local SWA CLI) and `terraform/terragrunt/personal-sub/subnet-calc-static-web-apps` stack `"noauth"`.
- **Frontend**: SWA hosting the TypeScript SPA (ports 4281 locally, Standard SKU in prod).
- **Backend**: Internet-accessible FastAPI Function App with `AUTH_METHOD=jwt`.
- **Auth Flow**: SPA manages login via `/api/v1/auth/login`, stores a JWT (demo/password123 for dev), and attaches `Authorization: Bearer` headers for every request.
- **Status**: Unchanged by the Easy Auth work; keep using JWT when you need simple credential-based access or when SWA proxies directly to the function without federated SSO.

## 3. Azure Static Web Apps + Easy Auth (Platform)

- **Where**: `make start-stack6` (SWA CLI) and Terragrunt stack `"entraid-linked"` in `subnet-calc-static-web-apps`.
- **Frontend**: SWA manages the Entra ID sign-in (`/.auth/login/aad`), injecting `X-MS-CLIENT-PRINCIPAL` headers into proxied requests.
- **Backend**: FastAPI Function App runs with `AUTH_METHOD="swa"` so it trusts those headers.
- **Auth Flow**: No custom code—SWA enforces login, the backend reads the principal headers, and the SPA never touches tokens. This stack continues to work exactly as before.

## 4. App Service React Web App + Function App (Easy Auth end-to-end)

- **Where**: `terraform/terragrunt/personal-sub/subnet-calc-react-easyauth-e2e` (staged tfvars pattern).
- **Frontend**: React build hosted on Linux Web App with Easy Auth v2 enabled.
- **Backend**: FastAPI Function App with Easy Auth enabled and `AUTH_METHOD="azure_ad"`.
- **Auth Flow**:
  1. Users sign in against the **frontend** Entra app registration.
  2. The SPA calls `/.auth/refresh?resource=api://subnet-calculator-react-easyauth-e2e-api`.
  3. App Service issues a downstream token for the **API** app registration.
  4. FastAPI receives the same Easy Auth headers/token and accepts the call.
- **Terraform Notes**:
  - `entra_id_apps.frontend` + `entra_id_apps.api` model the two registrations.
  - `entra_id_app_delegated_permissions` grants the frontend delegated access to the API’s `user_impersonation` scope so refresh calls succeed.
  - The staged tfvars (`stages/000-all.tfvars`, etc.) are the template for future stacks—copy these blocks when you need Easy Auth with a dedicated backend audience.

## Takeaways

- Local Compose, SWA + JWT, and SWA + platform auth scenarios are untouched; keep using them for development and the existing production stacks.
- The new “dual app registration” pattern only activates when a stack defines `entra_id_apps` + `entra_id_app_delegated_permissions` (currently the App Service Easy Auth stack). Other stacks stay lean and only set the fields they need.
- To add more hosting options in the future, follow the staged tfvars approach from `subnet-calc-react-easyauth-e2e` so every stack documents its toggles in a composable way.
