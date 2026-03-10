# Security Inspection Guide

This guide shows what an interested security researcher would see when inspecting traffic for each stack using Bruno GUI or browser dev tools.

## How to Inspect Traffic

### Option 1: Bruno GUI (Recommended)

```bash
# Install Bruno
brew install --cask bruno

# Open Bruno and load collection
open -a Bruno
# File > Open Collection > Select: bruno-collections/

# Select environment (top-right): local

# Run requests and inspect:
# - Headers tab (request/response headers)
# - Cookies tab (authentication cookies)
# - Auth tab (authentication configuration)
# - Timeline tab (request/response timing)
```

### Option 2: Browser DevTools

```bash
# Open DevTools (F12 or Cmd+Option+I)
# Network tab > Select request > Headers/Cookies/Preview
```

### Option 3: curl verbose

```bash
# See all headers
curl -v http://localhost:4280/api/v1/health 2>&1 | grep -E '^(<|>)'
```

---

## Stack 4: No Authentication

### What You See

**Request:**

```http
GET /api/v1/health HTTP/1.1
Host: localhost:4280
Accept: application/json
```

**Response:**

```http
HTTP/1.1 200 OK
Content-Type: application/json

{"status":"healthy","service":"Subnet Calculator API (Azure Function)","version":"1.0.0"}
```

### Security Observations

- **No authentication headers** - Anyone can call the API
- **No cookies** - Stateless, no session
- **No authorization** - All endpoints publicly accessible
- **Clear text** - All data visible (use HTTPS in production)

### What a Researcher Can Do

- Call any endpoint without credentials
- Enumerate all API endpoints via /api/v1/docs
- See all request/response data
- No rate limiting (in this implementation)

### When This is Acceptable

- Public APIs (weather, public data)
- Internal microservices behind API gateway
- Development/testing environments

---

## Stack 5: JWT Authentication

### What You See

**Login Request:**

```http
POST /api/v1/auth/login HTTP/1.1
Host: localhost:4281
Content-Type: application/json

{"username":"demo","password":"password123"}
```

**Login Response:**

```http
HTTP/1.1 200 OK
Content-Type: application/json

{
 "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJkZW1vIiwiZXhwIjoxNzA...",
 "token_type": "bearer"
}
```

**Authenticated Request:**

```http
GET /api/v1/health HTTP/1.1
Host: localhost:4281
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJkZW1vIiwiZXhwIjoxNzA...
```

### Security Observations

- **JWT token in Authorization header** - Visible in plain text
- **Token is base64 encoded** - Anyone can decode it (jwt.io)
- **Token contains claims** - Username, expiry, issued-at time visible
- **Token is signed** - Can't modify without secret key
- **Credentials in clear text** - Username/password sent without encryption (use HTTPS!)

### Decode the JWT Token

```bash
# Extract payload (middle section between dots)
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJkZW1vIiwiZXhwIjoxNzA..."
echo $TOKEN | cut -d. -f2 | base64 -d 2>/dev/null | jq

# Output:
{
 "sub": "demo",
 "exp": 1707123456,
 "iat": 1707119856
}
```

### What a Researcher Can Do

- **Intercept token** - Copy Authorization header, use it elsewhere
- **Decode token** - See user info, expiry time
- **Replay attacks** - Use stolen token until expiry (1 hour default)
- **Brute force login** - Try common passwords (no rate limiting in this implementation)
- **Cannot forge tokens** - Needs secret key to sign

### What a Researcher Cannot Do

- **Modify token** - Signature validation will fail
- **Create new tokens** - Needs JWT_SECRET_KEY (server-side only)
- **Extend expiry** - Re-signing requires secret key

### Security Recommendations

- **Use HTTPS** - Encrypt Authorization header in transit
- **Short expiry** - Default 1 hour, consider shorter
- **Refresh tokens** - Separate long-lived refresh token
- **Rate limiting** - Prevent brute force login attempts
- **Token rotation** - Invalidate old tokens on refresh

---

## Stack 6: Entra ID (Platform Authentication)

**IMPORTANT - Local Development Limitation:**

The SWA CLI emulator does NOT enforce route protection locally. You can access <http://localhost:4282> without logging in, even though `staticwebapp.config.json` requires authentication. This is a known limitation (see: <https://github.com/Azure/static-web-apps-cli/issues/630>).

In **production Azure**, route protection IS enforced - accessing the app will redirect to login.

### What You See

**Check Auth Status:**

```http
GET /.auth/me HTTP/1.1
Host: localhost:4282
```

**Response (Not Authenticated):**

```http
HTTP/1.1 200 OK
Content-Type: application/json

{"clientPrincipal":null}
```

**Response (Authenticated):**

```http
HTTP/1.1 200 OK
Content-Type: application/json
Set-Cookie: StaticWebAppsAuthCookie=<opaque-value>; HttpOnly; SameSite=Lax

{
 "clientPrincipal": {
 "userId": "demo@example.com",
 "userRoles": ["authenticated"],
 "claims": [...]
 }
}
```

**Authenticated Request:**

```http
GET /api/v1/health HTTP/1.1
Host: localhost:4282
Cookie: StaticWebAppsAuthCookie=<opaque-value>
```

### Security Observations

- **No Authorization header** - Cookie-based authentication
- **Opaque cookie** - Not a JWT, can't decode it
- **HttpOnly cookie** - JavaScript can't access it (XSS protection)
- **SameSite cookie** - CSRF protection
- **Platform-managed** - SWA validates, not your backend

### What You DON'T See (Backend Receives)

SWA injects headers to the backend (not visible in browser):

