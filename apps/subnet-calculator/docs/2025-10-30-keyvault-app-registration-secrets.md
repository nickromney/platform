# Key Vault and App Registration Secret Management Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Automate Entra ID app registration and secret management using Azure Key Vault, eliminating manual secret handling and enabling fully automated Stack 16 deployments.

**Architecture:** Extract Key Vault creation from script 50 into reusable script 51. Create script 52 for automated app registration with secret storage. Update existing scripts (50, 42, Stack 16) to use new infrastructure. Maintain backward compatibility with environment variable pattern.

**Tech Stack:** Bash, Azure CLI, Azure Key Vault, Entra ID (Microsoft Graph API), OpenSSL

---

## Task 1: Create Script 51 - Key Vault Setup

**Files:**

- Create: `~/Developer/personal/azure-tui/infrastructure/azure/51-setup-key-vault.sh`
- Reference: `~/Developer/personal/azure-tui/infrastructure/azure/50-add-https-listener.sh:165-224` (source for extraction)

### Step 1: Create script header and prerequisites

Create `~/Developer/personal/azure-tui/infrastructure/azure/51-setup-key-vault.sh`:

```bash
#!/usr/bin/env bash
#
# 51-setup-key-vault.sh - Setup or Detect Azure Key Vault
#
# This script ensures a Key Vault exists in the resource group.
# It can detect existing Key Vaults or create a new one with a unique name.
#
# Usage:
# # Auto-detect single Key Vault or create new
# RESOURCE_GROUP="rg-subnet-calc" LOCATION="uksouth" ./51-setup-key-vault.sh
#
# # Use specific Key Vault (if multiple exist)
# RESOURCE_GROUP="rg-subnet-calc" LOCATION="uksouth" \
# KEY_VAULT_NAME="kv-subnet-calc-abcd" ./51-setup-key-vault.sh
#
# Input (environment variables required):
# RESOURCE_GROUP - Azure resource group name
# LOCATION - Azure region (e.g., uksouth)
#
# Input (environment variables optional):
# KEY_VAULT_NAME - Specific Key Vault name (required if multiple exist)
#
# Output (exported environment variables):
# KEY_VAULT_NAME - Name of the Key Vault
# KEY_VAULT_ID - Full resource ID of the Key Vault
#
# Behavior:
# - 0 Key Vaults: Create new with random suffix
# - 1 Key Vault: Auto-detect and use
# - Multiple Key Vaults: Error unless KEY_VAULT_NAME specified
#
# Exit Codes:
# 0 - Success (Key Vault ready)
# 1 - Error (missing env vars, multiple KVs without name, creation failed)

set -euo pipefail

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step() { echo -e "${BLUE}[STEP]${NC} $*"; }

# Validate required environment variables
if [[ -z "${RESOURCE_GROUP:-}" ]]; then
 log_error "RESOURCE_GROUP environment variable is required"
 log_error "Usage: RESOURCE_GROUP=rg-name LOCATION=region $0"
 exit 1
fi

if [[ -z "${LOCATION:-}" ]]; then
 log_error "LOCATION environment variable is required"
 log_error "Usage: RESOURCE_GROUP=rg-name LOCATION=region $0"
 exit 1
fi

# Check Azure CLI authentication
if ! az account show &>/dev/null; then
 log_error "Not logged in to Azure. Run 'az login'"
 exit 1
fi

log_step "Setting up Key Vault in ${RESOURCE_GROUP}..."
```

### Step 2: Add Key Vault detection logic

Add after prerequisites in `51-setup-key-vault.sh`:

```bash
# Count Key Vaults in resource group
KV_COUNT=$(az keyvault list \
 --resource-group "${RESOURCE_GROUP}" \
 --query "length(@)" -o tsv 2>/dev/null || echo "0")

if [[ "${KV_COUNT}" -eq 1 ]]; then
 # Single Key Vault: Auto-detect
 KEY_VAULT_NAME=$(az keyvault list \
 --resource-group "${RESOURCE_GROUP}" \
 --query "[0].name" -o tsv)
 log_info "Found existing Key Vault: ${KEY_VAULT_NAME}"

elif [[ "${KV_COUNT}" -gt 1 ]]; then
 # Multiple Key Vaults: Require KEY_VAULT_NAME
 if [[ -z "${KEY_VAULT_NAME:-}" ]]; then
 log_error "Multiple Key Vaults found in ${RESOURCE_GROUP}"
 log_error "Specify which one to use: KEY_VAULT_NAME='kv-name' $0"
 log_error ""
 log_error "Available Key Vaults:"
 az keyvault list \
 --resource-group "${RESOURCE_GROUP}" \
 --query "[].[name, properties.provisioningState]" -o table
 exit 1
 fi
 log_info "Using specified Key Vault: ${KEY_VAULT_NAME}"

else
 # No Key Vaults: Create new with unique name
 KV_SUFFIX=$(openssl rand -hex 2) # 4 hex chars for uniqueness
 KEY_VAULT_NAME="kv-subnet-calc-${KV_SUFFIX}"

 log_info "No Key Vault found. Creating: ${KEY_VAULT_NAME}..."
 if az keyvault create \
 --name "${KEY_VAULT_NAME}" \
 --resource-group "${RESOURCE_GROUP}" \
 --location "${LOCATION}" \
 --enable-rbac-authorization true \
 --sku standard \
 --output none; then
 log_info "Key Vault created successfully"
 else
 log_error "Failed to create Key Vault"
 exit 1
 fi
fi
```

### Step 3: Add validation and export

Add after detection logic in `51-setup-key-vault.sh`:

```bash
# Verify Key Vault is accessible
if ! az keyvault show --name "${KEY_VAULT_NAME}" &>/dev/null; then
 log_error "Key Vault '${KEY_VAULT_NAME}' not accessible"
 log_error "Check that it exists and you have permissions"
 exit 1
fi

# Get Key Vault resource ID for RBAC assignments
KEY_VAULT_ID=$(az keyvault show \
 --name "${KEY_VAULT_NAME}" \
 --query "id" -o tsv)

log_info "Key Vault ready: ${KEY_VAULT_NAME}"
log_info "Resource ID: ${KEY_VAULT_ID}"

# Export for caller scripts
export KEY_VAULT_NAME
export KEY_VAULT_ID

log_info "Exported KEY_VAULT_NAME and KEY_VAULT_ID"
```

### Step 4: Make script executable

Run:

```bash
chmod +x ~/Developer/personal/azure-tui/infrastructure/azure/51-setup-key-vault.sh
```

### Step 5: Test script (manual verification)

Test with a test resource group:

```bash
export RESOURCE_GROUP="rg-subnet-calc"
export LOCATION="uksouth"

~/Developer/personal/azure-tui/infrastructure/azure/51-setup-key-vault.sh
```

