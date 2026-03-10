# Authentication Patterns Reference

Quick reference for authentication patterns across local development and Azure deployments.

## Pattern Comparison

| Pattern | Local Stack | Azure Service | Use Case |
|---------|------------|---------------|----------|
| **No Auth** | Stack 4 (React SPA) | Azure Static Web Apps (public) | Public applications, demos |
| **Client-Side OIDC** | Stack 11 (React + Keycloak) | Azure Static Web Apps (custom auth) | Standard SPA pattern |
| **Server-Side Auth** | Stack 12 (OAuth2 Proxy) | Azure Easy Auth (App Service, Container Apps) | Internal apps, forced login |
| **API Token Validation** | Stack 11/12 API | Azure API Management | Secure API access |

## Local Development (Podman Compose)

### Stack 11: Client-Side OIDC

```bash
# Start
podman-compose up -d keycloak api-fastapi-keycloak frontend-react-keycloak

# Access
http://localhost:3006

# Behavior
- User sees UI immediately
- Click "Login" button to authenticate
- OIDC flow handled in browser (oidc-client-ts)
- JWT token stored in localStorage
- Token sent with API requests

# Similar to
- Azure Static Web Apps with custom auth
- Standard SPA pattern
```

### Stack 12: OAuth2 Proxy (Easy Auth Simulation)

```bash
# Start
podman-compose up -d keycloak api-fastapi-keycloak apim-simulator frontend-react-keycloak-protected oauth2-proxy-frontend

# Access
http://localhost:3007

# Behavior
- User is redirected to login immediately
- Cannot see UI without authenticating
- OAuth2 Proxy handles authentication + static asset protection
- React SPA silently acquires a Keycloak token via OIDC
- API calls are sent to the APIM simulator on :8082 with subscription key + bearer token
- Session cookie set after login, identity headers forwarded to frontend

# Similar to
- Azure Easy Auth (App Service, Function Apps, Container Apps)
- Azure Static Web Apps with forced login
- AKS with OAuth2 Proxy sidecar
```

## Azure Deployment Patterns

### Azure Static Web Apps (Public or Custom Auth)

**Configuration:**

```json
{
  "routes": [
    {
      "route": "/*",
      "allowedRoles": ["authenticated"]
    }
  ],
  "responseOverrides": {
    "401": {
      "redirect": "/.auth/login/aad",
      "statusCode": 302
    }
  }
}
```

**Equivalent Local Stack:** Stack 11 or Stack 12 (depending on route config)

### Azure App Service / Function Apps (Easy Auth)

**Configuration:**

```bash
az webapp auth update \
  --resource-group rg-myapp \
  --name myapp \
  --enabled true \
  --action LoginWithAzureActiveDirectory
```

**Equivalent Local Stack:** Stack 12 (OAuth2 Proxy)

### Azure Container Apps (Easy Auth)

**Configuration:**

```bash
az containerapp auth update \
  --name myapp \
  --resource-group rg-myapp \
  --enabled true \
  --require-authentication true \
  --unauthenticated-client-action RedirectToLoginPage
```

**Equivalent Local Stack:** Stack 12 (OAuth2 Proxy)

### Azure Kubernetes Service (OAuth2 Proxy Sidecar)

**Configuration:**

```yaml
containers:
- name: oauth2-proxy
  image: quay.io/oauth2-proxy/oauth2-proxy:v7.6.0
  args:
  - --provider=oidc
  - --oidc-issuer-url=https://login.microsoftonline.com/{tenant}/v2.0
  - --upstream=http://localhost:80
- name: frontend
  image: myapp:latest
```

**Equivalent Local Stack:** Stack 12 (OAuth2 Proxy)

## Authentication Headers

### Easy Auth Headers (Azure)