```http
x-ms-client-principal: eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6...
x-ms-client-principal-id: demo@example.com
x-ms-client-principal-name: Demo User
```

**Key point:** These headers are added by SWA platform, not the client. Client cannot forge them.

### What a Researcher Can Do

- **Intercept cookie** - Copy cookie, use in another browser/tool
- **Check auth status** - Call /.auth/me to see user info
- **Replay attacks** - Use stolen cookie until expiry

### What a Researcher Cannot Do

- **Decode cookie** - It's opaque, not base64/JWT
- **Forge headers** - x-ms-client-principal* headers added by SWA, not client
- **Bypass platform auth** - SWA validates before reaching backend
- **Access cookie from JavaScript** - HttpOnly flag prevents it

### Security Advantages over Stack 5

| Feature | Stack 5 (JWT) | Stack 6 (Entra ID) |
|---------|---------------|-------------------|
| **Token visibility** | Visible in Authorization header | Opaque cookie |
| **Token decoding** | Anyone can decode JWT | Cannot decode cookie |
| **XSS protection** | JavaScript can access token | HttpOnly cookie blocks JS |
| **CSRF protection** | Must implement manually | SameSite cookie automatic |
| **Backend trust** | Backend validates JWT | Backend trusts SWA headers |
| **User management** | Custom (database/file) | Azure AD/Entra ID |
| **Token refresh** | Custom implementation | Automatic by platform |

### Security Model

**Stack 5 (Application-Level):**

```text
Browser → API → Validates JWT → Returns data
 ↑
 Backend must validate every request
```

**Stack 6 (Platform-Level):**

```text
Browser → SWA → Validates auth → Injects headers → API → Trusts SWA → Returns data
 ↑
 Single validation point
```

### Production Differences

**Local (SWA CLI):**

- Emulated authentication (any email works)
- No real Azure AD
- For development only

**Production (Azure):**

- Real Azure AD/Entra ID
- OAuth 2.0 / OpenID Connect
- Signed tokens from Microsoft
- Proper user directory

---

## Comparison Matrix

| Observable Behavior | Stack 4 (No Auth) | Stack 5 (JWT) | Stack 6 (Entra ID) |
|---------------------|-------------------|---------------|-------------------|
| **Authentication header** | None | `Authorization: Bearer <JWT>` | None (cookie-based) |
| **Cookies** | None | None | `StaticWebAppsAuthCookie` |
| **Token visible** | N/A | Yes (base64 encoded) | No (opaque) |
| **Can decode token** | N/A | Yes (jwt.io) | No |
| **XSS risk** | N/A | High (JS can access) | Low (HttpOnly) |
| **CSRF risk** | N/A | Medium (no state) | Low (SameSite) |
| **Replay attacks** | N/A | Until token expiry | Until cookie expiry |
| **Backend validation** | None | JWT signature | None (trusts SWA) |

---

## Inspection Checklist

Use this checklist when inspecting each stack with Bruno GUI:

### Stack 4

- [ ] No Authorization header
- [ ] No cookies
- [ ] All endpoints return 200 OK
- [ ] No authentication required

### Stack 5

- [ ] Login request contains username/password
- [ ] Login response contains JWT token
- [ ] JWT token in Authorization: Bearer header
- [ ] Can decode JWT with jwt.io
- [ ] Protected endpoints return 401 without token
- [ ] Protected endpoints return 200 with valid token

### Stack 6

- [ ] /.auth/me endpoint available (SWA platform)
- [ ] No Authorization header
- [ ] StaticWebAppsAuthCookie cookie present after login
- [ ] Cookie is HttpOnly (not visible in document.cookie)
- [ ] Cookie is SameSite=Lax
- [ ] Cannot decode cookie (opaque)
- [ ] Protected endpoints return 401/redirect without cookie
- [ ] Protected endpoints return 200 with valid cookie

---

## Recommended Tools

### Burp Suite (Professional Security Testing)

- Intercept and modify requests
- Automated vulnerability scanning
- Token manipulation testing

### Bruno GUI (Developer-Friendly)

- Clear visualization of headers/cookies
- Built-in environment variables
- Scripting and testing
- No account required (unlike Postman)

### Browser DevTools (Quick Inspection)

- Network tab for request/response
- Application tab for cookies
- Console for JavaScript debugging

### curl (Command Line)

```bash
# Stack 4 - No auth
curl -v http://localhost:4280/api/v1/health

# Stack 5 - JWT auth
TOKEN=$(curl -s -X POST http://localhost:4281/api/v1/auth/login \
 -H "Content-Type: application/json" \
 -d '{"username":"demo","password":"password123"}' | jq -r '.access_token')
curl -v -H "Authorization: Bearer $TOKEN" http://localhost:4281/api/v1/health

# Stack 6 - Cookie auth
curl -v -c cookies.txt http://localhost:4282/.auth/me
curl -v -b cookies.txt http://localhost:4282/api/v1/health
```

---

## Next Steps

1. **Start a stack:** `make start-stack4` (or stack5/stack6)
1. **Open Bruno GUI:** Load `bruno-collections/`
1. **Select environment:** Choose "local" from dropdown (top-right)
1. **Run requests:** Click through each request in the collection
1. **Inspect traffic:** Check Headers, Cookies, Auth, Timeline tabs
1. **Compare stacks:** Run different stacks and compare security models

For automated testing, use:

- `make test-bruno-stack4` - Tests Stack 4 only
- `make test-bruno-stack5` - Tests Stack 5 only
- `make test-bruno-stack6` - Tests Stack 6 only (unauthenticated)
