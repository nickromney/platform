# Implementation Plan: VNet Integration, Private Endpoints, and Custom Domains

**Last Updated:** 2025-01-13

**Status:** Implementation in progress

## Overview

This document provides the master implementation plan for adding VNet integration, private endpoints, and custom domains to the Azure subnet calculator deployment scripts.

### Goals

1. **Custom Domains** - Configure custom domains for Static Web App, Function App, and APIM
1. **VNet Integration** - Enable Function App to access private resources and route traffic through VNet
1. **Private Endpoints** - Restrict Static Web App access to private network only
1. **Cost Optimization** - Use App Service Plan instead of Elastic Premium to reduce costs by ~$147/month

### Key Decision: App Service Plan vs Elastic Premium

**Original Plan:** Use Elastic Premium (EP1) for VNet integration (~$160/month)

**Revised Plan:** Use App Service Plan (B1/S1) for VNet integration (~$13-70/month)

**Rationale:**

- App Service Basic B1 and Standard S1 now support VNet integration
- B1 saves $147/month vs EP1
- S1 saves $90/month vs EP1 and adds auto-scale
- Suitable for most production workloads
- Only downside: Cold start on scale-up (vs pre-warmed in EP1)

## Architecture

### Current State (Implemented)

```text
Azure Static Web App (Free)
 ↓ HTTPS
Azure Function App (Consumption)
```text

### Target State (After All Phases)

```text
Custom Domain (yourdomain.com)
 ↓
Azure Static Web App (Standard SKU)
 - Private Endpoint
 - Only accessible from VNet
 ↓ Private Link
Azure Virtual Network
 - Private DNS Zone
 - Subnets for integration & endpoints
 ↓ VNet Integration
Azure API Management (Developer)
 - Custom domain
 ↓ Private traffic
Azure Function App (App Service Plan)
 - VNet integration
 - Custom domain
 - Outbound via VNet
```text

## Phases

### Phase 1: Custom Domains (Scripts 40-42)

**Purpose:** Add custom domains to all three tiers

**Cost Impact:** $0 (free SSL/TLS certificates)

**Scripts:**

- `40-configure-custom-domain-swa.sh` - Static Web App custom domain
- `41-configure-custom-domain-function.sh` - Function App custom domain
- `42-configure-custom-domain-apim.sh` - APIM custom domain

**Prerequisites:**

- Own a domain name
- Access to DNS configuration (TXT and CNAME records)

**Deliverables:**

- Three scripts for custom domain configuration
- DNS validation automated where possible
- Free SSL/TLS certificates

**Testing:**

- Verify DNS propagation
- Test HTTPS on custom domains
- Verify redirect from default domains (optional)

### Phase 2: VNet Integration (Scripts 11-14)

**Purpose:** Enable Function App to access private resources and route traffic through VNet

**Cost Impact:** ~$13/month (B1) to ~$70/month (S1)

**Scripts:**

- `11-create-vnet-infrastructure.sh` - Create VNet, subnets, NSGs
- `12-create-app-service-plan.sh` - Create App Service Plan (B1/S1)
- `13-migrate-function-to-app-service-plan.sh` - Migrate from Consumption to ASP
- `14-configure-function-vnet-integration.sh` - Enable VNet integration

**Prerequisites:**

- Existing Function App (Consumption)
- Decide on SKU: B1 (testing) or S1 (production)

**Deliverables:**

- VNet with properly sized subnets
- App Service Plan with chosen SKU
- Function App running on ASP with VNet integration
- Migration path from Consumption

**Testing:**

- Verify outbound traffic routes through VNet
- Test Function can access resources in VNet
- Performance comparison (Consumption vs ASP)

### Phase 3: Private Endpoints (Scripts 50-52)

**Purpose:** Restrict Static Web App to private network access only

**Cost Impact:** ~$16/month (SWA Standard $9 + Private Endpoint $7)

**Scripts:**

- `50-upgrade-swa-to-standard.sh` - Upgrade SKU from Free to Standard
- `51-configure-private-endpoint-swa.sh` - Create private endpoint and DNS
- `52-verify-private-access.sh` - Verify configuration

