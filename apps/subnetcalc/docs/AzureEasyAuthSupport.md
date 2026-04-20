# Azure Easy Auth Support

## What is Easy Auth?

Azure Easy Authentication (Easy Auth) is a built-in authentication and authorization feature provided by specific Azure services. It acts as a **reverse proxy with authentication middleware** that sits between users and your application, enforcing authentication before serving content.

## How Easy Auth Works

```text
User Request
    ↓
Easy Auth Proxy (intercepts request, checks authentication)
    ↓ (if not authenticated)
302 Redirect to Identity Provider (Entra ID, Google, etc.)
    ↓ (user logs in)
OAuth/OIDC Flow Completes
    ↓
Easy Auth sets authentication cookie
    ↓ (redirect back to app)
Easy Auth Proxy (validates cookie)
    ↓ (authenticated)
Application receives request with user identity headers
```

## Key Features

1. **Server-Side Authentication Enforcement**
   - Intercepts requests BEFORE serving content
   - Can force login at the edge (before HTML/JS is delivered)
   - Unlike pure SPAs, users cannot bypass authentication

2. **Built-in Identity Provider Support**
   - Microsoft Entra ID (Azure AD)
   - Google, Facebook, Twitter
   - OpenID Connect (custom providers)

3. **User Identity Headers**
   Easy Auth injects headers with user information:
   - `X-MS-CLIENT-PRINCIPAL` - Base64 encoded user claims
   - `X-MS-CLIENT-PRINCIPAL-ID` - User's object ID
   - `X-MS-CLIENT-PRINCIPAL-NAME` - User's email/username
   - `X-MS-TOKEN-AAD-ACCESS-TOKEN` - Access token for downstream APIs
   - `X-MS-TOKEN-AAD-ID-TOKEN` - ID token

4. **Token Management**
   - Automatically refreshes tokens
   - Stores tokens securely
   - Provides token APIs (`/.auth/me`, `/.auth/refresh`)

5. **Session Management**
   - Cookie-based sessions
   - Configurable session timeout
   - Logout endpoint (`/.auth/logout`)

## Where Easy Auth is Available

### Services with Built-in Easy Auth

| Service | Easy Auth Support | Configuration Method | Notes |
|---------|------------------|---------------------|-------|
| **Azure App Service** | Yes (full support) | Portal / ARM template / CLI | Original Easy Auth implementation |
| **Azure Function Apps** | Yes (full support) | Portal / ARM template / CLI | Same as App Service |
| **Azure Static Web Apps** | Yes (full support) | `staticwebapp.config.json` | Slightly different config format |
| **Azure Container Apps** | Yes (full support) | ARM template / `az containerapp auth` | Built into ingress |

### Services without Easy Auth

| Service | Easy Auth Support | Alternative Solutions |
|---------|------------------|----------------------|
| **Azure Kubernetes Service (AKS)** | No | OAuth2 Proxy sidecar, Service Mesh (Istio/Linkerd), API Gateway auth |
| **Azure Container Instances** | No | Custom auth in application, reverse proxy with auth |
| **Azure Virtual Machines** | No | Application-level auth, reverse proxy with auth |
| **Azure App Gateway** | No | Can integrate with other auth services, but no built-in Easy Auth |
| **Azure API Management** | No (has OAuth validation) | JWT validation policies, OAuth2 authorization |

## Configuration Examples

### Azure App Service / Function Apps

**Portal Configuration:**

1. Navigate to Authentication in the left menu
2. Click "Add identity provider"
3. Select Microsoft (Entra ID)
4. Configure authentication settings

**ARM Template:**

```json
{
  "type": "Microsoft.Web/sites/config",
  "apiVersion": "2022-03-01",
  "name": "[concat(parameters('siteName'), '/authsettingsV2')]",
  "properties": {
    "globalValidation": {
      "requireAuthentication": true,
      "unauthenticatedClientAction": "RedirectToLoginPage"
    },
    "identityProviders": {
      "azureActiveDirectory": {
        "enabled": true,
        "registration": {
          "clientId": "[parameters('aadClientId')]",
          "clientSecretSettingName": "AAD_CLIENT_SECRET",
          "openIdIssuer": "[concat('https://sts.windows.net/', parameters('tenantId'), '/')]"
        },
        "validation": {
          "allowedAudiences": [
            "[concat('api://', parameters('aadClientId'))]"
          ]
        }
      }
    }
  }
}
```

