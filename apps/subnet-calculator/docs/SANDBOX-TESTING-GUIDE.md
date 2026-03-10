# Pluralsight Sandbox Testing Guide

**Purpose:** Step-by-step guide for testing Phase 2 (VNet Integration) in a 4-hour Pluralsight sandbox.

**Total Cost:** ~$0.07 for 4-hour sandbox session (B1 App Service Plan only)

## Prerequisites

- Active Pluralsight sandbox (4-hour window)
- Azure CLI installed locally
- This repository cloned

## Setup (5 minutes)

### 1. Login to Azure Sandbox

```bash
# Follow Pluralsight instructions to get credentials
az login

# Verify you're logged in
az account show
```

### 2. Configure Environment

```bash
cd ~/Developer/personal/azure-tui/infrastructure/azure

# Run setup script - it will auto-detect the sandbox resource group
./setup-env.sh

# Export the variable (copy command from setup script output)
export RESOURCE_GROUP='1-xxxxx-playground-sandbox'

# Verify it's set
echo $RESOURCE_GROUP
```

## Phase 2: VNet Integration (30 minutes total)

### Step 1: Create VNet Infrastructure (2 minutes)

**What it does:** Creates VNet with two subnets - one for Function integration, one for future Private Endpoints.

```bash
./11-create-vnet-infrastructure.sh
```

**Expected output:**

- VNet created: `vnet-subnet-calc` (10.0.0.0/16)
- Function subnet: `snet-function-integration` (10.0.1.0/28) with Microsoft.Web/serverFarms delegation
- Private Endpoints subnet: `snet-private-endpoints` (10.0.2.0/28)
- NSG attached: `nsg-subnet-calc`

**Verify:**

```bash
# Check VNet exists
az network vnet show \
 --name vnet-subnet-calc \
 --resource-group $RESOURCE_GROUP \
 --query "{name:name, addressSpace:addressSpace.addressPrefixes[0]}" \
 -o table

# Check Function subnet delegation
az network vnet subnet show \
 --name snet-function-integration \
 --vnet-name vnet-subnet-calc \
 --resource-group $RESOURCE_GROUP \
 --query "delegations[0].serviceName" \
 -o tsv
# Should output: Microsoft.Web/serverFarms
```

**Cost:** $0 (VNets are free)

---

### Step 2: Create App Service Plan (1 minute)

**What it does:** Creates B1 (Basic) App Service Plan for running Functions with VNet integration.

```bash
# Use B1 SKU for lowest cost
PLAN_SKU=B1 ./12-create-app-service-plan.sh
```

**Expected output:**

- Plan created: `plan-subnet-calc`
- SKU: B1 (Basic)
- Specs: 1 vCPU, 1.75 GB RAM
- OS: Linux
- Cost: $0.018/hour, $13.14/month, $0.07/4-hour sandbox

**Verify:**

```bash
# Check plan exists
az appservice plan show \
 --name plan-subnet-calc \
 --resource-group $RESOURCE_GROUP \
 --query "{name:name, sku:sku.name, tier:sku.tier, os:kind}" \
 -o table
```

**Cost:** Starts charging immediately (~$0.018/hour)

---

### Step 3: Create Function App on App Service Plan (3 minutes)

**What it does:** Creates Function App on the App Service Plan (not Consumption).

```bash
FUNCTION_APP_NAME="func-subnet-calc-asp" ./13-create-function-app-on-app-service-plan.sh
```

**Expected output:**

- Function App created: `func-subnet-calc-asp`
- Plan: `plan-subnet-calc` (B1)
- Storage account created (if needed)
- URL: `https://func-subnet-calc-asp.azurewebsites.net`

**Verify:**

```bash
# Check Function exists on correct plan
az functionapp show \
 --name func-subnet-calc-asp \
 --resource-group $RESOURCE_GROUP \
 --query "{name:name, state:state, plan:appServicePlanId}" \
 -o table

# Test Function is accessible
curl -I https://func-subnet-calc-asp.azurewebsites.net
# Should return: HTTP/1.1 200 OK
```

**Cost:** No additional cost (uses existing App Service Plan)

---

### Step 4: Enable VNet Integration (2 minutes)

**What it does:** Connects Function App to VNet, routes all outbound traffic through VNet.

```bash
# Check status BEFORE enabling
FUNCTION_APP_NAME="func-subnet-calc-asp" ./14-configure-function-vnet-integration.sh --check

# Enable VNet integration
FUNCTION_APP_NAME="func-subnet-calc-asp" ./14-configure-function-vnet-integration.sh

# Check status AFTER enabling
FUNCTION_APP_NAME="func-subnet-calc-asp" ./14-configure-function-vnet-integration.sh --check
```

**Expected output:**

- VNet integration: Connected
- Subnet: `snet-function-integration`
- WEBSITE_VNET_ROUTE_ALL: 1 (all traffic routed)
- Function still responding: 200 OK

**Verify:**

```bash
# Check integration status
az functionapp vnet-integration list \
 --name func-subnet-calc-asp \
 --resource-group $RESOURCE_GROUP \
 --query "[].{vnet:vnetResourceId, subnet:name}" \
 -o table

# Check route-all setting
az functionapp config appsettings list \
 --name func-subnet-calc-asp \
 --resource-group $RESOURCE_GROUP \
 --query "[?name=='WEBSITE_VNET_ROUTE_ALL'].{name:name, value:value}" \
 -o table

# Test Function still works
curl https://func-subnet-calc-asp.azurewebsites.net/api/v1/health
```

