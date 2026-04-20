# Stack 12 - OAuth2 Proxy Sidecar Pattern

## Overview

Stack 12 demonstrates the **OAuth2 Proxy sidecar pattern** - a local simulation of Azure Easy Auth's "forced login upfront" behavior. This stack shows how authentication can be enforced at the reverse proxy layer before users can access the frontend application.

## Architecture Comparison

### Stack 11 (Client-Side Auth)

```text
User → Frontend :3006 (nginx)
       ↓ (React loads immediately)
User sees UI → Clicks "Login" button
       ↓
OIDC flow in browser (oidc-client-ts)
       ↓ (authenticated)
API calls with JWT → Backend :8081
```

**Behavior:**

- Users see the UI immediately
- Authentication is optional until they try to use features
- Standard SPA pattern

### Stack 12 (OAuth2 Proxy - Easy Auth Simulation)

```text
User → OAuth2 Proxy :3007
       ↓ (checks authentication cookie)
       ↓ (if not authenticated)
302 Redirect to Keycloak login
       ↓ (user logs in)
OAuth flow completes
       ↓ (sets cookie)
OAuth2 Proxy :3007 (validates cookie)
       ↓ (authenticated - forwards request)
Frontend :8080 (nginx - NOT directly exposed)
       ↓ (React loads - user already authenticated)
OIDC flow in browser reuses SSO → SPA receives token
       ↓
API calls with JWT → APIM Simulator :8082 → FastAPI Backend :8081
```

**Behavior:**

- Users CANNOT see the UI without authenticating
- Authentication is required upfront
- Similar to Azure Easy Auth, Azure Static Web Apps, Azure Container Apps

## How It Works

### 1. OAuth2 Proxy as Authentication Gateway

OAuth2 Proxy acts as a reverse proxy that:

- Intercepts all requests to the frontend
- Checks for authentication cookie (`_oauth2_proxy`)
- If not authenticated: redirects to Keycloak login
- If authenticated: proxies request to the frontend nginx container
- Adds authentication headers to proxied requests

### 2. Frontend Container (Internal Only)

The `frontend-react-keycloak-protected` container:

- Does NOT have exposed ports (no `ports:` section)
- Only accessible through OAuth2 Proxy (via `expose: ["80"]`)
- Builds with `AUTH_METHOD=oidc` so the SPA can silently acquire tokens after OAuth2 Proxy signs the user in
- Cannot be accessed directly by users

### 3. Traffic Flow

```text
┌─────────────────────────────────────────────────────────┐
│ User's Browser                                          │
│                                                         │
│ 1. Requests http://localhost:3007                      │
│    ↓                                                    │
│ 2. No cookie? → Redirected to Keycloak                 │
│    ↓                                                    │
│ 3. Login at http://localhost:8180                      │
│    ↓                                                    │
│ 4. Redirected back to http://localhost:3007/oauth2/callback │
│    ↓                                                    │
│ 5. OAuth2 Proxy sets cookie                            │
│    ↓                                                    │
│ 6. Redirected to http://localhost:3007                 │
└─────────────────────────────────────────────────────────┘
         │
         ↓
┌─────────────────────────────────────────────────────────┐
│ OAuth2 Proxy Container (:3007)                          │
│                                                         │
│ 7. Validates cookie                                     │
│ 8. Adds headers:                                        │
│    - X-Auth-Request-User: demo@example.com              │
│    - X-Auth-Request-Email: demo@example.com             │
│    - Authorization: Bearer eyJ0eXAi...                  │
│ 9. Proxies to http://frontend-react-keycloak-protected:8080 │
└─────────────────────────────────────────────────────────┘
         │
         ↓
┌─────────────────────────────────────────────────────────┐
│ Frontend Container (internal :8080)                     │
│                                                         │
│ 10. Nginx serves React SPA                             │
│ 11. React loads (no client-side auth needed)           │
│ 12. React makes API calls to http://localhost:3007/apim     │
└─────────────────────────────────────────────────────────┘
         │
         ↓
┌─────────────────────────────────────────────────────────┐
│ APIM Simulator (:8082)                                  │
│                                                         │
│ 13. Validates subscription key + OIDC token            │
│ 14. Injects X-MS-CLIENT-PRINCIPAL headers               │
│ 15. Forwards to FastAPI backend :8081                   │
└─────────────────────────────────────────────────────────┘
```

## Quick Start

### Start Stack 12

