# Application Gateway for SWA Private Endpoint - Design Document

**Date:** 2025-10-30
**Status:** Approved
**Target:** Azure Stack 16 (Private Endpoint + Entra ID)

## Problem Statement

Azure Static Web App with private endpoint is currently inaccessible from the internet. The custom domain (`static-swa-private-endpoint.publiccloudexperiments.net`) returns HTTP 403 because:

- SWA has `publicNetworkAccess: Disabled`
- Default azurestaticapps.net hostname is disabled
- Only access path is via private endpoint (10.100.0.21) within VNet

Users need public access via custom domain through Cloudflare, which terminates HTTPS and forwards HTTP traffic.

## Design Goals

1. Provide public internet access to private SWA via Application Gateway
1. Preserve custom domain Host header for Entra ID authentication
1. Use FQDN-based backend pool (resilient to IP changes)
1. Minimize cost (capacity 1, Standard_v2 SKU)
1. Enable future WAF upgrade without recreation
1. Leverage existing private DNS zone infrastructure

## Architecture

```text
Internet
 ↓ (HTTPS)
Cloudflare (HTTPS termination, SSL certificate)
 ↓ (HTTP, Host: static-swa-private-endpoint.publiccloudexperiments.net)
DNS CNAME → Public IP (Standard SKU)
 ↓
Application Gateway (Standard_v2, capacity 1)
├─ Frontend Listener: HTTP/80
├─ Backend Pool: FQDN (delightful-field-0cd326e03.privatelink.3.azurestaticapps.net)
├─ HTTP Settings: HTTPS/443, Host: static-swa-private-endpoint.publiccloudexperiments.net
└─ Routing Rule: HTTP → Backend Pool
 ↓
Private DNS Resolution
├─ Zone: privatelink.3.azurestaticapps.net
└─ A Record: delightful-field-0cd326e03 → 10.100.0.21
 ↓
SWA Private Endpoint (10.100.0.21:443)
 ↓
Static Web App (receives custom domain, auth works)
```

## Network Topology

**VNet:** vnet-subnet-calc-private (10.100.0.0/24)

| Subnet | CIDR | Purpose |
|--------|------|---------|
| snet-function-integration | 10.100.0.0/28 | Function App VNet integration |
| snet-private-endpoints | 10.100.0.16/28 | SWA + Function private endpoints |
| snet-appgateway | 10.100.0.32/27 | Application Gateway (NEW) |

## Components

### Application Gateway Configuration

| Property | Value | Rationale |
|----------|-------|-----------|
| **Name** | agw-swa-subnet-calc-private-endpoint | Auto-generated from SWA name |
| **SKU** | Standard_v2 | Cheapest v2 option, allows WAF upgrade |
| **Capacity** | 1 unit | Minimum for v2, ~$214/month |
| **Subnet** | snet-appgateway (10.100.0.32/27) | Minimum /27 for AppGW v2 |
| **Public IP** | pip-agw-swa-subnet-calc-private-endpoint | Standard SKU required for v2 |

### Frontend Configuration

| Property | Value | Rationale |
|----------|-------|-----------|
| **Protocol** | HTTP | Cloudflare handles HTTPS termination |
| **Port** | 80 | Standard HTTP port |
| **Public IP** | Standard SKU, Static allocation | Required for AppGW v2 |

### Backend Pool Configuration

| Property | Value | Rationale |
|----------|-------|-----------|
| **Address Type** | FQDN | Resilient to IP changes |
| **FQDN** | delightful-field-0cd326e03.privatelink.3.azurestaticapps.net | Dynamically constructed |
| **DNS Resolution** | Private DNS zone (privatelink.3.azurestaticapps.net) | Resolves to 10.100.0.21 |

### HTTP Settings Configuration

| Property | Value | Rationale |
|----------|-------|-----------|
| **Protocol** | HTTPS | SWA requires HTTPS |
| **Port** | 443 | Standard HTTPS port |
| **Host Header** | static-swa-private-endpoint.publiccloudexperiments.net | Custom domain for Entra ID auth |
| **Cookie Affinity** | Disabled | Not required for SPA |
| **Timeout** | 30 seconds | Default for SWA |