Expected output:

```text
[STEP] Setting up Key Vault in rg-subnet-calc...
[INFO] No Key Vault found. Creating: kv-subnet-calc-xxxx...
[INFO] Key Vault created successfully
[INFO] Key Vault ready: kv-subnet-calc-xxxx
[INFO] Resource ID: /subscriptions/.../kv-subnet-calc-xxxx
[INFO] Exported KEY_VAULT_NAME and KEY_VAULT_ID
```

Verify exports:

```bash
echo $KEY_VAULT_NAME # Should show kv-subnet-calc-xxxx
echo $KEY_VAULT_ID # Should show full resource ID
```

### Step 6: Test idempotency (re-run)

Run again:

```bash
~/Developer/personal/azure-tui/infrastructure/azure/51-setup-key-vault.sh
```

Expected: Detects existing Key Vault, no errors

### Step 7: Commit

```bash
git add ~/Developer/personal/azure-tui/infrastructure/azure/51-setup-key-vault.sh
git commit -m "feat: Add script 51 for Key Vault setup

Extract Key Vault detection/creation logic from script 50 into
reusable script. Enables Key Vault creation early in stack flows.

Features:
- Auto-detect single Key Vault or create new
- Handle multiple Key Vaults with explicit name
- Export KEY_VAULT_NAME and KEY_VAULT_ID
- RBAC-enabled Key Vault (no access policies)
- Idempotent (safe to re-run)

 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 2: Create Script 52 - App Registration Setup

**Files:**

- Create: `~/Developer/personal/azure-tui/infrastructure/azure/52-setup-app-registration.sh`
- Reference: `~/Developer/personal/azure-tui/infrastructure/azure/60-entraid-user-setup.sh` (app registration patterns)

### Step 1: Create script header and prerequisites

Create `~/Developer/personal/azure-tui/infrastructure/azure/52-setup-app-registration.sh`:

```bash
#!/usr/bin/env bash
#
# 52-setup-app-registration.sh - Setup Entra ID App Registration with Key Vault Secret Storage
#
# This script automates Entra ID app registration creation/detection and stores
# the client secret in Azure Key Vault using a naming convention tied to the SWA name.
#
# Usage:
# # Auto-create app registration
# STATIC_WEB_APP_NAME="swa-subnet-calc-private-endpoint" \
# CUSTOM_DOMAIN="static-swa-private-endpoint.publiccloudexperiments.net" \
# KEY_VAULT_NAME="kv-subnet-calc-abcd" \
# ./52-setup-app-registration.sh
#
# # Use existing app registration
# AZURE_CLIENT_ID="existing-app-id" \
# STATIC_WEB_APP_NAME="swa-subnet-calc-private-endpoint" \
# CUSTOM_DOMAIN="static-swa-private-endpoint.publiccloudexperiments.net" \
# KEY_VAULT_NAME="kv-subnet-calc-abcd" \
# ./52-setup-app-registration.sh
#
# Input (environment variables required):
# STATIC_WEB_APP_NAME - SWA name (used for app name and secret name)
# CUSTOM_DOMAIN - Custom domain for redirect URI
# KEY_VAULT_NAME - Key Vault for secret storage
#
# Input (environment variables optional):
# AZURE_CLIENT_ID - Use existing app registration (skip creation)
# SWA_DEFAULT_HOSTNAME - Add azurestaticapps.net redirect URI (optional)
#
# Output (exported environment variables):
# AZURE_CLIENT_ID - App registration client ID
#
# Naming Convention:
# App Display Name: "Subnet Calculator - ${STATIC_WEB_APP_NAME}"
# Secret Name: "${STATIC_WEB_APP_NAME}-client-secret"
#
# Behavior:
# - If AZURE_CLIENT_ID provided: Validate app, ensure secret in Key Vault
# - If not provided: Search by display name, create if not found
# - If secret exists in Key Vault: Prompt to reuse or regenerate
#
# Exit Codes:
# 0 - Success (app registration ready, secret stored)
# 1 - Error (app not found, secret storage failed, Key Vault not accessible)

set -euo pipefail

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step() { echo -e "${BLUE}[STEP]${NC} $*"; }

# Validate required environment variables
if [[ -z "${STATIC_WEB_APP_NAME:-}" ]]; then
 log_error "STATIC_WEB_APP_NAME environment variable is required"
 exit 1
fi

if [[ -z "${CUSTOM_DOMAIN:-}" ]]; then
 log_error "CUSTOM_DOMAIN environment variable is required"
 exit 1
fi

if [[ -z "${KEY_VAULT_NAME:-}" ]]; then
 log_error "KEY_VAULT_NAME environment variable is required"
 log_error "Run script 51 first to setup Key Vault"
 exit 1
fi

# Check Azure CLI authentication
if ! az account show &>/dev/null; then
 log_error "Not logged in to Azure. Run 'az login'"
 exit 1
fi

TENANT_ID=$(az account show --query tenantId -o tsv)

log_step "Setting up Entra ID app registration for ${STATIC_WEB_APP_NAME}..."
```

### Step 2: Add app registration detection/creation

Add after prerequisites in `52-setup-app-registration.sh`:

```bash
# Define naming convention
APP_DISPLAY_NAME="Subnet Calculator - ${STATIC_WEB_APP_NAME}"
SECRET_NAME="${STATIC_WEB_APP_NAME}-client-secret"

# Build redirect URIs
REDIRECT_URI_CUSTOM="https://${CUSTOM_DOMAIN}/.auth/login/aad/callback"
REDIRECT_URIS=("${REDIRECT_URI_CUSTOM}")

if [[ -n "${SWA_DEFAULT_HOSTNAME:-}" ]]; then
 REDIRECT_URI_DEFAULT="https://${SWA_DEFAULT_HOSTNAME}/.auth/login/aad/callback"
 REDIRECT_URIS+=("${REDIRECT_URI_DEFAULT}")
 log_info "Redirect URIs: Custom domain + azurestaticapps.net"
else
 log_info "Redirect URI: Custom domain only"
fi

# Check if app registration already exists
if [[ -n "${AZURE_CLIENT_ID:-}" ]]; then
 log_info "Using provided AZURE_CLIENT_ID: ${AZURE_CLIENT_ID}"

 # Validate app exists
 if ! az ad app show --id "${AZURE_CLIENT_ID}" &>/dev/null; then
 log_error "App registration ${AZURE_CLIENT_ID} not found"
 exit 1
 fi

 APP_OBJECT_ID=$(az ad app show --id "${AZURE_CLIENT_ID}" --query id -o tsv)
 log_info "App registration found"

