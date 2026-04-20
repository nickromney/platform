# Stack 17 vs Stack 18: SWA + APIM Architecture Comparison

This document explains the architectural differences between Stack 17 and Stack 18, both of which integrate Static Web Apps with API Management.

## Quick Reference Table

| Feature | Stack 17 (External APIM) | Stack 18 (Internal APIM) |
|---------|--------------------------|--------------------------|
| **Custom Domain** | `static-swa-apim.publiccloudexperiments.net` | `static-swa-apim-private.publiccloudexperiments.net` |
| **APIM VNet Mode** | External | Internal |
| **APIM Gateway Access** | Public (internet accessible) | Private (VNet only) |
| **SWA Private Endpoint** | Yes | Yes |
| **APIM Private Endpoint** | No (public gateway) | Yes (private gateway) |
| **Function Private Endpoint** | Yes | Yes |
| **SWA→APIM Backend Link** | Yes (`az staticwebapp backends link`) | No (not supported) |
| **AppGW Routing Type** | Basic (single backend per listener) | Path-based (`/*` → SWA, `/api/*` → APIM) |
| **Azure Automation** | Full (product, subscription, JWT) | Manual (no SWA linking) |
| **API URL for Frontend** | `/api/*` (proxied by SWA) | `/api/*` (same domain, path routing) |
| **Deployment Steps** | 9 steps | 13 steps |
| **Complexity** | Medium | High |
| **Security Level** | High (SWA + Function private) | Maximum (all components private) |
| **Microsoft Recommended For** | Hybrid scenarios (public API, private backends) | Enterprise/maximum security |
| **Estimated Deployment Time** | ~50-60 minutes | ~55-65 minutes |

## Architecture Diagrams

### Stack 17: External APIM with SWA Linking

```text
Internet
 ↓
 │ HTTPS (443)
 ↓
┌──────────────────────────────────────┐
│ Application Gateway │
│ (agw-swa-subnet-calc-private-endpoint)
│ - Listener: swa-apim-listener │
│ - Custom Domain: static-swa-apim... │
└──────────────────────────────────────┘
 ↓ HTTPS (443)
 │ Host Header: static-swa-apim.publiccloudexperiments.net
 ↓
┌──────────────────────────────────────┐
│ Static Web App (Private Endpoint) │
│ (swa-subnet-calc-apim) │
│ Private IP: 10.100.0.x │
│ │
│ ┌────────────────────────────────┐ │
│ │ Built-in Backend Linking │ │
│ │ (az staticwebapp backends link)│ │
│ │ - Proxies /api/* → APIM │ │
│ │ - Injects subscription key │ │
│ │ - Forwards access token │ │
│ └────────────────────────────────┘ │
└──────────────────────────────────────┘
 ↓ /api/* requests
 │ Includes: Subscription-Key header
 │ Authorization: Bearer token
 ↓
┌──────────────────────────────────────┐
│ API Management (VNet External Mode) │
│ (apim-subnet-calc-xxxxx) │
│ Gateway: https://apim-xxx.azure-api.net (PUBLIC)
│ VNet: Subnet integration │
│ Private IP: 10.100.0.y │
│ │
│ Auto-created by SWA linking: │
│ Product: "Azure Static Web Apps...│
│ Subscription key │
│ Inbound validate-jwt policy │
└──────────────────────────────────────┘
 ↓ Internal VNet routing
 │ HTTPS (443)
 ↓
┌──────────────────────────────────────┐
│ Function App (Private Endpoint) │
│ (func-subnet-calc-xxxxx) │
│ Private IP: 10.100.0.z │
│ Private FQDN: *.privatelink.azurewebsites.net
└──────────────────────────────────────┘
```

### Stack 18: Internal APIM with Path-Based Routing

```text
Internet
 ↓
 │ HTTPS (443)
 ↓
┌──────────────────────────────────────────────────┐
│ Application Gateway │
│ (agw-swa-subnet-calc-private-endpoint) │
│ - Listener: swa-apim-private-listener │
│ - Custom Domain: static-swa-apim-private... │
│ │
│ ┌────────────────────────────────────────────┐ │
│ │ URL Path-Based Routing │ │
│ │ - /* (default) → SWA Backend Pool │ │
│ │ - /api/* → APIM Backend Pool │ │
│ └────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────┘
 ↓ ↓
 │ /* requests │ /api/* requests
 ↓ ↓
┌────────────────────┐ ┌──────────────────────────┐
│ Static Web App │ │ API Management │
│ (Private Endpoint) │ │ (VNet Internal Mode) │
│ Private IP: 10.x.x.x│ │ Private Endpoint │
│ │ │ Private IP: 10.x.x.y │
│ NO backend linking │ │ │
│ (not supported │ │ Gateway: PRIVATE │
│ with private APIM)│ │ Only accessible via VNet │
└────────────────────┘ │ │
 │ Manual Configuration: │
 │ Product (manual) │
 │ Subscription (manual) │
 │ Policies (manual) │
 └──────────────────────────┘
 ↓
 │ Internal VNet routing
 ↓
 ┌──────────────────────────┐
 │ Function App │
 │ (Private Endpoint) │
 │ Private IP: 10.x.x.z │
 └──────────────────────────┘
```