### Routing Rule Configuration

| Property | Value | Rationale |
|----------|-------|-----------|
| **Priority** | 100 | Default priority |
| **Listener** | HTTP/80 | Frontend listener |
| **Backend Pool** | SWA FQDN | Routes to private endpoint |
| **HTTP Settings** | Custom domain + HTTPS | Preserves auth context |

## Key Design Decisions

### 1. FQDN vs IP Address for Backend Pool

**Decision:** Use FQDN (`delightful-field-0cd326e03.privatelink.3.azurestaticapps.net`)

**Rationale:**

- Private endpoint IPs can change during re-provisioning
- FQDN resolution via private DNS zone is automatic
- More resilient to infrastructure changes
- Aligns with Azure best practices

**Trade-off:** Requires private DNS zone to be correctly configured (already done)

### 2. Host Header Configuration

**Decision:** Use custom domain (`static-swa-private-endpoint.publiccloudexperiments.net`)

**Rationale:**

- Entra ID redirect URIs are configured for custom domain
- SWA authentication expects requests from custom domain
- Consistent Host header from Cloudflare → AppGW → SWA
- Without this, authentication would fail (redirect URI mismatch)

**Alternative rejected:** Using default hostname would break Entra ID callbacks

### 3. Dynamic Region Number Extraction

**Decision:** Extract region number from SWA hostname using regex

**Rationale:**

- Region number (e.g., "3" in `*.3.azurestaticapps.net`) varies by SWA location
- Cannot hardcode `privatelink.3.azurestaticapps.net`
- Script must work across different Azure regions
- Pattern already established in script 48

**Implementation:**

```bash
if [[ "${SWA_HOSTNAME}" =~ \.([0-9]+)\.azurestaticapps\.net$ ]]; then
 SWA_REGION_NUMBER="${BASH_REMATCH[1]}"
 SWA_PRIVATE_FQDN=$(echo "${SWA_HOSTNAME}" | sed "s/\.${SWA_REGION_NUMBER}\.azurestaticapps\.net$/.privatelink.${SWA_REGION_NUMBER}.azurestaticapps.net/")
fi
```

### 4. Private IP Retrieval Method

**Decision:** Query DNS zone group instead of `customDnsConfigs`

**Rationale:**

- `customDnsConfigs[0].ipAddresses[0]` returns empty array (current bug)
- DNS zone group's `recordSets[0].ipAddresses[0]` reliably contains IP
- IP only used for verification and logging, not backend configuration
- Aligns with how private endpoint DNS actually works

**Implementation:**

```bash
SWA_PRIVATE_IP=$(az network private-endpoint dns-zone-group show \
 --name "default" \
 --endpoint-name "${PE_NAME}" \
 --resource-group "${RESOURCE_GROUP}" \
 --query "privateDnsZoneConfigs[0].recordSets[0].ipAddresses[0]" -o tsv)
```

### 5. Capacity and SKU Selection

**Decision:** Standard_v2 with capacity 1

**Rationale:**

- Minimum cost option (~$214/month vs ~$421 for capacity 2)
- Standard_v2 (not WAF_v2) saves ~$86/month initially
- Can upgrade to WAF_v2 later without full recreation
- Capacity 1 is sufficient for development/testing workload
- Can scale up if traffic increases

**Cost Breakdown:**

- Application Gateway Standard_v2: ~$0.295/hour × 730 hours = ~$215/month
- Public IP (Standard): ~$3.65/month
- Data processing: Variable (~$0.008/GB)
- **Total:** ~$219/month

## Script Modifications

### File: `49-create-application-gateway.sh`

#### Change 1: Add Dynamic FQDN Construction (after line 183)

**Location:** After retrieving `SWA_HOSTNAME`

**Code:**

