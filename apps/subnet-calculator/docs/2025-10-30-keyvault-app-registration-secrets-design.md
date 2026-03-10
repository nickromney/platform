# Key Vault and App Registration Secret Management - Design Document

**Date:** 2025-10-30
**Status:** Approved
**Author:** Claude Code

## Problem Statement

Current architecture has several issues with secret management:

1. **Stack 16 requires upfront secrets:** Users must provide `AZURE_CLIENT_SECRET` as environment variable
1. **No secure storage:** Secrets passed as environment variables, not stored securely
1. **Late Key Vault creation:** Script 50 creates Key Vault only for certificates (late in stack)
1. **Duplicate logic:** Key Vault setup code duplicated in script 50
1. **Poor naming convention:** Existing Stack 15 uses generic secret name `swa-auth`
1. **Manual app registration:** Users must create app registrations manually

## Design Goals

1. **Secure by default:** Store all secrets in Key Vault, never require secrets as environment variables
1. **Early Key Vault setup:** Create Key Vault before any secrets are needed
1. **Automated app registration:** Automatically create Entra ID app registrations with proper configuration
1. **Naming convention:** Tie secret names to SWA names for clarity (`${STATIC_WEB_APP_NAME}-client-secret`)
1. **Backward compatibility:** Support existing env var pattern for testing/CI
1. **Code reuse:** Extract Key Vault logic for use across multiple scripts
1. **Idempotency:** Safe to re-run, reuses existing resources

## Architecture Overview

### Current Flow (Stack 16)

```text
User provides AZURE_CLIENT_SECRET env var
 ↓
Stack 16 requires secret upfront (line 109)
 ↓
VNet → App Service → Function → SWA → Private Endpoints
 ↓
Application Gateway → Script 50 creates Key Vault (late)
 ↓
Store certificate in Key Vault
```

**Problem:** Secret required early, Key Vault created late

### New Flow (Stack 16)

```text
User provides AZURE_CLIENT_ID (optional)
 ↓
Step 0: Script 51 → Setup Key Vault (early)
 ↓
Step 0.5: Script 52 → Create/detect app registration
 ↓
 Generate client secret
 ↓
 Store in Key Vault as "${SWA_NAME}-client-secret"
 ↓
VNet → App Service → Function → SWA → Private Endpoints
 ↓
Script 42 retrieves secret from Key Vault
 ↓
Application Gateway → Script 50 reuses Key Vault (calls script 51)
 ↓
Store certificate in Key Vault
```

**Benefits:** Key Vault first, secrets stored securely, no env var required

## Component Design

### Script 51: Setup Key Vault

**File:** `~/Developer/personal/azure-tui/infrastructure/azure/51-setup-key-vault.sh`

**Purpose:** Create or detect Key Vault in resource group (extracted from script 50)

**Input (environment variables):**

- `RESOURCE_GROUP` (required) - Azure resource group
- `LOCATION` (required) - Azure region
- `KEY_VAULT_NAME` (optional) - Specific Key Vault name (required if multiple exist)

**Output (exported environment variables):**

- `KEY_VAULT_NAME` - Name of Key Vault to use
- `KEY_VAULT_ID` - Full resource ID for RBAC assignments

**Behavior:**

- **0 Key Vaults:** Create new with `kv-subnet-calc-${RANDOM_4_HEX}` name
- **1 Key Vault:** Auto-detect and use existing
- **Multiple Key Vaults:** Require `KEY_VAULT_NAME` env var or exit with error

**Key Vault Configuration:**

- SKU: `standard`
- RBAC authorization: `--enable-rbac-authorization true` (no access policies)
- Location: Matches resource group region

**Idempotency:** Safe to call multiple times, reuses existing if found

**Exit Codes:**

- `0` - Success (Key Vault ready)
- `1` - Error (multiple KVs without name specified, creation failed, not accessible)

**Example Usage:**

```bash
export RESOURCE_GROUP="rg-subnet-calc"
export LOCATION="uksouth"

./51-setup-key-vault.sh

# Now available:
echo $KEY_VAULT_NAME # kv-subnet-calc-a1b2
echo $KEY_VAULT_ID # /subscriptions/.../kv-subnet-calc-a1b2
```

### Script 52: Setup App Registration

**File:** `~/Developer/personal/azure-tui/infrastructure/azure/52-setup-app-registration.sh`

