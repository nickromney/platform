# Authentication and Authorization Options for Subnet Calculator API

Research document comparing authentication methods for FastAPI/Azure Functions.

**Date:** 2025-10-07
**Context:** Adding auth to subnet calculator API (static frontend + Flask frontend + Azure Functions backend)

---

## Quick Decision Tree

```text
Public API (anyone can call)?
├─ Yes → API Keys + Rate Limiting
└─ No → Who needs access?
 ├─ Just your frontends → JWT with backend login
 ├─ Enterprise users → Azure AD / OAuth 2.0
 ├─ Service-to-service → Managed Identity (Azure) or mTLS
 └─ Zero trust / multi-cloud → JWT + mTLS + API Gateway
```

---

## Option 1: API Keys

**What it is:** Client includes a key in every request header.

**Request format:**

```http
GET /api/v1/health
X-API-Key: api_key_abc123xyz
```

or

```http
GET /api/v1/health
Authorization: Bearer api_key_abc123xyz
```

### Pros

- - Dead simple to implement
- - Works with static frontends
- - Stateless (perfect for serverless)
- - Good for rate limiting per key
- - Easy to test locally

### Cons

- NO Key visible in browser (if client-side)
- NO No user identity (just "this key is valid")
- NO Key rotation is manual
- NO All-or-nothing (no fine-grained permissions)

### When to Use

- Public API with usage limits
- Developer API keys
- Server-to-server (Flask → API)
- Quick prototyping

### Code Complexity

- (very easy)

### Local Testing

YES **Excellent** - Just set environment variable or hardcode for dev

```python
# FastAPI example
from fastapi import Header, HTTPException

async def verify_api_key(x_api_key: str = Header(...)):
 if x_api_key != "dev-key-123": # In prod: check database
 raise HTTPException(status_code=401, detail="Invalid API key")
 return x_api_key

@app.get("/api/v1/health")
async def health(api_key: str = Depends(verify_api_key)):
 return {"status": "healthy"}
```

### Example Use Cases

- GitHub API
- Stripe API
- SendGrid API

---

## Option 2: JWT (JSON Web Tokens)

**What it is:** Signed tokens containing claims (user info, expiry, permissions).

**Token structure:**

```text
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9. # Header (algorithm)
eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6I # Payload (claims: user, expiry)
SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_ad # Signature
```

**Flow:**

```text
1. User logs in → Backend issues JWT
1. Client stores JWT (localStorage, cookie)
1. Client sends JWT with each request: Authorization: Bearer <token>
1. API validates signature + expiry
```

**Decoded payload:**

```json
{
 "sub": "user@example.com",
 "name": "John Doe",
 "iat": 1516239022,
 "exp": 1516242622,
 "roles": ["user", "admin"]
}
```

### Pros