**Azure CLI:**

```bash
# Enable authentication
az webapp auth update \
  --resource-group rg-myapp \
  --name myapp \
  --enabled true \
  --action LoginWithAzureActiveDirectory

# Configure Entra ID
az webapp auth microsoft update \
  --resource-group rg-myapp \
  --name myapp \
  --client-id "your-client-id" \
  --client-secret-setting-name "AAD_CLIENT_SECRET" \
  --issuer "https://sts.windows.net/your-tenant-id/"
```

### Azure Static Web Apps

**staticwebapp.config.json:**

```json
{
  "routes": [
    {
      "route": "/*",
      "allowedRoles": ["authenticated"]
    },
    {
      "route": "/login",
      "allowedRoles": ["anonymous"]
    }
  ],
  "responseOverrides": {
    "401": {
      "redirect": "/.auth/login/aad",
      "statusCode": 302
    }
  },
  "auth": {
    "identityProviders": {
      "azureActiveDirectory": {
        "registration": {
          "openIdIssuer": "https://login.microsoftonline.com/{tenant-id}/v2.0",
          "clientIdSettingName": "AZURE_CLIENT_ID",
          "clientSecretSettingName": "AZURE_CLIENT_SECRET"
        }
      }
    }
  }
}
```

### Azure Container Apps

**Bicep/ARM:**

```bicep
resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: 'myapp'
  properties: {
    configuration: {
      ingress: {
        external: true
        targetPort: 80
      }
      auth: {
        enabled: true
        requireAuthentication: true
        identityProviders: {
          azureActiveDirectory: {
            enabled: true
            registration: {
              clientId: 'your-client-id'
              clientSecretSettingName: 'aad-secret'
              openIdIssuer: 'https://login.microsoftonline.com/${tenantId}/v2.0'
            }
          }
        }
      }
    }
    template: {
      containers: [
        {
          name: 'myapp'
          image: 'myapp:latest'
        }
      ]
    }
  }
}
```

**Azure CLI:**

```bash
# Enable auth on existing Container App
az containerapp auth update \
  --name myapp \
  --resource-group rg-myapp \
  --enabled true \
  --require-authentication true \
  --unauthenticated-client-action RedirectToLoginPage

# Configure Entra ID
az containerapp auth microsoft update \
  --name myapp \
  --resource-group rg-myapp \
  --client-id "your-client-id" \
  --client-secret-setting-name "aad-secret" \
  --issuer "https://login.microsoftonline.com/your-tenant-id/v2.0"
```

## Easy Auth vs Application-Level Authentication

### Easy Auth (Server-Side)

**Pros:**

- Enforces authentication before serving content
- No application code changes required
- Centralized authentication configuration
- Built-in token management and refresh
- Security team can manage independently

**Cons:**

- Only available on specific Azure services
- Less flexibility in customizing auth flow
- Limited to supported identity providers

### Application-Level Authentication (Client-Side SPA)

**Pros:**

- Works on any hosting platform (AKS, VMs, other clouds)
- Full control over authentication flow
- Can customize UX extensively
- Works with any OAuth/OIDC provider

**Cons:**

- Users see UI before authentication
- Requires application code changes
- More complex to implement correctly
- Token management must be handled in code

## Using Easy Auth Headers in Downstream Services

When your frontend uses Easy Auth, downstream APIs can consume the user identity:

### Reading User Identity

```javascript
// Node.js / Express
app.get('/api/profile', (req, res) => {
  const principalHeader = req.headers['x-ms-client-principal'];
  if (!principalHeader) {
    return res.status(401).json({ error: 'Not authenticated' });
  }

  // Decode base64 principal
  const principal = JSON.parse(Buffer.from(principalHeader, 'base64').toString('utf-8'));

  res.json({
    userId: principal.userId,
    userDetails: principal.userDetails,
    claims: principal.claims
  });
});
```