```bash
cd subnetcalc

# Start Stack 12 services
podman-compose up -d keycloak api-fastapi-keycloak apim-simulator frontend-react-keycloak-protected oauth2-proxy-frontend

# Check status
podman-compose ps

# View logs
podman-compose logs -f oauth2-proxy-frontend
```

### Access the Application

1. **Open browser:** <http://localhost:3007>
2. **Automatic redirect:** You'll be redirected to Keycloak login
3. **Login:** Use demo credentials:
   - Username: `demo`
   - Password: `demo-password`
4. **Redirected back:** After login, you'll be redirected to the frontend
5. **Access granted:** You now have access to the subnet calculator

### Test the Flow

```bash
# 1. Try to access without authentication (should redirect)
curl -v http://localhost:3007

# 2. Check OAuth2 Proxy health
curl http://localhost:3007/ping

# 3. Call APIM simulator (fails without headers)
curl -i http://localhost:3007/apim/api/v1/health

# 4. Call APIM simulator with headers (still 401 without bearer token)
curl -i http://localhost:3007/apim/api/v1/health \
  -H "Ocp-Apim-Subscription-Key: stack12-demo-key"

# 5. Try to access frontend directly (should fail - not exposed)
curl http://localhost/
# curl: (7) Failed to connect to localhost port 80: Connection refused

# 6. After browser login, check your cookies
# Look for: _oauth2_proxy cookie
```

## Configuration Details

### OAuth2 Proxy Settings

Key configuration options in `compose.yml`:

```yaml
command:
  # OIDC Provider
  - --provider=oidc
  - --oidc-issuer-url=http://keycloak:8080/realms/subnetcalc
  - --client-id=frontend-app
  - --client-secret=frontend-secret

  # Where to proxy authenticated requests
  - --upstream=http://frontend-react-keycloak-protected:8080

  # Cookie settings (4 hour session, 1 hour refresh)
  - --cookie-expire=4h
  - --cookie-refresh=1h

  # Pass authentication info to upstream
  - --pass-authorization-header=true
  - --pass-access-token=true
  - --set-xauthrequest=true
```

### APIM Simulator (API Gateway) Settings

The `apim-simulator` container emulates Azure API Management in front of the FastAPI backend:

```yaml
environment:
  - BACKEND_BASE_URL=http://api-fastapi-keycloak:8080
  - OIDC_ISSUER=http://localhost:8180/realms/subnetcalc
  - OIDC_AUDIENCE=api-app
  - OIDC_JWKS_URI=http://keycloak:8080/realms/subnetcalc/protocol/openid-connect/certs
  - APIM_SUBSCRIPTION_KEY=stack12-demo-key
  - ALLOWED_ORIGINS=http://localhost:3007
```

Behavior:

- Rejects requests without `Ocp-Apim-Subscription-Key: stack12-demo-key`
- Validates OAuth2 access tokens against Keycloak JWKS
- Adds Easy Auth-style headers (`x-ms-client-principal`, `x-apim-user-email`, etc.)
- Proxies traffic to the FastAPI backend on port 8081

### Headers Added by OAuth2 Proxy

When proxying authenticated requests to the frontend, OAuth2 Proxy adds:

| Header | Description | Example Value |
|--------|-------------|---------------|
| `X-Auth-Request-User` | User's identifier | `demo@example.com` |
| `X-Auth-Request-Email` | User's email | `demo@example.com` |
| `X-Auth-Request-Preferred-Username` | Preferred username | `demo` |
| `X-Forwarded-User` | Forwarded user (legacy) | `demo@example.com` |
| `Authorization` | Bearer token | `Bearer eyJ0eXAiOiJKV1Qi...` |

These headers can be used by the frontend or backend to identify the authenticated user.

### Cookie Configuration

OAuth2 Proxy uses cookies for session management:

- **Cookie Name:** `_oauth2_proxy`
- **Cookie Duration:** 4 hours (configurable)
- **Cookie Refresh:** 1 hour before expiry
- **HTTPOnly:** Yes (cannot be accessed by JavaScript)
- **Secure:** No (only for local dev - set to `true` in production with HTTPS)

## Comparison with Azure Easy Auth