**Prerequisites:**

- VNet infrastructure (from Phase 2)
- VM or Bastion for testing private access

**Deliverables:**

- Static Web App upgraded to Standard
- Private endpoint configured
- Private DNS zone linked to VNet
- Verification script with manual test instructions

**Testing:**

- Verify public access returns 403
- Verify private access works from VNet
- DNS resolution test (public vs private IP)

## Script Dependencies

### Dependency Graph

```text
Prerequisites:
 ├── Azure CLI installed
 ├── Logged in (az login)
 ├── Resource group exists
 └── Subscription with permissions

Phase 1 (Custom Domains):
 ├── 40-configure-custom-domain-swa.sh
 │ └── Requires: Static Web App (from 00-static-web-app.sh)
 ├── 41-configure-custom-domain-function.sh
 │ └── Requires: Function App (from 10-function-app.sh)
 └── 42-configure-custom-domain-apim.sh
 └── Requires: APIM (from 30-apim-instance.sh)

Phase 2 (VNet Integration):
 ├── 11-create-vnet-infrastructure.sh (independent)
 ├── 12-create-app-service-plan.sh (independent)
 ├── 13-migrate-function-to-app-service-plan.sh
 │ └── Requires: Consumption Function, App Service Plan (12)
 └── 14-configure-function-vnet-integration.sh
 └── Requires: Function on ASP (13), VNet (11)

Phase 3 (Private Endpoints):
 ├── 50-upgrade-swa-to-standard.sh (independent)
 ├── 51-configure-private-endpoint-swa.sh
 │ └── Requires: SWA Standard (50), VNet (11)
 └── 52-verify-private-access.sh
 └── Requires: Private endpoint (51)

Modifications:
 ├── 10-function-app.sh (add ASP support)
 └── 99-cleanup.sh (add cleanup for VNet, ASP, PE)
```text

## Environment Variables Reference

### Global Variables

```bash
# Required
RESOURCE_GROUP="rg-subnet-calc" # Resource group name

# Optional (auto-detected from RG if not set)
LOCATION="eastus" # Azure region
```text

### Phase 1 Variables (Custom Domains)

```bash
# Static Web App (40)
STATIC_WEB_APP_NAME="swa-subnet-calc" # SWA name
CUSTOM_DOMAIN="www.example.com" # Custom domain
SET_AS_DEFAULT="true" # Redirect traffic

# Function App (41)
FUNCTION_APP_NAME="func-subnet-calc" # Function name
CUSTOM_DOMAIN="api.example.com" # Custom domain
USE_MANAGED_CERTIFICATE="true" # Free cert vs custom

# APIM (42)
APIM_NAME="apim-subnet-calc" # APIM name
CUSTOM_DOMAIN="gateway.example.com" # Custom domain
CERTIFICATE_PATH="/path/to/cert.pfx" # If not using managed
```text

### Phase 2 Variables (VNet Integration)

```bash
# VNet Infrastructure (11)
VNET_NAME="vnet-subnet-calc" # VNet name
VNET_ADDRESS_SPACE="10.0.0.0/16" # VNet CIDR
SUBNET_FUNCTION_PREFIX="10.0.1.0/28" # Function subnet
SUBNET_PE_PREFIX="10.0.2.0/28" # Private endpoint subnet

# App Service Plan (12)
PLAN_NAME="plan-subnet-calc" # ASP name
PLAN_SKU="B1" # B1, B2, B3, S1, S2, S3
PLAN_OS="Linux" # Linux or Windows

# Migration (13)
SOURCE_FUNCTION_APP="func-subnet-calc" # Consumption function
TARGET_FUNCTION_APP="func-subnet-calc-asp" # New function on ASP
KEEP_SOURCE="true" # Keep old function as backup

# VNet Integration (14)
FUNCTION_APP_NAME="func-subnet-calc-asp" # Function to configure
VNET_NAME="vnet-subnet-calc" # VNet to integrate with
SUBNET_NAME="snet-function-integration" # Subnet for integration
ROUTE_ALL_TRAFFIC="true" # Route all outbound via VNet
```text