```python
# Python / FastAPI
from fastapi import Header, HTTPException
import base64
import json

@app.get("/api/profile")
async def get_profile(x_ms_client_principal: str = Header(None)):
    if not x_ms_client_principal:
        raise HTTPException(status_code=401, detail="Not authenticated")

    # Decode principal
    principal_json = base64.b64decode(x_ms_client_principal).decode('utf-8')
    principal = json.loads(principal_json)

    return {
        "userId": principal["userId"],
        "userDetails": principal["userDetails"],
        "claims": principal["claims"]
    }
```

### Proxying Requests with Easy Auth Headers

Our `server.js` implementation shows how to forward Easy Auth headers to backend APIs:

```javascript
// Forward Easy Auth headers to backend
const easyAuthHeaderWhitelist = [
  'x-zumo-auth',
  'authorization',
  'x-ms-token-aad-access-token',
  'x-ms-token-aad-id-token',
  'x-ms-client-principal',
  'x-ms-client-principal-id',
  'x-ms-client-principal-name',
  'cookie',
];

app.use('/api', createProxyMiddleware({
  target: backendUrl,
  onProxyReq: (proxyReq, req) => {
    easyAuthHeaderWhitelist.forEach((header) => {
      const value = req.headers[header];
      if (value) {
        proxyReq.setHeader(header, value);
      }
    });
  }
}));
```

## Easy Auth APIs

All Easy Auth-enabled services provide standard endpoints:

### `/.auth/me` - Get Current User

```bash
curl https://myapp.azurewebsites.net/.auth/me \
  -H "Cookie: AppServiceAuthSession=..."
```

**Response:**

```json
[
  {
    "access_token": "eyJ0eXAiOiJKV1QiLCJhbGc...",
    "expires_on": "2024-01-01T12:00:00.0000000Z",
    "id_token": "eyJ0eXAiOiJKV1QiLCJhbGc...",
    "provider_name": "aad",
    "user_claims": [
      { "typ": "name", "val": "John Doe" },
      { "typ": "email", "val": "john@contoso.com" }
    ],
    "user_id": "john@contoso.com"
  }
]
```

### `/.auth/login/{provider}` - Initiate Login

```bash
# Redirect to login page
https://myapp.azurewebsites.net/.auth/login/aad
https://myapp.azurewebsites.net/.auth/login/google
https://myapp.azurewebsites.net/.auth/login/facebook
```

### `/.auth/logout` - Logout

```bash
# Logout and optionally redirect
https://myapp.azurewebsites.net/.auth/logout?post_logout_redirect_uri=/
```

### `/.auth/refresh` - Refresh Tokens

```bash
curl -X POST https://myapp.azurewebsites.net/.auth/refresh \
  -H "Cookie: AppServiceAuthSession=..."
```

## Security Considerations

1. **HTTPS Only**
   - Easy Auth requires HTTPS in production
   - Authentication cookies are marked as Secure

2. **Token Storage**
   - Tokens are stored server-side by default
   - Optional client-side token storage for SPAs

3. **CORS**
   - Configure CORS appropriately for API calls
   - Easy Auth cookies are same-origin only

4. **Token Expiration**
   - Configure session timeout appropriately
   - Enable automatic token refresh for long sessions

5. **Custom Domain**
   - Works with custom domains
   - Ensure redirect URIs include all domains

## Migration Between Services

### App Service → Container Apps

- Easy Auth configuration is similar
- CLI commands have different syntax
- Headers remain the same

### App Service → AKS

- Easy Auth not available
- Use OAuth2 Proxy sidecar pattern
- Application must handle auth headers differently

### Static Web Apps → App Service

- Different config format (`staticwebapp.config.json` vs ARM)
- Similar functionality
- May need to adjust routing rules

## References

- [App Service Authentication Documentation](https://learn.microsoft.com/en-us/azure/app-service/overview-authentication-authorization)
- [Static Web Apps Authentication](https://learn.microsoft.com/en-us/azure/static-web-apps/authentication-authorization)
- [Container Apps Authentication](https://learn.microsoft.com/en-us/azure/container-apps/authentication)
- [Easy Auth Token Store](https://learn.microsoft.com/en-us/azure/app-service/overview-authentication-authorization#token-store)