## Key Technical Differences

### 1. APIM VNet Integration Mode

#### Stack 17: External Mode

- **APIM gateway endpoint**: Publicly accessible on internet
- **APIM subnet**: Integrated into VNet subnet (10.100.0.64/27)
- **Backend connectivity**: Can reach private Function App via VNet
- **Use case**: Public API gateway that needs to reach private backends
- **DNS**: Public DNS resolves to public IP
- **Firewall**: Can be restricted via NSG rules, but gateway is fundamentally public

```bash
# Stack 17 APIM creation
APIM_VNET_MODE="External" ./43-create-apim-vnet.sh
```

#### Stack 18: Internal Mode

- **APIM gateway endpoint**: Private IP only (accessible within VNet)
- **APIM subnet**: Integrated into VNet subnet (10.100.0.64/27)
- **Backend connectivity**: Reaches private Function App via VNet
- **Use case**: Fully private API gateway for maximum security
- **DNS**: Private DNS zone (privatelink.azure-api.net) resolves to private IP
- **Access**: Requires Application Gateway, VPN, or ExpressRoute

```bash
# Stack 18 APIM creation
APIM_VNET_MODE="Internal" ./43-create-apim-vnet.sh
```

### 2. SWA Backend Integration

#### Stack 17: Automatic Linking (Azure "Magic")

When you run `az staticwebapp backends link`, Azure automatically:

1. **Creates APIM Product**: `Azure Static Web Apps - <hostname> (Linked)`
1. **Generates Subscription Key**: Automatic key generation
1. **Configures JWT Validation**: Inbound policy added to product
1. **Enables Request Proxying**: SWA proxies `/api/*` to APIM
1. **Injects Headers**: SWA adds subscription key and access token

```bash
# Stack 17: Automatic linking
az staticwebapp backends link \
 --name "swa-subnet-calc-apim" \
 --resource-group "rg-subnet-calc" \
 --backend-resource-id "/subscriptions/.../Microsoft.ApiManagement/service/apim-name" \
 --backend-region "uksouth"
```

**Benefits**:

- Zero manual APIM configuration
- Automatic subscription key rotation
- Built-in authentication flow
- SWA handles all complexity

**Limitations**:

- Only works with publicly accessible backends
- Network isolated backends NOT supported
- Single backend per SWA

#### Stack 18: Manual Configuration (No Linking)

Because APIM has a private endpoint, `az staticwebapp backends link` **fails** with:

```text
Error: Network isolated backends are not supported
```

Instead, Stack 18 uses **Application Gateway path-based routing**:

```bash
# Stack 18: Path-based routing configuration
# Route /* → SWA backend pool
# Route /api/* → APIM backend pool

SWA_BACKEND_POOL="swa-apim-private-listener-backend" \
APIM_BACKEND_POOL="apim-backend" \
./55-add-path-based-routing.sh
```

**Manual steps required**:

1. Create APIM product manually (script 31)
1. Configure subscription keys manually (script 32)
1. Apply policies manually (script 32)
1. Configure AppGW path routing (script 55)

### 3. Application Gateway Configuration

#### Stack 17: Basic Routing

```text
Listener: swa-apim-listener
 ↓
Backend Pool: swa-apim-listener-backend
 ↓
Target: SWA private FQDN (*.privatelink.azurestaticapps.net)
```

Single backend pool, single HTTP settings, simple routing rule.

#### Stack 18: Path-Based Routing

```text
Listener: swa-apim-private-listener
 ↓
URL Path Map: swa-apim-private-listener-path-map
 ├─ /* (default) → swa-apim-private-listener-backend → SWA
 └─ /api/* → apim-backend → APIM
```

Multiple backend pools, multiple HTTP settings, path map with rules.

### 4. API Request Flow

#### Stack 17: SWA Proxies to APIM

