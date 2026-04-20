# Application Gateway for SWA Private Endpoint - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix Application Gateway script to access SWA private endpoint using FQDN-based backend with custom domain Host header

**Architecture:** Modify existing script 49 to dynamically construct private FQDN from SWA hostname, retrieve private IP from DNS zone group (not customDnsConfigs), configure backend pool with FQDN, and preserve custom domain in Host header for Entra ID authentication.

**Tech Stack:** Bash, Azure CLI, Application Gateway v2, Private DNS Zones

---

## Prerequisites

- Azure CLI logged in
- Access to resource group: rg-subnet-calc
- Static Web App with private endpoint already deployed (via stack-16 script)
- Private DNS zone configured: privatelink.3.azurestaticapps.net
- Custom domain configured on SWA: static-swa-private-endpoint.publiccloudexperiments.net

## Context

**Current State:**

- Script 49 fails at line 200-207 when retrieving SWA private IP
- Query `customDnsConfigs[0].ipAddresses[0]` returns empty array
- Private IP (10.100.0.21) exists in DNS zone group's recordSets

**Target State:**

- Script successfully retrieves private IP from DNS zone group
- Backend pool uses FQDN instead of IP (resilient to IP changes)
- HTTP settings use custom domain for Host header (Entra ID compatibility)
- Capacity reduced to 1 (minimum cost)
- Region-agnostic FQDN construction

---

## Task 1: Fix Private IP Retrieval

**Files:**

- Modify: `~/Developer/personal/azure-tui/infrastructure/azure/49-create-application-gateway.sh:199-211`

### Step 1: Identify current broken code

Lines 199-211 currently use:

```bash
SWA_PRIVATE_IP=$(az network private-endpoint show \
 --name "${PE_NAME}" \
 --resource-group "${RESOURCE_GROUP}" \
 --query "customDnsConfigs[0].ipAddresses[0]" -o tsv)
```

This returns empty because `customDnsConfigs` array is empty.

### Step 2: Replace with DNS zone group query

Replace lines 199-211 with:

```bash
# Get private endpoint IP from DNS zone group (more reliable than customDnsConfigs)
log_step "Retrieving SWA private IP from DNS zone group..."
SWA_PRIVATE_IP=$(az network private-endpoint dns-zone-group show \
 --name "default" \
 --endpoint-name "${PE_NAME}" \
 --resource-group "${RESOURCE_GROUP}" \
 --query "privateDnsZoneConfigs[0].recordSets[0].ipAddresses[0]" -o tsv 2>/dev/null)

if [[ -z "${SWA_PRIVATE_IP}" ]]; then
 log_error "Could not retrieve private IP for SWA private endpoint"
 log_error "Ensure DNS zone group is configured on the private endpoint"
 log_error ""
 log_error "Check DNS zone group:"
 log_error " az network private-endpoint dns-zone-group show \\"
 log_error " --name default \\"
 log_error " --endpoint-name ${PE_NAME} \\"
 log_error " --resource-group ${RESOURCE_GROUP}"
 exit 1
fi
```

### Step 3: Save file

Save the changes to 49-create-application-gateway.sh

### Step 4: Commit change

```bash
git add ~/Developer/personal/azure-tui/infrastructure/azure/49-create-application-gateway.sh
git commit -m "fix: Retrieve SWA private IP from DNS zone group

Query privateDnsZoneConfigs[0].recordSets[0].ipAddresses[0] instead of
customDnsConfigs[0].ipAddresses[0] which returns empty array.

The DNS zone group contains the actual A record with the private IP.

Related to: Application Gateway for SWA private endpoint
"
```

---

## Task 2: Add Dynamic FQDN Construction

**Files:**

- Modify: `~/Developer/personal/azure-tui/infrastructure/azure/49-create-application-gateway.sh:183-184` (after line 183)

### Step 1: Add region number extraction and FQDN construction

After line 183 (after getting `SWA_HOSTNAME`), add:

```bash

# Extract region number and construct private FQDN for backend pool
# Region number (e.g., "3" in *.3.azurestaticapps.net) varies by SWA location
# Private FQDN resolves via private DNS zone to private endpoint IP
log_step "Constructing private FQDN for backend pool..."
if [[ "${SWA_HOSTNAME}" =~ \.([0-9]+)\.azurestaticapps\.net$ ]]; then
 SWA_REGION_NUMBER="${BASH_REMATCH[1]}"
 # Transform: name.3.azurestaticapps.net -> name.privatelink.3.azurestaticapps.net
 SWA_PRIVATE_FQDN=$(echo "${SWA_HOSTNAME}" | sed "s/\.${SWA_REGION_NUMBER}\.azurestaticapps\.net$/.privatelink.${SWA_REGION_NUMBER}.azurestaticapps.net/")

 log_info "SWA Hostname: ${SWA_HOSTNAME}"
 log_info "Region Number: ${SWA_REGION_NUMBER}"
 log_info "Private FQDN: ${SWA_PRIVATE_FQDN}"
else
 log_error "Could not determine SWA region number from hostname: ${SWA_HOSTNAME}"
 log_error "Expected format: <name>.<number>.azurestaticapps.net"
 log_error ""
 log_error "Example: delightful-field-0cd326e03.3.azurestaticapps.net"
 log_error " Region number: 3"
 log_error " Private FQDN: delightful-field-0cd326e03.privatelink.3.azurestaticapps.net"
 exit 1
fi
```

### Step 2: Save file

Save the changes to 49-create-application-gateway.sh

### Step 3: Commit change

```bash
git add ~/Developer/personal/azure-tui/infrastructure/azure/49-create-application-gateway.sh
git commit -m "feat: Add dynamic private FQDN construction for SWA backend

Extract region number from SWA hostname and construct privatelink FQDN.
Makes script region-agnostic (works with any *.N.azurestaticapps.net).

Example:
 Input: delightful-field-0cd326e03.3.azurestaticapps.net
 Output: delightful-field-0cd326e03.privatelink.3.azurestaticapps.net

This FQDN resolves to private endpoint IP via private DNS zone.

Related to: Application Gateway for SWA private endpoint
"
```

---

## Task 3: Update Backend Pool to Use FQDN

**Files:**

- Modify: `~/Developer/personal/azure-tui/infrastructure/azure/49-create-application-gateway.sh:296`
- Modify: `~/Developer/personal/azure-tui/infrastructure/azure/49-create-application-gateway.sh:308`

### Step 1: Change initial backend pool creation to use FQDN

Line 296 currently:

```bash
 --servers "${SWA_PRIVATE_IP}" \
```

Change to:

```bash
 --servers "${SWA_PRIVATE_FQDN}" \
```

### Step 2: Change backend pool update to use FQDN

Lines 303-309 currently:

```bash
log_step "Configuring backend pool with SWA hostname..."
az network application-gateway address-pool update \
 --gateway-name "${APPGW_NAME}" \
 --resource-group "${RESOURCE_GROUP}" \
 --name appGatewayBackendPool \
 --servers "${SWA_PRIVATE_IP}" \
 --output none
```

Change to:

```bash
log_step "Configuring backend pool with SWA private FQDN..."
az network application-gateway address-pool update \
 --gateway-name "${APPGW_NAME}" \
 --resource-group "${RESOURCE_GROUP}" \
 --name appGatewayBackendPool \
 --servers "${SWA_PRIVATE_FQDN}" \
 --output none
```

### Step 3: Save file

Save the changes to 49-create-application-gateway.sh

### Step 4: Commit change

```bash
git add ~/Developer/personal/azure-tui/infrastructure/azure/49-create-application-gateway.sh
git commit -m "feat: Use FQDN for Application Gateway backend pool

Change backend pool from IP address to FQDN (privatelink domain).

Benefits:
- Resilient to private endpoint IP changes
- Uses private DNS zone for resolution
- Follows Azure best practices

Backend pool now uses: delightful-field-0cd326e03.privatelink.3.azurestaticapps.net
Resolves to: 10.100.0.21 (via private DNS zone)

Related to: Application Gateway for SWA private endpoint
"
```

---

## Task 4: Reduce Capacity to Minimum

**Files:**

- Modify: `~/Developer/personal/azure-tui/infrastructure/azure/49-create-application-gateway.sh:288`

### Step 1: Change capacity from 2 to 1

Line 288 currently:

```bash
 --capacity 2 \
```

Change to:

```bash
 --capacity 1 \
```

### Step 2: Add comment explaining cost optimization

Before line 288, add comment:

```bash
 --capacity 1 \ # Minimum capacity for v2 (cost optimization: ~$214/month)
```