**Purpose:** Create/detect Entra ID app registration and store client secret in Key Vault

**Input (environment variables):**

- `STATIC_WEB_APP_NAME` (required) - Used for naming app registration and secret
- `CUSTOM_DOMAIN` (required) - Used for redirect URI
- `KEY_VAULT_NAME` (required) - Where to store client secret
- `AZURE_CLIENT_ID` (optional) - Use existing app registration, skip creation
- `SWA_DEFAULT_HOSTNAME` (optional) - Add azurestaticapps.net redirect URI

**Output (exported environment variables):**

- `AZURE_CLIENT_ID` - App registration client ID

**Naming Convention:**

| Component | Pattern | Example |
|-----------|---------|---------|
| App Registration Display Name | `Subnet Calculator - ${STATIC_WEB_APP_NAME}` | "Subnet Calculator - swa-subnet-calc-private-endpoint" |
| Key Vault Secret Name | `${STATIC_WEB_APP_NAME}-client-secret` | `swa-subnet-calc-private-endpoint-client-secret` |

**Behavior:**

1. **If `AZURE_CLIENT_ID` provided:**

- Validate app registration exists
- Check if secret exists in Key Vault
- If no secret: Generate and store
- If secret exists: Ask to regenerate or reuse

1. **If `AZURE_CLIENT_ID` not provided:**

- Search for app by display name pattern
- If found: Use existing (same behavior as above)
- If not found: Create new app registration

1. **App Registration Configuration:**

- Display name: `Subnet Calculator - ${STATIC_WEB_APP_NAME}`
- Redirect URIs (web platform):
- `https://${CUSTOM_DOMAIN}/.auth/login/aad/callback` (always)
- `https://${SWA_DEFAULT_HOSTNAME}/.auth/login/aad/callback` (if provided)
- Implicit grant: ID tokens enabled
- Access tokens: Enabled

1. **Client Secret Generation:**

- Description: "Generated by script 52 on YYYY-MM-DD"
- Validity: 2 years (Azure default, can be customized)
- Store in Key Vault immediately after generation
- Secret value never displayed to user or logged

**Secret Rotation Support:**

If secret already exists in Key Vault:

```text
Secret 'swa-subnet-calc-private-endpoint-client-secret' exists
Created: 2025-10-30T10:30:00Z

Options:
 1. Reuse existing secret (recommended if working)
 1. Regenerate new secret (creates new app credential)

Choice [1]: _
```

If regenerating:

- Create new credential on app registration
- Update Key Vault secret (creates new version)
- Old secret version retained in Key Vault (versioned storage)

**Idempotency:** Safe to re-run, reuses existing app registration and secret

**Exit Codes:**

- `0` - Success (app registration ready, secret stored)
- `1` - Error (app not found, secret storage failed, Key Vault not accessible)

**Example Usage:**

```bash
# Automated creation
export STATIC_WEB_APP_NAME="swa-subnet-calc-private-endpoint"
export CUSTOM_DOMAIN="static-swa-private-endpoint.publiccloudexperiments.net"
export KEY_VAULT_NAME="kv-subnet-calc-a1b2"

./52-setup-app-registration.sh

# Now available:
echo $AZURE_CLIENT_ID # 00000000-0000-0000-0000-000000000000

# Secret stored in Key Vault as:
# swa-subnet-calc-private-endpoint-client-secret
```

```bash
# Use existing app registration
export AZURE_CLIENT_ID="existing-app-id"
export STATIC_WEB_APP_NAME="swa-subnet-calc-private-endpoint"
export CUSTOM_DOMAIN="static-swa-private-endpoint.publiccloudexperiments.net"
export KEY_VAULT_NAME="kv-subnet-calc-a1b2"

./52-setup-app-registration.sh

# Validates app exists, ensures secret in Key Vault
```

### Script 50: HTTPS Listener (Updated)

**Changes:** Replace inline Key Vault setup with script 51 call

**Before (lines 165-224):**

```bash
setup_key_vault() {
 # 60 lines of Key Vault detection/creation logic
 # ...
}

# Call in main
setup_key_vault
```

**After:**

```bash
# Call script 51 for Key Vault setup
"${SCRIPT_DIR}/51-setup-key-vault.sh"

# KEY_VAULT_NAME and KEY_VAULT_ID now available from export
```

**Benefits:**

