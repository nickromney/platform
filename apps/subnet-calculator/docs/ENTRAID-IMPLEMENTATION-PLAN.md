# Entra ID Implementation Plan

## Current State

**What's Working:**

- [x] SWA-04 deployed with TypeScript Vite frontend
- [x] Backend linked via SWA proxy pattern (relative URLs)
- [x] Frontend successfully calling `/api/v1/health` through SWA proxy
- [x] Health check returns: "Subnet Calculator API (Azure Function)"

**What's Deployed:**

- Static Web App: `swa-subnet-calc-entraid-linked`
- Frontend URL: `https://proud-bay-05b7e1c03.1.azurestaticapps.net/`
- Backend: Azure Function (func-subnet-calc-43825) linked via SWA

## Entra ID Integration Steps

### Phase 1: Configure Entra ID on SWA

**Prerequisites:**

- Entra ID app registration already created (Client ID: 370b8618-a252-442e-9941-c47a9f7da89e)
- Client Secret available

**Steps:**

1. Configure SWA with Entra ID credentials
1. Set up authentication provider in SWA
1. Configure allowed redirect URIs

**Commands:**

```bash
# Set Entra ID configuration on SWA
az staticwebapp appsettings set \
 --name swa-subnet-calc-entraid-linked \
 --resource-group rg-subnet-calc \
 --setting-names \
 AZURE_CLIENT_ID="370b8618-a252-442e-9941-c47a9f7da89e" \
 AZURE_CLIENT_SECRET="<your-secret>"

# Configure auth provider
az staticwebapp authproviders create \
 --name swa-subnet-calc-entraid-linked \
 --resource-group rg-subnet-calc \
 --provider aad \
 --client-id "370b8618-a252-442e-9941-c47a9f7da89e" \
 --client-secret "<your-secret>"
```

### Phase 2: Update Frontend for Entra ID

**Changes needed:**

1. Enable `VITE_AUTH_ENABLED=true` at build time
1. Frontend will display Entra ID login flow
1. SWA will inject authentication headers via `/api` proxy

**Build command:**

```bash
export STATIC_WEB_APP_NAME="swa-subnet-calc-entraid-linked"
export RESOURCE_GROUP="rg-subnet-calc"
export FRONTEND="typescript"
export API_URL=""
export VITE_AUTH_ENABLED="true"

./20-deploy-frontend.sh
```

### Phase 3: Test Authentication Flow

**Test scenarios:**

1. Unauthenticated access → redirects to Entra ID login
1. After login → shows authenticated user info
1. API calls include authentication via SWA proxy
1. Protected endpoints return 401 if auth missing

**Bruno CLI test collection:**

- New collection: `swa-entraid-authenticated`
- Tests:
- Health check (authenticated)
- Subnet calculations (authenticated)
- Verify auth headers from SWA
- Test 401 responses for missing auth

### Phase 4: Document Flow

**Document:**

- How Entra ID authentication works with SWA proxy
- What headers SWA injects (`x-ms-client-principal`)
- How frontend detects authenticated user
- How to configure for other Entra ID tenants

## Architecture After Entra ID

```text
User
 ↓
Entra ID Login (SWA handles)
 ↓
SWA (4000s)
 ├─ Frontend (TypeScript)
 │ └─ User info displayed
 │
 └─ /api proxy → Function App (8090)
 └─ Auth headers injected by SWA
 └─ Returns data
```

## Success Criteria

- SWA redirects to Entra ID login when accessing unauthenticated
- User can log in with Entra ID credentials
- Frontend displays authenticated user information
- API calls work through SWA proxy with auth
- Bruno CLI tests validate authenticated flow
- Documentation explains complete flow

## Future SWA Stacks

Once Entra ID works on SWA-04:

1. **SWA-01**: Container App + no auth (public)
1. **SWA-02**: Azure Function + JWT auth (app-level)
1. **SWA-03**: Container App + SWA auth (simple)
1. **SWA-04**: Azure Function + SWA Entra ID (current) ← Working toward this

## Notes

- SWA Entra ID configuration is different from app-level authentication
- SWA handles user session management automatically
- Frontend receives user info via SWA injected headers
- Backend doesn't need auth middleware (SWA enforces at proxy layer)