```text
User Browser
 ↓ GET https://static-swa-apim.example.com/api/v1/calculate
AppGW
 ↓ Forwards to SWA
SWA (receives request)
 ↓ Detects /api/* path
 ↓ SWA built-in logic:
 ↓ - Adds: Ocp-Apim-Subscription-Key: <auto-key>
 ↓ - Adds: Authorization: Bearer <user-token>
 ↓ GET https://apim-xxx.azure-api.net/api/v1/calculate
APIM (public endpoint)
 ↓ Validates subscription key
 ↓ Validates JWT token
 ↓ Forwards to Function
Function App (private endpoint)
 ↓ Returns response
```

**Frontend code**:

```javascript
// Stack 17: Frontend makes API calls to relative /api/* paths
fetch('/api/v1/calculate', {
 method: 'POST',
 body: JSON.stringify(data)
})
// SWA automatically proxies to APIM
```

#### Stack 18: AppGW Routes to APIM

```text
User Browser
 ↓ GET https://static-swa-apim-private.example.com/api/v1/calculate
AppGW
 ↓ Path-based routing detects /api/*
 ↓ Routes to APIM backend pool
APIM (private endpoint, 10.x.x.y)
 ↓ Validates subscription key (if configured)
 ↓ Forwards to Function
Function App (private endpoint)
 ↓ Returns response
```

**Frontend code**:

```javascript
// Stack 18: Frontend makes API calls to same domain /api/* paths
// BUT the routing happens at AppGW level, not SWA
fetch('/api/v1/calculate', {
 method: 'POST',
 headers: {
 'Ocp-Apim-Subscription-Key': subscriptionKey // Manual if needed
 },
 body: JSON.stringify(data)
})
// AppGW routes /api/* to APIM directly
```

## When to Use Each Stack

### Use Stack 17 (External APIM) When

 You want **Azure automation** for APIM product/subscription/JWT configuration
 You're comfortable with APIM gateway being **publicly accessible**
 You want the **simplest** SWA→APIM integration
 You need to **iterate quickly** (less configuration)
 Your security requirements allow public APIM gateway (with NSG restrictions)
 You want SWA to **handle all API routing logic**

**Example use cases**:

- Public API with private backends
- Developer-facing APIs
- SaaS applications with private data tier
- Rapid prototyping with APIM

### Use Stack 18 (Internal APIM) When

 You require **maximum security** (all components private)
 You need **full isolation** of APIM gateway
 Compliance requires **no public API endpoints**
 You're implementing **enterprise security architecture**
 You want **split-brain DNS** (internal/external resolution)
 You're comfortable with **manual APIM configuration**

**Example use cases**:

- Enterprise internal applications
- Regulated industries (healthcare, finance)
- Zero-trust architecture
- Government/defense applications
- Multi-tenant SaaS with strict isolation

## Cost Comparison

Both stacks share most infrastructure:

| Resource | Stack 17 | Stack 18 | Monthly Cost |
|----------|----------|----------|--------------|
| **SWA Standard** | | | ~$9/month |
| **APIM Developer** | External mode | Internal mode | ~$50/month |
| **Function Consumption** | Reused | Reused | ~$0-20/month |
| **Application Gateway** | Reused | Reused | ~$215/month |
| **Key Vault** | Reused | Reused | ~$0.03/month |
| **Private Endpoints** | 2 (SWA, Function) | 3 (SWA, APIM, Function) | $0.01/hour each (~$21.60-$32.40/month) |
| **VNet** | Reused | Reused | Free |
| **DNS Zones** | Reused | +1 (APIM private) | ~$0.50/month |

**Total Incremental Cost per Stack**: ~$10-15/month beyond Stack 16

**Cost difference between Stack 17 and 18**: ~$10-11/month (one additional private endpoint + DNS zone)

## Deployment Time Comparison

| Phase | Stack 17 | Stack 18 |
|-------|----------|----------|
| **APIM Provisioning** | ~45 min (External mode) | ~45 min (Internal mode) |
| **Private Endpoint Creation** | 2 min (SWA only) | 5 min (SWA + APIM) |
| **APIM Configuration** | 3 min (auto via linking) | 8 min (manual) |
| **AppGW Configuration** | 5 min (basic routing) | 10 min (path-based routing) |
| **Other Steps** | ~5 min | ~5 min |
| **Total** | ~60 minutes | ~73 minutes |

## Migration Path

### Stack 17 → Stack 18

If you deploy Stack 17 first and later want Stack 18:

1. **Create new APIM instance** (Internal mode, different name)
1. **Create APIM private endpoint**
1. **Create new SWA** (different name for Stack 18)
1. **Add new AppGW listener** for Stack 18 domain
1. **Configure path-based routing**
1. **Copy APIM APIs** from Stack 17 APIM to Stack 18 APIM
1. **Update DNS** to point Stack 18 domain to AppGW