**Cost:** No additional cost (VNet integration is free with App Service Plan)

---

## Optional: Deploy Function Code (10 minutes)

If you want to test the actual subnet calculator API:

```bash
# Deploy Function code
cd ../../api-fastapi-azure-function
RESOURCE_GROUP="$RESOURCE_GROUP" \
FUNCTION_APP_NAME="func-subnet-calc-asp" \
DISABLE_AUTH=true \
~/Developer/personal/azure-tui/infrastructure/azure/21-deploy-function.sh

# Test API
curl https://func-subnet-calc-asp.azurewebsites.net/api/v1/health
curl "https://func-subnet-calc-asp.azurewebsites.net/api/v1/ipv4/calculate?cidr=10.0.0.0/24"
```

**Cost:** No additional cost

---

## Verification Checklist

Use this checklist to verify everything is working:

- [ ] VNet created with 10.0.0.0/16 address space
- [ ] Function subnet has Microsoft.Web/serverFarms delegation
- [ ] NSG attached to Function subnet
- [ ] App Service Plan is B1 (Basic tier)
- [ ] Function App created on App Service Plan (not Consumption)
- [ ] VNet integration shows "Connected" status
- [ ] WEBSITE_VNET_ROUTE_ALL is set to 1
- [ ] Function responds to HTTP requests
- [ ] (Optional) API endpoints work if code deployed

---

## Cleanup (5 minutes)

**IMPORTANT:** Pluralsight sandboxes auto-delete after 4 hours, but it's good practice to clean up manually.

```bash
# Option 1: Delete individual resources (keeps resource group for sandbox)
cd ~/Developer/personal/azure-tui/infrastructure/azure
./99-cleanup.sh
# Type 'yes' to confirm

# Option 2: Delete entire resource group (NOT RECOMMENDED for sandbox)
# DELETE_RG=true ./99-cleanup.sh
```

**What gets deleted:**

- Function Apps (all)
- App Service Plans (all)
- VNet and subnets
- NSG
- Storage accounts
- APIM instances (if any)

**Cost savings:** Stops B1 App Service Plan charges immediately

---

## Troubleshooting

### VNet Integration Shows "Unknown" Status

**Cause:** Integration is still initializing (can take 1-2 minutes)

**Solution:** Wait and check again:

```bash
FUNCTION_APP_NAME="func-subnet-calc-asp" ./14-configure-function-vnet-integration.sh --check
```

### Function Not Responding After VNet Integration

**Cause:** Outbound connectivity issue or NSG rules too restrictive

**Solution:**

1. Check NSG rules allow outbound 443/80:

 ```bash
 az network nsg rule list \
 --nsg-name nsg-subnet-calc \
 --resource-group $RESOURCE_GROUP \
 --query "[].{name:name, priority:priority, direction:direction, access:access}" \
 -o table
 ```

1. Check Function logs:

 ```bash
 az functionapp log tail --name func-subnet-calc-asp --resource-group $RESOURCE_GROUP
 ```

### App Service Plan Creation Fails

**Cause:** Region doesn't support Basic tier

**Solution:** Try Standard S1 instead:

```bash
PLAN_SKU=S1 ./12-create-app-service-plan.sh
# Note: S1 costs ~$0.40 for 4-hour sandbox
```

### Subnet Delegation Error

**Cause:** Subnet not properly delegated to Microsoft.Web/serverFarms

**Solution:** Re-run script 11 (it's idempotent):

```bash
./11-create-vnet-infrastructure.sh
```

---

## Time Estimates

| Task | Estimated Time | Notes |
|------|---------------|-------|
| Setup & Login | 5 min | One-time per sandbox |
| Script 11 (VNet) | 2 min | Very fast |
| Script 12 (ASP) | 1 min | Very fast |
| Script 13 (Function) | 3 min | Includes storage account creation |
| Script 14 (VNet Integration) | 2 min | Includes verification |
| Optional: Deploy Code | 10 min | Only if testing API |
| Cleanup | 5 min | Good practice |
| **Total** | **13-28 min** | Leaves 3.5 hours for testing |

---

## Cost Summary

| Resource | Cost/Hour | Cost/4-Hour | Notes |
|----------|-----------|-------------|-------|
| VNet | $0 | $0 | Always free |
| NSG | $0 | $0 | Always free |
| App Service Plan B1 | ~$0.018 | ~$0.07 | Only chargeable resource |
| Function App | $0 | $0 | No additional cost on ASP |
| VNet Integration | $0 | $0 | Free with App Service Plan |
| Storage Account | <$0.01 | <$0.01 | Minimal for Function storage |
| **Total** | **~$0.02** | **~$0.07** | Very affordable for testing |

---

## Next Steps After Sandbox

Once you've validated Phase 2 works in the sandbox:

1. **Repeat in production subscription** with real resource group
1. **Test Phase 1 (Custom Domains)** - requires real domain name
1. **Test Phase 3 (Private Endpoints)** - requires Standard SKU Static Web App (~$9/month)
1. **Deploy frontend and test full stack** with VNet-integrated backend

---

## Questions?

- Check main documentation: `docs/IMPLEMENTATION-PLAN.md`
- Check Phase 2 details: `docs/PHASE-2-VNET-INTEGRATION.md`
- Review script source code for detailed error messages
