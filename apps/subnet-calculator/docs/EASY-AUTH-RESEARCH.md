# Easy Auth Research: Azure Platform Authentication Comparison

Research conducted: November 2025

## Executive Summary

Easy Auth (Azure's built-in authentication) is available across multiple Azure compute platforms but with varying capabilities. This document compares availability and implementation patterns.

## What is Easy Auth?

"Easy Auth" refers to Azure's platform-level authentication feature that handles OAuth/OIDC flows without requiring code changes in your application. Also called:

- App Service Authentication
- Built-in Authentication
- Authentication/Authorization (AuthN/AuthZ)

## Platform Comparison

| Platform | Easy Auth Available | Configuration Method | Notes |
|----------|---------------------|---------------------|-------|
| **Static Web Apps** | Yes | `staticwebapp.config.json` | Simplest implementation |
| **Azure Web App** | Yes | Portal → Authentication | Identical to Static Web Apps |
| **Azure Container Apps** | Yes | Portal → Authentication | Same as Web App |
| **Azure Kubernetes Service** | No | Manual implementation | Requires custom solution |
| **Azure Container Instances** | No | Not applicable | No built-in auth |

## Detailed Analysis

### Azure Static Web Apps

**Status**: Fully Supported

**Configuration**: File-based (`staticwebapp.config.json`)

```json
{
  "auth": {
    "identityProviders": {
      "azureActiveDirectory": {
        "registration": {
          "openIdIssuer": "https://login.microsoftonline.com/common/v2.0",
          "clientIdSettingName": "AZURE_CLIENT_ID",
          "clientSecretSettingName": "AZURE_CLIENT_SECRET"
        }
      }
    }
  },
  "routes": [
    {
      "route": "/*",
      "allowedRoles": ["authenticated"]
    }
  ],
  "responseOverrides": {
    "401": {
      "redirect": "/.auth/login/aad",
      "statusCode": 302
    }
  }
}
```

**Built-in Endpoints**:

- `/.auth/login/aad` - Initiate login
- `/.auth/logout` - Logout
- `/.auth/me` - Get user info

**Advantages**:

- No code changes required
- Works with static HTML/JavaScript
- Version controlled configuration
- Automatic token management

**Limitations**:

- Limited to Static Web Apps only
- Cannot customize auth flow

---

### Azure Web App (App Service)

**Status**: Fully Supported

**Configuration**: Azure Portal → Settings → Authentication

**Setup Steps**:

1. Navigate to App Service → Authentication
2. Click "Add identity provider"
3. Select "Microsoft"
4. Configure:
   - **Application (client) ID**: From app registration
   - **Client secret**: From app registration
   - **Issuer URL**: `https://login.microsoftonline.com/{tenant-id}/v2.0`
   - **Allowed token audiences**: `api://{client-id}`
5. Choose authentication requirement:
   - **Require authentication**: Block unauthenticated requests (no code needed)
   - **Allow unauthenticated**: Allow anonymous access (check auth in code)

**How It Works**:

- Azure injects authentication middleware before your app
- Intercepts all HTTP requests
- Redirects unauthenticated users to login
- Injects identity information into request headers

**Request Headers Injected**:

```text
X-MS-CLIENT-PRINCIPAL-NAME: user@domain.com
X-MS-CLIENT-PRINCIPAL-ID: {object-id}
X-MS-TOKEN-AAD-ACCESS-TOKEN: {access-token}
X-MS-CLIENT-PRINCIPAL: {base64-encoded-json}
```

**Accessing User Info in Flask**:

```python
from flask import request
import base64
import json

# Option 1: Read from headers
user_name = request.headers.get('X-MS-CLIENT-PRINCIPAL-NAME')
user_id = request.headers.get('X-MS-CLIENT-PRINCIPAL-ID')

# Option 2: Decode full principal
principal_b64 = request.headers.get('X-MS-CLIENT-PRINCIPAL')
if principal_b64:
    principal_json = base64.b64decode(principal_b64)
    principal = json.loads(principal_json)
    claims = principal.get('claims', [])

# Option 3: Call /.auth/me endpoint
import requests
response = requests.get(f"{request.url_root}.auth/me")
user_info = response.json()
```

**Built-in Endpoints**:

- `/.auth/login/aad` - Initiate login
- `/.auth/logout` - Logout
- `/.auth/me` - Get user claims (JSON)
- `/.auth/refresh` - Refresh tokens

**Advantages**:

- Zero code required for basic auth
- Azure manages token lifecycle
- Works with any framework (Flask, Django, FastAPI, etc.)
- Same configuration as Static Web Apps
- Can enable/disable via Portal (no deployment needed)

**Limitations**:

- Requires Azure Web App (not available for local development)
- Less control over auth flow
- Debugging can be challenging

**Resource**: [Azure App Service Authentication Documentation](https://learn.microsoft.com/en-us/azure/app-service/overview-authentication-authorization)

---

### Azure Container Apps

**Status**: Fully Supported (as of 2025)

**Configuration**: Azure Portal → Settings → Authentication

**How It Works**:

- Runs as a sidecar container alongside your app container
- Intercepts HTTP requests before reaching application
- Identical behavior to Azure Web App

**2025 Update**:

- Now supports `X-MS-TOKEN-AAD-ACCESS-TOKEN` header
- Previously this header was missing in Container Apps
- Brings full parity with App Service Easy Auth

**Setup**:
Same as Azure Web App - Portal → Authentication → Add identity provider

**Request Headers**: Same as Azure Web App

**Built-in Endpoints**: Same as Azure Web App (`/.auth/*`)

**Advantages**:

- Modern container-based deployment
- Scales to zero (cost savings)
- Lower cost than App Service
- Same Easy Auth as Web App
- Container flexibility

**Disadvantages**:

- Newer service (less mature than App Service)
- Requires external ingress enabled

**Resource**: [Azure Container Apps Authentication Documentation](https://learn.microsoft.com/en-us/azure/container-apps/authentication)

---

### Azure Kubernetes Service (AKS)

**Status**: No built-in application authentication

**What AKS Provides**:

- **Cluster authentication**: kubectl access via Microsoft Entra ID
- **Workload identity**: Pods accessing Azure resources (managed identities)
- **Kubernetes RBAC**: API server authorization

**What AKS Does NOT Provide**:

- Application-level HTTP authentication
- Sidecar authentication containers
- `/.auth/*` endpoints
- Automatic token injection

**Implementation Patterns for App Authentication**:

#### Pattern 1: OAuth2 Proxy Sidecar

Deploy oauth2-proxy as a sidecar container in your pod:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: flask-app
spec:
  template:
    spec:
      containers:
      # Main application
      - name: flask-app
        image: your-flask-app
        ports:
        - containerPort: 5000

      # OAuth2 Proxy sidecar
      - name: oauth2-proxy
        image: quay.io/oauth2-proxy/oauth2-proxy:latest
        args:
        - --provider=oidc
        - --oidc-issuer-url=https://login.microsoftonline.com/{tenant-id}/v2.0
        - --client-id={client-id}
        - --client-secret={client-secret}
        - --upstream=http://localhost:5000
        - --http-address=0.0.0.0:4180
        ports:
        - containerPort: 4180
```

**Advantages**:

- Similar to Easy Auth
- Per-pod authentication
- Full control over configuration

**Disadvantages**:

- Manual setup and maintenance
- Each pod runs auth proxy (resource overhead)
- You manage the oauth2-proxy image

#### Pattern 2: Ingress-Level Authentication

Configure nginx-ingress with external auth:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: flask-app
  annotations:
    nginx.ingress.kubernetes.io/auth-url: "https://oauth2-proxy.namespace.svc.cluster.local/oauth2/auth"
    nginx.ingress.kubernetes.io/auth-signin: "https://oauth2-proxy.namespace.svc.cluster.local/oauth2/start"
spec:
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        backend:
          service:
            name: flask-app
            port: 5000
```

**Advantages**:

- Centralized authentication
- Single oauth2-proxy deployment

**Disadvantages**:

- More complex setup
- Ingress controller specific

#### Pattern 3: Application-Level (MSAL)

Keep authentication in your Flask code using the MSAL library (like the current `auth.py`):

**Advantages**:

- Works anywhere (local, Azure, on-prem)
- Full control over auth flow
- Portable across platforms

**Disadvantages**:

- Requires code changes
- You manage token lifecycle
- Framework/language specific

**Resource**: [AKS Identity Best Practices](https://learn.microsoft.com/en-us/azure/aks/operator-best-practices-identity)

---

## Recommendation Matrix

| Scenario | Recommended Platform | Auth Method |
|----------|---------------------|-------------|
| Static HTML/JS frontend | Static Web Apps | Easy Auth (config file) |
| Flask/Python backend | Azure Web App | Easy Auth (Portal) |
| Modern containers | Container Apps | Easy Auth (Portal) |
| Kubernetes required | AKS | OAuth2 Proxy or MSAL |
| Local development | Any | MSAL library |

## Implementation Strategy for Flask App

### Hybrid Approach (Recommended)

Detect environment and use appropriate auth method:

```python
import os
from flask import Flask, request

app = Flask(__name__)

# Check if running in Azure with Easy Auth
if os.getenv("WEBSITE_HOSTNAME"):
    # Azure Web App or Container App with Easy Auth
    USE_EASY_AUTH = True
    auth = None  # Platform handles authentication
else:
    # Local development or non-Azure environment
    USE_EASY_AUTH = False
    from auth import init_auth
    auth = init_auth(app)  # Use MSAL library

def get_user_info():
    """Get authenticated user info from either Easy Auth or MSAL"""
    if USE_EASY_AUTH:
        # Read from Easy Auth headers
        user_name = request.headers.get('X-MS-CLIENT-PRINCIPAL-NAME')
        principal_b64 = request.headers.get('X-MS-CLIENT-PRINCIPAL')
        if principal_b64:
            import base64, json
            principal = json.loads(base64.b64decode(principal_b64))
            return {
                'name': user_name,
                'claims': principal.get('claims', [])
            }
        return None
    else:
        # Use MSAL session
        return auth.get_user() if auth else None
```

**Benefits**:

- Works locally with MSAL (full OAuth flow)
- Works in Azure with Easy Auth (zero code)
- Single codebase for both environments
- Easy to test locally before Azure deployment

## Cost Comparison

| Service | Monthly Cost (UK South) | Easy Auth Support |
|---------|------------------------|-------------------|
| Static Web Apps (Free tier) | £0 | Yes |
| Static Web Apps (Standard) | ~£7 | Yes |
| Web App (B1) | ~£10 | Yes |
| Web App (P1v3) | ~£160 | Yes |
| Container Apps | ~£0-50* | Yes |
| AKS (single node) | ~£50+ | No |

\* Container Apps scales to zero, pay only for usage

## Security Considerations

### Easy Auth (Platform-Level)

**Pros**:

- Azure manages token refresh
- No secrets in application code
- Automatic security updates
- Consistent implementation

**Cons**:

- Less control over auth flow
- Harder to debug
- Azure-specific (vendor lock-in)

### MSAL (Application-Level)

**Pros**:

- Full control over flow
- Works anywhere
- Easy to debug locally
- Can customize scopes/claims

**Cons**:

- You manage MSAL library updates
- Client secret in environment variables
- More code to maintain

## Conclusion

**For Flask app deployment**:

- **Use Easy Auth** in Azure Web App or Container Apps (production)
- **Keep MSAL** for local development and testing
- **Implement hybrid approach** for maximum flexibility

**Migration path**:

1. Test locally with MSAL (current setup)
2. Deploy to Azure Web App with Easy Auth enabled
3. Verify headers are injected correctly
4. Optionally migrate to Container Apps for cost savings

Easy Auth simplifies authentication significantly in Azure environments while maintaining the ability to develop and test locally with MSAL.