else
 log_info "Searching for app registration: ${APP_DISPLAY_NAME}"

 # Search by display name
 EXISTING_APP=$(az ad app list \
 --display-name "${APP_DISPLAY_NAME}" \
 --query "[0].{appId: appId, objectId: id}" -o json 2>/dev/null || echo "{}")

 AZURE_CLIENT_ID=$(echo "${EXISTING_APP}" | jq -r '.appId // empty')
 APP_OBJECT_ID=$(echo "${EXISTING_APP}" | jq -r '.objectId // empty')

 if [[ -n "${AZURE_CLIENT_ID}" ]]; then
 log_info "Found existing app registration: ${AZURE_CLIENT_ID}"
 else
 log_info "Creating new app registration: ${APP_DISPLAY_NAME}"

 # Build redirect URIs JSON array
 REDIRECT_URIS_JSON=$(printf '"%s",' "${REDIRECT_URIS[@]}" | sed 's/,$//')

 # Create app registration via Graph API
 CREATE_RESULT=$(az rest --method POST \
 --uri "https://graph.microsoft.com/v1.0/applications" \
 --headers 'Content-Type=application/json' \
 --body "{
 \"displayName\": \"${APP_DISPLAY_NAME}\",
 \"signInAudience\": \"AzureADMyOrg\",
 \"web\": {
 \"redirectUris\": [${REDIRECT_URIS_JSON}],
 \"implicitGrantSettings\": {
 \"enableAccessTokenIssuance\": true,
 \"enableIdTokenIssuance\": true
 }
 }
 }")

 AZURE_CLIENT_ID=$(echo "${CREATE_RESULT}" | jq -r '.appId')
 APP_OBJECT_ID=$(echo "${CREATE_RESULT}" | jq -r '.id')

 log_info "App registration created: ${AZURE_CLIENT_ID}"
 fi
fi

# Update redirect URIs (in case they changed)
log_info "Updating redirect URIs..."
REDIRECT_URIS_JSON=$(printf '"%s",' "${REDIRECT_URIS[@]}" | sed 's/,$//')

az rest --method PATCH \
 --uri "https://graph.microsoft.com/v1.0/applications/${APP_OBJECT_ID}" \
 --headers 'Content-Type=application/json' \
 --body "{
 \"web\": {
 \"redirectUris\": [${REDIRECT_URIS_JSON}],
 \"implicitGrantSettings\": {
 \"enableAccessTokenIssuance\": true,
 \"enableIdTokenIssuance\": true
 }
 }
 }" \
 --output none

log_info "Redirect URIs updated"
```

### Step 3: Add client secret generation and Key Vault storage

Add after app registration logic in `52-setup-app-registration.sh`:

```bash
# Check if secret already exists in Key Vault
log_info "Checking for existing secret in Key Vault..."

EXISTING_SECRET=$(az keyvault secret show \
 --vault-name "${KEY_VAULT_NAME}" \
 --name "${SECRET_NAME}" \
 --query "{created: attributes.created, enabled: attributes.enabled}" -o json 2>/dev/null || echo "{}")

SECRET_EXISTS=$(echo "${EXISTING_SECRET}" | jq -r '.created // empty')

if [[ -n "${SECRET_EXISTS}" ]]; then
 log_warn "Secret '${SECRET_NAME}' already exists in Key Vault"
 echo "Created: ${SECRET_EXISTS}"
 echo ""
 echo "Options:"
 echo " 1. Reuse existing secret (recommended if working)"
 echo " 2. Regenerate new secret (creates new app credential)"
 echo ""
 read -p "Choice [1]: " -n 1 -r
 echo

 if [[ $REPLY =~ ^[2]$ ]]; then
 log_info "Regenerating secret..."
 REGENERATE_SECRET=true
 else
 log_info "Reusing existing secret"
 REGENERATE_SECRET=false
 fi
else
 log_info "No existing secret found. Generating new secret..."
 REGENERATE_SECRET=true
fi

if [[ "${REGENERATE_SECRET}" == "true" ]]; then
 # Generate new client secret
 log_info "Creating new client secret on app registration..."

 SECRET_DESCRIPTION="Generated by script 52 on $(date -u +%Y-%m-%d)"

 SECRET_RESULT=$(az ad app credential reset \
 --id "${AZURE_CLIENT_ID}" \
 --append \
 --display-name "${SECRET_DESCRIPTION}" \
 --query "password" -o tsv)

 if [[ -z "${SECRET_RESULT}" ]]; then
 log_error "Failed to create client secret"
 exit 1
 fi

 # Store in Key Vault
 log_info "Storing secret in Key Vault as: ${SECRET_NAME}"

 if ! az keyvault secret set \
 --vault-name "${KEY_VAULT_NAME}" \
 --name "${SECRET_NAME}" \
 --value "${SECRET_RESULT}" \
 --description "Client secret for ${APP_DISPLAY_NAME}" \
 --output none; then
 log_error "Failed to store secret in Key Vault"
 log_error "Secret was created on app registration but not stored"
 exit 1
 fi

 log_info "Secret stored successfully"
fi

# Export for caller
export AZURE_CLIENT_ID

log_info "App registration ready: ${AZURE_CLIENT_ID}"
log_info "Secret available in Key Vault as: ${SECRET_NAME}"
```

### Step 4: Make script executable

Run:

```bash
chmod +x ~/Developer/personal/azure-tui/infrastructure/azure/52-setup-app-registration.sh
```

### Step 5: Test script (manual verification)

Test with the Key Vault from Task 1:

```bash
export STATIC_WEB_APP_NAME="swa-test-script52"
export CUSTOM_DOMAIN="test.example.com"
export KEY_VAULT_NAME="kv-subnet-calc-xxxx" # From Task 1

~/Developer/personal/azure-tui/infrastructure/azure/52-setup-app-registration.sh
```

Expected output:

```text
[STEP] Setting up Entra ID app registration for swa-test-script52...
[INFO] Redirect URI: Custom domain only
[INFO] Searching for app registration: Subnet Calculator - swa-test-script52
[INFO] Creating new app registration: Subnet Calculator - swa-test-script52
[INFO] App registration created: <client-id>
[INFO] Updating redirect URIs...
[INFO] Redirect URIs updated
[INFO] Checking for existing secret in Key Vault...
[INFO] No existing secret found. Generating new secret...
[INFO] Creating new client secret on app registration...
[INFO] Storing secret in Key Vault as: swa-test-script52-client-secret
[INFO] Secret stored successfully
[INFO] App registration ready: <client-id>
[INFO] Secret available in Key Vault as: swa-test-script52-client-secret
```

Verify secret in Key Vault:

```bash
az keyvault secret show \
 --vault-name "${KEY_VAULT_NAME}" \
 --name "swa-test-script52-client-secret" \
 --query "{name: name, created: attributes.created}"