### Phase 3 Variables (Private Endpoints)

```bash
# Upgrade SWA (50)
STATIC_WEB_APP_NAME="swa-subnet-calc" # SWA to upgrade
CONFIRM_COST="true" # Acknowledge $9/month cost

# Private Endpoint (51)
STATIC_WEB_APP_NAME="swa-subnet-calc" # SWA name
VNET_NAME="vnet-subnet-calc" # VNet name
SUBNET_NAME="snet-private-endpoints" # PE subnet
PRIVATE_ENDPOINT_NAME="pe-swa" # PE name
DNS_ZONE_NAME="privatelink.azurestaticapps.net" # Private DNS zone

# Verification (52)
STATIC_WEB_APP_NAME="swa-subnet-calc" # SWA to verify
TEST_VM_NAME="vm-test" # VM for testing (optional)
```text

## Cost Breakdown

### By Phase

| Phase | Monthly Cost | One-Time | Total Month 1 |
|-------|--------------|----------|---------------|
| Current (Consumption + Free SWA) | $0-5 | $0 | $0-5 |
| Phase 1 (Custom Domains) | $0-5 | $0 | $0-5 |
| Phase 2 (VNet + B1) | $13 | $0 | $13 |
| Phase 2 (VNet + S1) | $70 | $0 | $70 |
| Phase 3 (Private Endpoint) | +$16 | $0 | +$16 |
| **Total (B1 + PE)** | **$29** | **$0** | **$29** |
| **Total (S1 + PE)** | **$86** | **$0** | **$86** |

### With APIM

| Configuration | Monthly Cost |
|---------------|--------------|
| Current (Consumption + Free SWA + APIM Dev) | $50-55 |
| B1 + APIM Dev | $63 |
| S1 + APIM Dev | $120 |
| S1 + PE + APIM Dev | $136 |
| S1 + PE + APIM Standard | $786 |

### SKU Comparison

| Feature | Consumption | Basic B1 | Standard S1 | Premium EP1 |
|---------|-------------|----------|-------------|-------------|
| **Cost/month** | $0-5 | ~$13 | ~$70 | ~$160 |
| **VNet Integration** | | | | |
| **Auto-scale** | | | (up to 10) | (dynamic) |
| **Cold Start** | Yes | Yes | Yes | No |
| **Staging Slots** | | | (5) | (3) |
| **Always On** | | | | |
| **Reserved Instances** | | | | |

### Sandbox Compatibility

| Feature | Pluralsight Sandbox | Cost | Recommendation |
|---------|---------------------|------|----------------|
| Custom Domains | Full support | $0 | **Implement** |
| VNet (B1) | Full support | ~$13/mo | **Good for testing** |
| VNet (S1) | Full support | ~$70/mo | Optional |
| Private Endpoint | Works but expensive | ~$16/mo | Document only |
| 4-hour limit | Challenging | N/A | Quick testing only |

## Implementation Order

### Recommended for Development

