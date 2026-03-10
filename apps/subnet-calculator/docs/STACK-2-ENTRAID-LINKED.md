# Stack 2: Public SWA + Entra ID + Linked Backend

## Overview

Stack 2 demonstrates enterprise-grade authentication using Azure Entra ID (Azure AD) with a linked Function App backend. This is the **RECOMMENDED** production setup.

## Architecture

```text
┌─────────────────────────────────────┐
│ User → Entra ID Login │
└──────────────┬──────────────────────┘
 │
┌──────────────▼──────────────────────┐
│ Azure Static Web App (Standard) │
│ - TypeScript Vite SPA │
│ - Entra ID authentication │
│ - /api/* → SWA Proxy → Function │
│ - Custom domain + azurestaticapps │
└──────────────┬──────────────────────┘
 │ Linked backend
┌──────────────▼──────────────────────┐
│ Azure Function App (Consumption) │
│ - Linked to SWA as managed backend │
│ - Accessible via both custom domains│
│ - No auth on Function (SWA handles) │
└─────────────────────────────────────┘
```

## Custom Domains

- **SWA**: `https://static-swa-entraid-linked.publiccloudexperiments.net`
- **Function**: `https://subnet-calc-fa-entraid-linked.publiccloudexperiments.net`

## Deployment

### Prerequisites

1. **Entra ID App Registration**: Existing app ID `370b8618-a252-442e-9941-c47a9f7da89e`
1. **Client Secret**: Valid secret for the app registration
1. **DNS Access**: Create CNAME records for both domains

### Quick Deploy

```bash
cd ~/Developer/personal/azure-tui/infrastructure/azure

# Set Entra ID credentials
export AZURE_CLIENT_ID="370b8618-a252-442e-9941-c47a9f7da89e"
export AZURE_CLIENT_SECRET="your-secret-here"

# Deploy
./azure-stack-15-swa-entraid-linked.sh
```

### DNS Records Required

```text
static-swa-entraid-linked.publiccloudexperiments.net → CNAME → <app>.azurestaticapps.net
subnet-calc-fa-entraid-linked.publiccloudexperiments.net → CNAME → <func>.azurewebsites.net
```

### Redirect URIs (Both Required)

The script automatically adds:

1. `https://<app>.azurestaticapps.net/.auth/login/aad/callback`
1. `https://static-swa-entraid-linked.publiccloudexperiments.net/.auth/login/aad/callback`

## Authentication Flow

### 1. User visits SWA

```text
https://static-swa-entraid-linked.publiccloudexperiments.net
```

### 2. SWA redirects to Entra ID login

```text
https://login.microsoftonline.com/{tenant}/oauth2/v2.0/authorize
```

### 3. User authenticates with Microsoft credentials

- Work/School account
- Personal Microsoft account (if configured)

### 4. Entra ID redirects back to SWA with auth code

```text
https://static-swa-entraid-linked.publiccloudexperiments.net/.auth/login/aad/callback?code=xxx
```

### 5. SWA exchanges code for tokens and sets HttpOnly cookie

Cookie: `StaticWebAppsAuthCookie` (HttpOnly, Secure, SameSite)

### 6. Frontend calls API via /api/* proxy

```http
GET https://static-swa-entraid-linked.publiccloudexperiments.net/api/v1/ipv4/validate?address=192.168.1.1
Cookie: StaticWebAppsAuthCookie
```

### 7. SWA proxies to Function App

```http
GET https://subnet-calc-fa-entraid-linked.publiccloudexperiments.net/api/v1/ipv4/validate?address=192.168.1.1
X-MS-CLIENT-PRINCIPAL: <base64-encoded-user-info>
```

## Testing

### 1. Test login flow

```bash
# Visit in browser
open https://static-swa-entraid-linked.publiccloudexperiments.net

# Should redirect to Microsoft login
# After login, should show app
```

### 2. Check user info

```bash
curl https://static-swa-entraid-linked.publiccloudexperiments.net/.auth/me \
 -H "Cookie: StaticWebAppsAuthCookie=<cookie-from-browser>"

# Returns user info
```

### 3. Test logout

```bash
# Visit logout URL
open https://static-swa-entraid-linked.publiccloudexperiments.net/logout

# Should redirect to /logged-out.html
```

### 4. Verify Function not publicly accessible

```bash
curl https://subnet-calc-fa-entraid-linked.publiccloudexperiments.net/api/v1/ipv4/validate?address=192.168.1.1

# Should return data (no auth on Function - SWA handles it)
```

## Security Features

### Strengths

- **Enterprise SSO** - Entra ID integration
- **HttpOnly cookies** - Protected from XSS attacks
- **Same-origin API** - No CORS issues
- **Platform-level auth** - Managed by Azure
- **Multiple domains** - Works with both custom and default
- **Token refresh** - Automatic, transparent to user

### Best Practices

1. **Use custom domain as primary** for user-facing URLs
1. **Configure logout redirect** to custom domain
1. **Set session timeout** appropriately for your use case
1. **Monitor failed logins** in Entra ID logs

## Configuration

### staticwebapp-entraid-builtin.config.json

```json
{
 "routes": [
 {
 "route": "/logged-out.html",
 "allowedRoles": ["anonymous", "authenticated"]
 },
 {
 "route": "/logout",
 "redirect": "/.auth/logout?post_logout_redirect_uri=/logged-out.html"
 },
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

### Function App Settings

```bash
AUTH_METHOD=none # SWA handles auth
CORS_ORIGINS=https://static-swa-entraid-linked.publiccloudexperiments.net
```

## Troubleshooting

### Issue: Redirect URI mismatch

**Error**: `AADSTS50011: The redirect URI specified in the request does not match`

**Solution**: Verify both URIs are in Entra ID app registration

```bash
az ad app show --id 370b8618-a252-442e-9941-c47a9f7da89e \
 --query "web.redirectUris"
```

### Issue: Infinite login loop

**Cause**: SWA authentication settings not configured

**Solution**: Verify AZURE_CLIENT_ID and AZURE_CLIENT_SECRET in SWA app settings

```bash
az staticwebapp appsettings list \
 --name swa-subnet-calc-entraid-linked \
 --resource-group rg-subnet-calc
```

## Cost Breakdown

| Resource | SKU | Monthly Cost |
|----------|-----|--------------|
| Static Web App | Standard | $9 |
| Function App | Consumption | ~$0 |
| **Total** | | **~$9/month** |

## Cleanup

```bash
az staticwebapp delete --name swa-subnet-calc-entraid-linked --yes
az functionapp delete --name func-subnet-calc-entraid-linked --resource-group rg-subnet-calc
```

## Next Steps

- **Stack 3**: Add private endpoints for network isolation

## References

- [SWA Authentication](https://learn.microsoft.com/en-us/azure/static-web-apps/authentication-authorization)
- [Entra ID OAuth](https://learn.microsoft.com/en-us/entra/identity-platform/v2-overview)