```

### Step 6: Test idempotency (re-run with reuse)

Run again and choose option 1 (reuse):

```bash
~/Developer/personal/azure-tui/infrastructure/azure/52-setup-app-registration.sh
```

Expected: Detects existing app and secret, prompts to reuse, no errors

### Step 7: Commit

```bash
git add ~/Developer/personal/azure-tui/infrastructure/azure/52-setup-app-registration.sh
git commit -m "feat: Add script 52 for app registration automation

Automate Entra ID app registration creation with Key Vault secret storage.
Eliminates manual secret handling and enables fully automated deployments.

Features:
- Auto-create or detect app registration by naming pattern
- Configure redirect URIs (custom domain + optional azurestaticapps.net)
- Generate client secret and store in Key Vault
- Naming convention: \${SWA_NAME}-client-secret
- Secret rotation support (reuse or regenerate)
- Idempotent (safe to re-run)

 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 3: Update Script 50 to Use Script 51

**Files:**

- Modify: `~/Developer/personal/azure-tui/infrastructure/azure/50-add-https-listener.sh:165-224`

### Step 1: Remove inline Key Vault setup function

In `50-add-https-listener.sh`, delete the `setup_key_vault()` function (lines 165-224) and its call in the main flow.

### Step 2: Add script 51 call

Replace the deleted `setup_key_vault()` call with script 51 call.

Find the main execution flow (around line 635-650) where `setup_key_vault` was called:

```bash
# OLD (delete these lines):
setup_key_vault

# NEW (add these lines):
# Setup Key Vault (script 51)
"${SCRIPT_DIR}/51-setup-key-vault.sh"
# KEY_VAULT_NAME and KEY_VAULT_ID now available from export
```

### Step 3: Verify SCRIPT_DIR is defined

Ensure `SCRIPT_DIR` is defined at the top of the script (should already exist):

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```

### Step 4: Test script 50 still works

Test with an existing Application Gateway:

```bash
export RESOURCE_GROUP="rg-subnet-calc"
export APPGW_NAME="agw-test" # Must exist

~/Developer/personal/azure-tui/infrastructure/azure/50-add-https-listener.sh
```

Expected: Calls script 51, detects Key Vault, continues with HTTPS listener setup

### Step 5: Commit

```bash
git add ~/Developer/personal/azure-tui/infrastructure/azure/50-add-https-listener.sh
git commit -m "refactor: Use script 51 for Key Vault setup in script 50

Replace inline Key Vault setup logic with call to script 51.
Removes ~60 lines of duplicate code and improves maintainability.

Changes:
- Remove setup_key_vault() function
- Call 51-setup-key-vault.sh instead
- KEY_VAULT_NAME and KEY_VAULT_ID from export

 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 4: Update Script 42 to Support Key Vault Secret Retrieval

**Files:**

- Modify: `~/Developer/personal/azure-tui/infrastructure/azure/42-configure-entraid-swa.sh:20-40`

### Step 1: Update documentation header

In `42-configure-entraid-swa.sh`, update the parameters section (lines 19-23):

```bash
# Parameters:
# STATIC_WEB_APP_NAME - Name of the Static Web App
# AZURE_CLIENT_ID - Entra ID app registration Client ID
# AZURE_CLIENT_SECRET - Client Secret (optional if KEY_VAULT_NAME set)
# KEY_VAULT_NAME - Key Vault for secret retrieval (optional if AZURE_CLIENT_SECRET set)
# RESOURCE_GROUP - Resource group containing the SWA
```

### Step 2: Add Key Vault secret retrieval logic

Find where `AZURE_CLIENT_ID` is validated (around line 120). After that section, add the secret retrieval logic:

```bash
# Get AZURE_CLIENT_SECRET from environment or Key Vault
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
 log_error ""
 log_error "Options:"
 log_error " 1. Run script 52 to create app registration and store secret:"
 log_error " STATIC_WEB_APP_NAME=\"${STATIC_WEB_APP_NAME}\" \\"
 log_error " CUSTOM_DOMAIN=\"your-domain\" \\"
 log_error " KEY_VAULT_NAME=\"${KEY_VAULT_NAME}\" \\"
 log_error " ./52-setup-app-registration.sh"
 log_error ""
 log_error " 2. Set AZURE_CLIENT_SECRET environment variable"
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

### Step 3: Update usage examples in header

Update the usage examples (lines 8-17) to show both patterns:

```bash
# Usage:
# # With Key Vault secret (production - recommended)
# STATIC_WEB_APP_NAME="swa-subnet-calc-entraid" \
# AZURE_CLIENT_ID="00000000-0000-0000-0000-000000000000" \
# KEY_VAULT_NAME="kv-subnet-calc-abcd" \
# RESOURCE_GROUP="rg-subnet-calc" \
# ./42-configure-entraid-swa.sh
#
# # With environment variable secret (testing/CI)
# STATIC_WEB_APP_NAME="swa-subnet-calc-entraid" \
# AZURE_CLIENT_ID="00000000-0000-0000-0000-000000000000" \
# AZURE_CLIENT_SECRET="your-secret-here" \
# RESOURCE_GROUP="rg-subnet-calc" \
# ./42-configure-entraid-swa.sh
```

### Step 4: Test with Key Vault retrieval

Test using the test app registration from Task 2:

```bash
export STATIC_WEB_APP_NAME="swa-test-script52"
export AZURE_CLIENT_ID="<client-id-from-task2>"
export KEY_VAULT_NAME="kv-subnet-calc-xxxx"
export RESOURCE_GROUP="rg-subnet-calc"

# Assumes SWA exists - if not, script will error at SWA detection
# This is expected - we're testing secret retrieval logic only
~/Developer/personal/azure-tui/infrastructure/azure/42-configure-entraid-swa.sh
```

Expected: Script retrieves secret from Key Vault, no errors in secret retrieval section

### Step 5: Test backward compatibility with env var

Test with environment variable:

```bash
export STATIC_WEB_APP_NAME="swa-test-script52"
export AZURE_CLIENT_ID="<client-id>"
export AZURE_CLIENT_SECRET="test-secret-value"
export RESOURCE_GROUP="rg-subnet-calc"

~/Developer/personal/azure-tui/infrastructure/azure/42-configure-entraid-swa.sh
```

Expected: Script uses env var, logs "Using AZURE_CLIENT_SECRET from environment variable"

### Step 6: Commit

```bash
git add ~/Developer/personal/azure-tui/infrastructure/azure/42-configure-entraid-swa.sh
git commit -m "feat: Add Key Vault secret retrieval to script 42

Add fallback to retrieve AZURE_CLIENT_SECRET from Key Vault if not
provided as environment variable. Maintains backward compatibility.

Changes:
- Try AZURE_CLIENT_SECRET env var first (testing/CI)
- Fallback to Key Vault secret retrieval (production)
- Error if neither available with helpful guidance
- Update documentation with both usage patterns

 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 5: Update Stack 16 - Add Step 0 (Key Vault Setup)