- Remove ~60 lines of duplicate code
- Consistent Key Vault setup across all scripts
- Script 50 becomes 40% shorter (652 → ~590 lines)
- Easier to maintain

### Script 42: Entra ID Configuration (Updated)

**Changes:** Add Key Vault secret retrieval fallback

**Current Behavior:** Requires `AZURE_CLIENT_SECRET` environment variable

**New Behavior:** Try three sources in priority order:

1. **Environment variable:** `AZURE_CLIENT_SECRET` (highest priority, for testing/CI)
1. **Key Vault secret:** `${STATIC_WEB_APP_NAME}-client-secret` (production)
1. **Error:** If neither available

**Implementation:**

```bash
# After AZURE_CLIENT_ID is validated (line ~120)

if [[ -n "${AZURE_CLIENT_SECRET:-}" ]]; then
 log_info "Using AZURE_CLIENT_SECRET from environment variable"

elif [[ -n "${KEY_VAULT_NAME:-}" ]]; then
 SECRET_NAME="${STATIC_WEB_APP_NAME}-client-secret"
 log_info "Retrieving secret from Key Vault: ${SECRET_NAME}"

 AZURE_CLIENT_SECRET=$(az keyvault secret show \
 --vault-name "${KEY_VAULT_NAME}" \
 --name "${SECRET_NAME}" \
 --query "value" -o tsv 2>/dev/null || echo "")

 if [[ -n "${AZURE_CLIENT_SECRET}" ]]; then
 log_info "Secret retrieved successfully"
 else
 log_error "Secret '${SECRET_NAME}' not found in Key Vault '${KEY_VAULT_NAME}'"
 log_error "Run script 52 to create app registration and store secret"
 exit 1
 fi

else
 log_error "AZURE_CLIENT_SECRET not provided and KEY_VAULT_NAME not set"
 log_error ""
 log_error "Options:"
 log_error " 1. Set AZURE_CLIENT_SECRET env var (testing/CI)"
 log_error " 2. Set KEY_VAULT_NAME to retrieve from Key Vault (production)"
 log_error " 3. Run script 52 to create app registration"
 exit 1
fi
```

**Backward Compatibility:** Existing usage with env var still works

**Documentation Updates:**

```bash
# Parameters (updated):
# AZURE_CLIENT_ID - Entra ID app registration Client ID (required)
# AZURE_CLIENT_SECRET - Client Secret (optional if KEY_VAULT_NAME set)
# KEY_VAULT_NAME - Key Vault for secret retrieval (optional if AZURE_CLIENT_SECRET set)
# STATIC_WEB_APP_NAME - Name of the Static Web App (required)
# RESOURCE_GROUP - Resource group containing the SWA (optional)
```

### Stack 16: Integration

**File:** `~/Developer/personal/azure-tui/infrastructure/azure/azure-stack-16-swa-private-endpoint.sh`

**Current Flow:**

```text
Line 109-116: Validate AZURE_CLIENT_ID and AZURE_CLIENT_SECRET required
Line 211-226: Step 1 - VNet infrastructure
...
Line 441-502: Step 11 - Update Entra ID (uses AZURE_CLIENT_SECRET)
...
Line 569: Call script 49 (Application Gateway)
Line 572: Call script 50 (HTTPS listener, creates Key Vault)
```

**New Flow:**

```text
Line 95-130: Remove AZURE_CLIENT_SECRET requirement (optional now)
Line 211: NEW Step 0 - Setup Key Vault (script 51)
Line 220: NEW Step 0.5 - Setup App Registration (script 52, optional prompt)
Line 230: Step 1 - VNet infrastructure (unchanged)
...
Line 450: Step 11 - Update Entra ID (uses Key Vault secret via script 42)
...
Line 580: Call script 49 (Application Gateway)
Line 583: Call script 50 (HTTPS listener, reuses Key Vault)
```

**Implementation Details:**

**Remove secret requirement (lines 109-116):**

```bash
# OLD:
if [[ -z "${AZURE_CLIENT_ID:-}" ]] || [[ -z "${AZURE_CLIENT_SECRET:-}" ]]; then
 log_error "AZURE_CLIENT_ID and AZURE_CLIENT_SECRET are required"
 log_error "Usage: AZURE_CLIENT_ID=xxx AZURE_CLIENT_SECRET=xxx $0"
 exit 1
fi

# NEW:
# No validation here - script 52 will handle app registration creation
AZURE_CLIENT_ID="${AZURE_CLIENT_ID:-}" # Optional, will be created if not provided
```