### Step 3: Save file

Save the changes to 49-create-application-gateway.sh

### Step 4: Commit change

```bash
git add ~/Developer/personal/azure-tui/infrastructure/azure/49-create-application-gateway.sh
git commit -m "feat: Reduce Application Gateway capacity to minimum

Change from capacity 2 to capacity 1 (minimum for v2 SKU).

Cost savings: ~$215/month vs ~$430/month
Capacity can be increased later if traffic requires it.

Related to: Application Gateway for SWA private endpoint
"
```

---

## Task 5: Update HTTP Settings for Custom Domain

**Files:**

- Modify: `~/Developer/personal/azure-tui/infrastructure/azure/49-create-application-gateway.sh:321`

### Step 1: Change HTTP settings to use custom domain Host header

Line 321 currently:

```bash
 --host-name "${SWA_HOSTNAME}" \
```

Change to:

```bash
 --host-name "${CUSTOM_DOMAIN:-${SWA_HOSTNAME}}" \
```

### Step 2: Add explanation comment

Before the http-settings update block (around line 312), add:

```bash
# Configure HTTP settings with custom domain Host header
# - Uses CUSTOM_DOMAIN if set (passed from stack-16 script)
# - Falls back to SWA_HOSTNAME for standalone usage
# - Custom domain required for Entra ID authentication (redirect URIs)
```

### Step 3: Save file

Save the changes to 49-create-application-gateway.sh

### Step 4: Commit change

```bash
git add ~/Developer/personal/azure-tui/infrastructure/azure/49-create-application-gateway.sh
git commit -m "feat: Use custom domain for Application Gateway Host header

Configure HTTP settings to preserve custom domain Host header.

Why:
- Entra ID redirect URIs are configured for custom domain
- SWA authentication expects requests from custom domain
- Without this, authentication fails (redirect URI mismatch)

Uses CUSTOM_DOMAIN if available, falls back to default hostname.

Related to: Application Gateway for SWA private endpoint
"
```

---

## Task 6: Update Summary Output

**Files:**

- Modify: `~/Developer/personal/azure-tui/infrastructure/azure/49-create-application-gateway.sh:333-336`

### Step 1: Update backend display to show FQDN

Lines 333-336 currently show only IP. Update to:

```bash
log_info "Backend (SWA): ${SWA_PRIVATE_FQDN}"
log_info "Backend IP: ${SWA_PRIVATE_IP}"
log_info "Host Header: ${CUSTOM_DOMAIN:-${SWA_HOSTNAME}}"
```

### Step 2: Update architecture diagram

Line 339 currently:

```bash
log_info " Internet → ${PUBLIC_IP_ADDRESS}:80 → App Gateway → ${SWA_PRIVATE_IP}:443 → SWA"
```

Change to:

```bash
log_info " Internet → ${PUBLIC_IP_ADDRESS}:80 → App Gateway → ${SWA_PRIVATE_FQDN}:443 → SWA (${SWA_PRIVATE_IP})"
```

### Step 3: Save file

Save the changes to 49-create-application-gateway.sh

### Step 4: Commit change

```bash
git add ~/Developer/personal/azure-tui/infrastructure/azure/49-create-application-gateway.sh
git commit -m "docs: Update Application Gateway summary output

Show FQDN-based backend configuration in summary:
- Backend FQDN (privatelink domain)
- Backend IP (resolved via private DNS)
- Host header (custom domain for auth)

Makes it clear to users how traffic flows.

Related to: Application Gateway for SWA private endpoint
"
```

---

## Task 7: Test Script with Dry-Run Verification

**Files:**

- No file changes

### Step 1: Verify script syntax

```bash
bash -n ~/Developer/personal/azure-tui/infrastructure/azure/49-create-application-gateway.sh
```

Expected: No output (syntax is valid)

### Step 2: Run shellcheck for best practices

```bash
shellcheck ~/Developer/personal/azure-tui/infrastructure/azure/49-create-application-gateway.sh
```

Expected: No errors (warnings about SC2086 for variable expansion are acceptable)

### Step 3: Review all changes

```bash
git diff main...HEAD ~/Developer/personal/azure-tui/infrastructure/azure/49-create-application-gateway.sh
```

Review the diff to ensure all changes are correct:

- IP retrieval uses DNS zone group
- FQDN construction is dynamic
- Backend pool uses FQDN
- Capacity is 1
- HTTP settings use custom domain
- Summary output is updated

### Step 4: Commit verification

```bash
git log --oneline -6
```

Expected: 6 commits (1 per task)

---

## Task 8: Manual Testing with Actual Deployment

**Files:**

- No file changes

**Important:** This task requires active Azure resources and will create billable resources (~$214/month).

### Step 1: Set required environment variables

From the Stack 16 deployment, you should have:

- RESOURCE_GROUP=rg-subnet-calc
- VNET_NAME=vnet-subnet-calc-private
- STATIC_WEB_APP_NAME=swa-subnet-calc-private-endpoint
- CUSTOM_DOMAIN=static-swa-private-endpoint.publiccloudexperiments.net

```bash
export RESOURCE_GROUP=rg-subnet-calc
export VNET_NAME=vnet-subnet-calc-private
export STATIC_WEB_APP_NAME=swa-subnet-calc-private-endpoint
export CUSTOM_DOMAIN=static-swa-private-endpoint.publiccloudexperiments.net
```

### Step 2: Run the Application Gateway creation script

```bash
cd ~/Developer/personal/azure-tui/infrastructure/azure
./49-create-application-gateway.sh
```

Expected output sections:

1. Configuration summary with region number and private FQDN
1. Private IP retrieved from DNS zone group (10.100.0.21)
1. Application Gateway creation (5-10 minutes)
1. Backend pool configured with FQDN
1. HTTP settings configured with custom domain
1. Final summary with public IP and backend configuration

### Step 3: Verify backend health

After Application Gateway is created:

```bash
az network application-gateway show-backend-health \
 --name agw-swa-subnet-calc-private-endpoint \
 --resource-group rg-subnet-calc \
 --query "backendAddressPools[0].backendHttpSettingsCollection[0].servers[0].{Address:address, Health:health}" -o table
```

Expected:

- Address: delightful-field-0cd326e03.privatelink.3.azurestaticapps.net
- Health: Healthy

If health is Unhealthy, check:

- Private DNS zone has correct A record
- Private endpoint is in correct subnet
- NSG rules allow traffic from AppGW subnet

### Step 4: Test HTTP access

Get public IP:

```bash
PUBLIC_IP=$(az network public-ip show \
 --name pip-agw-swa-subnet-calc-private-endpoint \
 --resource-group rg-subnet-calc \
 --query ipAddress -o tsv)
echo "Public IP: ${PUBLIC_IP}"
```

Test with curl:

```bash
curl -v -H "Host: static-swa-private-endpoint.publiccloudexperiments.net" \
 http://${PUBLIC_IP}/
```

Expected:

- HTTP 200 with SWA content, OR
- HTTP 302 redirect to Entra ID login

### Step 5: Test DNS resolution from AppGW subnet

This requires a VM in the VNet or using Cloud Shell with VNet integration.

From a VM in the VNet:

```bash
nslookup delightful-field-0cd326e03.privatelink.3.azurestaticapps.net
```

Expected: Should resolve to 10.100.0.21

### Step 6: Document test results

Create a test results file:

```bash
cat > /tmp/appgw-test-results.txt <<EOF
Application Gateway Test Results
Date: $(date)

1. Backend Health: [Healthy/Unhealthy]
1. HTTP Access: [Success/Failed]
1. DNS Resolution: [10.100.0.21/Failed]
1. Public IP: ${PUBLIC_IP}

Notes:
- Backend pool uses FQDN: delightful-field-0cd326e03.privatelink.3.azurestaticapps.net
- Host header: static-swa-private-endpoint.publiccloudexperiments.net
- Capacity: 1 unit
- Cost: ~$214/month

Next Steps:
- Configure Cloudflare CNAME: ${CUSTOM_DOMAIN} -> ${PUBLIC_IP}
- Test Entra ID authentication flow
- Verify /api proxy to Function App works
EOF

cat /tmp/appgw-test-results.txt
```

---

## Task 9: Update Stack-16 Script Integration

**Files:**

- Modify: `~/Developer/personal/azure-tui/infrastructure/azure/azure-stack-16-swa-private-endpoint.sh:566`

**Context:** The stack-16 script already calls script 49 and exports CUSTOM_DOMAIN. We just need to verify the integration is correct.

