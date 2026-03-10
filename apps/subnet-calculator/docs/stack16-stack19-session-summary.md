# Stack 16/19 Session Summary - 2025-11-05

## Session Objective

Configure Azure Stack 19 routing architecture for Stack 16 resources to enable:
**User → Cloudflare → Application Gateway → APIM (Internal) → Function App**

## What We Accomplished

### 1. Created New Function App Infrastructure

- **Deleted:** `func-subnet-calc-private-endpoint` (had private endpoint incompatible with SWA linked backend)
- **Created:** App Service Plan `asp-subnet-calc-stack16` (B1 Basic tier - supports VNet)
- **Created:** Function App `func-subnet-calc-asp-46195` on B1 plan
- **Configured:** VNet integration to `vnet-subnet-calc-private/snet-function-integration`
- **Deployed:** Function code successfully
- **Settings:** `AUTH_METHOD=none`, `CORS_ORIGINS`, `ALLOWED_SWA_HOSTS`

### 2. Validated Architecture Components

- **APIM:** Confirmed Internal VNet mode (NOT publicly accessible)
- **Function App:** Confirmed NOT publicly accessible (returns 401 without proper headers)
- **VNet Peering:** Confirmed Connected between AppGW VNet and APIM VNet
- **AppGW:** Path-based routing configured (`/api/*` → APIM, `/*` → SWA)

### 3. Fixed Critical NSG Issues

**Problem:** Network Security Groups were blocking all traffic between components

**Fixed:**

- **APIM NSG Outbound** (`nsg-apim-internal`): Added rule Priority 130 to allow HTTPS (443) to Function App
- **Function NSG Inbound** (`nsg-subnet-calc`): Added rule Priority 100 to allow traffic from APIM subnet (10.201.0.0/27)
- **APIM NSG Inbound** (`nsg-apim-internal`): Added rule Priority 105 to allow traffic from AppGW subnet (10.100.0.0/24)

### 4. Created Custom AppGW Health Probe

**Problem:** AppGW couldn't health check APIM internal endpoint, resulting in 502 errors

**Fixed:**

- Created custom health probe `apim-health-probe` with:
- Protocol: HTTPS
- Host: `apim-subnet-calc-05845.azure-api.net`
- Path: `/status-0123456789abcdef` (APIM status endpoint)
- Interval: 30s, Timeout: 30s, Threshold: 3
- Updated APIM HTTP settings to use custom probe

