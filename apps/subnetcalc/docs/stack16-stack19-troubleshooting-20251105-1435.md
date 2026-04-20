# Stack 16/19 Troubleshooting Session

**Timestamp:** 2025-11-05 14:35 UTC

## Objective

Configure Stack 19 routing architecture for Stack 16 resources:
**User Cloudflare AppGW SWA (frontend) + APIM (API) Function App**

## Current Resources

### Function App: `func-subnet-calc-asp-46195`

- **Plan:** `asp-subnet-calc-stack16` (B1 Basic - supports VNet)
- **Default hostname:** `func-subnet-calc-asp-46195.azurewebsites.net`
- **VNet integration:** `vnet-subnet-calc-private/snet-function-integration` (10.100.0.0/28)
- **Public access:** Enabled (but restricted)
- **Access restrictions:** Only allows traffic from APIM subnet (10.201.0.0/27)
- **Settings:**
- `AUTH_METHOD=none`
- `CORS_ORIGINS=https://static-swa-private-endpoint.publiccloudexperiments.net`
- `ALLOWED_SWA_HOSTS=static-swa-private-endpoint.publiccloudexperiments.net`
- **State:** Running
- **NSG:** `nsg-subnet-calc` on `snet-function-integration`

### APIM: `apim-subnet-calc-05845`

- **Gateway URL:** `https://apim-subnet-calc-05845.azure-api.net`
- **VNet Type:** Internal (NOT publicly accessible)
- **VNet:** `vnet-subnet-calc-apim-internal/snet-apim` (10.201.0.0/27)
- **Internal IP:** 10.201.0.4
- **API Configuration:**
- **API ID:** `func-subnet-calc-private-endpoint`
- **Path:** `` (empty string for pass-through)
- **Service URL:** `https://func-subnet-calc-asp-46195.azurewebsites.net`
- **Operations:**
- GET `/*` (wildcard)
- POST `/{route}` (original)
- **Policy:** Applied with IP-based auth, JWT forwarding, CORS
- **NSG:** `nsg-apim-internal` on `snet-apim`

### Static Web App: `swa-subnet-calc-private-endpoint`

- **Custom domain:** `static-swa-private-endpoint.publiccloudexperiments.net`
- **Default hostname:** `delightful-field-0cd326e03.3.azurestaticapps.net`
- **Linked backend:** Unlinked (was `func-subnet-calc-asp-46195`, now removed)
- **Private endpoint:** Yes (in `vnet-subnet-calc-private/snet-private-endpoints`)

### Application Gateway: `agw-swa-subnet-calc-private-endpoint`

- **VNet:** `vnet-subnet-calc-private` (10.100.0.0/24)
- **Subnet:** `snet-appgateway` (10.100.0.32/27)
- **Backend Pools:**
- `appGatewayBackendPool` SWA private endpoint
- `apim-backend-pool` 10.201.0.4 (APIM internal IP)
- **HTTP Settings:**
- `appGatewayBackendHttpSettings` Port 443, HTTPS, for SWA
- `apim-http-settings` Port 443, HTTPS, hostname: `apim-subnet-calc-05845.azure-api.net`
- **URL Path Map:** `path-map-swa-apim`
- Default rule: `/*` SWA backend pool
- Path rule: `/api/*` APIM backend pool
- **State:** Running

## VNet Architecture

### VNet: `vnet-subnet-calc-private` (10.100.0.0/24)

- `snet-private-endpoints` (10.100.0.16/28) - SWA private endpoint
- `snet-function-integration` (10.100.0.0/28) - Function VNet integration (outbound)
- `snet-appgateway` (10.100.0.32/27) - Application Gateway
- `snet-apim` (10.100.0.64/27) - Unused in this VNet

### VNet: `vnet-subnet-calc-apim-internal` (10.201.0.0/16)

- `snet-apim` (10.201.0.0/27) - APIM Internal (10.201.0.4)

### VNet Peering

- **Connected:** `vnet-subnet-calc-private` `vnet-subnet-calc-apim-internal`

## NSG Configuration

### NSG: `nsg-apim-internal` (on APIM subnet 10.201.0.0/27)

**Inbound Rules:**

- Priority 100: Allow-APIM-Management (ApiManagement VirtualNetwork:3443)
- Priority 105: **Allow-AppGW-to-APIM** (10.100.0.0/24 *:443) ADDED
- Priority 110: Allow-LoadBalancer (AzureLoadBalancer VirtualNetwork:*)
- Priority 120: Allow-Client-Traffic (Internet VirtualNetwork:?) [Incomplete rule]

**Outbound Rules:**

- Priority 100: Allow-Storage (VirtualNetwork Storage:443)
- Priority 110: Allow-AzureSQL (VirtualNetwork Sql:1433)
- Priority 120: Allow-AzureMonitor (VirtualNetwork AzureMonitor:?)
- Priority 130: **Allow-Function-HTTPS** (VirtualNetwork *:443) ADDED

### NSG: `nsg-subnet-calc` (on Function integration subnet 10.100.0.0/28)

**Inbound Rules:**

- Priority 100: **Allow-APIM-to-Function** (10.201.0.0/27 *:443) ADDED
- Priority 4096: DenyAllInbound (**:*)