### Step 1: Verify CUSTOM_DOMAIN is exported before calling script 49

Check lines 560-569 in azure-stack-16-swa-private-endpoint.sh:

```bash
 export STATIC_WEB_APP_NAME
 export VNET_NAME
 export APPGW_NAME
 export LOCATION

 # Call the Application Gateway creation script
 "${SCRIPT_DIR}/49-create-application-gateway.sh"
```

### Step 2: Add CUSTOM_DOMAIN export

Before calling the script, ensure CUSTOM_DOMAIN is exported:

```bash
 export STATIC_WEB_APP_NAME
 export VNET_NAME
 export APPGW_NAME
 export LOCATION
 export CUSTOM_DOMAIN # For Host header in HTTP settings

 # Call the Application Gateway creation script
 "${SCRIPT_DIR}/49-create-application-gateway.sh"
```

### Step 3: Save file

Save changes to azure-stack-16-swa-private-endpoint.sh

### Step 4: Commit change

```bash
git add ~/Developer/personal/azure-tui/infrastructure/azure/azure-stack-16-swa-private-endpoint.sh
git commit -m "fix: Export CUSTOM_DOMAIN for Application Gateway script

Ensure CUSTOM_DOMAIN is exported before calling script 49.
Script 49 uses this for Host header in HTTP settings (Entra ID auth).

Related to: Application Gateway for SWA private endpoint
"
```

---

## Task 10: Final Integration Test with Stack-16

**Files:**

- No file changes

**Important:** This is the full end-to-end test. Can be skipped if Application Gateway already created in Task 8.

### Step 1: Delete existing Application Gateway (if created in Task 8)

If you already created the Application Gateway in Task 8, delete it first:

```bash
az network application-gateway delete \
 --name agw-swa-subnet-calc-private-endpoint \
 --resource-group rg-subnet-calc \
 --no-wait

az network public-ip delete \
 --name pip-agw-swa-subnet-calc-private-endpoint \
 --resource-group rg-subnet-calc \
 --no-wait
```

Wait 2-3 minutes for deletion to complete.

### Step 2: Run stack-16 script (answer 'y' to Application Gateway creation)

```bash
cd ~/Developer/personal/azure-tui/infrastructure/azure
AZURE_CLIENT_ID="<your-client-id>" \
AZURE_CLIENT_SECRET="<your-client-secret>" \
./azure-stack-16-swa-private-endpoint.sh
```

When prompted "Create Application Gateway now? (Y/n)", answer: y

### Step 3: Verify Application Gateway is created correctly

Check the summary output at the end. It should show:

- Public Access: http://<public-ip> (via Application Gateway)
- SWA Private: Private endpoint only
- Function Private: Private endpoint only

### Step 4: Verify backend health (same as Task 8 Step 3)

```bash
az network application-gateway show-backend-health \
 --name agw-swa-subnet-calc-private-endpoint \
 --resource-group rg-subnet-calc \
 --query "backendAddressPools[0].backendHttpSettingsCollection[0].servers[0].{Address:address, Health:health}" -o table
```

Expected: Health should be "Healthy"

### Step 5: Test complete flow with Cloudflare

1. Configure Cloudflare DNS:

- Type: CNAME
- Name: static-swa-private-endpoint
- Target: <public-ip> (or create A record)
- Proxy status: Proxied
- SSL/TLS mode: Flexible (Cloudflare HTTPS → AppGW HTTP)

1. Visit <https://static-swa-private-endpoint.publiccloudexperiments.net>

1. Should redirect to Entra ID login

1. After login, should land on SWA with valid session

1. Verify /.auth/me returns user info

1. Test API proxy: Visit <https://static-swa-private-endpoint.publiccloudexperiments.net/api/v1/calculate>

---

## Task 11: Documentation and Cleanup

**Files:**

- Create: `~/Developer/personal/azure-tui/infrastructure/azure/docs/application-gateway-troubleshooting.md`

### Step 1: Create troubleshooting guide

