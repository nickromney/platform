# Stack 3: Private Endpoint SWA + Entra ID

## Overview

Stack 3 demonstrates maximum security with private endpoints and custom domain as the ONLY access point. The default *.azurestaticapps.net domain is disabled for enhanced security.

## Architecture

```text
┌──────────────────────────────────────┐
│ User → Entra ID Login │
└──────────────┬───────────────────────┘
 │
┌──────────────▼───────────────────────┐
│ Azure Static Web App (Standard) │
│ - Custom domain (PRIMARY) │
│ - azurestaticapps.net (DISABLED) │
│ - Entra ID authentication │
│ - /api/* → Private VNet → Function │
└──────────────┬───────────────────────┘
 │ Private VNet
┌──────────────▼───────────────────────┐
│ VNet (10.0.0.0/16) │
│ ├─ functions subnet (10.0.1.0/24) │
│ └─ endpoints subnet (10.0.2.0/24) │
└──────────────┬───────────────────────┘
 │ Private Endpoint
┌──────────────▼───────────────────────┐
│ Azure Function App (S1/P0V3) │
│ - NO public access │
│ - Private endpoint only │
│ - VNet integration │
└──────────────────────────────────────┘
```

## Custom Domain

- **SWA**: `https://static-swa-private-endpoint.publiccloudexperiments.net` (PRIMARY ONLY)
- **Function**: Internal only (no public domain)

## Deployment

### Prerequisites

1. **Entra ID App**: Client ID and secret
1. **DNS Access**: CNAME for custom domain
1. **Budget**: ~$79-128/month for App Service Plan

### Quick Deploy

```bash
cd ~/Developer/personal/azure-tui/infrastructure/azure

# Set credentials
export AZURE_CLIENT_ID="your-client-id"
export AZURE_CLIENT_SECRET="your-secret"

# Optional: Choose plan (S1 or P0V3)
export APP_SERVICE_PLAN_SKU="S1" # Default: S1 ($70/mo)
# OR
export APP_SERVICE_PLAN_SKU="P0V3" # More RAM ($119/mo)

# Deploy
./azure-stack-16-swa-private-endpoint.sh
```

### DNS Record

```text
static-swa-private-endpoint.publiccloudexperiments.net → CNAME → <app>.azurestaticapps.net
```

### Redirect URI (Custom Domain ONLY)

Only one redirect URI is configured:

```text
https://static-swa-private-endpoint.publiccloudexperiments.net/.auth/login/aad/callback
```

Note: NO `*.azurestaticapps.net` URI - that domain is disabled.

## Key Security Features

### Network Isolation

1. **Private Endpoint**: Function App has NO public IP
1. **VNet Integration**: All backend communication via private network
1. **Network Security Group**: Controls subnet-level traffic
1. **Custom Domain PRIMARY**: Default *.azurestaticapps.net domain disabled

### Authentication

1. **Entra ID Only**: Platform-level authentication
1. **Single Domain**: Custom domain is ONLY access point
1. **HttpOnly Cookies**: Protected session management
1. **Restricted Redirects**: Only custom domain in redirect URIs

## Testing

### 1. Verify custom domain works

```bash
curl https://static-swa-private-endpoint.publiccloudexperiments.net
# Should redirect to Entra ID login
```

### 2. Verify default domain is disabled

```bash
curl https://<app>.azurestaticapps.net
# Should return error or refuse connection
```

### 3. Verify Function has no public endpoint

```bash
curl https://<func>.azurewebsites.net
# Should timeout or refuse (private endpoint only)
```

### 4. Test API via SWA proxy (authenticated)

```bash
# Login via browser first, then:
curl https://static-swa-private-endpoint.publiccloudexperiments.net/api/v1/health \
 -H "Cookie: StaticWebAppsAuthCookie=<cookie>"
# Should work (goes via private network)
```

## Architecture Components

### VNet Configuration

| Component | CIDR | Purpose |
|-----------|------|---------|
| VNet | 10.0.0.0/16 | Main virtual network |
| functions-subnet | 10.0.1.0/24 | VNet integration for Function |
| endpoints-subnet | 10.0.2.0/24 | Private endpoints |

### App Service Plan

Choose based on requirements:

| SKU | vCPU | RAM | Cost/Month | Best For |
|-----|------|-----|------------|----------|
| S1 | 1 | 1.75GB | $70 | Cost-effective |
| P0V3 | 1 | 4GB | $119 | More memory needed |

Both support:

- Private endpoints
- VNet integration
- Custom domains
- Linux + Python

## Security Comparison

| Feature | Stack 1 | Stack 2 | Stack 3 |
|---------|---------|---------|---------|
| Auth Method | JWT | Entra ID | Entra ID |
| Frontend Access | Public | Public | Public (custom only) |
| Backend Access | Public | Public | **Private only** |
| Default Domain | Active | Active | **Disabled** |
| Network Isolation | None | None | **Full VNet** |
| Compliance Ready | No | Partial | Yes |

## Troubleshooting

### Issue: Default domain still accessible

**Solution**: Run disable script manually

```bash
cd ~/Developer/personal/azure-tui/infrastructure/azure
./47-disable-default-hostname.sh
```

### Issue: Function App timeout

**Cause**: Private endpoint not properly configured

**Solution**: Verify private endpoint and DNS

```bash
# Check private endpoint
az network private-endpoint list \
 --resource-group rg-subnet-calc \
 --query "[].{Name:name, State:provisioningState}"

# Check DNS
nslookup <func>.azurewebsites.net
# Should resolve to private IP (10.0.x.x)
```

### Issue: High costs

**Mitigation**: Use S1 instead of P0V3

```bash
# Switch to S1 plan
export APP_SERVICE_PLAN_SKU="S1"
./azure-stack-16-swa-private-endpoint.sh
```

## Cost Breakdown

### With S1 Plan

| Resource | SKU | Monthly Cost |
|----------|-----|--------------|
| Static Web App | Standard | $9 |
| App Service Plan | S1 Linux | $70 |
| Private Endpoint | Standard | Included |
| **Total** | | **$79/month** |

### With P0V3 Plan

| Resource | SKU | Monthly Cost |
|----------|-----|--------------|
| Static Web App | Standard | $9 |
| App Service Plan | P0V3 Linux | $119 |
| Private Endpoint | Standard | Included |
| **Total** | | **$128/month** |

## When to Use Stack 3

### Good For

- Compliance requirements (SOC2, HIPAA, PCI-DSS)
- High-security environments
- Sensitive data processing
- Corporate internal applications
- Defense-in-depth security strategy

### NOT Needed For

- Public demos
- Non-sensitive data
- Tight budget constraints
- Simple prototypes

For most cases, **Stack 2** provides sufficient security at lower cost.

## Cleanup

```bash
# Delete all resources
az group delete --name rg-subnet-calc --yes --no-wait
```

## References

- [Azure Private Endpoints](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-overview)
- [VNet Integration](https://learn.microsoft.com/en-us/azure/app-service/overview-vnet-integration)
- [SWA Custom Domains](https://learn.microsoft.com/en-us/azure/static-web-apps/custom-domain)
