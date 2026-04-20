# Easy Auth Setup Guide for Azure Web App

This guide explains how to enable Azure Easy Auth (platform-level authentication) for the Flask frontend when deployed to Azure Web App or Azure Container Apps.

## Prerequisites

1. **Azure App Registration** (if you don't have one, create it first)
2. **Azure Web App** or **Azure Container Apps** deployed
3. **Flask application** deployed to Azure

## Quick Start

The Flask app automatically detects whether it's running in Azure and switches between:

- **Easy Auth** (Azure platform) - no code changes needed
- **MSAL library** (local development) - uses auth.py

Detection is based on the `WEBSITE_HOSTNAME` environment variable (automatically set by Azure).

## Step 1: Create App Registration (if needed)

If you don't already have an app registration:

```bash
# Login to Azure
az login

# Create app registration
az ad app create \
  --display-name "Subnet Calculator Flask Frontend" \
  --sign-in-audience AzureADMyOrg

# Get the client ID
CLIENT_ID=$(az ad app list --display-name "Subnet Calculator Flask Frontend" --query "[0].appId" -o tsv)

# Create client secret
az ad app credential reset --id $CLIENT_ID --append --query password -o tsv
```

**Save the client secret** - you cannot retrieve it later!

## Step 2: Configure App Registration

### Set Redirect URI

Add the Azure Web App redirect URI to your app registration:

```bash
# Get your Web App hostname
WEB_APP_NAME="your-web-app-name"
HOSTNAME=$(az webapp show --name $WEB_APP_NAME --resource-group your-rg --query defaultHostName -o tsv)

# Add redirect URI
az ad app update --id $CLIENT_ID \
  --web-redirect-uris "https://$HOSTNAME/.auth/login/aad/callback"
```

Or via Azure Portal:

1. Azure Portal → App registrations → Your app
2. Authentication → Add a platform → Web
3. Redirect URI: `https://your-app.azurewebsites.net/.auth/login/aad/callback`

## Step 3: Enable Easy Auth on Azure Web App

### Option A: Azure Portal (Recommended for first-time setup)

1. Navigate to your Web App in Azure Portal
2. Settings → **Authentication**
3. Click **Add identity provider**
4. Select **Microsoft**
5. Configure:
   - **App registration type**: Provide the details of an existing app registration
   - **Application (client) ID**: Paste your client ID
   - **Client secret**: Click "Add a client secret" → Paste your secret
   - **Issuer URL**: `https://login.microsoftonline.com/{tenant-id}/v2.0`
     - Replace `{tenant-id}` with your Azure AD tenant ID
     - Or use `common` for multi-tenant: `https://login.microsoftonline.com/common/v2.0`
   - **Allowed token audiences**: (Leave empty or add `api://{client-id}`)

6. **Restrict access**:
   - Choose "Require authentication"
   - Unauthenticated requests: "HTTP 302 Found redirect: recommended for websites"

7. Click **Add**

### Option B: Azure CLI

```bash
WEB_APP_NAME="your-web-app-name"
RESOURCE_GROUP="your-resource-group"
CLIENT_ID="your-client-id"
CLIENT_SECRET="your-client-secret"
TENANT_ID="your-tenant-id"

# Enable Easy Auth
az webapp auth update \
  --name $WEB_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --enabled true \
  --action LoginWithAzureActiveDirectory \
  --aad-client-id $CLIENT_ID \
  --aad-client-secret $CLIENT_SECRET \
  --aad-token-issuer-url "https://login.microsoftonline.com/$TENANT_ID/v2.0"
```

### Option C: Bicep/Terraform

**Bicep**:

```bicep
resource webApp 'Microsoft.Web/sites@2022-03-01' existing = {
  name: webAppName
}

resource authSettings 'Microsoft.Web/sites/config@2022-03-01' = {
  name: 'authsettingsV2'
  parent: webApp
  properties: {
    globalValidation: {
      requireAuthentication: true
      unauthenticatedClientAction: 'RedirectToLoginPage'
      redirectToProvider: 'azureActiveDirectory'
    }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        registration: {
          openIdIssuer: 'https://login.microsoftonline.com/${tenantId}/v2.0'
          clientId: clientId
          clientSecretSettingName: 'MICROSOFT_PROVIDER_AUTHENTICATION_SECRET'
        }
        validation: {
          allowedAudiences: []
        }
      }
    }
  }
}

resource clientSecret 'Microsoft.Web/sites/config@2022-03-01' = {
  name: 'appsettings'
  parent: webApp
  properties: {
    MICROSOFT_PROVIDER_AUTHENTICATION_SECRET: clientSecretValue
  }
}
```

## Step 4: Test Easy Auth

### Test 1: Verify Authentication is Required

Visit your web app URL without being logged in:

```bash
curl -I https://your-app.azurewebsites.net/
```

Expected: **302 redirect** to `https://login.microsoftonline.com/...`

### Test 2: Login via Browser

1. Open browser to `https://your-app.azurewebsites.net/`
2. Should redirect to Microsoft login page
3. Sign in with your Azure AD account
4. Should redirect back to your app

### Test 3: Verify User Info

Once logged in, check that user info is displayed:

- Look for username in top-right corner
- Verify "Logout" button appears

### Test 4: Check Easy Auth Headers

SSH into your Web App:

```bash
az webapp ssh --name your-app-name --resource-group your-rg
```

Make a request to localhost and check headers:

```bash
curl -H "X-MS-CLIENT-PRINCIPAL: $(cat <<EOF | base64
{
  "userId": "test-user-id",
  "identityProvider": "aad",
  "claims": [
    {"typ": "name", "val": "Test User"},
    {"typ": "preferred_username", "val": "test@example.com"}
  ]
}
EOF
)" http://localhost:8000/
```

## Step 5: Understanding Easy Auth Headers

When Easy Auth is enabled, Azure injects these headers into every request:

| Header | Description | Example |
|--------|-------------|---------|
| `X-MS-CLIENT-PRINCIPAL-NAME` | User's display name | `user@contoso.com` |
| `X-MS-CLIENT-PRINCIPAL-ID` | User's object ID | `00000000-0000-0000-0000-000000000000` |
| `X-MS-CLIENT-PRINCIPAL` | Base64-encoded user info JSON | See below |
| `X-MS-TOKEN-AAD-ACCESS-TOKEN` | Azure AD access token | `eyJ0eXAiOiJKV1QiLCJhbGc...` |

**Decoding X-MS-CLIENT-PRINCIPAL**:

```python
import base64
import json

principal_b64 = request.headers.get('X-MS-CLIENT-PRINCIPAL')
principal_json = base64.b64decode(principal_b64)
principal = json.loads(principal_json)

# Structure:
{
  "auth_typ": "aad",
  "claims": [
    {"typ": "name", "val": "John Doe"},
    {"typ": "preferred_username", "val": "john.doe@contoso.com"},
    {"typ": "email", "val": "john.doe@contoso.com"}
  ],
  "name_typ": "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name",
  "role_typ": "http://schemas.microsoft.com/ws/2008/06/identity/claims/role",
  "userId": "00000000-0000-0000-0000-000000000000",
  "identityProvider": "aad"
}
```

## Step 6: Local Development vs Azure

The Flask app automatically detects the environment:

| Environment | Auth Method | Detection |
|-------------|-------------|-----------|
| **Local** (`flask run`) | MSAL library | `WEBSITE_HOSTNAME` not set |
| **Azure Web App** | Easy Auth | `WEBSITE_HOSTNAME` is set |
| **Azure Container Apps** | Easy Auth | `WEBSITE_HOSTNAME` is set |

### Local Development Setup

For local development with MSAL, set these environment variables:

```bash
export AZURE_CLIENT_ID="your-client-id"
export AZURE_CLIENT_SECRET="your-client-secret"
export AZURE_TENANT_ID="your-tenant-id"
export REDIRECT_URI="http://localhost:5000/auth/callback"

flask run
```

The app will use the MSAL library (`auth.py`) to handle authentication locally.

## Step 7: Built-in Easy Auth Endpoints

Easy Auth provides these endpoints automatically:

| Endpoint | Purpose | Example |
|----------|---------|---------|
| `/.auth/login/aad` | Initiate Azure AD login | `GET /.auth/login/aad` |
| `/.auth/logout` | Logout and clear session | `GET /.auth/logout` |
| `/.auth/me` | Get current user info (JSON) | `GET /.auth/me` |
| `/.auth/refresh` | Refresh auth tokens | `POST /.auth/refresh` |

**Example: Get user info via API**:

```bash
curl https://your-app.azurewebsites.net/.auth/me
```

Returns:

```json
[
  {
    "access_token": "eyJ0eXAiOiJKV1QiLCJhbGc...",
    "expires_on": "2025-11-07T12:00:00.000Z",
    "id_token": "eyJ0eXAiOiJKV1QiLCJhbGc...",
    "provider_name": "aad",
    "user_claims": [
      {"typ": "name", "val": "John Doe"},
      {"typ": "preferred_username", "val": "john.doe@contoso.com"}
    ],
    "user_id": "john.doe@contoso.com"
  }
]
```

## Troubleshooting

### Issue: Redirect loop after login

**Cause**: Redirect URI mismatch

**Fix**:

1. Check app registration redirect URI matches exactly: `https://your-app.azurewebsites.net/.auth/login/aad/callback`
2. Ensure no trailing slash
3. Verify protocol is `https://` not `http://`

### Issue: "AADSTS50011: The reply URL specified in the request does not match"

**Cause**: Redirect URI not registered in app registration

**Fix**:

```bash
az ad app update --id $CLIENT_ID \
  --web-redirect-uris "https://your-app.azurewebsites.net/.auth/login/aad/callback"
```

### Issue: Headers not appearing in Flask request

**Cause**: Easy Auth not fully initialized or misconfigured

**Fix**:

1. Wait 5-10 minutes after enabling Easy Auth
2. Restart Web App: `az webapp restart --name your-app --resource-group your-rg`
3. Check Authentication status in Portal (should show "Configured")

### Issue: User info is None in Flask

**Cause**: `X-MS-CLIENT-PRINCIPAL` header missing or malformed

**Debug**:

```python
# Add to your route
print("Headers:", dict(request.headers))
print("Principal header:", request.headers.get('X-MS-CLIENT-PRINCIPAL'))
```

Check logs: `az webapp log tail --name your-app --resource-group your-rg`

### Issue: Works in Azure, fails locally

**Expected behavior** - use different auth for each:

- Azure: Easy Auth (platform)
- Local: MSAL library (requires env vars)

Ensure local env vars are set:

```bash
export AZURE_CLIENT_ID="..."
export AZURE_CLIENT_SECRET="..."
export AZURE_TENANT_ID="..."
```

## Security Best Practices

1. **Use Require Authentication**: Set Easy Auth to block unauthenticated requests
2. **HTTPS Only**: Always use HTTPS in production (enforced by Azure Web App)
3. **Client Secret Rotation**: Rotate secrets regularly (90 days recommended)
4. **Restrict Redirect URIs**: Only add necessary redirect URIs to app registration
5. **Monitor Sign-ins**: Use Azure AD sign-in logs to detect unusual activity
6. **Use Managed Identity**: For app-to-service auth, use managed identity instead of secrets

## Next Steps

- Configure custom domains with Easy Auth
- Add role-based access control (RBAC)
- Integrate with Azure Key Vault for secrets
- Set up monitoring and alerts
- Deploy to Azure Container Apps (cheaper, same Easy Auth)

## Resources

- [Azure App Service Authentication Documentation](https://learn.microsoft.com/en-us/azure/app-service/overview-authentication-authorization)
- [Easy Auth Headers Reference](https://learn.microsoft.com/en-us/azure/app-service/configure-authentication-user-identities)
- [Configure Microsoft Provider](https://learn.microsoft.com/en-us/azure/app-service/configure-authentication-provider-aad)
- [Azure Container Apps Authentication](https://learn.microsoft.com/en-us/azure/container-apps/authentication)
