# Authentication Patterns (Easy Auth)

This document captures the current state of Microsoft Entra Easy Auth across the subnet-calculator stacks and highlights the practical limitations we have hit when trying to reuse the same user token across multiple App Service hosts.

## Browser → Web App → Function App (direct calls)

- Each App Service slot (`*.azurewebsites.net`) is its own Easy Auth boundary.
- The token issued to the React Web App has `aud = <frontend-app-id>` and does **not** include the Function App’s audience/scope.
- The Azure portal/ARM/terraform APIs for App Service **do not expose** the `loginParameters` setting that Static Web Apps supports. As a result, `/.auth/refresh?scopes=api://…/.default` returns `403` because the frontend never requested the API scope.
- Without a downstream access token the Function App Easy Auth layer correctly rejects the browser’s call, even if you allow-list the frontend app ID.

### Status (Nov 2025)

- Terraform creates both Entra ID applications, exposes the API scope, and grants delegated permission, but we cannot automate the scope request.
- The only way to get a working cross-domain Easy Auth flow today is to configure it manually in the portal (one-off) or to avoid cross-domain in the first place (proxy/shared host/On-Behalf-Of).

## Supported patterns

| Pattern | How it works | Stacks |
|---------|--------------|--------|
| **Proxy (recommended now)** | React Web App proxies `/api/*` through `server.js`, forwarding Easy Auth headers to the Function App. The browser never calls the backend host directly. | `terraform/terragrunt/personal-sub/subnet-calc-react-easyauth-proxied` |
| **Shared Easy Auth boundary** | Front Door / APIM / App Gateway terminates Easy Auth once, then routes `/` to the SPA and `/api` to the Function App on the same hostname. | Future APIM/App Gateway stack |
| **On-Behalf-Of (OBO)** | Web App code uses MSAL to exchange the user token for an API token (`AcquireTokenOnBehalfOf`). The Function App receives a valid access token with the API audience. | Not implemented (requires custom server-side code) |

## Recommendations

1. **Need something today?** Use the proxy stack. It keeps the Function App hidden, forwards Easy Auth headers for you, and requires no custom auth code.
2. **Need a single ingress hostname?** Put both services behind APIM, Front Door, or App Gateway so Easy Auth runs at the edge.
3. **Need per-user delegation inside the Function App?** Implement MSAL’s On-Behalf-Of flow in the Web App (server-side) and forward the resulting API token yourself.

Whenever Microsoft exposes `loginParameters` for App Service we can revisit the direct-call stack (`subnet-calc-react-easyauth-e2e`). Until then, plan on using one of the patterns above for production deployments.