**Add Step 0 (after resource group detection, ~line 211):**

```bash
# Step 0: Setup Key Vault
log_step "Step 0/12: Setting up Key Vault..."
echo ""

export RESOURCE_GROUP
export LOCATION="${REQUESTED_LOCATION}" # Not SWA_LOCATION

"${SCRIPT_DIR}/51-setup-key-vault.sh"

log_info "Key Vault ready: ${KEY_VAULT_NAME}"
echo ""
```

**Add Step 0.5 (after Step 0, ~line 220):**

```bash
# Step 0.5: Setup App Registration
log_step "Step 0.5/12: Setting up Entra ID App Registration..."
echo ""

if [[ -z "${AZURE_CLIENT_ID:-}" ]]; then
 log_info "No AZURE_CLIENT_ID provided"
 log_info "Script can automatically:"
 log_info " • Create Entra ID app registration"
 log_info " • Configure redirect URIs for custom domain"
 log_info " • Generate and store client secret in Key Vault"
 log_info ""
 read -p "Create app registration automatically? (Y/n) " -n 1 -r
 echo

 if [[ ! $REPLY =~ ^[Nn]$ ]]; then
 export STATIC_WEB_APP_NAME
 export CUSTOM_DOMAIN
 export KEY_VAULT_NAME

 "${SCRIPT_DIR}/52-setup-app-registration.sh"

 log_info "App registration created: ${AZURE_CLIENT_ID}"
 log_info "Secret stored in Key Vault as: ${STATIC_WEB_APP_NAME}-client-secret"
 else
 log_error "App registration required to continue"
 log_error ""
 log_error "Options:"
 log_error " 1. Re-run with AZURE_CLIENT_ID=xxx"
 log_error " 2. Run script 52 manually: ./52-setup-app-registration.sh"
 exit 1
 fi
else
 log_info "Using provided AZURE_CLIENT_ID: ${AZURE_CLIENT_ID}"
 log_info "Validating app registration and ensuring secret in Key Vault..."

 export STATIC_WEB_APP_NAME
 export CUSTOM_DOMAIN
 export KEY_VAULT_NAME
 export AZURE_CLIENT_ID

 "${SCRIPT_DIR}/52-setup-app-registration.sh"

 log_info "App registration validated"
fi

echo ""
```

**Update Step 11 (Entra ID config, ~line 495):**

```bash
# Configure Entra ID on SWA
export STATIC_WEB_APP_NAME
export AZURE_CLIENT_ID
export KEY_VAULT_NAME # NEW: Pass to script 42 for secret retrieval
# AZURE_CLIENT_SECRET no longer passed - script 42 retrieves from Key Vault

"${SCRIPT_DIR}/42-configure-entraid-swa.sh"

log_info "Entra ID configured on SWA"
```

**Update documentation header:**

```bash
# Usage:
# # Fully automated (creates everything)
# ./azure-stack-16-swa-private-endpoint.sh
#
# # With existing app registration
# AZURE_CLIENT_ID="xxx" ./azure-stack-16-swa-private-endpoint.sh
#
# # With explicit Key Vault
# KEY_VAULT_NAME="kv-subnet-calc-abcd" ./azure-stack-16-swa-private-endpoint.sh
#
# Environment variables (optional - all auto-created if not provided):
# AZURE_CLIENT_ID - Entra ID app registration client ID
# KEY_VAULT_NAME - Key Vault name (auto-created if not exists)
# RESOURCE_GROUP - Azure resource group (auto-detected if not set)
# LOCATION - Azure region (default: uksouth)
# CUSTOM_DOMAIN - SWA custom domain (default: static-swa-private-endpoint.publiccloudexperiments.net)
#
# IMPORTANT CHANGES:
# • AZURE_CLIENT_SECRET no longer required! Retrieved from Key Vault automatically.
# • Script can create app registration automatically if AZURE_CLIENT_ID not provided.
# • Key Vault created early (Step 0) and used for all secrets.
```

**Benefits:**

- No manual secret management required
- Fully automated setup from scratch
- Secrets never exposed in environment or logs
- Existing workflows still supported (AZURE_CLIENT_ID override)

