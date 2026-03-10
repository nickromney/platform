# Phase 2: VNet Integration with App Service Plan

**Status:** Ready for implementation

**Sandbox Compatible:** Yes (~$0.08 for 4-hour sandbox)

## Overview

Phase 2 enables Azure Function App to run on an App Service Plan with VNet integration, allowing it to:

- Access private resources in the VNet (databases, VMs, etc.)
- Route all outbound traffic through the VNet
- Maintain "Always On" status (no cold starts)
- Run at predictable cost (vs Consumption's variable pricing)

### Cost Comparison

| Plan | Cost/Month | Cost/Hour | 4-Hour Sandbox | VNet Support |
|------|------------|-----------|----------------|--------------|
| Consumption | $0-5 | Variable | ~$0 | No |
| Basic B1 | ~$13 | ~$0.02 | ~$0.08 | Yes |
| Standard S1 | ~$70 | ~$0.10 | ~$0.40 | Yes |
| Premium EP1 | ~$160 | ~$0.22 | ~$0.88 | Yes |

**Recommendation:** B1 for sandbox testing, S1 for production

## Scripts

### 11-create-vnet-infrastructure.sh

#### Purpose

Create Azure Virtual Network with subnets for Function App integration and future Private Endpoints.

#### Prerequisites

- Resource group exists
- Azure CLI authenticated
- User has Network Contributor permissions

#### Environment Variables

```bash
# Required
RESOURCE_GROUP="${RESOURCE_GROUP:?Required}"

# Optional (with defaults)
LOCATION="${LOCATION:-}" # Auto-detected from RG if not set
VNET_NAME="${VNET_NAME:-vnet-subnet-calc}"
VNET_ADDRESS_SPACE="${VNET_ADDRESS_SPACE:-10.0.0.0/16}"
SUBNET_FUNCTION_NAME="${SUBNET_FUNCTION_NAME:-snet-function-integration}"
SUBNET_FUNCTION_PREFIX="${SUBNET_FUNCTION_PREFIX:-10.0.1.0/28}"
SUBNET_PE_NAME="${SUBNET_PE_NAME:-snet-private-endpoints}"
SUBNET_PE_PREFIX="${SUBNET_PE_PREFIX:-10.0.2.0/28}"
NSG_NAME="${NSG_NAME:-nsg-subnet-calc}"
```text

#### Logic Flow

1. **Validate prerequisites**
 - Check Azure CLI authentication
 - Verify resource group exists
 - Detect location from RG or use LOCATION variable

1. **Create VNet**
 - Name: `vnet-subnet-calc`
 - Address space: `10.0.0.0/16` (65,536 addresses)
 - Location: Same as resource group
 - Idempotent: Check if exists first

1. **Create Function integration subnet**
 - Name: `snet-function-integration`
 - Prefix: `10.0.1.0/28` (16 addresses)
 - Delegation: `Microsoft.Web/serverFarms` (required for ASP integration)
 - Purpose: For Function App VNet integration

1. **Create Private Endpoints subnet**
 - Name: `snet-private-endpoints`
 - Prefix: `10.0.2.0/28` (16 addresses)
 - No delegation
 - Purpose: For future Private Endpoint deployment

1. **Create Network Security Group**
 - Name: `nsg-subnet-calc`
 - Attach to Function integration subnet
 - Rules:
 - Allow outbound to internet (443, 80)
 - Allow outbound to Azure services
 - Deny all inbound (Function doesn't accept inbound from VNet)

1. **Output results**
 - VNet ID
 - Subnet IDs
 - NSG ID
 - Next steps

#### Expected Outputs

```text
VNet created: vnet-subnet-calc
 Address space: 10.0.0.0/16
 Location: eastus

Subnets created:
 snet-function-integration (10.0.1.0/28) - 16 addresses
 Delegated to: Microsoft.Web/serverFarms
 snet-private-endpoints (10.0.2.0/28) - 16 addresses
 No delegation

NSG attached: nsg-subnet-calc

Next steps:
 1. Create App Service Plan: ./12-create-app-service-plan.sh
 1. Migrate Function: ./13-migrate-function-to-app-service-plan.sh
```text

#### Testing Procedure

```bash
# Run script
RESOURCE_GROUP="1-xxxxx-playground-sandbox" ./11-create-vnet-infrastructure.sh

# Verify VNet created
az network vnet show \
 --name vnet-subnet-calc \
 --resource-group $RESOURCE_GROUP \
 --query "{name:name, addressSpace:addressSpace, subnets:subnets[].name}" \
 -o table

# Verify Function subnet delegation
az network vnet subnet show \
 --name snet-function-integration \
 --vnet-name vnet-subnet-calc \
 --resource-group $RESOURCE_GROUP \
 --query "delegations[0].serviceName" \
 -o tsv
# Expected: Microsoft.Web/serverFarms

# Verify NSG attached
az network vnet subnet show \
 --name snet-function-integration \
 --vnet-name vnet-subnet-calc \
 --resource-group $RESOURCE_GROUP \
 --query "networkSecurityGroup.id" \
 -o tsv
# Should show NSG resource ID

# Test idempotency (run again)
./11-create-vnet-infrastructure.sh
# Should handle existing resources gracefully
```text

#### Error Scenarios

**Error:** `Resource group not found`

- **Cause:** RESOURCE_GROUP doesn't exist or wrong name
- **Solution:** Verify RG name: `az group list --query "[].name" -o table`

**Error:** `Address space overlaps with existing VNet`

- **Cause:** 10.0.0.0/16 already in use
- **Solution:** Set `VNET_ADDRESS_SPACE="10.1.0.0/16"` and adjust subnet prefixes

**Error:** `Subnet delegation failed`

- **Cause:** Subnet already has resources or different delegation
- **Solution:** Delete subnet and recreate, or use different subnet name

**Error:** `NSG rule conflict`

- **Cause:** Conflicting NSG rules from previous deployment
- **Solution:** Delete NSG: `az network nsg delete --name nsg-subnet-calc --resource-group $RG`

#### Rollback

```bash
# Delete NSG
az network nsg delete --name nsg-subnet-calc --resource-group $RESOURCE_GROUP --yes

# Delete VNet (deletes all subnets)
az network vnet delete --name vnet-subnet-calc --resource-group $RESOURCE_GROUP --yes

# Or use cleanup script
./99-cleanup.sh
```text

#### Integration Points

- **Called by:** None (independent)
- **Used by:**
 - `14-configure-function-vnet-integration.sh` (uses Function subnet)
 - `51-configure-private-endpoint-swa.sh` (uses PE subnet, future)
- **Cost:** $0 (VNets are free, only resources using them cost money)

---

### 12-create-app-service-plan.sh

#### Purpose

Create an App Service Plan (B1 or S1) for running Azure Functions with VNet integration support.

#### Prerequisites

- Resource group exists
- Azure CLI authenticated
- User has Contributor permissions

#### Environment Variables

```bash
# Required
RESOURCE_GROUP="${RESOURCE_GROUP:?Required}"

# Optional (with defaults)
LOCATION="${LOCATION:-}" # Auto-detected from RG if not set
PLAN_NAME="${PLAN_NAME:-plan-subnet-calc}"
PLAN_SKU="${PLAN_SKU:-B1}" # B1, B2, B3, S1, S2, S3, P1V2, P1V3, etc.
PLAN_OS="${PLAN_OS:-Linux}" # Linux or Windows
PLAN_IS_LINUX="true" # Internal: true for Linux, false for Windows
```text

#### SKU Options

**Basic Tier:**

- B1: 1 core, 1.75GB RAM, ~$13/month
- B2: 2 cores, 3.5GB RAM, ~$26/month
- B3: 4 cores, 7GB RAM, ~$52/month
- Features: VNet integration, Always On, manual scale only

**Standard Tier:**

- S1: 1 core, 1.75GB RAM, ~$70/month
- S2: 2 cores, 3.5GB RAM, ~$140/month
- S3: 4 cores, 7GB RAM, ~$280/month
- Features: VNet integration, Always On, auto-scale (up to 10 instances), 5 staging slots

#### Logic Flow

1. **Validate prerequisites**
 - Check Azure CLI authentication
 - Verify resource group exists
 - Detect location from RG

1. **Check if App Service Plan exists**
 - Query for existing plan with same name
 - If exists and matches SKU: exit successfully
 - If exists with different SKU: warn and exit (don't auto-upgrade)

1. **Create App Service Plan**
 - Name: `plan-subnet-calc` (or custom)
 - SKU: B1 (or specified)
 - OS: Linux (required for Python Functions)
 - Location: Same as resource group
 - Number of workers: 1 (can scale later)

1. **Verify creation**
 - Query created plan
 - Display SKU, pricing tier, location
 - Calculate hourly and monthly cost

1. **Output results**
 - Plan name and ID
 - SKU details
 - Cost estimate
 - Next steps

#### Expected Outputs

```text
App Service Plan created: plan-subnet-calc
 SKU: B1 (Basic)
 vCPU: 1
 RAM: 1.75 GB
 OS: Linux
 Location: eastus

Cost estimate:
 Per hour: ~$0.02
 Per month: ~$13
 4-hour sandbox: ~$0.08

Next steps:
 1. Migrate function: ./13-migrate-function-to-app-service-plan.sh
 1. Or create new function on this plan:
 az functionapp create --name func-new --resource-group $RG \
 --plan plan-subnet-calc --runtime python --runtime-version 3.11
```text

#### Testing Procedure

```bash
# Test 1: Create B1 plan
RESOURCE_GROUP="1-xxxxx-playground-sandbox" \
PLAN_SKU="B1" \
./12-create-app-service-plan.sh

# Verify plan created
az appservice plan show \
 --name plan-subnet-calc \
 --resource-group $RESOURCE_GROUP \
 --query "{name:name, sku:sku.name, tier:sku.tier, cores:sku.capacity, os:reserved}" \
 -o table

# Verify pricing tier
az appservice plan show \
 --name plan-subnet-calc \
 --resource-group $RESOURCE_GROUP \
 --query "sku.tier" \
 -o tsv
# Expected: Basic

# Test 2: Idempotency (run again with same SKU)
./12-create-app-service-plan.sh
# Should detect existing and skip

# Test 3: Try different SKU (should warn and exit)
PLAN_SKU="S1" ./12-create-app-service-plan.sh
# Should warn that B1 already exists
```text

#### Error Scenarios

**Error:** `Plan already exists with different SKU`

- **Cause:** Plan exists as B1 but trying to create as S1
- **Solution:** Delete existing plan or use different name: `PLAN_NAME="plan-subnet-calc-s1"`

**Error:** `Invalid SKU`

- **Cause:** Typo in SKU name (e.g., "B1v2" doesn't exist)
- **Solution:** Use valid SKU: B1, B2, B3, S1, S2, S3, P1V2, P1V3, P2V2, P2V3, etc.

**Error:** `Insufficient quota`

- **Cause:** Sandbox region doesn't have capacity for B1
- **Solution:** Try different region or wait and retry

**Error:** `Resource group not found`

- **Cause:** RESOURCE_GROUP wrong or doesn't exist
- **Solution:** Verify: `az group show --name $RESOURCE_GROUP`

#### Rollback

```bash
# Delete App Service Plan (stops all charges)
az appservice plan delete \
 --name plan-subnet-calc \
 --resource-group $RESOURCE_GROUP \
 --yes

# Note: Must delete or move all apps on the plan first
# List apps: az functionapp list --resource-group $RG --query "[?appServicePlanId contains(@, 'plan-subnet-calc')].name"
```text

#### Integration Points

- **Called by:** `13-migrate-function-to-app-service-plan.sh`
- **Requires:** Resource group only
- **Used by:** Function Apps (one or more can share the plan)
- **Cost:** Starts immediately upon creation (~$0.02/hour for B1)

---

### 13-migrate-function-to-app-service-plan.sh

#### Purpose

Migrate an existing Consumption Function App to an App Service Plan, preserving all settings and code.

#### Prerequisites

- Source Function App exists (Consumption plan)
- Target App Service Plan exists (from script 12)
- Azure CLI authenticated
- Function code deployable (has deployment method)

#### Environment Variables

```bash
# Required
RESOURCE_GROUP="${RESOURCE_GROUP:?Required}"
SOURCE_FUNCTION_APP="${SOURCE_FUNCTION_APP:?Required: name of Consumption function}"
TARGET_FUNCTION_APP="${TARGET_FUNCTION_APP:-${SOURCE_FUNCTION_APP}-asp}"
APP_SERVICE_PLAN="${APP_SERVICE_PLAN:-plan-subnet-calc}"

# Optional
KEEP_SOURCE="${KEEP_SOURCE:-true}" # Keep source function as backup
DEPLOY_METHOD="${DEPLOY_METHOD:-zip}" # zip or scm
STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-}" # Auto-detected if not set
PYTHON_VERSION="${PYTHON_VERSION:-3.11}"
```text

#### Logic Flow

1. **Validate prerequisites**
 - Verify source Function App exists
 - Verify source is on Consumption plan
 - Verify target App Service Plan exists
 - Check if target Function App name is available

1. **Get source Function App details**
 - Retrieve all app settings
 - Get storage account connection string
 - Get runtime version (Python 3.11)
 - Get Functions version (4)
 - Note: Code will be redeployed from source

1. **Create target Function App on App Service Plan**
 - Name: `${SOURCE_FUNCTION_APP}-asp` (or custom)
 - Plan: `plan-subnet-calc` (the B1/S1 plan)
 - Storage: Same as source
 - Runtime: Python 3.11
 - Functions version: 4
 - OS: Linux

1. **Copy app settings**
 - Copy all settings from source to target
 - Exclude internal Azure settings (AzureWebJobsStorage, etc. - auto-set)
 - Include custom settings (AUTH_METHOD, JWT_SECRET_KEY, API_KEYS, etc.)

1. **Deploy code to target**
 - Get deployment package from source
 - Deploy to target using zip deployment
 - Wait for deployment to complete
 - Wait for function to warm up (2-3 minutes)

1. **Verify target Function App**
 - Test health endpoint
 - Verify app settings match
 - Compare function list

1. **Output migration report**
 - Source vs target comparison
 - Settings copied
 - Functions deployed
 - URLs for both
 - Recommendation to test before deleting source

#### Expected Outputs

```text
Migration Summary:
================

Source Function App:
 Name: func-subnet-calc-12345
 Plan: Consumption (Dynamic)
 URL: https://func-subnet-calc-12345.azurewebsites.net
 Functions: 5
 Settings: 12

Target Function App:
 Name: func-subnet-calc-asp
 Plan: plan-subnet-calc (Basic B1)
 URL: https://func-subnet-calc-asp.azurewebsites.net
 Functions: 5
 Settings: 12

Settings copied:
 AUTH_METHOD=apim
 API_KEYS=*****
 CORS=*
 (9 more settings)

Deployment:
 Code deployed successfully
 Function app responding
 Health check: PASSED

Next steps:
 1. Test new function: curl https://func-subnet-calc-asp.azurewebsites.net/api/v1/health
 1. Update frontend/APIM to use new URL
 1. Enable VNet integration: ./14-configure-function-vnet-integration.sh
 1. After verification, delete source: az functionapp delete --name func-subnet-calc-12345
```text

#### Testing Procedure

```bash
# Ensure source function exists and is deployed
curl https://func-subnet-calc-12345.azurewebsites.net/api/v1/health

# Run migration
RESOURCE_GROUP="1-xxxxx-playground-sandbox" \
SOURCE_FUNCTION_APP="func-subnet-calc-12345" \
TARGET_FUNCTION_APP="func-subnet-calc-asp" \
./13-migrate-function-to-app-service-plan.sh

# Test target function works
curl https://func-subnet-calc-asp.azurewebsites.net/api/v1/health

# Compare app settings
az functionapp config appsettings list \
 --name func-subnet-calc-12345 \
 --resource-group $RESOURCE_GROUP \
 --query "[].{name:name, value:value}" \
 -o table

az functionapp config appsettings list \
 --name func-subnet-calc-asp \
 --resource-group $RESOURCE_GROUP \
 --query "[].{name:name, value:value}" \
 -o table

# Verify plan type
az functionapp show \
 --name func-subnet-calc-asp \
 --resource-group $RESOURCE_GROUP \
 --query "serverFarmId" \
 -o tsv
# Should show: /subscriptions/.../plan-subnet-calc

# Test a few endpoints
curl https://func-subnet-calc-asp.azurewebsites.net/api/v1/docs
curl https://func-subnet-calc-asp.azurewebsites.net/api/v1/openapi.json
```text

#### Error Scenarios

**Error:** `Source function not found`

- **Cause:** SOURCE_FUNCTION_APP name wrong or doesn't exist
- **Solution:** List functions: `az functionapp list --resource-group $RG --query "[].name"`

**Error:** `Source is not on Consumption plan`

- **Cause:** Trying to migrate function already on App Service Plan
- **Solution:** Skip migration, or use different source

**Error:** `Target function name already exists`

- **Cause:** Function with target name already exists
- **Solution:** Choose different name: `TARGET_FUNCTION_APP="func-subnet-calc-b1"`

**Error:** `App Service Plan not found`

- **Cause:** Plan doesn't exist or wrong name
- **Solution:** Run `12-create-app-service-plan.sh` first

**Error:** `Deployment failed`

- **Cause:** Code deployment error, source function not properly deployed
- **Solution:** Check source function works first, check deployment logs

**Error:** `Function not responding after deployment`

- **Cause:** Cold start, or deployment still in progress
- **Solution:** Wait 2-3 minutes for warm-up, then retry health check

#### Rollback

```bash
# Target function not working? Keep using source
# Frontend/APIM still pointing to source, so no downtime

# Delete target function
az functionapp delete \
 --name func-subnet-calc-asp \
 --resource-group $RESOURCE_GROUP

# Source function unchanged, continues working

# If needed, delete App Service Plan to stop charges
az appservice plan delete \
 --name plan-subnet-calc \
 --resource-group $RESOURCE_GROUP
```text

#### Integration Points

- **Requires:**
 - Source Function App (Consumption)
 - App Service Plan (from script 12)
- **Used by:** `14-configure-function-vnet-integration.sh` (configures the migrated function)
- **Affects:** Frontend (API_URL must be updated), APIM (backend URL must be updated)
- **Cost:** Adds Function to existing B1 plan (no additional cost beyond plan)

---

### 14-configure-function-vnet-integration.sh

#### Purpose

Enable VNet integration on a Function App running on App Service Plan, routing outbound traffic through the VNet.

#### Prerequisites

- Function App exists on App Service Plan (from script 13)
- VNet with delegated subnet exists (from script 11)
- Function App and VNet in same region
- Azure CLI authenticated

#### Environment Variables

```bash
# Required
RESOURCE_GROUP="${RESOURCE_GROUP:?Required}"
FUNCTION_APP_NAME="${FUNCTION_APP_NAME:?Required: name of function on ASP}"
VNET_NAME="${VNET_NAME:-vnet-subnet-calc}"
SUBNET_NAME="${SUBNET_NAME:-snet-function-integration}"

# Optional
ROUTE_ALL_TRAFFIC="${ROUTE_ALL_TRAFFIC:-true}" # Route all outbound via VNet
```text

#### Logic Flow

1. **Validate prerequisites**
 - Verify Function App exists
 - Verify Function is on App Service Plan (not Consumption)
 - Verify VNet and subnet exist
 - Verify subnet is delegated to Microsoft.Web/serverFarms
 - Verify Function and VNet in same region

1. **Check current VNet integration status**
 - Query if VNet integration already enabled
 - If enabled: verify it's correct VNet/subnet
 - If wrong VNet: remove old integration first

1. **Enable VNet integration**
 - Add VNet integration to Function App
 - Connect to `snet-function-integration` subnet
 - Wait for integration to complete

1. **Configure route-all traffic**
 - Set `WEBSITE_VNET_ROUTE_ALL=1` app setting
 - This routes ALL outbound traffic through VNet (not just RFC1918)
 - Without this, only private IP ranges (10.x, 172.x, 192.168.x) route through VNet

1. **Verify integration**
 - Query VNet integration status (should show "Connected")
 - Test Function still responds
 - Check outbound IP (should be VNet NAT Gateway IP if configured)

1. **Output results**
 - Integration status
 - Connected VNet/subnet
 - Route-all status
 - Next steps (test connectivity to private resources)

#### Expected Outputs

```text
VNet Integration Configuration:
================================

Function App: func-subnet-calc-asp
 Current status: Not integrated
 Plan: plan-subnet-calc (Basic B1)

VNet: vnet-subnet-calc
 Subnet: snet-function-integration (10.0.1.0/28)
 Delegation: Microsoft.Web/serverFarms

Enabling integration...
 VNet integration added
 Connected to snet-function-integration
 WEBSITE_VNET_ROUTE_ALL=1 set

Integration status: Connected
 VNet ID: /subscriptions/.../vnet-subnet-calc
 Subnet ID: /subscriptions/.../snet-function-integration

Verification:
 Function app responding: 200 OK
 Health endpoint: PASSED

Next steps:
 1. Test function still works: curl https://func-subnet-calc-asp.azurewebsites.net/api/v1/health
 1. Test access to private resources (if any)
 1. Update APIM/frontend if needed: ./23-deploy-function-apim.sh
```text

#### Testing Procedure

```bash
# Run VNet integration
RESOURCE_GROUP="1-xxxxx-playground-sandbox" \
FUNCTION_APP_NAME="func-subnet-calc-asp" \
./14-configure-function-vnet-integration.sh

# Verify integration status
az functionapp vnet-integration list \
 --name func-subnet-calc-asp \
 --resource-group $RESOURCE_GROUP \
 --query "[].{vnet:vnetResourceId, subnet:subnetResourceId, status:status}" \
 -o table

# Check route-all setting
az functionapp config appsettings list \
 --name func-subnet-calc-asp \
 --resource-group $RESOURCE_GROUP \
 --query "[?name=='WEBSITE_VNET_ROUTE_ALL'].value" \
 -o tsv
# Expected: 1

# Test function still responds
curl https://func-subnet-calc-asp.azurewebsites.net/api/v1/health

# Test outbound IP (advanced)
# Create test function that returns outbound IP:
# curl https://func-subnet-calc-asp.azurewebsites.net/api/v1/test-outbound-ip
# Compare to VNet NAT Gateway IP (if configured)

# Test idempotency
./14-configure-function-vnet-integration.sh
# Should handle already-integrated gracefully
```text

#### Error Scenarios

**Error:** `Function not found`

- **Cause:** FUNCTION_APP_NAME wrong or doesn't exist
- **Solution:** List functions: `az functionapp list --resource-group $RG --query "[].name"`

**Error:** `Function not on App Service Plan`

- **Cause:** Trying to integrate Consumption function (not supported)
- **Solution:** Migrate to ASP first: `13-migrate-function-to-app-service-plan.sh`

**Error:** `VNet or subnet not found`

- **Cause:** VNet/subnet name wrong or doesn't exist
- **Solution:** Run `11-create-vnet-infrastructure.sh` first

**Error:** `Subnet not delegated`

- **Cause:** Subnet missing Microsoft.Web/serverFarms delegation
- **Solution:** Re-run `11-create-vnet-infrastructure.sh` or manually delegate

**Error:** `Region mismatch`

- **Cause:** Function in eastus, VNet in westus
- **Solution:** VNet and Function must be in same region

**Error:** `Integration failed`

- **Cause:** Network configuration issue, NSG blocking
- **Solution:** Check NSG rules allow outbound, check subnet has available IPs

**Error:** `Function not responding after integration`

- **Cause:** NSG blocking required Azure service traffic
- **Solution:** Update NSG to allow Azure service tags

#### Rollback

```bash
# Disable VNet integration
az functionapp vnet-integration remove \
 --name func-subnet-calc-asp \
 --resource-group $RESOURCE_GROUP

# Remove route-all setting
az functionapp config appsettings delete \
 --name func-subnet-calc-asp \
 --resource-group $RESOURCE_GROUP \
 --setting-names WEBSITE_VNET_ROUTE_ALL

# Function continues working, outbound traffic via Azure default routing
```text

#### Integration Points

- **Requires:**
 - Function App on ASP (from script 13)
 - VNet with delegated subnet (from script 11)
- **Enables:** Function to access private resources in VNet
- **Used for:** Connecting to private databases, VMs, storage accounts in VNet
- **Cost:** $0 (just configuration, no additional charges)

---

## Integration Testing

### Full Phase 2 Test (All 4 Scripts)

```bash
#!/usr/bin/env bash
# Test all Phase 2 scripts in sequence

set -euo pipefail

# Set variables
export RESOURCE_GROUP="1-xxxxx-playground-sandbox"
export SOURCE_FUNCTION_APP="func-subnet-calc-12345" # Your existing function

echo "======================================"
echo "Phase 2 Integration Test"
echo "======================================"
echo ""

# Test 1: VNet infrastructure
echo "Test 1: Creating VNet infrastructure..."
./11-create-vnet-infrastructure.sh
echo " VNet created"
echo ""

# Test 2: App Service Plan
echo "Test 2: Creating App Service Plan B1..."
PLAN_SKU=B1 ./12-create-app-service-plan.sh
echo " App Service Plan created"
echo ""

# Test 3: Migrate function
echo "Test 3: Migrating function to App Service Plan..."
TARGET_FUNCTION_APP="${SOURCE_FUNCTION_APP}-asp" \
./13-migrate-function-to-app-service-plan.sh
echo " Function migrated"
echo ""

# Test 4: VNet integration
echo "Test 4: Enabling VNet integration..."
FUNCTION_APP_NAME="${SOURCE_FUNCTION_APP}-asp" \
./14-configure-function-vnet-integration.sh
echo " VNet integration enabled"
echo ""

# Verification
echo "======================================"
echo "Verification"
echo "======================================"
echo ""

FUNCTION_URL="https://${SOURCE_FUNCTION_APP}-asp.azurewebsites.net"

echo "Testing function health..."
curl -f "${FUNCTION_URL}/api/v1/health" || echo "Health check failed!"
echo ""

echo "Testing function docs..."
curl -f "${FUNCTION_URL}/api/v1/docs" > /dev/null && echo " Docs accessible"
echo ""

echo "======================================"
echo "Phase 2 Complete!"
echo "======================================"
echo ""
echo "Function URL: ${FUNCTION_URL}"
echo "Old function still running as backup: https://${SOURCE_FUNCTION_APP}.azurewebsites.net"
echo ""
echo "Cost for 4-hour sandbox: ~$0.08"
echo ""
echo "Cleanup:"
echo " ./99-cleanup.sh"
```text

## Cost Tracking

### Actual Costs in Sandbox

Use this to track actual vs estimated costs:

```bash
# Get actual cost for App Service Plan
az appservice plan show \
 --name plan-subnet-calc \
 --resource-group $RESOURCE_GROUP \
 --query "sku.{tier:tier, name:name, capacity:capacity}" \
 -o table

# Pricing reference:
# B1: $0.018/hour = $13.14/month
# S1: $0.10/hour = $73/month

# For 4-hour sandbox:
# B1: $0.018 × 4 = $0.072
# S1: $0.10 × 4 = $0.40
```text

## Success Criteria

- [ ] All 4 scripts run without errors
- [ ] VNet created with 2 subnets
- [ ] Function subnet delegated to Microsoft.Web/serverFarms
- [ ] App Service Plan created with B1 SKU
- [ ] Function migrated and responding
- [ ] All app settings copied correctly
- [ ] VNet integration shows "Connected"
- [ ] WEBSITE_VNET_ROUTE_ALL=1 is set
- [ ] Function health endpoint returns 200 OK
- [ ] Cleanup removes all billable resources

## Troubleshooting

### Function not responding after VNet integration

**Symptoms:** Function returns 500 or timeout after enabling VNet integration

**Causes:**

1. NSG blocking Azure service tags
1. Subnet has no available IPs
1. DNS resolution failing

**Solutions:**

1. Check NSG rules: `az network nsg show --name nsg-subnet-calc`
1. Check subnet IP usage: `az network vnet subnet show --name snet-function-integration --vnet-name vnet-subnet-calc --query "ipConfigurations"`
1. Check function logs: `az functionapp log tail --name func-subnet-calc-asp`

### High costs in production

**Symptoms:** App Service Plan costs more than expected

**Causes:**

1. Auto-scaled to multiple instances (S1 tier)
1. Forgot to delete after testing
1. Using P1V2 instead of B1

**Solutions:**

1. Check instance count: `az appservice plan show --query "sku.capacity"`
1. Set scale rules: `az monitor autoscale create`
1. Downgrade SKU if not needed: `az appservice plan update --sku B1`
1. Delete unused plans: `az appservice plan delete`

### Migration failed

**Symptoms:** Target function created but not responding

**Causes:**

1. Deployment package corrupted
1. Source function was never deployed
1. Storage account connection lost

**Solutions:**

1. Verify source works: `curl https://source-function.azurewebsites.net/api/v1/health`
1. Redeploy manually: Use `22-deploy-function-zip.sh` pointing to target
1. Check storage connection: `az functionapp config appsettings list | grep AzureWebJobsStorage`
