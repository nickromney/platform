# Application Gateway HTTPS Listener with Key Vault - Design Document

**Date:** 2025-10-30
**Status:** Implemented
**Target:** Azure Stack 16 (Private Endpoint + Entra ID)

## Problem Statement

Current Application Gateway configuration uses HTTP/80 listener with Cloudflare "Flexible" SSL/TLS mode:

- **Current:** Cloudflare (HTTPS) → AppGW (HTTP/80) → SWA (HTTPS/443)
- **Limitation:** No encryption between Cloudflare and Azure
- **Security Gap:** HTTP traffic exposed between Cloudflare edge and Application Gateway

Cloudflare "Full" mode requires backend HTTPS but accepts self-signed certificates:

- Provides end-to-end encryption
- Does not require publicly trusted certificate authority
- Better security posture without additional CA costs

## Design Goals

1. Add HTTPS/443 listener to Application Gateway
1. Use self-signed certificate (sufficient for Cloudflare Full mode)
1. Store certificate in Azure Key Vault with managed identity access
1. Replace HTTP/80 listener (HTTPS-only for simplicity)
1. Maintain idempotent script design (safe to re-run)
1. Minimal cost impact (~$1/month for Key Vault)

## Architecture

### New Traffic Flow

```text
Internet (HTTPS)
 ↓
Cloudflare (Full mode: HTTPS→HTTPS, accepts self-signed)
 ↓
Application Gateway Public IP:443 (HTTPS listener)
 ↓ (TLS with self-signed certificate)
Key Vault
 ├─ Certificate storage (PFX format)
 └─ Managed identity access (RBAC)
 ↓
Application Gateway → SWA Private Endpoint:443
 ↓ (HTTPS with custom domain Host header)
Static Web App (Entra ID authentication)
```

### Key Changes

| Component | Current | New | Rationale |
|-----------|---------|-----|-----------|
| **Cloudflare Mode** | Flexible | Full | End-to-end encryption |
| **AppGW Frontend** | HTTP/80 | HTTPS/443 | TLS termination at AppGW |
| **Certificate** | None | Self-signed in Key Vault | No CA cost, Cloudflare accepts |
| **Certificate Access** | N/A | Managed identity + RBAC | No secrets in configuration |
| **Backend Connection** | HTTP→HTTPS | HTTPS→HTTPS | Fully encrypted path |

## Components

### 1. Azure Key Vault

**Purpose:** Secure storage for TLS certificate with centralized management.

| Property | Value | Rationale |
|----------|-------|-----------|
| **Name** | kv-subnet-calc-${RANDOM} | Globally unique (3-24 chars) |
| **SKU** | Standard | Sufficient for certificate storage |
| **RBAC** | Enabled | Modern access control (not access policies) |
| **Soft-delete** | Enabled (default) | 90-day recovery window |
| **Purge Protection** | Disabled | Allow immediate cleanup in dev/test |

**Idempotency:**

- Check for existing Key Vault in resource group first
- If single KV exists, reuse it
- If multiple exist, require `KEY_VAULT_NAME` environment variable
- Only create new KV if none found

### 2. Self-Signed Certificate

**Generation Method:** OpenSSL (cross-platform, already used in repo)

| Property | Value | Rationale |
|----------|-------|-----------|
| **Subject CN** | `${CUSTOM_DOMAIN}` | Matches SWA custom domain |
| **Key Size** | 2048-bit RSA | Balance of security and performance |
| **Validity** | 365 days | Annual renewal cadence |
| **Format** | PFX with password | Required by Application Gateway |
| **SAN** | Not required | Single domain, CN sufficient |

**Certificate Lifecycle:**

```bash
# Generate private key and certificate
openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem \
 -days 365 -nodes \
 -subj "/CN=${CUSTOM_DOMAIN}"

# Export as PFX (PKCS#12)
CERT_PASSWORD=$(openssl rand -base64 16)
openssl pkcs12 -export \
 -out certificate.pfx \
 -inkey key.pem \
 -in cert.pem \
 -password "pass:${CERT_PASSWORD}"

# Cleanup temporary files
rm key.pem cert.pem
```

**Storage Format in Key Vault:**

- Stored as **secret** (not certificate object) - AppGW uses secrets API
- Value format: JSON with base64-encoded PFX and password
- Content-Type: `application/x-pkcs12`

```json
{
 "data": "<base64-encoded-pfx>",
 "password": "<certificate-password>"
}
```

**Idempotency:**

- Check if certificate secret exists before generation
- Show expiration date if exists
- Prompt user to update or reuse existing
- Support forced regeneration via flag