## Migration Path for Existing Stack 15

**Current State:**

- App registration: "Subnet Calculator - swa-subnet-calc-entraid-linked"
- Key Vault: Exists in resource group (created by script 50 in past run)
- Secret name: `swa-auth` (non-standard, generic)

**Issue:** Secret name doesn't follow new convention

**Migration Steps (one-time, manual):**

```bash
# 1. Find Key Vault
RESOURCE_GROUP="rg-subnet-calc"
KEY_VAULT_NAME=$(az keyvault list \
 --resource-group "${RESOURCE_GROUP}" \
 --query "[0].name" -o tsv)

echo "Key Vault: ${KEY_VAULT_NAME}"

# 2. Verify old secret exists
az keyvault secret show \
 --vault-name "${KEY_VAULT_NAME}" \
 --name "swa-auth" \
 --query "{name: name, created: attributes.created, enabled: attributes.enabled}"

# 3. Copy to new naming convention
OLD_SECRET=$(az keyvault secret show \
 --vault-name "${KEY_VAULT_NAME}" \
 --name "swa-auth" \
 --query "value" -o tsv)

NEW_SECRET_NAME="swa-subnet-calc-entraid-linked-client-secret"

az keyvault secret set \
 --vault-name "${KEY_VAULT_NAME}" \
 --name "${NEW_SECRET_NAME}" \
 --value "${OLD_SECRET}" \
 --description "Migrated from swa-auth on $(date -u +%Y-%m-%d)"

echo "Secret copied to: ${NEW_SECRET_NAME}"

# 4. Verify new secret
az keyvault secret show \
 --vault-name "${KEY_VAULT_NAME}" \
 --name "${NEW_SECRET_NAME}" \
 --query "{name: name, created: attributes.created}"

# 5. Test Stack 15 works with new secret
export RESOURCE_GROUP="${RESOURCE_GROUP}"
export KEY_VAULT_NAME="${KEY_VAULT_NAME}"

# This should work without AZURE_CLIENT_SECRET env var
./azure-stack-15-swa-entraid-linked.sh

# 6. After successful test, delete old secret
read -p "Stack 15 tested successfully? Delete old secret 'swa-auth'? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
 az keyvault secret delete \
 --vault-name "${KEY_VAULT_NAME}" \
 --name "swa-auth"

 echo "Old secret deleted. Purge after 90 days with:"
 echo "az keyvault secret purge --vault-name ${KEY_VAULT_NAME} --name swa-auth"
fi
```

**Stack 15 Code Updates:**

No changes required to Stack 15 if:

- User provides `AZURE_CLIENT_SECRET` env var (backward compatible)
- OR user sets `KEY_VAULT_NAME` env var (script 42 retrieves secret)

Optional enhancement:

- Update Stack 15 to call script 51 early (like Stack 16)
- Update Stack 15 to call script 52 for app registration validation
- Remove `AZURE_CLIENT_SECRET` requirement

## Security Considerations

### Secret Storage

**Key Vault Advantages:**

- Secrets encrypted at rest (Microsoft-managed keys)
- Access controlled via RBAC (least privilege)
- Audit logging via Azure Monitor
- Versioned secrets (rotation support)
- Soft delete and purge protection

**RBAC Roles Required:**

| Principal | Role | Scope | Purpose |
|-----------|------|-------|---------|
| User running scripts | Key Vault Secrets Officer | Key Vault | Create/update secrets |
| Script 42 (reading secrets) | Key Vault Secrets User | Key Vault | Read secrets only |
| Application Gateway | Key Vault Secrets User | Key Vault | Read certificates |

**Secret Lifecycle:**

1. Script 52 creates secret → Stored in Key Vault
1. Script 42 reads secret → Uses for SWA configuration
1. Secret rotation → Update Key Vault (new version)
1. Old secret versions retained → Manual purge after validation

### Entra ID App Registration

**Security Settings:**

- **Redirect URIs:** Whitelist only custom domain (primary) and azurestaticapps.net (optional)
- **Implicit grant:** ID tokens only (no access tokens unless needed)
- **Token lifetime:** Default (1 hour, refreshable)
- **Client secret expiry:** 2 years (configurable)

**Least Privilege:**

- App registration has no API permissions by default
- No admin consent required for basic auth
- Secrets scoped to single app registration

### Network Security

**Key Vault Access:**