**Result:** Changed error from 502 (Bad Gateway - can't reach APIM) to 404 (APIM reachable but API routing issue)

### 5. Configured Function Access Restrictions

- Added inbound access restriction to only allow APIM subnet (10.201.0.0/27)
- Function App properly secured - not publicly accessible

## Current Status: 404 Not Found

### Progress

- User → Cloudflare → AppGW: **Working**
- AppGW → APIM: **Working** (confirmed by 404 instead of 502)
- NSG rules: **All configured correctly**
- VNet peering: **Connected**
- APIM API routing: **Not matching requests** (persistent 404)

### Error Analysis

When accessing `https://static-swa-private-endpoint.publiccloudexperiments.net/api/v1/health`:

- Client receives: `HTTP/2 404`
- This 404 is coming from **APIM**, not AppGW or Function
- APIM is receiving the request but not routing it to any operation

### APIM Configuration Attempts

We tried multiple configurations:

1. **API path: empty, Operations: `/*`** → 404
1. **API path: `api`, Operations: `/*`** → 404
1. **API path: `api`, Operations: `/api/*`** → 404
1. **API path: empty, Operations: `/api/*`** → 404
1. **Recreated API from scratch** → 404
1. **Disabled subscription requirement** → 404
1. **Added wildcard operations (GET, POST, OPTIONS)** → 404

## Infrastructure Resources

### Function App: `func-subnet-calc-asp-46195`

- **Hostname:** `func-subnet-calc-asp-46195.azurewebsites.net`
- **Plan:** `asp-subnet-calc-stack16` (B1 Basic)
- **VNet:** `vnet-subnet-calc-private/snet-function-integration` (10.100.0.0/28)
- **Settings:** `AUTH_METHOD=none`, `ALLOWED_SWA_HOSTS=static-swa-private-endpoint.publiccloudexperiments.net`
- **Access Restrictions:** Only APIM subnet (10.201.0.0/27)
- **State:** Running

### APIM: `apim-subnet-calc-05845`

- **Gateway URL:** `https://apim-subnet-calc-05845.azure-api.net`
- **Type:** Internal VNet (10.201.0.0/27)
- **Internal IP:** 10.201.0.4
- **API:** `func-subnet-calc-stack16`
- Path: `api`
- Service URL: `https://func-subnet-calc-asp-46195.azurewebsites.net`
- Subscription Required: false
- Operations: GET/POST `/*`

### Application Gateway: `agw-swa-subnet-calc-private-endpoint`

- **VNet:** `vnet-subnet-calc-private` (10.100.0.0/24)
- **Subnet:** `snet-appgateway` (10.100.0.32/27)
- **Backend Pools:**
- `appGatewayBackendPool` → SWA private endpoint
- `apim-backend-pool` → 10.201.0.4 (APIM internal IP)
- **HTTP Settings:**
- `apim-http-settings` → Port 443, HTTPS, Host: `apim-subnet-calc-05845.azure-api.net`, Probe: `apim-health-probe`
- **URL Path Map:** `path-map-swa-apim`
- `/api/*` → APIM backend pool
- `/*` (default) → SWA backend pool

### Static Web App: `swa-subnet-calc-private-endpoint`

- **Custom Domain:** `static-swa-private-endpoint.publiccloudexperiments.net`
- **Linked Backend:** None (unlinked)
- **State:** Running, frontend loads with Entra ID auth

## Key Learnings

### SWA Linked Backend Limitation

**Azure Static Web Apps' managed linked backend feature is incompatible with Function Apps that have:**

- Private endpoints
- VNet integration (even on Basic/Premium plans)
- Any advanced networking configuration

This is why Stack 16 requires the AppGW + APIM routing approach instead of simple SWA linked backend.

### Internal APIM with Application Gateway

Successfully configured AppGW to communicate with Internal APIM:

- Requires custom health probe with APIM hostname
- Requires NSG rules allowing AppGW subnet → APIM
- Requires VNet peering between AppGW and APIM VNets
- **Requires proper API routing configuration** (still working on this)

## Outstanding Issues

### Issue 1: APIM API Routing Returns 404

**Problem:** APIM receives requests from AppGW but doesn't route them to Function App

**Hypotheses:**

1. **Path mismatch:** AppGW sends `/api/v1/health`, APIM API has path `api`, operations have `/*`, but something in the matching logic fails
1. **Request header missing:** APIM might require specific headers that AppGW isn't forwarding
1. **APIM policy blocking:** The applied policy might be rejecting requests before reaching operations
1. **API versioning:** APIM might have revision/version requirements we're not meeting

**Next Steps to Debug:**

1. Enable APIM diagnostic logging to see exactly what requests APIM receives
1. Test APIM directly from within the VNet (create test VM in AppGW subnet)
1. Check APIM policy at global level (not just API level)
1. Try removing all APIM policies to see if they're blocking
1. Consider using APIM "All APIs" policies instead of API-specific
1. Test with a simpler Function endpoint (no authentication)

## Cost Considerations

**Current Infrastructure:**

- Application Gateway: ~$125/month (Basic v2)
- APIM Internal: ~$700/month (Developer tier)
- App Service Plan B1: ~$13/month
- Static Web App: Free tier
- **Total: ~$838/month**

**Alternative Approaches to Consider:**

1. **SWA + Function (no VNet):** Just use SWA linked backend with public Function App + host validation (~$0-13/month)
1. **AppGW + Function directly:** Skip APIM, route directly to Function (~$125-138/month)
1. **Azure Front Door + Function:** Use AFD instead of AppGW+APIM (~$30-50/month)

## Files Modified/Created

- `subnet-calculator/docs/stack16-stack19-troubleshooting-20251105-1435.md` - Detailed troubleshooting log
- `subnet-calculator/docs/stack16-stack19-session-summary.md` - This summary

## Azure Resources Modified (via CLI - not in code)

- Created App Service Plan: `asp-subnet-calc-stack16`
- Created Function App: `func-subnet-calc-asp-46195`
- Added NSG rules on: `nsg-apim-internal`, `nsg-subnet-calc`
- Created AppGW health probe: `apim-health-probe`
- Updated AppGW HTTP settings: `apim-http-settings`
- Created/modified APIM API: `func-subnet-calc-stack16`
- Added Function access restrictions
- Configured Function VNet integration

## Recommendations

### Short-term: Fix APIM Routing

Continue debugging the APIM 404 issue with diagnostic logging and VNet testing.

### Long-term: Reconsider Architecture

Given the complexity and cost, consider:

1. **For Stack 16 (Private SWA):** Use AppGW → Function directly (skip APIM)
1. **For Stack 19 (Full private):** Current AppGW → APIM → Function makes sense if all must be private
1. **For simpler stacks:** Use SWA linked backend with public Function App + host validation

### Alternative: Simplify Stack 16

Stack 16's goal is "SWA with private endpoint." The Function doesn't need to be fully private - it can be public with:

- `AUTH_METHOD=none` + `ALLOWED_SWA_HOSTS` validation
- Or keep VNet integration but allow public inbound
- This avoids the AppGW+APIM complexity entirely

## Session Duration

Approximately 4 hours (2025-11-05 12:00-16:00 UTC)

## Next Session Goals

1. Enable APIM diagnostic logging
1. Create test VM in AppGW subnet to test APIM directly
1. Review APIM policies and try removing them
1. If APIM routing cannot be fixed, consider alternative architectures
