# Entra ID Setup Guide for Azure Static Web App

This guide covers the complete setup of Entra ID authentication on Azure Static Web App with a focus on production security best practices.

## Overview

The subnet-calculator uses **Azure Static Web App (SWA) platform-level authentication** with Microsoft Entra ID. This means:

- Authentication is handled by SWA at the edge (before requests reach your app)
- No custom authentication code in your frontend or backend
- User information injected via headers (`x-ms-client-principal`)
- Secure OAuth2 code flow (Authorization Code Flow with PKCE)

## Architecture

```text
User Browser
 ↓
Static Web App (Edge)
 ├─ Route Protection (enforced at edge)
 ├─ Entra ID Redirect (for unauthenticated)
 ├─ Token Validation
 └─ Header Injection
 ↓
Protected Frontend
 ├─ User info available via /.auth/me
 └─ API calls via /api proxy
 ↓
Backend API
 ├─ Receives x-ms-client-principal header
 ├─ Knows user is authenticated (no validation needed)
 └─ Can read user claims if needed
```

## Prerequisites

Before starting, you need:

1. **Azure Subscription** with permissions to:

- Create Entra ID app registrations
- Configure Azure Static Web App
- Set environment variables

1. **Azure CLI** installed and logged in:

 ```bash
 az login
 ```

1. **Static Web App** already created:

 ```bash
 az staticwebapp show --name <your-swa-name> --resource-group <your-rg>
 ```

## Step 1: Get Your Static Web App URL

First, find your SWA's public URL (needed for redirect URI configuration):

```bash
SWA_NAME="swatest" # Your SWA name
RESOURCE_GROUP="your-resource-group"

SWA_URL=$(az staticwebapp show \
 --name "$SWA_NAME" \
 --resource-group "$RESOURCE_GROUP" \
 --query defaultHostname -o tsv)

echo "Your SWA URL: https://${SWA_URL}"
```

Example output:

```text
Your SWA URL: https://swatest-xyz123.azurestaticapps.net
```

## Step 2: Create Entra ID App Registration

### Via Azure Portal (Recommended for First Time)

1. Go to **Azure Portal** → **Entra ID** → **App registrations**
1. Click **New registration**
1. Fill in:

- **Name**: `subnet-calc-entraid` (or your preferred name)
- **Supported account types**: **Accounts in this organizational directory only (Single tenant)**
- Click **Register**

### Via Azure CLI

```bash
APP_NAME="subnet-calc-entraid"

az ad app create --display-name "$APP_NAME"
```

This returns:

```json
{
 "appId": "370b8618-a252-442e-9941-c47a9f7da89e",
 ...
}
```

**Save the `appId`** - this is your `AZURE_CLIENT_ID`.

## Step 3: Add Redirect URI

The redirect URI tells Entra ID where to send users after they authenticate.

### Via Azure Portal

1. In the app registration, go to **Authentication** blade
1. Click **Add a Redirect URI**
1. Add this exact URI:

 ```text
 https://<your-swa-url>/.auth/login/aad/callback
 ```

 Example:

 ```text
 https://swatest-xyz123.azurestaticapps.net/.auth/login/aad/callback
 ```

1. Click **Save**

### Via Azure CLI

```bash
SWA_URL="swatest-xyz123.azurestaticapps.net"
APP_ID="370b8618-a252-442e-9941-c47a9f7da89e"

az ad app update --id "$APP_ID" \
 --web-redirect-uris "https://${SWA_URL}/.auth/login/aad/callback"
```

## Step 4: Create Client Secret

The client secret is used by SWA to authenticate with Entra ID (backend to backend).

### Via Azure Portal

1. In the app registration, go to **Certificates & secrets** blade
1. Click **New client secret**
1. Fill in:

- **Description**: `SWA Backend` (or your preference)
- **Expires**: 24 months (or your security policy)

1. Click **Add**
1. **Immediately copy the Value** (this is your `AZURE_CLIENT_SECRET`)

- You can only see it once! If you lose it, delete and create a new one

### Via Azure CLI

```bash
APP_ID="370b8618-a252-442e-9941-c47a9f7da89e"

az ad app credential create --id "$APP_ID" \
 --display-name "SWA Backend" \
 --years 2
```

This returns:

```json
{
 "hint": "xxx",
 "keyId": "xxxxxx",
 "secretText": "your-secret-here"
}
```