- Public endpoint enabled (required for Azure CLI)
- No IP restrictions (Azure CLI uses various IPs)
- RBAC ensures only authorized principals can access

Future enhancement: Private endpoint for Key Vault

## Cost Impact

**Key Vault:**

- Standard SKU: $0.03 per 10,000 operations
- Estimated: ~100 operations/month (secret reads during deployments)
- Cost: ~$0.03/month (negligible)

**No Additional Costs:**

- App registrations: Free
- Secret storage: First 10,000 operations free
- RBAC: No cost

**Total Impact:** Less than $0.10/month

## Testing Plan

### Unit Testing (Individual Scripts)

**Script 51:**

```bash
# Test 1: Create new Key Vault (empty resource group)
export RESOURCE_GROUP="rg-test"
export LOCATION="uksouth"
./51-setup-key-vault.sh
# Verify: Key Vault created, KEY_VAULT_NAME exported

# Test 2: Reuse existing Key Vault (single KV)
./51-setup-key-vault.sh
# Verify: Same Key Vault reused, no error

# Test 3: Multiple Key Vaults without name specified
# Create second Key Vault manually
./51-setup-key-vault.sh
# Verify: Exits with error, lists Key Vaults

# Test 4: Multiple Key Vaults with name specified
export KEY_VAULT_NAME="kv-subnet-calc-xxxx"
./51-setup-key-vault.sh
# Verify: Uses specified Key Vault
```

**Script 52:**

```bash
# Test 1: Create new app registration (fresh start)
export STATIC_WEB_APP_NAME="swa-test-001"
export CUSTOM_DOMAIN="test.example.com"
export KEY_VAULT_NAME="kv-subnet-calc-xxxx"
./52-setup-app-registration.sh
# Verify: App created, secret stored, AZURE_CLIENT_ID exported

# Test 2: Reuse existing app registration
./52-setup-app-registration.sh
# Verify: Reuses app, secret already in KV, no new credential

# Test 3: Use existing app by ID
export AZURE_CLIENT_ID="existing-app-id"
./52-setup-app-registration.sh
# Verify: Validates app, ensures secret in KV

# Test 4: Secret rotation
# Choose option 2 when prompted
./52-setup-app-registration.sh
# Verify: New credential created, KV secret updated (new version)
```

**Script 42:**

```bash
# Test 1: Retrieve from Key Vault
export STATIC_WEB_APP_NAME="swa-test-001"
export AZURE_CLIENT_ID="xxx"
export KEY_VAULT_NAME="kv-subnet-calc-xxxx"
# Do NOT set AZURE_CLIENT_SECRET
./42-configure-entraid-swa.sh
# Verify: Secret retrieved from KV, SWA configured

# Test 2: Use environment variable (backward compat)
export AZURE_CLIENT_SECRET="test-secret"
./42-configure-entraid-swa.sh
# Verify: Uses env var, no KV lookup

# Test 3: No secret available
unset AZURE_CLIENT_SECRET KEY_VAULT_NAME
./42-configure-entraid-swa.sh
# Verify: Error with helpful message
```

**Script 50:**

```bash
# Test: Verify script 51 integration
export RESOURCE_GROUP="rg-test"
export APPGW_NAME="agw-test"
./50-add-https-listener.sh
# Verify: Calls script 51, reuses Key Vault, adds HTTPS listener
```

### Integration Testing (Full Stack)

**Stack 16 - Fully Automated:**

```bash
# Start fresh (no app registration, no Key Vault)
./azure-stack-16-swa-private-endpoint.sh
# User actions:
# - Select resource group (if multiple)
# - Answer "Y" to create app registration
# - Confirm DNS configuration for custom domain
# - Answer "Y" to create Application Gateway
# Verify:
# - Key Vault created (Step 0)
# - App registration created (Step 0.5)
# - Secret stored in KV
# - SWA deployed and accessible
# - Entra ID auth works
# - Application Gateway with HTTPS
```

**Stack 16 - With Existing App:**

```bash
# Provide existing app registration
export AZURE_CLIENT_ID="existing-app-id"
./azure-stack-16-swa-private-endpoint.sh
# Verify:
# - Uses existing app
# - Ensures secret in KV
# - Rest of stack deploys successfully
```

**Stack 15 - After Migration:**