| Feature | Stack 12 (OAuth2 Proxy) | Azure Easy Auth |
|---------|------------------------|-----------------|
| **Forced Login** | Yes | Yes |
| **Server-Side Auth** | Yes | Yes |
| **Session Cookies** | Yes | Yes |
| **User Headers** | Yes (`X-Auth-Request-*`) | Yes (`X-MS-CLIENT-PRINCIPAL-*`) |
| **Token Refresh** | Yes (automatic) | Yes (automatic) |
| **OIDC/OAuth Support** | Yes (many providers) | Yes (Entra ID, Google, etc.) |
| **Configuration** | Container args | Portal / ARM template |
| **Hosting** | Any platform | Azure-specific services |
| **Local Development** | Easy (this stack!) | Difficult to simulate |

## Stack 12 vs Stack 11

### When to Use Stack 11 (Client-Side Auth)

**Best for:**

- Public-facing applications where users can browse before logging in
- Progressive authentication (login only when needed)
- Simple deployment (no reverse proxy needed)
- Standard SPA pattern

**Trade-offs:**

- Users see UI before authentication
- Cannot enforce "must be logged in to view anything"
- More client-side complexity

### When to Use Stack 12 (OAuth2 Proxy)

**Best for:**

- Internal applications requiring authentication upfront
- Simulating Azure Easy Auth behavior locally
- Testing AKS deployment patterns before going to production
- Security requirement: "no access without authentication"

**Trade-offs:**

- Additional container (OAuth2 Proxy)
- Slightly more complex setup
- Users cannot browse without logging in

## Using Stack 12 for Azure Deployment Testing

Stack 12 is ideal for testing patterns before deploying to Azure:

### Local (Stack 12)

```text
User → OAuth2 Proxy (Podman) → Frontend → API
```

### Azure Container Apps

```text
User → Built-in Easy Auth → Frontend → API
```

### Azure AKS

```text
User → Ingress → OAuth2 Proxy (Sidecar) → Frontend → API
```

## Troubleshooting

### Issue: Redirect Loop

**Symptoms:**

- Browser keeps redirecting between OAuth2 Proxy and Keycloak
- Never completes login

**Solutions:**

```bash
# 1. Check redirect URL matches
# In compose.yml:
- --redirect-url=http://localhost:3007/oauth2/callback

# 2. Check Keycloak allows the redirect
# In realm-export.json:
"redirectUris": ["http://localhost:3007/*"]

# 3. Clear browser cookies and try again
# Delete _oauth2_proxy cookie
```

### Issue: 403 Forbidden After Login

**Symptoms:**

- Login succeeds but OAuth2 Proxy returns 403
- "Permission denied" or "Forbidden" error

**Solutions:**

```bash
# 1. Check email-domain setting
# In compose.yml:
- --email-domain=*  # Allow all domains

# 2. Check user's email in Keycloak
# Make sure user has valid email set

# 3. Check OAuth2 Proxy logs
podman-compose logs oauth2-proxy-frontend
```

### Issue: Cannot Access Frontend Directly

**Symptoms:**

- `curl http://localhost:80` fails
- Connection refused

**Expected Behavior:**

- This is CORRECT! The frontend is only accessible through OAuth2 Proxy
- Direct access should be blocked

### Issue: OAuth2 Proxy Cannot Reach Keycloak

**Symptoms:**

- OAuth2 Proxy logs show connection errors
- "Failed to verify OIDC provider"

**Solutions:**

```bash
# 1. Check Keycloak is healthy
podman-compose ps
# keycloak should show "healthy"

# 2. Check containers are on same network
podman network inspect subnetcalc_default

# 3. Test connectivity
podman exec subnetcalc_oauth2-proxy-frontend_1 wget -O- http://keycloak:8080/realms/subnetcalc/.well-known/openid-configuration
```

### Issue: Cookies Not Persisting

**Symptoms:**

- Must log in every time
- Cookies don't save

**Solutions:**

```bash
# 1. Check cookie-secret is set
# In compose.yml:
- --cookie-secret=OQINaROshtE9TcZkNAm-5Zs2pZWWyqhBcfyqGMC5H0A=

# 2. Check browser cookie settings
# Make sure cookies are enabled
# Check for cookie blockers/extensions

# 3. Check cookie-secure setting
- --cookie-secure=false  # Must be false for HTTP (local dev)
```

## Advanced Configuration

### Custom Session Duration

```yaml
# Shorter sessions (1 hour)
- --cookie-expire=1h
- --cookie-refresh=30m

# Longer sessions (8 hours)
- --cookie-expire=8h
- --cookie-refresh=2h
```

### Restrict to Specific Domains

```yaml
# Only allow @example.com emails
- --email-domain=example.com

# Allow multiple domains
- --email-domain=example.com
- --email-domain=contoso.com
```

### Custom Scopes