- - Stateless (no session storage needed)
- - Contains user info (sub, email, roles)
- - Works with static frontends
- - Industry standard
- - Can add custom claims (permissions, roles)
- - Self-contained (API doesn't need to query database)

### Cons

- NO Can't revoke before expiry (unless you add a blacklist)
- NO Token visible in browser (XSS risk)
- NO Signature validation adds latency (~1ms)
- NO Token size larger than API keys (~200-500 bytes)

### When to Use

- Need user identity
- Stateless authentication
- Microservices (each service validates JWT)
- Works across domains
- Need custom claims (roles, permissions)

### Code Complexity

\*\* (moderate)

### Local Testing

YES **Excellent** - Generate tokens with same secret

```python
# FastAPI example with python-jose
from jose import jwt, JWTError
from datetime import datetime, timedelta

SECRET_KEY = "dev-secret-key-change-in-production"
ALGORITHM = "HS256"

def create_token(data: dict, expires_delta: timedelta = timedelta(hours=1)):
 to_encode = data.copy()
 expire = datetime.utcnow() + expires_delta
 to_encode.update({"exp": expire})
 return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

async def verify_token(authorization: str = Header(...)):
 try:
 token = authorization.replace("Bearer ", "")
 payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
 return payload
 except JWTError:
 raise HTTPException(status_code=401, detail="Invalid token")

# Generate test token
test_token = create_token({"sub": "test@example.com", "roles": ["user"]})
print(f"Test token: {test_token}")
```

**Test with curl:**

```bash
TOKEN="eyJhbGc..."
curl -H "Authorization: Bearer $TOKEN" http://localhost:7071/api/v1/health
```

### Libraries

- **FastAPI:** `python-jose[cryptography]`, `passlib`
- **Validation:** `PyJWT`, `python-jose`

### Example Use Cases

- Auth0
- Firebase Auth
- Custom login systems

---

## Option 3: OAuth 2.0 / OpenID Connect (OIDC)

**What it is:** Industry standard for delegated authorization + authentication.

### Authorization Code Flow (Web Apps)

```text
1. User clicks "Login with Google"
1. Redirect to accounts.google.com → user logs in
1. Google redirects back with authorization code
1. Backend exchanges code for access_token + id_token
1. Frontend uses access_token for API calls
```

**Request:**

```http
GET /api/v1/health
Authorization: Bearer <access_token_from_google>
```

### Client Credentials Flow (Service-to-Service)

```text
1. Service A requests token from OAuth server
1. OAuth server validates client_id + client_secret
1. Service A gets access_token
1. Service A calls Service B with token
```

### OpenID Connect

OAuth 2.0 + identity layer (adds `id_token` with user info)

**id_token** is a JWT containing:

```json
{
 "iss": "https://accounts.google.com",
 "sub": "10769150350006150715113082367",
 "email": "user@example.com",
 "email_verified": true,
 "iat": 1516239022,
 "exp": 1516242622
}
```

### Pros

- - Industry standard
- - Delegated auth (Google, GitHub, Microsoft login)
- - Fine-grained scopes (`read:email`, `write:posts`)
- - Refresh tokens (long-lived sessions)
- - User doesn't give you their password

### Cons

- NO Complex to implement from scratch
- NO Requires OAuth provider (Azure AD, Auth0, etc.)
- NO Multiple round-trips for token exchange
- NO Static frontend needs PKCE (extra complexity)

### When to Use

- "Login with Google/GitHub/Microsoft"
- Enterprise SSO (SAML → OIDC bridge)
- Fine-grained permissions
- Third-party API access

### Code Complexity

\*\*\* (complex if DIY, easy if using provider)

### Local Testing

WARNING **Moderate** - Need OAuth provider or mock server

**Options:**

1. **Use real provider (recommended):**

- Google OAuth (free, easy setup)
- GitHub OAuth (free, easy setup)
- Auth0 (free tier available)

1. **Mock OAuth server:**

- `pytest-httpx` for testing
- Manually validate test tokens
- Use `id_token` from real provider, validate locally

```python
# FastAPI with Google OAuth
from authlib.integrations.starlette_client import OAuth

oauth = OAuth()
oauth.register(
 name='google',
 client_id='your-client-id.apps.googleusercontent.com',
 client_secret='your-client-secret',
 server_metadata_url='https://accounts.google.com/.well-known/openid-configuration',
 client_kwargs={'scope': 'openid email profile'}
)

# Validate token
async def verify_google_token(authorization: str = Header(...)):
 token = authorization.replace("Bearer ", "")
 # Verify against Google's public keys
 payload = jwt.decode(
 token,
 options={"verify_signature": True},
 audience="your-client-id.apps.googleusercontent.com"
 )
 return payload
```

**Local testing:**

```bash
# Get token from OAuth playground
# https://developers.google.com/oauthplayground/

TOKEN="ya29.a0AfB_..."
curl -H "Authorization: Bearer $TOKEN" http://localhost:7071/api/v1/health
```

### Azure Options

- **Azure AD B2C** (consumer apps, social logins)
- **Azure AD / Entra ID** (enterprise)
- **Managed Identity** (Azure-to-Azure)

### Example Use Cases

- "Login with Google"
- GitHub OAuth Apps
- Slack Apps

---

## Option 4: Azure AD / Entra ID (Enterprise SSO)

**What it is:** Microsoft's identity platform (OAuth 2.0 + OIDC).

### Flow

```text
1. User visits app → redirected to login.microsoftonline.com
1. User logs in with corporate account (user@company.com)
1. Azure AD issues access_token + id_token
1. App validates tokens against Azure AD
```

### Two Flavors

#### Azure AD B2C (Business-to-Consumer)

- For public apps (customer-facing)
- Social logins (Google, Facebook, custom)
- Custom branding
- User self-signup
- Custom user attributes

**Tenant:** `yourapp.b2clogin.com`

#### Azure AD / Entra ID (Enterprise)

- Corporate accounts only (`user@company.com`)
- Conditional access (MFA, device compliance)
- Integration with on-prem AD
- RBAC (role-based access control)
- Group memberships

**Tenant:** `login.microsoftonline.com/your-tenant-id`

### Pros

- - Native Azure integration
- - EasyAuth (Azure App Service feature - zero code)
- - Managed Identity (Azure-to-Azure calls)
- - Enterprise features (MFA, Conditional Access)
- - Free tier available
- - MSAL libraries for all platforms

### Cons

- NO Locked into Microsoft ecosystem
- NO Complex admin setup (App Registrations, permissions)
- NO Doesn't work well across clouds (Azure → Cloudflare)
- NO Static frontend needs SPA flow (PKCE)

### When to Use

- Azure-native apps
- Enterprise customers using Microsoft 365
- Need MFA, Conditional Access
- Azure Functions + Azure Static Web Apps

### Code Complexity

**With EasyAuth:** \* (zero code)

```yaml
# Just enable in Azure Portal
# App Service → Authentication → Add identity provider → Microsoft
```

**Manual MSAL:** \*\*\* (moderate)

### Local Testing

YES **Good** - Use Azure AD tenant (even free tier)

**Options:**

1. **Use real Azure AD tenant:**

- Free with Azure subscription
- Create test users
- Register app in Azure Portal

1. **Use Microsoft identity platform emulator (limited):**

- `azurite` doesn't support AD
- Must use real Azure AD

1. **Mock tokens for unit tests:**

```python
# Generate mock Azure AD token
mock_token = create_jwt({
"iss": "https://login.microsoftonline.com/tenant-id/v2.0",
"aud": "your-app-client-id",
"sub": "user-object-id",
"email": "user@company.com",
"roles": ["User"]
})
```

**Setup for local testing:**

1. **Register app in Azure Portal:**

- App Registrations → New registration
- Name: "Subnet Calculator API"
- Redirect URI: `http://localhost:7071/.auth/login/aad/callback`

1. **Get credentials:**

```bash
TENANT_ID="..."
CLIENT_ID="..."
CLIENT_SECRET="..."
```

1. **FastAPI with MSAL:**

```python
from msal import ConfidentialClientApplication

app_config = {
"client_id": CLIENT_ID,
"client_secret": CLIENT_SECRET,
"authority": f"https://login.microsoftonline.com/{TENANT_ID}"
}

async def verify_azure_ad_token(authorization: str = Header(...)):
token = authorization.replace("Bearer ", "")
# Validate against Azure AD
# Use MSAL to verify token signature
return payload
```

1. **Get test token:**

```bash
# Use Azure CLI
az login
az account get-access-token --resource "api://your-app-client-id" --query accessToken -o tsv
```

### Azure Functions Specific

**EasyAuth (easiest):**

1. Enable in Azure Portal
1. All requests have `X-MS-TOKEN-AAD-ID-TOKEN` header
1. Zero code changes

**Manual validation:**

```python
# Azure Functions can use MSAL like any Python app
from msal import ConfidentialClientApplication
```

### Example Use Cases

- Microsoft 365 add-ins
- Enterprise web apps
- Internal tools

---

## Option 5: mTLS (Mutual TLS)

**What it is:** Both client and server present certificates for authentication.

### Flow

```text
1. Client initiates TLS connection
1. Server presents its certificate
1. Client validates server cert (normal TLS)
1. Server requests client certificate
1. Client presents its certificate
1. Server validates client cert → authenticated
```

**Result:** Both parties cryptographically verified

### Pros

- - Strongest authentication (cryptographic proof)
- - No passwords, no tokens
- - Perfect for service-to-service
- - Zero trust friendly
- - Works across clouds
- - Certificate rotation built-in (with automation)

### Cons

- NO Certificate management complexity
- NO Doesn't work in browsers (static frontend)
- NO Requires PKI infrastructure
- NO Cert rotation is manual (without automation)
- NO Not human-friendly (no "login" UI)

### When to Use

- Service-to-service (Flask → API, API → Database)
- Zero trust architectures
- High security requirements (banking, healthcare)
- Cross-cloud communication
- Kubernetes pod-to-pod

### Code Complexity

\*\*\*\* (complex - need PKI)

### Local Testing

WARNING **Difficult** - Need to generate certificates

**Setup:**

1. **Generate CA and certificates:**

```bash
# Create CA
openssl req -x509 -newkey rsa:4096 -nodes \
-keyout ca-key.pem -out ca-cert.pem \
-days 365 -subj "/CN=Local CA"

# Create client certificate
openssl req -newkey rsa:4096 -nodes \
-keyout client-key.pem -out client-req.pem \
-subj "/CN=client"

# Sign with CA
openssl x509 -req -in client-req.pem \
-CA ca-cert.pem -CAkey ca-key.pem \
-CAcreateserial -out client-cert.pem -days 365
```

1. **Configure FastAPI to require client cert:**

```python
import ssl
import uvicorn

ssl_context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
ssl_context.load_cert_chain('server-cert.pem', 'server-key.pem')
ssl_context.load_verify_locations('ca-cert.pem')
ssl_context.verify_mode = ssl.CERT_REQUIRED

uvicorn.run(app, host="0.0.0.0", port=8443, ssl=ssl_context)
```

1. **Test with curl:**

```bash
curl --cert client-cert.pem --key client-key.pem \
--cacert ca-cert.pem \
https://localhost:8443/api/v1/health
```

**Easier option for testing:** Use Cloudflare Tunnel or similar service that handles mTLS.

### Azure Options

- Azure Key Vault for cert storage
- Azure API Management (mTLS support)
- Azure App Gateway (mTLS offloading)
- Service Mesh (Linkerd, Istio)

### Example Use Cases

- Kubernetes pod-to-pod (service mesh)
- Cloudflare Authenticated Origin Pulls
- Banking APIs
- Healthcare systems (HIPAA)

---

## Option 6: Zero Trust Architecture

**What it is:** Never trust, always verify - every request authenticated/authorized.

### Identity-Based (Modern)

```text
User/Service → Identity Provider → Issues short-lived JWT
 ↓
 API Gateway
 ↓ Validates JWT
 API (validates again)
 ↓ Checks permissions
 Data access
```

### Network-Based (Traditional)

```text
Client → API Gateway (mTLS, JWT validation, IP allow-list)
 ↓ Adds internal auth header
 Private Network
 ↓
 API (trusts gateway, validates again for defense in depth)
```

### Tools by Cloud

| Layer | Azure | Cloudflare | Generic |
| ------------ | -------------------------- | --------------------- | ----------------- |
| **Identity** | Azure AD, Managed Identity | Cloudflare Access | Auth0, Okta |
| **Network** | Azure Front Door, APIM | Cloudflare Tunnel | Envoy, Istio |
| **Policy** | Azure Policy | Cloudflare Zero Trust | Open Policy Agent |
| **Secrets** | Azure Key Vault | Cloudflare Workers KV | HashiCorp Vault |

### Multi-Cloud Example

**Scenario:** Frontend on Azure Static Web Apps, API on Cloudflare Workers

**Setup:**

```text
Browser → Azure Static Web App (Azure AD login)
 ↓ Gets JWT from Azure AD
 Cloudflare Worker API
 ↓ Validates Azure AD JWT (checks public keys)
 ↓ Checks permissions in JWT claims
 Returns data
```

**Requirements:**

1. Azure AD issues JWT
1. Cloudflare Worker validates Azure AD public keys
1. Or: Use shared JWT issuer (Auth0, Okta)

**Code (Cloudflare Worker):**

```javascript
// Validate Azure AD JWT in Cloudflare Worker
import { importSPKI, jwtVerify } from "jose";

export default {
 async fetch(request) {
 const token = request.headers.get("Authorization")?.replace("Bearer ", "");

 // Get Azure AD public keys
 const jwks = await fetch(
 "https://login.microsoftonline.com/common/discovery/v2.0/keys"
 );

 // Verify token
 const { payload } = await jwtVerify(token, jwks);

 // Check permissions
 if (!payload.roles.includes("ApiUser")) {
 return new Response("Forbidden", { status: 403 });
 }

 return new Response("OK");
 },
};
```

### Pros

- - Works across clouds
- - Principle of least privilege
- - Audit trail for every request
- - Defense in depth (multiple validation layers)
- - Granular permissions

### Cons

- NO Most complex setup
- NO Multiple moving parts (many failure points)
- NO Higher latency (extra validation hops)
- NO Cost (API Gateway, Auth provider, etc.)

### Code Complexity

**\*** (very complex)

### Local Testing

NO **Difficult** - Need to mock/run multiple services

**Options:**

1. **Use real cloud services** (Azure AD + Cloudflare Workers)
1. **Mock each layer:**

- Identity: Use test JWT with known secret
- Network: Run API gateway locally (Envoy, nginx)
- Policy: Inline validation

### When to Use

- Multi-cloud deployments
- High security requirements
- Compliance needs (audit every request)
- Large organizations with complex policies

---

## Comparison Matrix

| Feature | API Keys | JWT | OAuth/OIDC | Azure AD | mTLS | Zero Trust |
| ------------------------ | -------- | ------- | ---------- | -------- | -------- | ---------- |
| **User Identity** | NO | YES | YES | YES | YES | YES |
| **Stateless** | YES | YES | WARNING | WARNING | YES | YES |
| **Browser-Friendly** | YES | YES | YES | YES | NO | YES |
| **Service-to-Service** | YES | YES | YES | YES | YES | YES |
| **Revocation** | NO | NO | YES | YES | YES | YES |
| **Granular Permissions** | NO | YES | YES | YES | NO | YES |
| **Local Testing** | **\*** | **\*** | \*\*\* | \*\*\*\* | \*\* | \* |
| **Setup Time** | < 1 hour | ~ 1 day | ~ 1 week | ~ 3 days | ~ 1 week | ~ 1 month |
| **Code Complexity** | \* | \*\* | \*\*\* | \*\*\* | \*\*\*\* | **\*** |

---

## Progressive Enhancement Strategy

### Phase 1: No Auth (Current)

- Open API
- Good for development
- No security

### Phase 2: API Keys (Part 8)

- Simple header check
- Environment variable or database
- Feature flag: `AUTH_ENABLED=false`

```python
@app.middleware("http")
async def auth_middleware(request, call_next):
 if not os.getenv("AUTH_ENABLED", "false") == "true":
 return await call_next(request) # Skip auth

 # Check API key
 api_key = request.headers.get("X-API-Key")
 if not api_key or api_key != os.getenv("API_KEY"):
 return JSONResponse({"error": "Unauthorized"}, status_code=401)

 return await call_next(request)
```

### Phase 3: JWT (Part 9)

- Add login endpoint
- Issue JWT tokens
- Feature flag: `AUTH_METHOD=jwt`

```python
AUTH_METHOD = os.getenv("AUTH_METHOD", "none") # none, api_key, jwt

if AUTH_METHOD == "jwt":
 # JWT validation
elif AUTH_METHOD == "api_key":
 # API key validation
else:
 # No auth
```

### Phase 4: Azure AD (Part 10)

- Production-ready
- Feature flag: `AUTH_METHOD=azure_ad`

```python
if AUTH_METHOD == "azure_ad":
 # Validate Azure AD token
elif AUTH_METHOD == "jwt":
 # JWT validation
# ... etc
```

**Result:** Same codebase, different auth methods based on environment.

---

## Recommendations

### For Learning/Demo

**Use:** API Keys → JWT progression

**Why:**

- Easy to understand
- Progressive enhancement
- Works with both frontends
- Local testing is trivial

### For Production (Azure-only)

**Use:** Azure AD + EasyAuth

**Why:**

- Zero code if using EasyAuth
- Enterprise-ready
- MFA, Conditional Access
- Free tier available

### For Public API

**Use:** API Keys + Rate Limiting

**Why:**

- Simple for developers
- Easy to revoke
- Good for usage tracking

### For Multi-Cloud

**Use:** JWT with shared issuer (Auth0)

**Why:**

- Works across clouds
- Not locked to Azure
- Professional auth service

---

## Next Steps

1. **Implement API Keys (Part 8)**

- Simple header validation
- Environment variable for dev
- Database for production

1. **Add JWT (Part 9)**

- Login endpoint
- Token generation
- Token validation

1. **Azure AD integration (Part 10)**

- App registration
- MSAL library
- EasyAuth option

1. **Zero Trust (Optional Part 11)**

- Multi-cloud setup
- Defense in depth
- Advanced topic

---

## Testing Strategy

### Unit Tests

```python
# Test without auth
def test_health_no_auth():
 response = client.get("/api/v1/health")
 assert response.status_code == 200

# Test with API key
def test_health_with_api_key():
 response = client.get(
 "/api/v1/health",
 headers={"X-API-Key": "test-key"}
 )
 assert response.status_code == 200

# Test with JWT
def test_health_with_jwt():
 token = create_test_jwt({"sub": "test@example.com"})
 response = client.get(
 "/api/v1/health",
 headers={"Authorization": f"Bearer {token}"}
 )
 assert response.status_code == 200
```

### Integration Tests

```bash
# API Key
curl -H "X-API-Key: dev-key" http://localhost:7071/api/v1/health

# JWT
TOKEN=$(python -c "from auth import create_token; print(create_token({'sub': 'test'}))")
curl -H "Authorization: Bearer $TOKEN" http://localhost:7071/api/v1/health

# Azure AD
TOKEN=$(az account get-access-token --resource "api://app-id" --query accessToken -o tsv)
curl -H "Authorization: Bearer $TOKEN" http://localhost:7071/api/v1/health
```

---

## Resources

### API Keys

- [FastAPI Security](https://fastapi.tiangolo.com/tutorial/security/)
- [API Key Best Practices (OWASP)](https://cheatsheetseries.owasp.org/cheatsheets/REST_Security_Cheat_Sheet.html)

### JWT

- [JWT.io](https://jwt.io/) - Decode and test JWTs
- [python-jose documentation](https://python-jose.readthedocs.io/)
- [RFC 7519 - JWT](https://datatracker.ietf.org/doc/html/rfc7519)

### OAuth 2.0 / OIDC

- [OAuth 2.0 Simplified](https://www.oauth.com/)
- [OpenID Connect Core](https://openid.net/specs/openid-connect-core-1_0.html)
- [Auth0 Documentation](https://auth0.com/docs)

### Azure AD

- [Microsoft identity platform](https://learn.microsoft.com/en-us/azure/active-directory/develop/)
- [MSAL Python](https://github.com/AzureAD/microsoft-authentication-library-for-python)
- [Azure AD B2C](https://learn.microsoft.com/en-us/azure/active-directory-b2c/)

### mTLS

- [Mutual TLS Overview](https://www.cloudflare.com/learning/access-management/what-is-mutual-tls/)
- [nginx mTLS](https://nginx.org/en/docs/http/ngx_http_ssl_module.html#ssl_verify_client)

### Zero Trust

- [NIST Zero Trust Architecture](https://www.nist.gov/publications/zero-trust-architecture)
- [Cloudflare Zero Trust](https://www.cloudflare.com/zero-trust/)
- [Azure Zero Trust](https://learn.microsoft.com/en-us/security/zero-trust/)