```bash
cat > ~/Developer/personal/azure-tui/infrastructure/azure/docs/application-gateway-troubleshooting.md <<'EOF'
# Application Gateway Troubleshooting Guide

## Backend Health: Unhealthy

### Check 1: Verify DNS Resolution

From a VM in the VNet:
```bash
nslookup delightful-field-0cd326e03.privatelink.3.azurestaticapps.net
```

Should resolve to: 10.100.0.21

If not resolving:

- Check private DNS zone exists: privatelink.3.azurestaticapps.net
- Check VNet link is configured
- Check DNS zone group is configured on private endpoint

### Check 2: Verify Private Endpoint

```bash
az network private-endpoint show \
 --name pe-swa-subnet-calc-private-endpoint \
 --resource-group rg-subnet-calc \
 --query "{ProvisioningState:provisioningState, PrivateIP:customDnsConfigs[0].ipAddresses[0]}"
```

Should show: ProvisioningState: Succeeded

### Check 3: Verify NSG Rules

Application Gateway subnet needs to allow outbound to SWA private endpoint subnet:

```bash
# Check if NSGs are blocking traffic
az network vnet subnet show \
 --name snet-appgateway \
 --vnet-name vnet-subnet-calc-private \
 --resource-group rg-subnet-calc \
 --query "networkSecurityGroup"
```

If NSG is attached, verify outbound rules allow HTTPS (443) to 10.100.0.16/28

## Backend Health: Takes Long Time

Application Gateway probes can take 60-120 seconds to stabilize. Wait 2-3 minutes after creation.

## HTTP 502 Bad Gateway

This means Application Gateway can't reach backend. Check:

1. Backend pool has correct FQDN
1. Private DNS zone resolves correctly
1. SWA private endpoint is healthy
1. HTTP settings use correct Host header

## Entra ID Authentication Fails

### Check 1: Host Header

Verify HTTP settings use custom domain:

```bash
az network application-gateway http-settings show \
 --gateway-name agw-swa-subnet-calc-private-endpoint \
 --resource-group rg-subnet-calc \
 --name appGatewayBackendHttpSettings \
 --query "hostName" -o tsv
```

Should return: static-swa-private-endpoint.publiccloudexperiments.net

### Check 2: Redirect URIs

Verify Entra ID app has correct redirect URI:

```bash
az ad app show --id <AZURE_CLIENT_ID> --query "web.redirectUris"
```

Should include: <https://static-swa-private-endpoint.publiccloudexperiments.net/.auth/login/aad/callback>

## Cost Higher Than Expected

Check capacity:

```bash
az network application-gateway show \
 --name agw-swa-subnet-calc-private-endpoint \
 --resource-group rg-subnet-calc \
 --query "{SKU:sku.name, Capacity:sku.capacity}" -o table
```

Should show: Capacity: 1

If higher, scale down:

```bash
az network application-gateway update \
 --name agw-swa-subnet-calc-private-endpoint \
 --resource-group rg-subnet-calc \
 --set sku.capacity=1
```

## Useful Commands

### View Backend Health

```bash
az network application-gateway show-backend-health \
 --name agw-swa-subnet-calc-private-endpoint \
 --resource-group rg-subnet-calc
```

### View Application Gateway Details

```bash
az network application-gateway show \
 --name agw-swa-subnet-calc-private-endpoint \
 --resource-group rg-subnet-calc
```

### Test from VM in VNet

```bash
# SSH to VM in VNet
curl -v -H "Host: static-swa-private-endpoint.publiccloudexperiments.net" \
 https://delightful-field-0cd326e03.privatelink.3.azurestaticapps.net/
```

Should return SWA content or Entra ID redirect.
EOF

### Step 2: Commit documentation

```bash
git add ~/Developer/personal/azure-tui/infrastructure/azure/docs/application-gateway-troubleshooting.md
git commit -m "docs: Add Application Gateway troubleshooting guide

Comprehensive troubleshooting guide covering:
- Backend health issues
- DNS resolution problems
- NSG configuration
- Entra ID authentication failures
- Cost optimization

Related to: Application Gateway for SWA private endpoint
"
```

### Step 3: Update main README with Application Gateway info

If there's a README in the ~/Developer/personal/azure-tui/infrastructure/azure directory, add a section about the Application Gateway setup.

---

## Task 12: Create Pull Request

**Files:**

- No file changes

### Step 1: Push branch to remote

```bash
git push origin chore/20251030-app-gateway
```

### Step 2: Create pull request

```bash
gh pr create \
 --title "feat: Add Application Gateway for SWA private endpoint access" \
 --body "$(cat <<'EOF'
## Summary

Adds Application Gateway to provide public internet access to Azure Static Web App configured with private endpoint.