```bash
# Extract region number and construct private FQDN
if [[ "${SWA_HOSTNAME}" =~ \.([0-9]+)\.azurestaticapps\.net$ ]]; then
 SWA_REGION_NUMBER="${BASH_REMATCH[1]}"
 SWA_PRIVATE_FQDN=$(echo "${SWA_HOSTNAME}" | sed "s/\.${SWA_REGION_NUMBER}\.azurestaticapps\.net$/.privatelink.${SWA_REGION_NUMBER}.azurestaticapps.net/")
 log_info "SWA Region Number: ${SWA_REGION_NUMBER}"
 log_info "SWA Private FQDN: ${SWA_PRIVATE_FQDN}"
else
 log_error "Could not determine SWA region number from hostname: ${SWA_HOSTNAME}"
 exit 1
fi
```

#### Change 2: Fix Private IP Retrieval (lines 199-211)

**Current (broken):**

```bash
SWA_PRIVATE_IP=$(az network private-endpoint show \
 --name "${PE_NAME}" \
 --resource-group "${RESOURCE_GROUP}" \
 --query "customDnsConfigs[0].ipAddresses[0]" -o tsv)
```

**New (working):**

```bash
SWA_PRIVATE_IP=$(az network private-endpoint dns-zone-group show \
 --name "default" \
 --endpoint-name "${PE_NAME}" \
 --resource-group "${RESOURCE_GROUP}" \
 --query "privateDnsZoneConfigs[0].recordSets[0].ipAddresses[0]" -o tsv 2>/dev/null)

if [[ -z "${SWA_PRIVATE_IP}" ]]; then
 log_error "Could not retrieve private IP for SWA private endpoint"
 log_error "Ensure DNS zone group is configured on the private endpoint"
 exit 1
fi
```

#### Change 3: Update Backend Pool to Use FQDN (line 296)

**Current:**

```bash
--servers "${SWA_PRIVATE_IP}" \
```

**New:**

```bash
--servers "${SWA_PRIVATE_FQDN}" \
```

#### Change 4: Reduce Capacity to Minimum (line 288)

**Current:**

```bash
--capacity 2 \
```

**New:**

```bash
--capacity 1 \
```

#### Change 5: Update HTTP Settings (lines 312-323)

**Current:**

```bash
--host-name "${SWA_HOSTNAME}" \
```

**New:**

```bash
--host-name "${CUSTOM_DOMAIN:-${SWA_HOSTNAME}}" \
```

**Rationale:** Uses custom domain if available (passed from stack-16), falls back to default hostname for standalone usage.

#### Change 6: Update Backend Pool After Creation (lines 303-309)

**Current:**

```bash
az network application-gateway address-pool update \
 --gateway-name "${APPGW_NAME}" \
 --resource-group "${RESOURCE_GROUP}" \
 --name appGatewayBackendPool \
 --servers "${SWA_PRIVATE_IP}" \
 --output none
```

**New:**

```bash
az network application-gateway address-pool update \
 --gateway-name "${APPGW_NAME}" \
 --resource-group "${RESOURCE_GROUP}" \
 --name appGatewayBackendPool \
 --servers "${SWA_PRIVATE_FQDN}" \
 --output none
```

#### Change 7: Update Summary Output (lines 326-363)

Update logging to show FQDN-based configuration:

```bash
log_info "Backend (SWA): ${SWA_PRIVATE_FQDN} (${SWA_PRIVATE_IP})"
log_info "Host Header: ${CUSTOM_DOMAIN:-${SWA_HOSTNAME}}"
```

## Testing Plan

### Phase 1: DNS Resolution Verification

**From Application Gateway subnet:**

```bash
# Should resolve to 10.100.0.21
nslookup delightful-field-0cd326e03.privatelink.3.azurestaticapps.net
```

### Phase 2: Backend Health Check

**Azure Portal:**

1. Navigate to Application Gateway → Backend health
1. Verify backend pool shows "Healthy" status
1. Check for any DNS resolution errors

**Azure CLI:**

```bash
az network application-gateway show-backend-health \
 --name agw-swa-subnet-calc-private-endpoint \
 --resource-group rg-subnet-calc
```

### Phase 3: HTTP Access Test

**Direct HTTP request:**