**Save `secretText`** - this is your `AZURE_CLIENT_SECRET`.

## Step 5: Verify Tenant ID

Get your Entra ID tenant ID (needed for secure tenant-specific configuration):

```bash
TENANT_ID=$(az account show --query tenantId -o tsv)
echo "Your Tenant ID: $TENANT_ID"
```

## Step 6: Configure Static Web App with Entra ID

Run the configuration script to set up SWA with Entra ID:

```bash
export RESOURCE_GROUP="your-resource-group"
export STATIC_WEB_APP_NAME="swatest"
export AZURE_CLIENT_ID="370b8618-a252-442e-9941-c47a9f7da89e"
export AZURE_CLIENT_SECRET="your-secret-here"
export AZURE_TENANT_ID="your-tenant-id"

# Run Phase 1: Configure Entra ID
~/Developer/personal/azure-tui/infrastructure/azure/42-configure-entraid-swa.sh
```

This script will:

- Auto-detect your SWA and resource group
- Set Entra ID credentials in SWA app settings
- Display your tenant ID
- Provide Phase 2 instructions

## Step 7: Deploy Frontend with Entra ID

Deploy the frontend with Entra ID authentication enabled:

```bash
export VITE_AUTH_ENABLED=true
export AZURE_TENANT_ID="your-tenant-id" # Optional if in Azure CLI context

# Run Phase 2: Deploy frontend
~/Developer/personal/azure-tui/infrastructure/azure/20-deploy-frontend.sh
```

This script will:

- Build the TypeScript frontend with auth enabled
- Substitute your tenant ID in the config
- Deploy to Static Web App using SWA CLI

## Step 8: Test Authentication

1. **Open your SWA URL** in a browser:

 ```text
 https://swatest-xyz123.azurestaticapps.net
 ```

1. **You should be redirected to Entra ID login** with:

- Your organization's Entra ID login page
- Tenant-specific endpoint (not `/common/`)

1. **Sign in with your Entra ID account**:

 ```text
 swatest@akscicdpipelines.onmicrosoft.com
 ```

1. **You should see the app** with your user information displayed

1. **Test API calls**:

- App should make calls to `/api/v1/health` through SWA proxy
- Backend receives authenticated request via headers

## Configuration Details

### OAuth2 Flow: Authorization Code Flow (Secure)

The configuration uses **Authorization Code Flow** which is the most secure for SPAs:

```json
{
 "auth": {
 "identityProviders": {
 "azureActiveDirectory": {
 "registration": {
 "openIdIssuer": "https://login.microsoftonline.com/AZURE_TENANT_ID/v2.0",
 "clientIdSettingName": "AZURE_CLIENT_ID",
 "clientSecretSettingName": "AZURE_CLIENT_SECRET"
 },
 "login": {
 "loginParameters": [
 "response_type=code",
 "scope=openid profile email"
 ]
 }
 }
 }
 }
}
```

**Key Security Features:**

- Uses **tenant-specific endpoint** (`/AZURE_TENANT_ID/v2.0`, not `/common/`)
- Prevents cross-tenant attacks
- Explicit single-tenant configuration
- Better for compliance

- Uses **Authorization Code Flow** (`response_type=code`)
- Authorization code never exposed to browser
- Tokens obtained server-to-server
- PKCE automatically enabled for SPAs

- **Tokens never in browser URL**
- Not vulnerable to URL history exposure
- Not logged in server access logs
- Safer for copy/paste operations

### Protected Routes

All routes are protected in `staticwebapp-entraid.config.json`:

```json
{
 "routes": [
 {
 "route": "/api/*",
 "allowedRoles": ["authenticated"]
 },
 {
 "route": "/*",
 "allowedRoles": ["authenticated"]
 }
 ],
 "responseOverrides": {
 "401": {
 "statusCode": 302,
 "redirect": "/.auth/login/aad"
 }
 }
}
```

**This means:**

- Unauthenticated users cannot access `/api/*` or `/` routes
- 401 responses automatically redirect to `/.auth/login/aad`
- All routes enforced at SWA edge (before your app receives the request)

## Troubleshooting

### Error: AADSTS500113 - No reply address is registered

**Cause**: Redirect URI not configured in app registration

**Fix**:

1. Go to **Azure Portal** → **Entra ID** → **App registrations** → `subnet-calc-entraid`
1. Go to **Authentication** blade
1. Add redirect URI: `https://<your-swa-url>/.auth/login/aad/callback`
1. Click **Save**
1. Wait 2-3 minutes for changes to propagate
1. Try login again (this is the step you need to do manually in Azure Portal)

### Error: AADSTS50194 - Application not configured as multi-tenant

**Cause**: Using `/common/` endpoint with single-tenant app

**Fix**: Ensure configuration uses tenant-specific endpoint:

```json
"openIdIssuer": "https://login.microsoftonline.com/AZURE_TENANT_ID/v2.0"
```

(This is automatic if you use the deployment scripts)

### Error: AADSTS700054 - response_type 'id_token' is not enabled

**Cause**: Trying to use hybrid flow (`code id_token`) with single-tenant app

**Fix**: Use code flow only (this is the default):

```json
"response_type=code"
```

### Error: No user information displayed

**Cause**: Frontend not configured with `VITE_AUTH_ENABLED=true`

**Fix**:

```bash
VITE_AUTH_ENABLED=true ~/Developer/personal/azure-tui/infrastructure/azure/20-deploy-frontend.sh
```

### Error: API calls return 401

**Cause**: Backend not receiving authentication headers from SWA

**Fix**:

1. Verify SWA proxy is configured correctly (relative URLs, no API_URL)
1. Check SWA has Entra ID configured:

 ```bash
 az staticwebapp appsettings list --name $SWA_NAME --resource-group $RG
 ```

1. Verify redirect URI matches your SWA URL exactly

## Environment Variables

Save these in `.env.example` for consistency:

```bash
# Static Web App
RESOURCE_GROUP=rg-subnet-calc
STATIC_WEB_APP_NAME=swatest

# Entra ID Configuration
AZURE_CLIENT_ID=370b8618-a252-442e-9941-c47a9f7da89e
AZURE_CLIENT_SECRET=your-secret-here
AZURE_TENANT_ID=your-tenant-id

# Frontend Authentication
VITE_AUTH_ENABLED=true
VITE_API_URL= # Leave empty - SWA proxy pattern
```

## Security Best Practices

1. **Use Tenant-Specific Endpoints**

- Always use `https://login.microsoftonline.com/TENANT_ID/v2.0`
- Never use `/common/` for single-tenant apps

1. **Use Authorization Code Flow**

- Always use `response_type=code`
- Never use hybrid flow (`code id_token`) unnecessarily

1. **Protect Secrets**

- Store `AZURE_CLIENT_SECRET` in Azure Key Vault in production
- Never commit secrets to git
- Rotate secrets regularly (e.g., every 24 months)

1. **Monitor Access**

- Check Azure logs for failed authentication attempts
- Review authorized users periodically
- Set up alerts for suspicious activity

1. **Test with Multiple Users**

- Test with different Entra ID user accounts
- Verify role-based access control (if using roles)
- Test token expiration and refresh

## Next Steps

- **Add Custom Domain**: Configure custom domain and update redirect URI
- **Add Role-Based Access**: Set up Entra ID app roles for fine-grained control
- **Backend Integration**: Add code to read user claims from headers
- **Monitoring**: Set up Application Insights to monitor authentication flow
- **Multi-Tenant**: If needed, configure app for multiple tenants

## Related Files

- Configuration: `~/Developer/personal/azure-tui/infrastructure/azure/staticwebapp-entraid.config.json`
- Setup Script: `~/Developer/personal/azure-tui/infrastructure/azure/42-configure-entraid-swa.sh`
- Deploy Script: `~/Developer/personal/azure-tui/infrastructure/azure/20-deploy-frontend.sh`
- Environment Template: `~/Developer/personal/azure-tui/infrastructure/azure/.env.example`
- Frontend Config: `frontend-typescript-vite/src/config.ts`

## References

- [Azure Static Web App Authentication](https://docs.microsoft.com/azure/static-web-apps/authentication-authorization)
- [Microsoft Entra ID Best Practices](https://docs.microsoft.com/azure/active-directory/fundamentals/active-directory-deployment-plans)
- [OAuth 2.0 Authorization Code Flow](https://tools.ietf.org/html/rfc6749#section-1.3.1)
- [PKCE (RFC 7636)](https://tools.ietf.org/html/rfc7636)