```yaml
# Request additional scopes
- --scope=openid profile email groups

# Request custom scopes
- --scope=openid user_impersonation api.read
```

### Skip Authentication for Specific Paths

```yaml
# Allow public access to specific paths
- --skip-auth-regex=^/health$
- --skip-auth-regex=^/public/.*
```

### Add Custom Headers

```yaml
# Add custom headers to upstream requests
- --request-header=X-Custom-Header:value
- --request-header=X-Source:oauth2-proxy
```

## Production Considerations

### 1. HTTPS Only

```yaml
# Always use HTTPS in production
- --cookie-secure=true
- --redirect-url=https://myapp.example.com/oauth2/callback
```

### 2. Strong Cookie Secret

```bash
# Generate secure cookie secret
python -c 'import os,base64; print(base64.b64encode(os.urandom(32)).decode())'

# Or:
openssl rand -base64 32 | head -c 32
```

### 3. Use Kubernetes Secrets

```yaml
# Don't hardcode secrets in YAML
env:
  - name: OAUTH2_PROXY_CLIENT_SECRET
    valueFrom:
      secretKeyRef:
        name: oauth2-proxy-secrets
        key: client-secret
```

### 4. Configure Proper OIDC Provider

```yaml
# Use real Entra ID issuer
- --oidc-issuer-url=https://login.microsoftonline.com/{tenant-id}/v2.0
- --client-id={actual-client-id}
```

### 5. Resource Limits

```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi
```

## Testing

### Manual Testing

```bash
# 1. Start Stack 12
podman-compose up -d keycloak api-fastapi-keycloak apim-simulator frontend-react-keycloak-protected oauth2-proxy-frontend

# 2. Wait for services to be healthy
watch podman-compose ps

# 3. Open browser
open http://localhost:3007

# 4. Login with demo/demo-password

# 5. Verify authentication
# Check browser cookies for _oauth2_proxy

# 6. Try API calls
# Should work automatically with authentication
```

### Automated Testing

```bash
# Test OAuth flow end-to-end (requires browser automation)
cd frontend-react
bun run test:stack12

# Or use curl to test endpoints
curl -v http://localhost:3007/ping  # Should return OK
curl -v http://localhost:3007       # Should redirect to login
```

## Integration with Azure Deployment

This stack helps you test authentication patterns before deploying to Azure:

### Development Flow

1. **Local Development (Stack 12)**
   - Test OAuth2 Proxy configuration
   - Verify authentication flow
   - Test with Keycloak (Entra ID simulation)

2. **Azure Container Apps (Staging)**
   - Replace OAuth2 Proxy with Easy Auth
   - Same user experience
   - Minimal code changes

3. **Azure AKS (Production)**
   - Deploy OAuth2 Proxy as sidecar
   - Use same configuration as Stack 12
   - Connect to real Entra ID

### Configuration Mapping

| Stack 12 | Azure Container Apps | Azure AKS |
|----------|---------------------|-----------|
| OAuth2 Proxy container | Built-in Easy Auth | OAuth2 Proxy sidecar |
| Keycloak (local) | N/A | Entra ID |
| `--oidc-issuer-url` | `issuer` in ARM | `--oidc-issuer-url` |
| `--client-id` | `clientId` in ARM | `--client-id` |
| `--upstream` | Automatic | `--upstream` in pod |

## Next Steps

- **Learn more about OAuth2 Proxy:** [OAuth2 Proxy Documentation](https://oauth2-proxy.github.io/oauth2-proxy/)
- **Deploy to Azure:** See [AKSAuthentication.md](./AKSAuthentication.md) for AKS deployment
- **Understand Easy Auth:** See [AzureEasyAuthSupport.md](./AzureEasyAuthSupport.md) for Azure services
- **Compare stacks:** See [HOSTING-MATRIX.md](./HOSTING-MATRIX.md) for the
  stack and authentication overview

## Summary

Stack 12 demonstrates:

- "Forced login upfront" behavior (like Azure Easy Auth)
- OAuth2 Proxy as authentication gateway
- Server-side authentication enforcement
- Local testing of AKS deployment patterns
- Session management with cookies
- Automatic token refresh

This pattern is production-ready and can be deployed to:

- Azure Kubernetes Service (AKS) with OAuth2 Proxy sidecar
- Azure Container Apps with Easy Auth (similar behavior)
- Azure App Service with Easy Auth (similar behavior)
- Any Kubernetes cluster (on-prem, AWS EKS, GCP GKE)