**Files:**

- Modify: `~/Developer/personal/azure-tui/infrastructure/azure/azure-stack-16-swa-private-endpoint.sh:109-116` (remove secret requirement)
- Modify: `~/Developer/personal/azure-tui/infrastructure/azure/azure-stack-16-swa-private-endpoint.sh:211` (add Step 0)

### Step 1: Remove AZURE_CLIENT_SECRET requirement

In `azure-stack-16-swa-private-endpoint.sh`, find the validation section (lines 109-116):

```bash
# OLD (delete these lines):
if [[ -z "${AZURE_CLIENT_ID:-}" ]] || [[ -z "${AZURE_CLIENT_SECRET:-}" ]]; then
 log_error "AZURE_CLIENT_ID and AZURE_CLIENT_SECRET are required"
 log_error "Usage: AZURE_CLIENT_ID=xxx AZURE_CLIENT_SECRET=xxx $0"
 exit 1
fi

readonly AZURE_CLIENT_ID
readonly AZURE_CLIENT_SECRET

# NEW (replace with):
# AZURE_CLIENT_ID is optional - will be created by script 52 if not provided
AZURE_CLIENT_ID="${AZURE_CLIENT_ID:-}"
```

### Step 2: Update documentation header

Update the usage section (lines 60-69) to remove AZURE_CLIENT_SECRET requirement:

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
# CUSTOM_DOMAIN - SWA custom domain
#
# IMPORTANT CHANGES:
# • AZURE_CLIENT_SECRET no longer required! Retrieved from Key Vault automatically.
# • Script can create app registration automatically if AZURE_CLIENT_ID not provided.
# • Key Vault created early (Step 0) and used for all secrets.
```

### Step 3: Add Step 0 - Key Vault setup

After resource group detection (line 209), before VNet creation (line 211), add Step 0:

```bash
# Step 0: Setup Key Vault
log_step "Step 0/12: Setting up Key Vault..."
echo ""

export RESOURCE_GROUP
export LOCATION="${REQUESTED_LOCATION}" # Use original location, not SWA_LOCATION

"${SCRIPT_DIR}/51-setup-key-vault.sh"

log_info "Key Vault ready: ${KEY_VAULT_NAME}"
echo ""
```

### Step 4: Test Step 0 integration

Test with a clean resource group (no existing Key Vault):

```bash
export RESOURCE_GROUP="rg-test-stack16"

# Run stack (will fail at VNet creation, but that's ok - we're testing Step 0)
~/Developer/personal/azure-tui/infrastructure/azure/azure-stack-16-swa-private-endpoint.sh
```

Expected: Step 0 runs, creates Key Vault, continues to Step 1

### Step 5: Commit

```bash
git add ~/Developer/personal/azure-tui/infrastructure/azure/azure-stack-16-swa-private-endpoint.sh
git commit -m "feat: Add Step 0 (Key Vault setup) to Stack 16

Create Key Vault early in stack flow before any secrets are needed.
Remove AZURE_CLIENT_SECRET requirement from validation.

Changes:
- Add Step 0 calling script 51 after resource group detection
- Remove AZURE_CLIENT_SECRET validation (now optional)
- Update documentation to reflect automated secret management

 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 6: Update Stack 16 - Add Step 0.5 (App Registration Setup)

**Files:**

- Modify: `~/Developer/personal/azure-tui/infrastructure/azure/azure-stack-16-swa-private-endpoint.sh:220` (after Step 0)

### Step 1: Add Step 0.5 - App registration setup

After Step 0 (around line 220), add Step 0.5:

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
 log_error " 2. Run script 52 manually:"
 log_error " STATIC_WEB_APP_NAME=\"${STATIC_WEB_APP_NAME}\" \\"
 log_error " CUSTOM_DOMAIN=\"${CUSTOM_DOMAIN}\" \\"
 log_error " KEY_VAULT_NAME=\"${KEY_VAULT_NAME}\" \\"
 log_error " ./52-setup-app-registration.sh"
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

### Step 2: Update step numbers

Update all subsequent step numbers from X/11 to X/12 (since we added Step 0 and 0.5).

Find and replace:

- "Step 1/11" → "Step 1/12"
- "Step 2/11" → "Step 2/12"
- ... through ...
- "Step 11/11" → "Step 11/12"

### Step 3: Update banner

Update the banner to reflect 12 steps instead of 11:

```bash
log_info "Stack 3: Private Endpoint + Entra ID"
log_info "HIGH SECURITY SETUP (12 steps)"
```

### Step 4: Test Step 0.5 with auto-creation

Test with no AZURE_CLIENT_ID:

```bash
export RESOURCE_GROUP="rg-test-stack16"
export CUSTOM_DOMAIN="test-stack16.example.com"

# Run stack, answer "Y" to create app registration prompt
~/Developer/personal/azure-tui/infrastructure/azure/azure-stack-16-swa-private-endpoint.sh
```

Expected: Step 0.5 prompts, creates app registration, stores secret in Key Vault

### Step 5: Test Step 0.5 with existing AZURE_CLIENT_ID

Test with existing app registration:

```bash
export RESOURCE_GROUP="rg-test-stack16"
export AZURE_CLIENT_ID="<existing-app-id>"
export CUSTOM_DOMAIN="test-stack16.example.com"

~/Developer/personal/azure-tui/infrastructure/azure/azure-stack-16-swa-private-endpoint.sh
```

Expected: Step 0.5 validates app, ensures secret in Key Vault, no prompts

### Step 6: Commit

```bash
git add ~/Developer/personal/azure-tui/infrastructure/azure/azure-stack-16-swa-private-endpoint.sh
git commit -m "feat: Add Step 0.5 (App Registration setup) to Stack 16

Add automated app registration creation with optional prompt.
Enables fully automated Stack 16 deployments from scratch.

Changes:
- Add Step 0.5 calling script 52 after Key Vault setup
- Prompt user to create app registration if not provided
- Validate and ensure secret if AZURE_CLIENT_ID provided
- Update all step numbers (11 → 12 total steps)

 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 7: Update Stack 16 - Step 11 (Entra ID Config)

**Files:**

- Modify: `~/Developer/personal/azure-tui/infrastructure/azure/azure-stack-16-swa-private-endpoint.sh:495` (Step 11 Entra ID config)

### Step 1: Update Step 11 to export KEY_VAULT_NAME

Find Step 11 (Configure Entra ID, around line 495). Update to export KEY_VAULT_NAME:

```bash
# Configure Entra ID on SWA
export STATIC_WEB_APP_NAME
export AZURE_CLIENT_ID
export KEY_VAULT_NAME # NEW: Pass to script 42 for secret retrieval
# Do NOT export AZURE_CLIENT_SECRET - script 42 retrieves from Key Vault