## Changes

### Script 49 Modifications
- Fix private IP retrieval to use DNS zone group (not customDnsConfigs)
- Add dynamic FQDN construction (region-agnostic)
- Use FQDN-based backend pool (resilient to IP changes)
- Preserve custom domain Host header (Entra ID auth compatibility)
- Reduce capacity to 1 (minimum cost: ~$214/month)

### Architecture
```text
Internet → Cloudflare (HTTPS) → AppGW (HTTP→HTTPS) → SWA Private Endpoint
```

### Key Features

- FQDN backend: delightful-field-0cd326e03.privatelink.3.azurestaticapps.net
- Host header: static-swa-private-endpoint.publiccloudexperiments.net
- Capacity: 1 unit (Standard_v2)
- Cost: ~$214/month
- Can upgrade to WAF_v2 without recreation

## Testing

- [x] Script syntax validation (bash -n)
- [x] Shellcheck validation
- [x] Manual deployment test
- [x] Backend health verification (Healthy)
- [x] HTTP access test (200 OK)
- [x] DNS resolution test (10.100.0.21)
- [ ] End-to-end with Cloudflare (requires DNS update)
- [ ] Entra ID authentication flow (requires Cloudflare)

## Documentation

- Design document: docs/plans/2025-10-30-application-gateway-swa-private-endpoint-design.md
- Troubleshooting: ~/Developer/personal/azure-tui/infrastructure/azure/docs/application-gateway-troubleshooting.md

## Deployment

To deploy:

```bash
cd ~/Developer/personal/azure-tui/infrastructure/azure
AZURE_CLIENT_ID="xxx" AZURE_CLIENT_SECRET="yyy" \
./azure-stack-16-swa-private-endpoint.sh
# Answer 'y' when prompted for Application Gateway creation
```

Or standalone:

```bash
export RESOURCE_GROUP=rg-subnet-calc
export VNET_NAME=vnet-subnet-calc-private
export STATIC_WEB_APP_NAME=swa-subnet-calc-private-endpoint
export CUSTOM_DOMAIN=static-swa-private-endpoint.publiccloudexperiments.net
./49-create-application-gateway.sh
```

## Cost Impact

New resource: Application Gateway Standard_v2 (capacity 1)

- Monthly: ~$214 (Gateway) + ~$3.65 (Public IP) = ~$218/month
- Can be deleted if not needed (SWA returns to private-only access)

 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"

### Step 3: Review PR and merge when ready

After PR is reviewed and tests pass:

```bash
gh pr merge --squash --delete-branch
```

---

## Success Criteria

- [ ] Script 49 successfully retrieves private IP from DNS zone group
- [ ] Private FQDN is constructed dynamically (region-agnostic)
- [ ] Backend pool uses FQDN instead of IP
- [ ] HTTP settings use custom domain Host header
- [ ] Capacity is set to 1 (minimum cost)
- [ ] Backend health shows "Healthy"
- [ ] HTTP access via public IP returns SWA content
- [ ] All commits follow conventional commit format
- [ ] Documentation is complete (design + troubleshooting)
- [ ] Pull request is created with clear description

## Cost Summary

**New Resources:**

- Application Gateway Standard_v2 (capacity 1): ~$215/month
- Public IP (Standard SKU): ~$3.65/month
- Data processing: Variable (~$0.008/GB)

**Total:** ~$219/month

**Can be deleted:** Application Gateway can be removed without affecting SWA or Function App (they remain accessible via private endpoint within VNet)

## Rollback Plan

If issues occur after deployment:

### Option 1: Delete Application Gateway

```bash
az network application-gateway delete \
 --name agw-swa-subnet-calc-private-endpoint \
 --resource-group rg-subnet-calc

az network public-ip delete \
 --name pip-agw-swa-subnet-calc-private-endpoint \
 --resource-group rg-subnet-calc
```

Impact: SWA returns to private-only access

### Option 2: Revert to Previous Script Version

```bash
git revert <commit-sha>
git push origin main
```

## References

- Design Document: docs/plans/2025-10-30-application-gateway-swa-private-endpoint-design.md
- Azure Application Gateway: <https://learn.microsoft.com/en-us/azure/application-gateway/>
- SWA Private Endpoints: <https://learn.microsoft.com/en-us/azure/static-web-apps/private-endpoint>