```bash
# After renaming secret in Key Vault
export KEY_VAULT_NAME="kv-subnet-calc-xxxx"
./azure-stack-15-swa-entraid-linked.sh
# Verify:
# - Retrieves secret from KV (new name)
# - Stack deploys successfully
# - Entra ID auth works
```

### Verification Commands

**Check Key Vault:**

```bash
az keyvault show --name "${KEY_VAULT_NAME}" \
 --query "{name: name, location: location, rbacEnabled: properties.enableRbacAuthorization}"
```

**Check Secrets:**

```bash
az keyvault secret list --vault-name "${KEY_VAULT_NAME}" \
 --query "[].{name: name, created: attributes.created}" -o table
```

**Check App Registration:**

```bash
az ad app show --id "${AZURE_CLIENT_ID}" \
 --query "{displayName: displayName, appId: appId, redirectUris: web.redirectUris}"
```

**Check RBAC Assignments:**

```bash
az role assignment list \
 --scope "/subscriptions/xxx/resourceGroups/rg-subnet-calc/providers/Microsoft.KeyVault/vaults/${KEY_VAULT_NAME}" \
 --query "[].{principal: principalName, role: roleDefinitionName}"
```

## Documentation Updates

### Files to Update

1. **Script 50 Usage:** `~/Developer/personal/azure-tui/infrastructure/azure/docs/script-50-usage.md`

- Update to mention script 51 dependency
- Document Key Vault reuse pattern

1. **Stack 16 README:** Update usage instructions

- Remove AZURE_CLIENT_SECRET requirement
- Document automated app registration
- Add migration notes for existing users

1. **Script 42 Documentation:** Add Key Vault retrieval section

1. **New Documentation:**

- `docs/script-51-usage.md` - Key Vault setup guide
- `docs/script-52-usage.md` - App registration automation guide

### Example Documentation Snippets

**Stack 16 Usage (updated):**

```markdown
## Usage

### Fully Automated (Recommended)

```bash
./azure-stack-16-swa-private-endpoint.sh
```

Script will automatically:

- Create Key Vault for secure secret storage
- Create Entra ID app registration
- Generate and store client secret
- Deploy entire stack

No manual secret management required!

### With Existing App Registration

```bash
AZURE_CLIENT_ID="your-app-id" ./azure-stack-16-swa-private-endpoint.sh
```

Validates existing app and ensures secret is in Key Vault.

### Environment Variables

All optional (auto-created if not provided):

- `AZURE_CLIENT_ID` - Entra ID app registration client ID
- `KEY_VAULT_NAME` - Key Vault name
- `RESOURCE_GROUP` - Azure resource group
- `LOCATION` - Azure region (default: uksouth)
- `CUSTOM_DOMAIN` - Custom domain for SWA

### Important Changes from v1

- AZURE_CLIENT_SECRET no longer required (retrieved from Key Vault)
- Fully automated setup - no manual app registration needed
- Key Vault created early (Step 0) for all secrets

## Implementation Approach

Following the brainstorming skill workflow, next steps:

1. **Write this design document** to `docs/plans/2025-10-30-keyvault-app-registration-secrets-design.md`
1. **Create implementation plan** using `writing-plans` skill
1. **Set up worktree** using `using-git-worktrees` skill
1. **Execute implementation** using `subagent-driven-development` or manual implementation

## Success Criteria

1. Script 51 creates/detects Key Vault idempotently
1. Script 52 automates app registration with secret storage
1. Script 50 reuses script 51 (no duplicate code)
1. Script 42 retrieves secrets from Key Vault
1. Stack 16 works without AZURE_CLIENT_SECRET env var
1. Stack 15 works with renamed secret after migration
1. All tests pass (unit + integration)
1. Documentation updated and accurate
1. Backward compatibility maintained (env var still works)
1. No secrets exposed in logs or output

## References

- Current Script 50: `~/Developer/personal/azure-tui/infrastructure/azure/50-add-https-listener.sh`
- Current Script 42: `~/Developer/personal/azure-tui/infrastructure/azure/42-configure-entraid-swa.sh`
- Current Stack 16: `~/Developer/personal/azure-tui/infrastructure/azure/azure-stack-16-swa-private-endpoint.sh`
- Azure Key Vault RBAC: <https://learn.microsoft.com/en-us/azure/key-vault/general/rbac-guide>
- Entra ID App Registration: <https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app>