### 3. Application Gateway Managed Identity

**Type:** System-assigned managed identity

| Property | Value | Rationale |
|----------|-------|-----------|
| **Identity Type** | System-assigned | Lifecycle tied to AppGW |
| **RBAC Role** | Key Vault Secrets User | Read-only access to secrets |
| **Scope** | Specific Key Vault only | Least privilege principle |

**Why System-Assigned:**

- Automatically created/deleted with Application Gateway
- No separate lifecycle management required
- Simpler than user-assigned for single-resource scenarios

**RBAC Role Details:**

- Built-in role: `Key Vault Secrets User` (ID: 4633458b-17de-408a-b874-0445c86b69e6)
- Permissions: `Microsoft.KeyVault/vaults/secrets/getSecret/action`
- Does not grant list, delete, or management operations

### 4. HTTPS Listener Configuration

**New Listener:**

| Property | Value | Rationale |
|----------|-------|-----------|
| **Name** | appGatewayHttpsListener | Descriptive, follows naming convention |
| **Port** | 443 | Standard HTTPS port |
| **Protocol** | HTTPS | TLS termination |
| **Certificate Source** | Key Vault | Managed identity access |
| **Frontend IP** | Public IP (existing) | Reuse existing public IP |

**Old Listener (HTTP/80):**

- **Action:** Delete (replaced entirely)
- **Rationale:** Simplified configuration, HTTPS-only security posture
- **Impact:** Direct HTTP access to public IP will fail (expected)

### 5. Updated Resources

**Frontend Port:**

- Delete: `appGatewayFrontendPort` (port 80)
- Create: `appGatewayHttpsPort` (port 443)

**HTTP Listener:**

- Delete: `appGatewayHttpListener` (HTTP)
- Create: `appGatewayHttpsListener` (HTTPS)

**Routing Rule:**

- Name: `rule1` (existing, update reference)
- Change: Listener from HTTP to HTTPS
- Backend: Unchanged (SWA private FQDN)
- HTTP Settings: Unchanged (HTTPS to backend)

## Script Design

### Script 50: Add HTTPS Listener (`50-add-https-listener.sh`)

**Purpose:** Add HTTPS/443 listener to Application Gateway using Key Vault-stored certificate.

**Prerequisites:**

- Application Gateway exists (created by script 49)
- Custom domain configured on SWA
- OpenSSL available (standard on Linux/macOS)

**Environment Variables:**

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `RESOURCE_GROUP` | Yes | - | Azure resource group |
| `APPGW_NAME` | No | Auto-detect | Application Gateway name |
| `CUSTOM_DOMAIN` | No | Auto-detect from AppGW | Custom domain for certificate |
| `KEY_VAULT_NAME` | No | Auto-detect/create | Key Vault name (required if multiple exist) |
| `FORCE_CERT_REGEN` | No | false | Force certificate regeneration |

**Script Flow:**

1. **Validation**

- Check Azure CLI authentication
- Verify Application Gateway exists
- Retrieve custom domain from AppGW tags or environment

1. **Key Vault Setup (Idempotent)**

- Search for existing Key Vault in resource group
- If single KV: Reuse
- If multiple: Require `KEY_VAULT_NAME`
- If none: Create new with random suffix

1. **Certificate Generation (Idempotent)**

- Check if certificate secret exists
- If exists: Show expiration, prompt to update
- If `FORCE_CERT_REGEN=true`: Skip prompt
- Generate self-signed certificate with OpenSSL
- Export as PFX with random password
- Upload to Key Vault as secret

1. **Managed Identity (Idempotent)**

- Check if system identity already assigned
- If not: Enable system-assigned managed identity
- Retrieve identity principal ID
- Check if RBAC role assignment exists
- If not: Assign "Key Vault Secrets User" role
- Wait for RBAC propagation (30 seconds)

1. **Application Gateway Update**

- Delete HTTP/80 frontend port
- Delete HTTP listener
- Create HTTPS/443 frontend port
- Create SSL certificate reference to Key Vault
- Create HTTPS listener with certificate
- Update routing rule to use HTTPS listener

1. **Summary Output**

- Key Vault name
- Certificate expiration date
- Public IP address
- HTTPS access URL
- Cloudflare configuration instructions

**Idempotency Patterns:**