**No migration needed for**:

- VNet (shared)
- Application Gateway (add listener)
- Function App (shared)
- Key Vault (shared)

### Stack 18 → Stack 17

If you want to simplify from Stack 18 to Stack 17:

1. **Create new APIM instance** (External mode)
1. **Create new SWA** (for Stack 17)
1. **Link SWA to APIM** using `az staticwebapp backends link`
1. **Add AppGW listener** with basic routing
1. **Copy APIM APIs** from Stack 18 to Stack 17 APIM
1. **Update DNS**

## Security Considerations

### Stack 17 Attack Surface

**Public Components**:

- APIM gateway (public IP)
- Application Gateway (public IP)

**Private Components**:

- SWA (private endpoint only)
- Function App (private endpoint only)

**Security Controls**:

- NSG rules on APIM subnet (restrict public access)
- AppGW WAF (if using WAF_v2 SKU)
- APIM subscription keys
- APIM JWT validation
- Function App managed identity authentication

**Risk**: APIM gateway is publicly accessible (can be mitigated with NSG/firewall rules)

### Stack 18 Attack Surface

**Public Components**:

- Application Gateway (public IP) only

**Private Components**:

- SWA (private endpoint only)
- APIM (private endpoint only)
- Function App (private endpoint only)

**Security Controls**:

- All Stack 17 controls PLUS:
- APIM gateway not internet accessible
- Split-brain DNS (internal/external resolution)
- Network-level isolation for APIM

**Risk**: Minimal - only AppGW exposed to internet

## Testing and Validation

### Stack 17 Testing

```bash
# 1. Test SWA access
curl -v https://static-swa-apim.publiccloudexperiments.net/

# 2. Test API through SWA (automatic proxying)
curl -v https://static-swa-apim.publiccloudexperiments.net/api/v1/health

# 3. Test APIM directly (should work - public gateway)
curl -v https://apim-subnet-calc-xxxxx.azure-api.net/api/v1/health \
 -H "Ocp-Apim-Subscription-Key: <key>"

# 4. Verify SWA→APIM linking
az staticwebapp backends list \
 --name "swa-subnet-calc-apim" \
 --resource-group "rg-subnet-calc"
```

### Stack 18 Testing

```bash
# 1. Test SWA access
curl -v https://static-swa-apim-private.publiccloudexperiments.net/

# 2. Test API through AppGW path routing
curl -v https://static-swa-apim-private.publiccloudexperiments.net/api/v1/health

# 3. Test APIM directly (should FAIL - private gateway)
# From internet:
curl -v https://apim-subnet-calc-private-xxxxx.azure-api.net/api/v1/health
# Should timeout or refuse connection

# 4. Verify path routing
az network application-gateway url-path-map show \
 --gateway-name "agw-swa-subnet-calc-private-endpoint" \
 --resource-group "rg-subnet-calc" \
 --name "swa-apim-private-listener-path-map"
```

## Troubleshooting

### Stack 17 Common Issues

**Issue**: SWA→APIM linking fails with "Network isolated backends not supported"

- **Cause**: APIM is in Internal mode or has private endpoint
- **Fix**: Verify APIM is in External mode: `az apim show --name <name> --query virtualNetworkType`

**Issue**: API requests return 401 Unauthorized

- **Cause**: Subscription key not being injected
- **Fix**: Verify SWA backend link exists, check APIM product configuration

**Issue**: API requests timeout

- **Cause**: APIM cannot reach private Function App
- **Fix**: Verify APIM VNet integration, check NSG rules

### Stack 18 Common Issues

**Issue**: /api/* requests return 404

- **Cause**: Path-based routing not configured
- **Fix**: Verify URL path map exists with /api/* rule

**Issue**: /* requests route to APIM instead of SWA

- **Cause**: Path map default rule misconfigured
- **Fix**: Check default path rule points to SWA backend pool

**Issue**: APIM returns 502 Bad Gateway

- **Cause**: APIM cannot reach private Function App
- **Fix**: Verify both APIM and Function are in same VNet, check private endpoint DNS

## Summary

| Aspect | Stack 17 | Stack 18 |
|--------|----------|----------|
| **Simplicity** | Easier | More complex |
| **Security** | High | Maximum |
| **Azure Automation** | Full | Manual APIM config |
| **Enterprise Ready** | Good | Excellent |
| **Development Speed** | Fast | Slower |
| **Maintenance** | Low | Medium |

**Recommendation**: Start with **Stack 17** for development and testing. Migrate to **Stack 18** if security requirements demand fully private APIM gateway.