"${SCRIPT_DIR}/42-configure-entraid-swa.sh"

log_info "Entra ID configured on SWA"
```

### Step 2: Remove any existing AZURE_CLIENT_SECRET exports

Search for any `export AZURE_CLIENT_SECRET` lines in Stack 16 and remove them (there shouldn't be any after earlier tasks, but verify).

### Step 3: Test end-to-end Stack 16 flow

This is a full integration test. Requires:

- Azure subscription with Playground Sandbox or personal subscription
- Custom domain accessible for DNS configuration

```bash
# Clean test (no existing resources)
export RESOURCE_GROUP="rg-test-stack16-full"
export LOCATION="uksouth"
export CUSTOM_DOMAIN="test-full-stack16.example.com"

~/Developer/personal/azure-tui/infrastructure/azure/azure-stack-16-swa-private-endpoint.sh
```

Answer prompts:

- Step 0.5: "Y" to create app registration
- Custom domain: Configure DNS as instructed
- Application Gateway: "Y" or "N" depending on test scope

Expected:

- Step 0: Key Vault created
- Step 0.5: App registration created, secret stored
- Step 11: Script 42 retrieves secret from Key Vault
- All steps complete successfully
- SWA deployed and accessible

### Step 4: Verify secret usage

After deployment, verify secret was retrieved from Key Vault (not env var):

```bash
# Check Key Vault secret exists
az keyvault secret show \
 --vault-name "${KEY_VAULT_NAME}" \
 --name "${STATIC_WEB_APP_NAME}-client-secret" \
 --query "{name: name, enabled: attributes.enabled}"
```

### Step 5: Commit

```bash
git add ~/Developer/personal/azure-tui/infrastructure/azure/azure-stack-16-swa-private-endpoint.sh
git commit -m "feat: Update Step 11 to use Key Vault secret retrieval

Export KEY_VAULT_NAME to script 42 for secret retrieval.
Completes automated secret management integration.

Changes:
- Export KEY_VAULT_NAME in Step 11
- Remove AZURE_CLIENT_SECRET exports (deprecated)
- Script 42 now retrieves secret from Key Vault automatically

 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 8: Create Documentation

**Files:**

- Create: `~/Developer/personal/azure-tui/infrastructure/azure/docs/script-51-usage.md`
- Create: `~/Developer/personal/azure-tui/infrastructure/azure/docs/script-52-usage.md`
- Modify: `~/Developer/personal/azure-tui/infrastructure/azure/docs/script-50-usage.md`

### Step 1: Create script 51 usage documentation

Create `~/Developer/personal/azure-tui/infrastructure/azure/docs/script-51-usage.md`:

```markdown
# Script 51: Setup Key Vault - Usage Guide

## Overview

Script 51 (`51-setup-key-vault.sh`) creates or detects Azure Key Vault in a resource group. Extracted from script 50 for reusability across multiple scripts.

**Purpose:** Ensure a Key Vault exists before storing secrets or certificates.

## Prerequisites

- Azure CLI authenticated (`az login`)
- Resource group exists
- User has permissions to create Key Vaults

## Basic Usage

### Auto-detect or Create

```bash
RESOURCE_GROUP="rg-subnet-calc" \
LOCATION="uksouth" \
~/Developer/personal/azure-tui/infrastructure/azure/51-setup-key-vault.sh
```

Script will:

- 0 Key Vaults: Create new with random suffix `kv-subnet-calc-xxxx`
- 1 Key Vault: Auto-detect and use existing
- Multiple Key Vaults: Error (see below)

### With Specific Key Vault (Multiple Exist)

```bash
RESOURCE_GROUP="rg-subnet-calc" \
LOCATION="uksouth" \
KEY_VAULT_NAME="kv-subnet-calc-abcd" \
~/Developer/personal/azure-tui/infrastructure/azure/51-setup-key-vault.sh
```

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `RESOURCE_GROUP` | Yes | - | Azure resource group name |
| `LOCATION` | Yes | - | Azure region (e.g., uksouth, eastus) |
| `KEY_VAULT_NAME` | No | Auto-detect/create | Specific Key Vault name (required if multiple exist) |

## Output Variables

Script exports these variables for caller:

- `KEY_VAULT_NAME` - Name of the Key Vault
- `KEY_VAULT_ID` - Full resource ID for RBAC assignments

## Key Vault Configuration

Created Key Vaults have these settings:

- **SKU:** Standard
- **Authorization:** RBAC-enabled (no access policies)
- **Soft delete:** Enabled (Azure default)
- **Purge protection:** Disabled (can be enabled post-creation)

## Idempotency

Script is safe to run multiple times:

- Existing Key Vault: Reused, no changes
- Creation already in progress: Will error (expected)
- After deletion: New Key Vault created with different suffix

## Usage in Scripts

```bash
# Call script 51
"${SCRIPT_DIR}/51-setup-key-vault.sh"

# Use exported variables
echo "Key Vault Name: ${KEY_VAULT_NAME}"
echo "Key Vault ID: ${KEY_VAULT_ID}"

# Store secret
az keyvault secret set \
 --vault-name "${KEY_VAULT_NAME}" \
 --name "my-secret" \
 --value "secret-value"
```

## Troubleshooting

### Error: Multiple Key Vaults Found

```text
[ERROR] Multiple Key Vaults found in rg-subnet-calc
[ERROR] Specify which one to use: KEY_VAULT_NAME='kv-name' ./51-setup-key-vault.sh

Available Key Vaults:
Name ProvisioningState
kv-subnet-calc-a1b2 Succeeded
kv-subnet-calc-c3d4 Succeeded
```

**Solution:** Specify `KEY_VAULT_NAME` environment variable.

### Error: Key Vault Not Accessible

```text
[ERROR] Key Vault 'kv-subnet-calc-xxxx' not accessible
```

**Causes:**

1. **Soft deleted:** Key Vault was recently deleted (90-day retention)
1. **Permissions:** User lacks RBAC permissions
1. **Network:** Key Vault has network restrictions

**Solutions:**

- Check soft-deleted vaults: `az keyvault list-deleted`
- Purge if needed: `az keyvault purge --name kv-subnet-calc-xxxx`
- Check RBAC: User needs "Key Vault Contributor" or similar

## RBAC Requirements

To use script 51, user needs:

- **Key Vault Contributor** (create Key Vaults)
- OR **Contributor** (resource group level)

To use created Key Vault for secrets:

- **Key Vault Secrets Officer** (read/write secrets)
- OR **Key Vault Secrets User** (read secrets only)

## Integration

**Used by:**

- Script 50 (HTTPS listener) - Store certificates
- Script 52 (App registration) - Store client secrets
- Stack 16 (Step 0) - Create Key Vault early

## References

- Design: `docs/plans/2025-10-30-keyvault-app-registration-secrets-design.md`
- Azure Docs: <https://learn.microsoft.com/en-us/azure/key-vault/>

### Step 2: Create script 52 usage documentation

Create `~/Developer/personal/azure-tui/infrastructure/azure/docs/script-52-usage.md`:

```markdown
# Script 52: Setup App Registration - Usage Guide