```bash
# Pattern 1: Resource existence check
if az keyvault show --name "${KV_NAME}" &>/dev/null; then
 log_info "Key Vault ${KV_NAME} already exists"
else
 log_info "Creating Key Vault..."
 az keyvault create ...
fi

# Pattern 2: Secret existence with prompt
if az keyvault secret show --vault-name "${KV_NAME}" --name "cert" &>/dev/null; then
 if [[ "${FORCE_CERT_REGEN}" != "true" ]]; then
 read -r -p "Certificate exists. Update? (y/N): " update
 [[ "${update}" =~ ^[Yy]$ ]] || return
 fi
fi

# Pattern 3: Identity check
IDENTITY_ID=$(az network application-gateway show \
 --query "identity.principalId" -o tsv 2>/dev/null)
if [[ -z "${IDENTITY_ID}" ]]; then
 log_info "Enabling managed identity..."
 az network application-gateway identity assign ...
fi

# Pattern 4: RBAC check
if az role assignment list \
 --assignee "${IDENTITY_ID}" \
 --role "Key Vault Secrets User" \
 --scope "${KV_ID}" \
 --query "[0].id" -o tsv | grep -q .; then
 log_info "RBAC assignment already exists"
else
 az role assignment create ...
fi
```

### Script 58: Deploy Flask App Service (Renamed)

**Change:** Renamed from `50-deploy-flask-app-service.sh` to `58-deploy-flask-app-service.sh`

- **Rationale:** Keep numbered scripts without alpha suffixes
- **Impact:** None, script functionality unchanged

## Implementation Phases

### Phase 1: Create Key Vault and Upload Certificate

1. Detect or create Key Vault
1. Generate self-signed certificate
1. Upload certificate to Key Vault
1. Verify secret storage

### Phase 2: Configure Managed Identity

1. Enable system-assigned identity on AppGW
1. Assign RBAC role to identity
1. Verify permissions with test query

### Phase 3: Update Application Gateway

1. Delete HTTP listener components
1. Create HTTPS listener components
1. Update routing rule
1. Verify backend health

### Phase 4: Test and Validate

1. Test HTTPS access to public IP
1. Switch Cloudflare to Full mode
1. Verify end-to-end HTTPS
1. Test Entra ID authentication flow

## Testing Plan

### Test 1: Certificate Storage Verification

**Command:**

```bash
az keyvault secret show \
 --vault-name "${KV_NAME}" \
 --name "appgw-ssl-cert" \
 --query "{name: name, contentType: contentType, expires: attributes.expires}" -o json
```

**Expected:**

```json
{
 "name": "appgw-ssl-cert",
 "contentType": "application/x-pkcs12",
 "expires": "2026-10-30T12:34:56+00:00"
}
```

### Test 2: Managed Identity Verification

**Command:**

```bash
# Get identity principal ID
IDENTITY_ID=$(az network application-gateway show \
 --name "${APPGW_NAME}" \
 --resource-group "${RESOURCE_GROUP}" \
 --query "identity.principalId" -o tsv)

# Verify RBAC assignment
az role assignment list \
 --assignee "${IDENTITY_ID}" \
 --scope "${KV_ID}" \
 --query "[].{Role:roleDefinitionName, Scope:scope}" -o table
```

**Expected:**

```text
Role Scope
------------------------ ----------------------------------------------------
Key Vault Secrets User /subscriptions/.../resourceGroups/.../providers/Microsoft.KeyVault/vaults/kv-subnet-calc-xxxx
```

### Test 3: HTTPS Listener Configuration

**Command:**

```bash
az network application-gateway http-listener show \
 --gateway-name "${APPGW_NAME}" \
 --resource-group "${RESOURCE_GROUP}" \
 --name "appGatewayHttpsListener" \
 --query "{name: name, port: frontendPort, protocol: protocol, sslCertificate: sslCertificate.id}" -o json
```

**Expected:**

```json
{
 "name": "appGatewayHttpsListener",
 "port": "/subscriptions/.../frontendPorts/appGatewayHttpsPort",
 "protocol": "Https",
 "sslCertificate": "/subscriptions/.../sslCertificates/appgw-ssl-cert"
}
```

### Test 4: Direct HTTPS Access

**Command:**

```bash
PUBLIC_IP=$(az network public-ip show \
 --name pip-agw-swa-subnet-calc-private-endpoint \
 --resource-group "${RESOURCE_GROUP}" \
 --query ipAddress -o tsv)

curl -k -v -H "Host: ${CUSTOM_DOMAIN}" https://${PUBLIC_IP}/
```

**Expected:**

- TLS handshake succeeds
- Self-signed certificate presented
- HTTP 302 redirect to Entra ID or HTTP 200 with content

### Test 5: Cloudflare Full Mode

**Steps:**

1. Log into Cloudflare dashboard
1. Navigate to SSL/TLS settings for domain
1. Change mode from "Flexible" to "Full"
1. Wait for propagation (~30 seconds)