1. Create documentation (you are here)
1. Implement Phase 1 (custom domains) - $0
1. Test Phase 1 with real domain
1. Implement Phase 2 (VNet + B1) - $13/month
1. Test Phase 2 in sandbox
1. Skip Phase 3 (document but don't deploy)

### Recommended for Production

1. All phases in order
1. Use Standard S1 (auto-scale)
1. Implement Private Endpoint
1. Add Entra ID SSO (if needed)
1. Consider reserved instances for additional savings

## Testing Strategy

### Per-Script Testing

Each script should be tested for:

1. **Functionality** - Does it work?
1. **Idempotency** - Can run multiple times?
1. **Error handling** - Graceful failures?
1. **Rollback** - Can undo changes?

### Integration Testing

Test script combinations:

1. Phase 1 only
1. Phase 1 + Phase 2
1. All three phases together

### Manual Testing

Some tests require manual verification:

- DNS propagation (Phase 1)
- VNet connectivity (Phase 2)
- Private access from VM (Phase 3)

See `TESTING-GUIDE.md` for detailed procedures.

## Rollback Procedures

### Phase 1 Rollback (Custom Domains)

```bash
# Remove custom domain from SWA
az staticwebapp hostname delete \
 --name swa-subnet-calc \
 --resource-group rg-subnet-calc \
 --hostname www.example.com

# Remove custom domain from Function
az functionapp config hostname delete \
 --name func-subnet-calc \
 --resource-group rg-subnet-calc \
 --hostname api.example.com

# Remove custom domain from APIM
az apim api hostname delete \
 --name apim-subnet-calc \
 --resource-group rg-subnet-calc \
 --hostname gateway.example.com
```text

### Phase 2 Rollback (VNet Integration)

```bash
# Disable VNet integration
az functionapp vnet-integration remove \
 --name func-subnet-calc-asp \
 --resource-group rg-subnet-calc

# Keep App Service Plan (to avoid re-migration)
# Or delete and recreate Consumption Function App
```text

### Phase 3 Rollback (Private Endpoint)

```bash
# Delete private endpoint
az network private-endpoint delete \
 --name pe-swa \
 --resource-group rg-subnet-calc

# Delete private DNS zone (if not used elsewhere)
az network private-dns zone delete \
 --name privatelink.azurestaticapps.net \
 --resource-group rg-subnet-calc

# Downgrade SWA to Free (optional - cost savings)
az staticwebapp update \
 --name swa-subnet-calc \
 --resource-group rg-subnet-calc \
 --sku Free
```text

## Success Criteria

### Phase 1 Success

- [ ] Custom domains configured on all three services
- [ ] DNS validation passed
- [ ] HTTPS working on custom domains
- [ ] Free SSL/TLS certificates issued
- [ ] Optional: Traffic redirected to custom domains

### Phase 2 Success

- [ ] VNet and subnets created
- [ ] App Service Plan created with chosen SKU
- [ ] Function migrated from Consumption to ASP
- [ ] VNet integration enabled
- [ ] Outbound traffic routes through VNet
- [ ] Function can access private resources (if tested)

### Phase 3 Success

- [ ] Static Web App upgraded to Standard
- [ ] Private endpoint created
- [ ] Private DNS zone configured
- [ ] Public access returns 403
- [ ] Private access works from VNet
- [ ] Custom domain still works through private endpoint

## Timeline Estimate

| Activity | Time Estimate |
|----------|---------------|
| Documentation (all files) | 2-3 hours |
| Phase 1 Implementation | 1-2 hours |
| Phase 1 Testing | 30 min - 2 hours (DNS propagation) |
| Phase 2 Implementation | 2-3 hours |
| Phase 2 Testing | 1 hour |
| Phase 3 Implementation | 2-3 hours |
| Phase 3 Testing | 1-2 hours (requires VM setup) |
| Modifications | 1 hour |
| Integration Testing | 1-2 hours |
| Documentation Updates | 1 hour |
| **Total** | **12-18 hours** |

## Next Steps

1. Create `docs/` directory
1. Write `IMPLEMENTATION-PLAN.md` (this document)
1. Write `PHASE-1-CUSTOM-DOMAINS.md`
1. Write `PHASE-2-VNET-INTEGRATION.md`
1. Write `PHASE-3-PRIVATE-ENDPOINTS.md`
1. Write `MODIFICATIONS.md`
1. Write `TESTING-GUIDE.md`
1. Write `COST-CALCULATOR.md`
1. Implement scripts per phase
10. Test and validate
11. Update main `README.md`

## References

- [Azure Functions VNet Integration](https://learn.microsoft.com/en-us/azure/app-service/overview-vnet-integration)
- [Static Web Apps Private Endpoints](https://learn.microsoft.com/en-us/azure/static-web-apps/private-endpoint)
- [Azure Functions Hosting Options](https://learn.microsoft.com/en-us/azure/azure-functions/functions-scale)
- [App Service Plans](https://learn.microsoft.com/en-us/azure/app-service/overview-hosting-plans)
- [Custom Domains in Static Web Apps](https://learn.microsoft.com/en-us/azure/static-web-apps/custom-domain)