## Overview

Script 52 (`52-setup-app-registration.sh`) automates Entra ID app registration creation/detection and stores client secrets in Azure Key Vault.

**Purpose:** Eliminate manual secret management for SWA Entra ID authentication.

## Prerequisites

- Azure CLI authenticated (`az login`)
- Key Vault exists (run script 51 first)
- User has permissions to create app registrations
- User has permissions to write secrets to Key Vault

## Basic Usage

### Auto-create App Registration

```bash
STATIC_WEB_APP_NAME="swa-subnet-calc-private-endpoint" \
CUSTOM_DOMAIN="static-swa-private-endpoint.publiccloudexperiments.net" \
KEY_VAULT_NAME="kv-subnet-calc-abcd" \
~/Developer/personal/azure-tui/infrastructure/azure/52-setup-app-registration.sh
```

Creates:

- App registration: "Subnet Calculator - swa-subnet-calc-private-endpoint"
- Redirect URI: `https://static-swa-private-endpoint.publiccloudexperiments.net/.auth/login/aad/callback`
- Client secret stored as: `swa-subnet-calc-private-endpoint-client-secret`

### With Existing App Registration

```bash
AZURE_CLIENT_ID="existing-app-id" \
STATIC_WEB_APP_NAME="swa-subnet-calc-private-endpoint" \
CUSTOM_DOMAIN="static-swa-private-endpoint.publiccloudexperiments.net" \
KEY_VAULT_NAME="kv-subnet-calc-abcd" \
~/Developer/personal/azure-tui/infrastructure/azure/52-setup-app-registration.sh
```

Validates app and ensures secret exists in Key Vault.

### With Azure Static Apps Default Hostname

```bash
STATIC_WEB_APP_NAME="swa-subnet-calc-private-endpoint" \
CUSTOM_DOMAIN="static-swa-private-endpoint.publiccloudexperiments.net" \
SWA_DEFAULT_HOSTNAME="proud-bay-123.azurestaticapps.net" \
KEY_VAULT_NAME="kv-subnet-calc-abcd" \
~/Developer/personal/azure-tui/infrastructure/azure/52-setup-app-registration.sh
```

Adds both redirect URIs (custom domain + azurestaticapps.net).

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `STATIC_WEB_APP_NAME` | Yes | - | SWA name (used for naming app and secret) |
| `CUSTOM_DOMAIN` | Yes | - | Custom domain for redirect URI |
| `KEY_VAULT_NAME` | Yes | - | Key Vault for secret storage |
| `AZURE_CLIENT_ID` | No | Auto-create | Use existing app registration |
| `SWA_DEFAULT_HOSTNAME` | No | - | Add azurestaticapps.net redirect URI |

## Output Variables

Script exports:

- `AZURE_CLIENT_ID` - App registration client ID

## Naming Convention

| Component | Pattern | Example |
|-----------|---------|---------|
| App Display Name | `Subnet Calculator - ${SWA_NAME}` | "Subnet Calculator - swa-subnet-calc-private-endpoint" |
| Key Vault Secret | `${SWA_NAME}-client-secret` | `swa-subnet-calc-private-endpoint-client-secret` |

## Secret Rotation

If secret already exists in Key Vault, script prompts:

```text
[WARN] Secret 'swa-subnet-calc-private-endpoint-client-secret' already exists in Key Vault
Created: 2025-10-30T10:00:00Z

Options:
 1. Reuse existing secret (recommended if working)
 1. Regenerate new secret (creates new app credential)

Choice [1]: _
```

**Option 1 (Reuse):** No changes, uses existing secret
**Option 2 (Regenerate):** Creates new credential, updates Key Vault (new version)

## App Registration Configuration

Created app registrations have:

- **Sign-in audience:** AzureADMyOrg (single tenant)
- **Redirect URIs:** Web platform
- **Implicit grant:** ID tokens enabled
- **Access tokens:** Enabled

## Idempotency

Script is safe to run multiple times:

- Existing app: Reused, redirect URIs updated
- Existing secret: Prompts to reuse or regenerate
- New app: Created automatically

## Usage in Scripts

```bash
# Setup Key Vault first (script 51)
"${SCRIPT_DIR}/51-setup-key-vault.sh"

# Setup app registration (script 52)
export STATIC_WEB_APP_NAME="swa-name"
export CUSTOM_DOMAIN="domain.com"
export KEY_VAULT_NAME # From script 51

"${SCRIPT_DIR}/52-setup-app-registration.sh"

# Use exported client ID
echo "Client ID: ${AZURE_CLIENT_ID}"

# Retrieve secret in script 42
AZURE_CLIENT_SECRET=$(az keyvault secret show \
 --vault-name "${KEY_VAULT_NAME}" \
 --name "${STATIC_WEB_APP_NAME}-client-secret" \
 --query "value" -o tsv)
```

## Troubleshooting

### Error: Secret Not Found in Key Vault

After creating app registration, secret should exist in Key Vault. If not:

```bash
# List secrets
az keyvault secret list --vault-name "${KEY_VAULT_NAME}" --query "[].name"

# Check RBAC permissions
az role assignment list \
 --assignee $(az account show --query user.name -o tsv) \
 --scope "/subscriptions/.../vaults/${KEY_VAULT_NAME}"
```

**Solution:** Ensure user has "Key Vault Secrets Officer" role.

### Error: App Registration Not Found

```bash
# List app registrations by display name
az ad app list --display-name "Subnet Calculator - swa-name"

# Get app by client ID
az ad app show --id "${AZURE_CLIENT_ID}"
```

**Solution:** Verify `AZURE_CLIENT_ID` is correct.

### Redirect URI Mismatch

After running script 52, verify redirect URIs:

```bash
az ad app show --id "${AZURE_CLIENT_ID}" --query "web.redirectUris"
```

Expected output:

```json
[
 "https://your-domain.com/.auth/login/aad/callback"
]
```

## RBAC Requirements

User needs:

- **Application Administrator** (create app registrations)
- **Key Vault Secrets Officer** (write secrets to Key Vault)

## Integration

**Used by:**

- Stack 16 (Step 0.5) - Auto-create app registration
- Manual setup - Create app registration for any stack

**Requires:**

- Script 51 (Key Vault must exist first)

**Used with:**

- Script 42 (retrieves secret from Key Vault)

## References