```text
X-MS-CLIENT-PRINCIPAL: <base64-encoded-user-info>
X-MS-CLIENT-PRINCIPAL-ID: <user-object-id>
X-MS-CLIENT-PRINCIPAL-NAME: <user-email>
X-MS-TOKEN-AAD-ACCESS-TOKEN: <access-token>
X-MS-TOKEN-AAD-ID-TOKEN: <id-token>
```

### OAuth2 Proxy Headers (Stack 12, AKS)

```text
X-Auth-Request-User: <user-email>
X-Auth-Request-Email: <user-email>
X-Auth-Request-Preferred-Username: <username>
Authorization: Bearer <jwt-token>
X-Forwarded-User: <user-email>
```

### OIDC Headers (Stack 11)

```text
Authorization: Bearer <jwt-token>
(Client-side only - no server-side headers)
```

## Decision Matrix

### Choose Stack 11 (Client-Side OIDC) When

- Users can browse before logging in
- Progressive authentication (login only when needed)
- Standard SPA pattern preferred
- Deploying to Azure Static Web Apps (custom auth)
- Simple deployment requirements

### Choose Stack 12 (OAuth2 Proxy) When

- Must enforce login before viewing any content
- Testing Azure Easy Auth patterns locally
- Preparing for AKS deployment
- Security requirement: "no access without authentication"
- Need to simulate Azure App Service / Container Apps behavior

## Architecture Diagrams

### Stack 11 (Client-Side OIDC)

```text
┌──────────────┐
│ User Browser │
└──────┬───────┘
       │ 1. Request http://localhost:3006
       ↓
┌──────────────────────┐
│ Frontend (nginx)     │
│ Port: 3006           │
└──────┬───────────────┘
       │ 2. HTML/JS/CSS served
       ↓
┌──────────────────────┐
│ React App Loads      │
│ (oidc-client-ts)     │
└──────┬───────────────┘
       │ 3. User clicks "Login"
       ↓
┌──────────────────────┐
│ Keycloak             │
│ Port: 8180           │
└──────┬───────────────┘
       │ 4. OAuth flow
       ↓
┌──────────────────────┐
│ localStorage         │
│ (JWT token)          │
└──────┬───────────────┘
       │ 5. API calls with Bearer token
       ↓
┌──────────────────────┐
│ API Backend          │
│ Port: 8081           │
│ (validates JWT)      │
└──────────────────────┘
```

### Stack 12 (OAuth2 Proxy)

```text
┌──────────────┐
│ User Browser │
└──────┬───────┘
       │ 1. Request http://localhost:3007
       ↓
┌──────────────────────┐
│ OAuth2 Proxy         │
│ Port: 3007           │
│ (checks cookie)      │
└──────┬───────────────┘
       │ 2. No cookie? Redirect to Keycloak
       ↓
┌──────────────────────┐
│ Keycloak             │
│ Port: 8180           │
└──────┬───────────────┘
       │ 3. OAuth flow
       ↓
┌──────────────────────┐
│ OAuth2 Proxy         │
│ (sets cookie)        │
└──────┬───────────────┘
       │ 4. Redirect back, proxy to frontend
       ↓
┌──────────────────────┐
│ Frontend (nginx)     │
│ (internal only)      │
│ (adds auth headers)  │
└──────┬───────────────┘
       │ 5. API calls (cookie auto-sent)
       ↓
┌──────────────────────┐
│ API Backend          │
│ Port: 8081           │
│ (validates JWT)      │
└──────────────────────┘
```

## Testing Your Pattern

### Stack 11 Testing

```bash
# 1. Access frontend
curl http://localhost:3006
# Should return HTML immediately

# 2. Try API without auth
curl http://localhost:8081/api/v1/ipv4/validate?ip_address=192.168.1.1
# Should return 401 Unauthorized

# 3. Get token (browser flow only)
# Use browser to login, get token from localStorage

# 4. Try API with token
curl http://localhost:8081/api/v1/ipv4/validate?ip_address=192.168.1.1 \
  -H "Authorization: Bearer <token>"
# Should return results
```