**Outbound Rules:**

- (Default rules)

## Configuration Changes Made This Session

### 1. Created New Function App (14:05 UTC)

- Deleted old `func-subnet-calc-private-endpoint` (had private endpoint - incompatible with SWA linked backend)
- Created App Service Plan `asp-subnet-calc-stack16` (B1 Basic)
- Created Function App `func-subnet-calc-asp-46195` on B1 plan
- Configured VNet integration to `vnet-subnet-calc-private/snet-function-integration`
- Set `AUTH_METHOD=azure_swa` initially
- Deployed Function App code
- Linked to SWA backend **Still got 502** (SWA linked backend doesn't work with VNet-integrated Function Apps)

### 2. Switched to Stack 19 Routing (14:10 UTC)

- Ran `azure-stack-19-swa-private-apim-internal.sh` script
- Configured APIM backend API pointing to `func-subnet-calc-asp-46195`
- Applied APIM policy (IP-based auth, JWT forwarding)
- Configured AppGW path-based routing
- Changed Function `AUTH_METHOD=jwt` (script default)

### 3. Fixed Function App Settings (14:15 UTC)

- Changed `AUTH_METHOD=none` (APIM handles auth, not Function)
- Removed `JWT_SECRET` setting
- Unlinked SWA backend
- Restarted Function App

### 4. Restricted Function App Access (14:48 UTC)

- Added Function App access restriction: Only allow APIM subnet (10.201.0.0/27)
- Verified Function is NOT publicly accessible
- Verified APIM is NOT publicly accessible (Internal VNet mode)

### 5. Fixed NSG Rules (14:24-14:33 UTC)

**Problem Found:** NSGs were blocking traffic!

**Fixed:**

- Added `nsg-apim-internal` outbound rule: Allow HTTPS to Function App
- Added `nsg-subnet-calc` inbound rule: Allow APIM subnet (10.201.0.0/27)
- Added `nsg-apim-internal` inbound rule: Allow AppGW subnet (10.100.0.0/24)

### 6. Fixed APIM API Path (14:26 UTC)

- Changed APIM API path from `func-private-endpoint` to `` (empty) for pass-through routing
- Added GET `/*` wildcard operation to APIM API

## Current Status: 502 Bad Gateway

### Test Results (14:35 UTC)

```bash
curl -sI https://static-swa-private-endpoint.publiccloudexperiments.net/api/v1/health
HTTP/2 502
```

### What Works

1. Frontend loads (302 redirect to Entra ID login)
1. VNet peering is Connected
1. All NSG rules are in place
1. Function App access restrictions configured
1. APIM is Internal-only (not publicly accessible)
1. AppGW path-based routing configured

### What Doesn't Work

1. API requests return 502 Bad Gateway
1. Full routing path fails: User Cloudflare AppGW APIM Function

## Root Cause Analysis

The persistent 502 error suggests the issue is in the **AppGW APIM** connection.

### Why AppGW APIM is likely failing

1. **Internal APIM Certificate/SNI Issue:**

- AppGW is configured with hostname `apim-subnet-calc-05845.azure-api.net`
- AppGW backend pool points to internal IP `10.201.0.4`
- APIM Internal mode requires SNI and proper certificate validation
- AppGW may not be able to validate APIM's certificate on internal IP

1. **Health Probe Failure:**

- AppGW health probe command times out
- Cannot determine backend health status
- If probe fails, AppGW marks backend as unhealthy returns 502

1. **Missing DNS Resolution:**

- AppGW needs to resolve `apim-subnet-calc-05845.azure-api.net` to `10.201.0.4`
- No custom DNS or private DNS zone configured
- AppGW may be trying to resolve to public IP (which doesn't exist for Internal APIM)

## Next Steps to Debug

### Option 1: Check AppGW Health Probe Configuration

```bash
az network application-gateway probe list \
 --gateway-name agw-swa-subnet-calc-private-endpoint \
 --resource-group rg-subnet-calc
```

- Verify if a custom probe exists for APIM
- Check probe path, protocol, interval

### Option 2: Add Custom Health Probe for APIM

- Create probe pointing to APIM echo API or status endpoint
- Configure with proper hostname and path

### Option 3: Check Certificate Trust

- Verify APIM's certificate chain
- Check if AppGW needs certificate added to trusted root

### Option 4: Test APIM Connectivity from AppGW Subnet

- Create test VM in AppGW subnet
- Try to curl APIM internal endpoint
- Verify DNS resolution and connectivity

### Option 5: Check APIM Diagnostic Logs

- Enable APIM diagnostics
- Check for incoming requests from AppGW
- Verify if requests are being received and processed

### Option 6: Simplify Test

- Temporarily change APIM to External mode
- Test if AppGW can reach APIM when it has public IP
- This would confirm if issue is Internal APIM specific

## Configuration Files Referenced

- `/tmp/stack16-apim-routing-changes.md` (previous session)
- `azure-stack-19-swa-private-apim-internal.sh`
- `staticwebapp-entraid.config.json`

## Key Learning

**Azure Static Web Apps' linked backend feature is incompatible with Function Apps that have:**

1. Private endpoints
1. VNet integration (even on Basic/Premium plans)

This is why we switched to Stack 19's AppGW path-based routing architecture.