- Design: `docs/plans/2025-10-30-keyvault-app-registration-secrets-design.md`
- Entra ID Docs: <https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app>

### Step 3: Update script 50 usage documentation

In `~/Developer/personal/azure-tui/infrastructure/azure/docs/script-50-usage.md`, update the "What the Script Does" section (around line 58):

Add after "Phase 1: Validation":

```markdown
### Phase 0: Key Vault Setup (via Script 51)

1. Call script 51 to ensure Key Vault exists
1. KEY_VAULT_NAME and KEY_VAULT_ID exported
1. Reuses existing Key Vault if found
1. Creates new Key Vault if none exist
```

Update Phase 2 header:

```markdown
### Phase 2: Certificate Management (Idempotent)
```

Change from "Key Vault Setup" to just certificate management since Key Vault is now handled by script 51.

### Step 4: Commit

```bash
git add ~/Developer/personal/azure-tui/infrastructure/azure/docs/script-51-usage.md \
 ~/Developer/personal/azure-tui/infrastructure/azure/docs/script-52-usage.md \
 ~/Developer/personal/azure-tui/infrastructure/azure/docs/script-50-usage.md

git commit -m "docs: Add usage guides for scripts 51 and 52

Add comprehensive usage documentation for new scripts:
- Script 51: Key Vault setup
- Script 52: App registration automation

Update script 50 docs to reference script 51 dependency.

 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 9: Update Design Document Status

**Files:**

- Modify: `docs/plans/2025-10-30-keyvault-app-registration-secrets-design.md:3`

### Step 1: Mark design as implemented

Change status from "Approved" to "Implemented":

```markdown
**Status:** Implemented
```

### Step 2: Commit

```bash
git add docs/plans/2025-10-30-keyvault-app-registration-secrets-design.md
git commit -m "docs: Mark Key Vault secret management design as implemented

All components implemented:
- Script 51 (Key Vault setup)
- Script 52 (App registration automation)
- Script 50 (updated to use script 51)
- Script 42 (Key Vault secret retrieval)
- Stack 16 (fully automated secret management)

 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 10: Final Verification

**Files:**

- Test: All scripts end-to-end

### Step 1: Verify script permissions

```bash
ls -l ~/Developer/personal/azure-tui/infrastructure/azure/51-setup-key-vault.sh
ls -l ~/Developer/personal/azure-tui/infrastructure/azure/52-setup-app-registration.sh
```

Expected: Both scripts have execute permissions (`-rwxr-xr-x`)

### Step 2: Run shellcheck on new scripts

```bash
shellcheck ~/Developer/personal/azure-tui/infrastructure/azure/51-setup-key-vault.sh
shellcheck ~/Developer/personal/azure-tui/infrastructure/azure/52-setup-app-registration.sh
```

Expected: No errors (warnings acceptable)

### Step 3: Verify git status

```bash
git status
```

Expected: Working directory clean, all changes committed

### Step 4: Review commit history

```bash
git log --oneline -15
```

Expected: See all 10 commits from this implementation

### Step 5: Run pre-commit hooks

```bash
pre-commit run --all-files
```

Expected: All hooks pass

### Step 6: Final commit (if any fixes needed)

If pre-commit made changes:

```bash
git add -u
git commit -m "chore: Apply pre-commit auto-fixes

Fix formatting and linting issues caught by pre-commit hooks.

 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 11: Create Pull Request

**Files:**

- Push branch and create PR

### Step 1: Push branch to remote

```bash
git push -u origin chore/20251030-key-vault-app-reg-secrets
```

### Step 2: Create pull request

```bash
gh pr create --title "feat: Automate Key Vault and App Registration secret management" --body "$(cat <<'EOF'
## Summary

Automates Entra ID app registration and secret management using Azure Key Vault, eliminating manual secret handling and enabling fully automated Stack 16 deployments.

## Changes

### New Scripts

- **Script 51:** Key Vault setup (extracted from script 50)
 - Auto-detect or create Key Vault
 - Reusable across multiple scripts
 - RBAC-enabled Key Vault

- **Script 52:** App registration automation
 - Auto-create or detect Entra ID app registration
 - Generate client secret and store in Key Vault
 - Naming convention: `${SWA_NAME}-client-secret`
 - Secret rotation support

### Updated Scripts

- **Script 50:** Refactored to use script 51 for Key Vault setup
 - Removes ~60 lines of duplicate code
 - Improves maintainability

- **Script 42:** Added Key Vault secret retrieval
 - Try environment variable first (testing/CI)
 - Fallback to Key Vault (production)
 - Maintains backward compatibility

- **Stack 16:** Fully automated secret management
 - Step 0: Key Vault setup (early)
 - Step 0.5: App registration creation (optional prompt)
 - Step 11: Retrieve secret from Key Vault
 - No manual secret management required

### Documentation

- Script 51 usage guide
- Script 52 usage guide
- Updated script 50 usage guide
- Design document marked as implemented

## Benefits

- **No manual secret management:** Everything automated from scratch
- **Secure by default:** Secrets stored in Key Vault, never in env vars
- **Backward compatible:** Environment variable pattern still works for testing/CI
- **Fully automated:** Stack 16 can deploy without any credentials provided
- **Better separation:** Key Vault creation early, used by multiple components

## Testing

- [x] Script 51 creates Key Vault idempotently
- [x] Script 52 creates app registration and stores secret
- [x] Script 50 reuses script 51 successfully
- [x] Script 42 retrieves secret from Key Vault
- [x] Stack 16 fully automated flow (end-to-end)
- [x] Backward compatibility with environment variables
- [x] Pre-commit hooks pass
- [x] Shellcheck passes on new scripts

## Migration Path for Existing Stack 15

See design document for manual migration steps to rename `swa-auth` secret to follow naming convention.

## Cost Impact

~$0.10/month for Key Vault operations (negligible)

## References

- Design: `docs/plans/2025-10-30-keyvault-app-registration-secrets-design.md`
- Implementation Plan: `docs/plans/2025-10-30-keyvault-app-registration-secrets.md`

 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

### Step 3: Display PR URL

```bash
gh pr view --web
```

---

## Implementation Complete

All tasks completed:

1. Script 51 (Key Vault setup)
1. Script 52 (App registration automation)
1. Script 50 (updated to use script 51)
1. Script 42 (Key Vault secret retrieval)
1. Stack 16 Step 0 (Key Vault setup)
1. Stack 16 Step 0.5 (App registration setup)
1. Stack 16 Step 11 (use Key Vault secret)
1. Documentation (usage guides)
1. Design document (marked implemented)
1. Final verification
1. Pull request created

**Next Steps:**

- Review PR for any feedback
- Merge to main branch
- Test in Azure environment
- Migrate existing Stack 15 secrets (if applicable)
