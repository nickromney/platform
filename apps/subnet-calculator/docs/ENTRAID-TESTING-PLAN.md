# Entra ID Testing Plan

## Overview

This document outlines the approach for testing Entra ID authentication with Azure Static Web Apps (SWA), specifically for the subnet calculator application.

### Architecture

```text
┌────────────────────────────────────────┐
│ User in Browser │
│ Visit: https://swa-xxx.azurestaticapps.net│
└─────────────┬──────────────────────────┘
 │
 │ User not authenticated
 ▼
┌────────────────────────────────────────┐
│ Entra ID Login Flow │
│ 1. SWA redirects to Entra ID │
│ 2. User enters credentials │
│ 3. Entra ID redirects back with token │
│ 4. SWA creates session cookie │
└─────────────┬──────────────────────────┘
 │
 │ User authenticated
 ▼
┌────────────────────────────────────────┐
│ TypeScript Vite Frontend (SWA) │
│ - Rendered by SWA │
│ - Authenticated user │
│ - Has session cookie (HttpOnly) │
└─────────────┬──────────────────────────┘
 │
 │ /api/* requests
 │ (via SWA proxy)
 ▼
┌────────────────────────────────────────┐
│ Azure Function App │
│ - IP restricted (SWA service tag only) │
│ - Linked backend (private) │
│ - Backend trusts SWA proxy headers │
│ - Returns x-ms-client-principal header │
└────────────────────────────────────────┘
```

### Testing Strategy

**Local Testing (SWA CLI):**

- Cannot simulate Entra ID in dev mode
- `swa start` with `apiDevserverUrl` only proxies to local backend
- Limited to unauthenticated testing

**Remote Testing (Azure Deployment):**

- Deploy actual SWA with Entra ID enabled
- Use real Entra ID credentials
- Test complete authentication flow
- Use Bruno CLI to validate API calls with authenticated tokens

### Approach: Remote-First for Entra ID

We will deploy to Azure and test against real Entra ID rather than trying to simulate it locally. This provides:

- Real-world testing of authentication flow
- Proper validation of SWA proxy behavior
- Actual HTTP headers from SWA (x-ms-client-principal, etc.)
- Foundation for production deployment

## Implementation Plan

### Phase 1: Entra ID App Registration (Manual - Azure Portal)

**Prerequisites:**

- Azure account with Entra ID tenant
- Permissions to create app registrations

**Steps:**

1. **Create App Registration**

- Portal: Azure Active Directory → App registrations
- Click "New registration"
- Name: `subnet-calc-entraid`
- Supported account types: Single tenant (default)
- Click "Register"

1. **Note These Values**

- Application (client) ID - shown on Overview page
- Directory (tenant) ID - shown on Overview page
- These will be used in deployment script

1. **Create Client Secret**

- Go to "Certificates & secrets"
- Click "New client secret"
- Description: `swa-auth`
- Expires: 24 months
- Click "Add"
- **COPY THE SECRET VALUE IMMEDIATELY** (only shown once)

### Phase 2: Deploy Stack to Azure

**Command:**

```bash
cd ~/Developer/personal/azure-tui/infrastructure/azure

export AZURE_CLIENT_ID="<your-application-id>"
export AZURE_CLIENT_SECRET="<your-client-secret>"

./azure-stack-06-swa-typescript-entraid-linked.sh
```

**What This Deploys:**

- Static Web App (Standard tier, Entra ID enabled)
- Azure Function App (linked backend)
- IP restrictions (SWA service tag only)
- Entra ID configuration (automatic redirect URI setup)

**Output:**

- SWA URL: `https://swa-subnet-calc-entraid-linked-xxxxx.eastus.azurestaticapps.net`
- Function App endpoint: Available via SWA proxy only

### Phase 3: Manual Testing (Browser)

1. **Visit the SWA URL**

- Should redirect to Entra ID login
- Login with your Entra ID credentials
- Should redirect back to SWA app

1. **Test Frontend**

- Verify page loads correctly
- Test calculator functionality
- Try subnet calculation

1. **Browser DevTools**

- Check Network tab
- Verify `/api/*` calls succeed
- Check response headers for `x-ms-client-principal` (indicates SWA proxy)

### Phase 4: Automated Testing (Bruno CLI)

**What to Test:**

- API health check (authenticated)
- Subnet calculations (authenticated)
- Authentication required validation

**Bruno Collection Structure:**

```text
swa-entraid/
 ├── Login Flow (if needed for token)
 ├── Health Check (with auth)
 ├── Subnet Info (with auth)
 └── 401 Validation (attempt without auth)
```

**Token Handling:**

Since SWA handles authentication via cookies (not Bearer tokens), Bruno tests will need to:

1. Access SWA frontend (which sets cookies)
1. Make subsequent API calls with cookies preserved
1. Validate successful responses

**Alternative Approach:**

- If API requires Bearer token, we may need Azure Service Principal token
- This would test service-to-service authentication pattern
- Different from user Entra ID but validates token-based flow

### Phase 5: Documentation

Document:

- How to set up Entra ID app registration
- How to obtain client ID and secret
- Deployment steps with Entra ID
- Testing procedures (browser + automated)
- Header expectations (x-ms-client-principal)
- Backend implementation notes (token validation if needed)

## Key Design Decisions

### 1. Auto-Generated Azure Domain (Not Custom)

**Why:**

- No DNS setup required
- No domain ownership verification
- No Cloudflare DNS complexity
- Works immediately after deployment
- Azure generates: `swa-xxx.eastus.azurestaticapps.net`

### 2. Linked Backend (Not Managed Function)

**Why:**

- Uses our existing Function App code
- Full control over backend implementation
- Can add custom authentication logic if needed
- Simulates production architecture

### 3. IP Restricted Backend (Defense-in-depth)

**Why:**

- Direct backend access blocked
- Only SWA proxy traffic allowed (via service tag)
- Matches production security posture
- Tests complete "protected API" scenario

### 4. Remote Testing First

**Why:**

- SWA CLI cannot simulate Entra ID
- Real Entra ID provides definitive testing
- Validates complete end-to-end flow
- Foundation for production deployment

## Success Criteria

- [ ] Entra ID app registration created
- [ ] Stack deployed to Azure
- [ ] Browser can log in via Entra ID
- [ ] Frontend loads after authentication
- [ ] API calls work (through SWA proxy)
- [ ] Bruno CLI tests validate flow
- [ ] Documentation complete
- [ ] Baseline confidence established

## Next Steps

1. Create Entra ID app registration in Azure Portal
1. Export Client ID and Secret
1. Run deployment script
1. Verify browser access
1. Create Bruno CLI tests
1. Document findings

## References

- [PRODUCTION-DEPLOYMENT.md](./PRODUCTION-DEPLOYMENT.md) - Complete Entra ID setup details
- [azure-stack-06-swa-typescript-entraid-linked.sh](~/Developer/personal/azure-tui/infrastructure/azure/azure-stack-06-swa-typescript-entraid-linked.sh) - Deployment script
- [STACK_INTENTIONS.md](./STACK_INTENTIONS.md) - Architecture framework