```bash
PUBLIC_IP=$(az network public-ip show \
 --name pip-agw-swa-subnet-calc-private-endpoint \
 --resource-group rg-subnet-calc \
 --query ipAddress -o tsv)

curl -v -H "Host: static-swa-private-endpoint.publiccloudexperiments.net" \
 http://${PUBLIC_IP}/
```

**Expected:** HTTP 200 with SWA content or HTTP 302 redirect to Entra ID login

### Phase 4: Entra ID Authentication Flow

1. Configure Cloudflare CNAME: `static-swa-private-endpoint.publiccloudexperiments.net` → `${PUBLIC_IP}`
1. Visit `https://static-swa-private-endpoint.publiccloudexperiments.net` (via Cloudflare)
1. Should redirect to Entra ID login
1. After login, should redirect back to SWA with valid session
1. Verify `/.auth/me` returns user information

### Phase 5: API Proxy Test

**Test linked backend Function App:**

```bash
curl https://static-swa-private-endpoint.publiccloudexperiments.net/api/v1/calculate \
 -H "Content-Type: application/json" \
 -d '{"network":"10.0.0.0/24","required_hosts":10}'
```

**Expected:** JSON response from Function App (routed via SWA → private Function endpoint)

## Rollback Plan

If Application Gateway causes issues:

### Option 1: Delete Application Gateway (retain private endpoint)

```bash
az network application-gateway delete \
 --name agw-swa-subnet-calc-private-endpoint \
 --resource-group rg-subnet-calc

az network public-ip delete \
 --name pip-agw-swa-subnet-calc-private-endpoint \
 --resource-group rg-subnet-calc
```

**Impact:** SWA returns to private-only access (no public access)

### Option 2: Re-enable Public Access (bypass private endpoint)

```bash
az staticwebapp update \
 --name swa-subnet-calc-private-endpoint \
 --resource-group rg-subnet-calc \
 --set properties.publicNetworkAccess=Enabled
```

**Impact:** Reverts to public SWA (defeats purpose of private endpoint)

## Future Enhancements

### 1. Enable WAF Protection

**Cost:** Additional ~$86/month (~$0.119/hour)

```bash
az network application-gateway update \
 --name agw-swa-subnet-calc-private-endpoint \
 --resource-group rg-subnet-calc \
 --set sku.name=WAF_v2 sku.tier=WAF_v2
```

### 2. Add HTTPS Listener

**Requirements:**

- SSL certificate for custom domain
- Additional frontend port (443)
- Updated routing rules

**Cost:** No additional charge (same capacity)

### 3. Increase Capacity/Enable Autoscaling

**For increased traffic:**

```bash
az network application-gateway update \
 --name agw-swa-subnet-calc-private-endpoint \
 --resource-group rg-subnet-calc \
 --set autoscaleConfiguration.minCapacity=1 \
 --set autoscaleConfiguration.maxCapacity=3
```

**Cost:** Variable based on actual capacity (~$214/month per unit)

## Security Considerations

1. **TLS Version:** Application Gateway → SWA uses TLS 1.2+ (Azure default)
1. **Host Header Validation:** SWA validates Host header against custom domain configuration
1. **Private Endpoint:** Backend traffic never leaves Azure backbone network
1. **Public IP:** Standard SKU includes DDoS protection Basic
1. **NSG Rules:** No NSG modifications required (AppGW subnet allows required traffic)

## Maintenance

### Monitor Backend Health

```bash
az network application-gateway show-backend-health \
 --name agw-swa-subnet-calc-private-endpoint \
 --resource-group rg-subnet-calc \
 --query "backendAddressPools[0].backendHttpSettingsCollection[0].servers[0].health" -o tsv
```

### View Application Gateway Metrics (Azure Portal)

- Backend response time
- Failed requests
- Total requests
- Backend connection time

## References

- Azure Application Gateway documentation: <https://learn.microsoft.com/en-us/azure/application-gateway/>
- SWA Private Endpoints: <https://learn.microsoft.com/en-us/azure/static-web-apps/private-endpoint>
- Application Gateway pricing: <https://azure.microsoft.com/en-us/pricing/details/application-gateway/>

## Approval

- **Design Approved:** 2025-10-30
- **Approved By:** User
- **Implementation:** Ready to proceed