### Stack 12 Testing

```bash
# 1. Access frontend without auth
curl -v http://localhost:3007
# Should redirect to Keycloak (302)

# 2. Check OAuth2 Proxy health
curl http://localhost:3007/ping
# Should return OK

# 3. Try to access frontend directly
curl http://localhost:80
# Should fail (connection refused - not exposed)

# 4. Browser test
open http://localhost:3007
# Should redirect to login automatically
```

## Migration Paths

### Local Development → Azure Deployment

#### Pattern 1: Stack 11 → Azure Static Web Apps

```text
Local:  React SPA with oidc-client-ts
        ↓
Azure:  Azure Static Web Apps with custom auth provider
        - Update OIDC authority to Entra ID
        - Update client ID to Azure app registration
        - Deploy with `swa deploy`
```

#### Pattern 2: Stack 12 → Azure Container Apps

```text
Local:  OAuth2 Proxy + Frontend
        ↓
Azure:  Azure Container Apps with Easy Auth
        - Remove OAuth2 Proxy container
        - Enable Easy Auth via Portal/CLI
        - Configure Entra ID provider
        - Deploy container image
```

#### Pattern 3: Stack 12 → Azure AKS

```text
Local:  OAuth2 Proxy + Frontend
        ↓
Azure:  AKS with OAuth2 Proxy sidecar
        - Use same OAuth2 Proxy configuration
        - Update OIDC issuer to Entra ID
        - Deploy as Kubernetes pod with sidecar
        - Configure ingress
```

## Common Issues and Solutions

### Issue: Redirect Loop (Stack 12)

```text
Cause: OAuth2 Proxy redirect URL doesn't match Keycloak config

Solution:
1. Check OAuth2 Proxy: --redirect-url=http://localhost:3007/oauth2/callback
2. Check Keycloak: redirectUris: ["http://localhost:3007/*"]
3. Clear browser cookies and retry
```

### Issue: JWT Validation Fails (Stack 11)

```text
Cause: Token issuer doesn't match API configuration

Solution:
1. Check token issuer: http://localhost:3007/realms/subnet-calculator
2. Check API config: OIDC_ISSUER=http://localhost:3007/realms/subnet-calculator
3. Ensure issuer URLs match exactly
```

### Issue: CORS Errors (Both Stacks)

```text
Cause: API doesn't allow requests from frontend origin

Solution:
1. Check API CORS config: CORS_ORIGINS=http://localhost:3006,http://localhost:3007
2. Ensure origin includes protocol (http://)
3. No trailing slash in origin URL
```

## References

- **Stack 11 Details:** See compose.yml Stack 11 section
- **Stack 12 Details:** [Stack12-OAuth2Proxy.md](./Stack12-OAuth2Proxy.md)
- **Azure Easy Auth:** [AzureEasyAuthSupport.md](./AzureEasyAuthSupport.md)
- **AKS Deployment:** [AKSAuthentication.md](./AKSAuthentication.md)

## Quick Command Reference

```bash
# Stack 11 (Client-Side OIDC)
podman-compose up -d keycloak api-fastapi-keycloak frontend-react-keycloak
open http://localhost:3006

# Stack 12 (OAuth2 Proxy)
podman-compose up -d keycloak api-fastapi-keycloak apim-simulator frontend-react-keycloak-protected oauth2-proxy-frontend
open http://localhost:3007

# View logs
podman-compose logs -f frontend-react-keycloak          # Stack 11
podman-compose logs -f oauth2-proxy-frontend            # Stack 12

# Restart services
podman-compose restart frontend-react-keycloak          # Stack 11
podman-compose restart oauth2-proxy-frontend            # Stack 12

# Stop services
podman-compose down keycloak api-fastapi-keycloak frontend-react-keycloak  # Stack 11
podman-compose down oauth2-proxy-frontend apim-simulator frontend-react-keycloak-protected # Stack 12
```