**Verification:**

```bash
curl -v https://${CUSTOM_DOMAIN}/
```

**Expected:**

- No certificate warnings
- HTTP 302 or 200 response
- TLS 1.2+ connection

### Test 6: Backend Health Check

**Command:**

```bash
az network application-gateway show-backend-health \
 --name "${APPGW_NAME}" \
 --resource-group "${RESOURCE_GROUP}" \
 --query "backendAddressPools[0].backendHttpSettingsCollection[0].servers[0].{address: address, health: health}" -o json
```

**Expected:**

```json
{
 "address": "delightful-field-0cd326e03.privatelink.3.azurestaticapps.net",
 "health": "Healthy"
}
```

### Test 7: Entra ID Authentication Flow

**Steps:**

1. Visit `https://${CUSTOM_DOMAIN}` in browser
1. Should redirect to Entra ID login
1. Log in with test user credentials
1. Should redirect back to SWA with session

**Verification:**

```bash
# After login in browser, check auth endpoint
curl -H "Cookie: StaticWebAppsAuthCookie=<from-browser>" \
 https://${CUSTOM_DOMAIN}/.auth/me
```

**Expected:**

```json
{
 "clientPrincipal": {
 "identityProvider": "azuread",
 "userId": "...",
 "userDetails": "user@domain.com",
 "userRoles": ["authenticated"]
 }
}
```

## Cost Impact

| Resource | Current | New | Monthly Cost | Delta |
|----------|---------|-----|--------------|-------|
| Application Gateway (Standard_v2, capacity 1) | Exists | Unchanged | ~$215 | $0 |
| Public IP (Standard) | Exists | Unchanged | ~$3.65 | $0 |
| **Key Vault (Standard)** | N/A | **New** | **~$0.03** | **+$0.03** |
| Key Vault secret operations | N/A | New | ~$0.03/10K ops | Negligible |
| **Total** | ~$218/month | ~$219/month | - | **+~$1/month** |

**Notes:**

- Key Vault costs ~$0.03 per 10,000 secret operations
- AppGW retrieves certificate on startup and listener updates only
- Estimated ~100 operations/month = $0.0003/month (negligible)
- Primary cost is Key Vault existence fee (~$0.25/month minimum)

## Security Considerations

### TLS Configuration

| Layer | Protocol | Certificate | Notes |
|-------|----------|-------------|-------|
| **Internet → Cloudflare** | TLS 1.2+ | Cloudflare managed | Public CA certificate |
| **Cloudflare → AppGW** | TLS 1.2+ | Self-signed | Full mode accepts self-signed |
| **AppGW → SWA** | TLS 1.2+ | Azure managed | Private endpoint, Azure backbone |

**Cipher Suites:** Application Gateway uses Azure-managed cipher suites (cannot customize in Standard_v2)

### Certificate Management

**Expiration Handling:**

- Certificate valid for 365 days
- No automatic renewal (self-signed)
- Script provides expiration date in output
- Re-run script to regenerate certificate before expiration
- Key Vault retains old versions (can rollback if needed)

**Access Control:**

- Managed identity: Least privilege (secrets read-only)
- No certificate password stored in AppGW configuration
- Certificate password only in Key Vault secret (encrypted at rest)
- Soft-delete prevents accidental certificate deletion

### Network Security

**Endpoints:**

- Application Gateway: Public IP (required for internet access)
- Key Vault: Public endpoint (required for AppGW access)
- SWA: Private endpoint only (no public access)

**DDoS Protection:**

- Public IP has Azure DDoS Basic (included with Standard SKU)
- Upgrade to DDoS Standard (~$2,944/month) if needed

**NSG Rules:**

- AppGW subnet: Azure-managed NSG rules (ports 65200-65535)
- No custom NSG modifications required

## Maintenance

### Certificate Renewal

**Procedure:**

```bash
# Regenerate certificate (force flag skips prompt)
RESOURCE_GROUP="rg-subnet-calc" \
FORCE_CERT_REGEN=true \
./50-add-https-listener.sh
```

**Frequency:** Annually (365-day validity)

**Automation Opportunity:** Future enhancement - use Azure Automation to regenerate certificate quarterly.

### Monitoring

**Key Vault Metrics (Azure Portal):**

- Service API hit rate
- Service API latency
- Overall vault availability

**Application Gateway Metrics:**

- Backend response time
- Failed requests
- Healthy/Unhealthy host count
- SSL protocol (verify TLS 1.2+)

### Troubleshooting

