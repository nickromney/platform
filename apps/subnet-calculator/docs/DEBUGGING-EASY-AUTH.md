# Debugging Azure Easy Auth and Managed Identity

This document contains debugging techniques discovered while troubleshooting authentication issues between a Web App (with Easy Auth) and a Function App (with Easy Auth), using Managed Identity for service-to-service authentication.

## Problem Statement

Web App users authenticate with Azure AD via Easy Auth, then the Web App's server-side proxy needs to call a Function App API on behalf of the user. The Function App also has Easy Auth enabled.

**Challenge**: The user's token is issued for the Web App's audience, but the Function App expects tokens for its own audience. This causes 401 errors.

**Solution**: Use the Web App's User-Assigned Managed Identity to acquire a token for the Function App's audience.

## Debugging Steps

### 1. Verify User Authentication Status

Check if the user is properly authenticated at the Web App level:

```bash
# From browser dev tools, check for cookies
# Look for: AppServiceAuthSession cookie
# Presence indicates Easy Auth authentication succeeded
```

### 2. Check Entra ID App Registrations

There should be two separate app registrations for this pattern:

```bash
# List all apps with similar names
az ad app list --display-name "Subnet Calculator React EasyAuth" \
  --query "[].{displayName:displayName, appId:appId, identifierUris:identifierUris}" \
  -o json

# Expected: Two apps
# 1. Frontend app - for user sign-in
# 2. API app - for the Function App
```

**Key insight**: Multiple apps can have the same display name. Use `appId` to distinguish them.

### 3. Verify Web App Managed Identity

Check if the Web App has a User-Assigned Managed Identity:

```bash
WEBAPP_NAME="web-subnet-calc-react-easyauth-proxied"
RESOURCE_GROUP="rg-subnet-calc"

# Get managed identity details
az webapp identity show \
  --name $WEBAPP_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "{type:type, userAssignedIdentities:userAssignedIdentities}" \
  -o json

# Note the clientId - this is used by DefaultAzureCredential
```

### 4. Verify App Role Assignment

The Web App's UAMI needs an app role assignment to access the Function App:

```bash
# First, get the API app's service principal and app roles
API_APP_ID="ee7f985b-f622-425e-9cc5-9fab601ef886"  # Replace with your API app ID

az ad sp show --id $API_APP_ID \
  --query "{displayName:displayName, appId:appId, appRoles:appRoles[].{value:value, id:id}}" \
  -o json

# Then check if the UAMI has the app role assignment
az ad sp show --id $API_APP_ID --query "id" -o tsv | \
  xargs -I {} az rest --method GET \
    --uri "https://graph.microsoft.com/v1.0/servicePrincipals/{}/appRoleAssignedTo" \
    --query "value[].{principalDisplayName:principalDisplayName, principalId:principalId, appRoleId:appRoleId}" \
    -o json

# Look for your Web App's UAMI in the results
```

### 5. Check Function App Easy Auth Configuration

Verify the Function App is configured correctly:

```bash
FUNCTION_APP_NAME="func-subnet-calc-react-easyauth-proxied-api"

# Get auth configuration (v1 settings)
az webapp auth show \
  --name $FUNCTION_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  -o json | head -80

# Key fields to check:
# - clientId: Should match the API app registration
# - allowedAudiences: Should include the identifier URI and frontend app ID
# - enabled: Should be true
# - unauthenticatedClientAction: Usually "RedirectToLoginPage" or "Return401"
```

### 6. Verify Web App Configuration

Check the Web App's app settings for Managed Identity configuration:

```bash
# Get relevant app settings
az webapp config appsettings list \
  --name $WEBAPP_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "[?name=='PROXY_FORWARD_EASYAUTH_HEADERS' || name=='PROXY_API_URL' || name=='API_PROXY_ENABLED' || name=='AZURE_CLIENT_ID' || name=='EASYAUTH_RESOURCE_ID'].{name:name, value:value}" \
  -o table

# Expected values:
# API_PROXY_ENABLED: true
# PROXY_FORWARD_EASYAUTH_HEADERS: false (use MI, not user headers)
# PROXY_API_URL: https://your-function-app.azurewebsites.net
# AZURE_CLIENT_ID: <your UAMI client ID>
# EASYAUTH_RESOURCE_ID: api://your-api-identifier/.default
```

**Critical**: `EASYAUTH_RESOURCE_ID` must end with `/.default` for app role authentication.

### 7. Check Application Logs

Enable application logging to see console.log output:

```bash
# Enable filesystem logging at Information level
az webapp log config \
  --name $WEBAPP_NAME \
  --resource-group $RESOURCE_GROUP \
  --application-logging filesystem \
  --level information

# Stream logs in real-time
az webapp log tail \
  --name $WEBAPP_NAME \
  --resource-group $RESOURCE_GROUP

# Or filter for specific keywords
az webapp log tail \
  --name $WEBAPP_NAME \
  --resource-group $RESOURCE_GROUP 2>&1 | \
  grep -i "token\|error\|managed\|identity"
```

### 8. Check Log Configuration

Verify logging is enabled:

```bash
az webapp log show \
  --name $WEBAPP_NAME \
  --resource-group $RESOURCE_GROUP \
  -o json
```

### 9. Test API Endpoint Directly

Test if the Function App is responding:

```bash
# This will return 401 without auth (expected)
curl -I https://func-subnet-calc-react-easyauth-proxied-api.azurewebsites.net/api/v1/health

# Check headers:
# WWW-Authenticate: Bearer realm="..." - indicates Easy Auth is active
# x-ms-middleware-request-id: Should be a valid GUID (not all zeros)
```

### 10. Restart Web App

After configuration changes, restart to ensure they're picked up:

```bash
az webapp restart \
  --name $WEBAPP_NAME \
  --resource-group $RESOURCE_GROUP

# Wait 30-60 seconds for restart to complete
sleep 30
```

## Common Issues and Solutions

### Issue 1: Async/Await Not Working in onProxyReq

**Symptom**: Managed Identity token never gets added to requests, even though code looks correct.

**Root Cause**: The `onProxyReq` callback in http-proxy-middleware v3 doesn't support async/await.

**Solution**: Move async token acquisition to Express middleware that runs before the proxy:

```javascript
// WRONG - onProxyReq doesn't await async functions
app.use('/api', createProxyMiddleware({
  onProxyReq: async (proxyReq, req) => {
    const token = await getManagedIdentityToken();  // Won't wait!
    proxyReq.setHeader('Authorization', `Bearer ${token}`);
  }
}));

// RIGHT - Use Express middleware before proxy
app.use('/api', async (req, res, next) => {
  const token = await getManagedIdentityToken();
  req.headers.authorization = `Bearer ${token}`;
  next();
});

app.use('/api', createProxyMiddleware({
  // proxy config
}));
```

### Issue 2: Token Audience Mismatch

**Symptom**: 401 Unauthorized when calling Function App, even with valid user token.

**Root Cause**: User's token is issued for Web App audience, but Function App expects its own audience.

**Solution**: Use Managed Identity to get a token for the Function App's audience:

```javascript
import { DefaultAzureCredential } from '@azure/identity';

const credential = new DefaultAzureCredential();
const scope = process.env.EASYAUTH_RESOURCE_ID || 'api://your-api/.default';

const tokenResponse = await credential.getToken(scope);
const token = tokenResponse.token;
```

### Issue 3: Wrong API App Referenced

**Symptom**: Configuration looks correct but still getting authentication errors.

**Root Cause**: Frontend app registration requesting permission to wrong API app (e.g., e2e API instead of proxied API).

**Solution**: Verify all app IDs in terraform configuration match the intended apps:

```bash
# List all apps to find the correct ones
az ad app list --display-name "Your App Name" \
  --query "[].{displayName:displayName, appId:appId, identifierUris:identifierUris}"

# Update terraform with correct app IDs
```

### Issue 4: Missing .default Suffix

**Symptom**: Managed Identity token acquisition fails or token is rejected.

**Root Cause**: App role authentication requires `/.default` scope suffix.

**Solution**: Always use `/.default` suffix for app role authentication:

```javascript
// WRONG
const scope = 'api://your-api-identifier';

// RIGHT
const scope = 'api://your-api-identifier/.default';
```

### Issue 5: Python 3.14 Build Failures

**Symptom**: Function App deployment fails with PyO3 errors about Python 3.14.

**Root Cause**: Local environment using Python 3.14, but pydantic-core doesn't support it yet.

**Solution**: Skip local pip install and let Azure do remote build:

```bash
# In build-function-zip.sh
echo "Skipping local dependency installation (Azure will build remotely)..."
# Don't run: pip install -r requirements.txt

# Pin Python version
cd api-fastapi-azure-function
uv python pin 3.13  # or 3.11
```

## Diagnostic Script

See `debug-easyauth.sh` for an automated diagnostic script that runs all these checks.

## Azure CLI Commands Quick Reference

```bash
# Identity
az webapp identity show --name <app> --resource-group <rg>

# App Settings
az webapp config appsettings list --name <app> --resource-group <rg>

# Logging
az webapp log config --name <app> --resource-group <rg> --application-logging filesystem --level information
az webapp log tail --name <app> --resource-group <rg>
az webapp log show --name <app> --resource-group <rg>

# Auth Configuration
az webapp auth show --name <app> --resource-group <rg>

# Entra ID Apps
az ad app list --display-name "App Name"
az ad sp show --id <app-id>

# App Role Assignments (via Microsoft Graph)
az rest --method GET --uri "https://graph.microsoft.com/v1.0/servicePrincipals/<sp-object-id>/appRoleAssignedTo"

# Restart
az webapp restart --name <app> --resource-group <rg>
```

## Key Learnings

1. **Multiple apps can share display names** - Always use `appId` to distinguish
2. **onProxyReq doesn't support async** - Use Express middleware instead
3. **App role auth requires `.default`** - Don't forget the suffix
4. **UAMI needs both assignment and config** - Must have app role AND `AZURE_CLIENT_ID` set
5. **Logging is essential** - Enable early and watch for startup errors
6. **Test incrementally** - Verify each component (UAMI, app role, token acquisition) separately

## References

- [Azure App Service Authentication](https://learn.microsoft.com/en-us/azure/app-service/overview-authentication-authorization)
- [Azure Managed Identities](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/overview)
- [Azure Identity SDK for JavaScript](https://learn.microsoft.com/en-us/javascript/api/overview/azure/identity-readme)
- [http-proxy-middleware](https://github.com/chimurai/http-proxy-middleware)