#### Issue: "Certificate could not be retrieved from Key Vault"

**Cause:** RBAC permissions not propagated or incorrect role assignment.

**Fix:**

```bash
# Verify managed identity exists
az network application-gateway show \
 --name "${APPGW_NAME}" \
 --resource-group "${RESOURCE_GROUP}" \
 --query "identity.principalId" -o tsv

# Verify RBAC assignment
az role assignment list \
 --assignee "<principal-id>" \
 --scope "<key-vault-resource-id>"

# Re-apply RBAC if missing
az role assignment create \
 --assignee "<principal-id>" \
 --role "Key Vault Secrets User" \
 --scope "<key-vault-resource-id>"
```

#### Issue: "Backend health shows Unhealthy after HTTPS change"

**Cause:** Backend pool still configured for HTTP or wrong host header.

**Fix:**

```bash
# Verify HTTP settings use HTTPS and correct host
az network application-gateway http-settings show \
 --gateway-name "${APPGW_NAME}" \
 --resource-group "${RESOURCE_GROUP}" \
 --name appGatewayBackendHttpSettings \
 --query "{protocol: protocol, port: port, hostName: hostName}"
```

Expected: `{"protocol": "Https", "port": 443, "hostName": "static-swa-private-endpoint.publiccloudexperiments.net"}`

## Rollback Plan

### Option 1: Revert to HTTP Listener

**Impact:** Returns to Cloudflare Flexible mode (HTTP backend)

**Steps:**

```bash
# Delete HTTPS listener and port
az network application-gateway http-listener delete \
 --gateway-name "${APPGW_NAME}" \
 --resource-group "${RESOURCE_GROUP}" \
 --name appGatewayHttpsListener

az network application-gateway frontend-port delete \
 --gateway-name "${APPGW_NAME}" \
 --resource-group "${RESOURCE_GROUP}" \
 --name appGatewayHttpsPort

# Recreate HTTP listener (port 80)
az network application-gateway frontend-port create \
 --gateway-name "${APPGW_NAME}" \
 --resource-group "${RESOURCE_GROUP}" \
 --name appGatewayFrontendPort \
 --port 80

az network application-gateway http-listener create \
 --gateway-name "${APPGW_NAME}" \
 --resource-group "${RESOURCE_GROUP}" \
 --name appGatewayHttpListener \
 --frontend-port appGatewayFrontendPort \
 --frontend-ip appGatewayFrontendIP

# Update routing rule
az network application-gateway rule update \
 --gateway-name "${APPGW_NAME}" \
 --resource-group "${RESOURCE_GROUP}" \
 --name rule1 \
 --http-listener appGatewayHttpListener

# Switch Cloudflare back to Flexible mode
```

### Option 2: Delete Key Vault (Cleanup)

**Impact:** Removes certificate storage, AppGW cannot start with HTTPS

**Steps:**

```bash
# Delete Key Vault (soft-delete enabled, 90-day recovery)
az keyvault delete \
 --name "${KV_NAME}" \
 --resource-group "${RESOURCE_GROUP}"

# Purge immediately (optional, prevents name reuse delay)
az keyvault purge --name "${KV_NAME}"
```

## Future Enhancements

### 1. Automated Certificate Renewal

**Approach:** Azure Automation Runbook or Azure Function

- Run monthly, check certificate expiration
- If <30 days remaining, regenerate certificate
- Update Key Vault secret
- AppGW automatically picks up new version (versionless URI)

**Cost:** ~$1/month (Azure Automation or Function App consumption)

### 2. Let's Encrypt Integration

**Approach:** Use ACME protocol to obtain publicly trusted certificate

- Requires DNS validation (Cloudflare API integration)
- 90-day validity, automatic renewal
- Removes self-signed certificate warnings

**Cost:** Free certificate, ~$5/month for automation infrastructure

### 3. Certificate from Azure App Service

**Approach:** Create App Service Managed Certificate, export to Key Vault

- Free managed certificate from Azure
- Automatic renewal
- Requires App Service (additional cost)

**Cost:** App Service Basic plan minimum ~$13/month

## References

- Azure Application Gateway documentation: <https://learn.microsoft.com/en-us/azure/application-gateway/>
- Key Vault managed identity: <https://learn.microsoft.com/en-us/azure/key-vault/general/managed-identity>
- Self-signed certificates: <https://learn.microsoft.com/en-us/azure/application-gateway/self-signed-certificates>
- Cloudflare SSL/TLS modes: <https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/>

## Approval

- **Design Approved:** 2025-10-30
- **Approved By:** User
- **Implementation:** Ready to proceed with script 50 creation
