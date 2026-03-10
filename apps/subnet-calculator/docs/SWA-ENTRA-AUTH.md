# Stack 6: Azure Static Web Apps with Entra ID Authentication

Stack 6 demonstrates Azure Static Web Apps **platform-level authentication** using Microsoft Entra ID (formerly Azure AD).

## Architecture

### Authentication Layer: SWA Platform

- SWA CLI handles all authentication
- No custom auth code in frontend or backend
- Emulated locally, real Entra ID in production

### Frontend: TypeScript + Vite

- Same as local-stack-04 (no custom auth code)
- Access user info via `/.auth/me`
- Login/logout via `/.auth/login/aad` and `/.auth/logout`

### Backend: Azure Function

- `AUTH_METHOD=none` (same as local-stack-04)
- No JWT validation needed
- SWA passes authenticated user via headers

## Key Differences from local-stack-05

| Feature | local-stack-05 (JWT) | local-stack-06 (Entra ID) |
|---------|---------------|-------------------|
| Auth Layer | Application | Platform (SWA) |
| Login Endpoint | `/api/v1/auth/login` | `/.auth/login/aad` |
| Backend Auth | Custom JWT validation | None (SWA handles it) |
| User Management | Custom (test users) | Entra ID directory |
| Deployment | Complex | Simple (just config) |

## How It Works

### 1. User Access

```text
User → /.auth/login/aad → Entra ID → SWA validates → Your App
```

### 2. Protected Routes (staticwebapp.config.json)

```json
{
 "routes": [
 {
 "route": "/api/*",
 "allowedRoles": ["authenticated"]
 }
 ]
}
```

### 3. User Info Available

```javascript
// Frontend can call:
const response = await fetch('/.auth/me')
const user = await response.json()
// Returns: { clientPrincipal: { userId, userRoles, claims } }
```

### 4. Backend Receives Headers

```text
x-ms-client-principal: base64-encoded user info
x-ms-client-principal-id: user ID
x-ms-client-principal-name: user name
```

## Local Development with SWA CLI

The SWA CLI **emulates** Entra ID authentication for local testing:

```bash
npm run swa -- start stack6-entra
# Opens: http://localhost:4282
```

### Emulated Auth Flow

1. Click "Login with Azure AD" (emulated button)
1. SWA CLI shows a fake login screen
1. Enter any email/username (no password needed locally)
1. SWA CLI sets authentication cookies
1. Your app receives the authenticated user

**IMPORTANT LIMITATIONS - Local Development:**

The SWA CLI emulator does NOT fully enforce route protection:

- `staticwebapp.config.json` routes with `allowedRoles` are NOT enforced locally
- You can access <http://localhost:4282> without logging in (even though config requires auth)
- API endpoints MAY enforce auth (backend-level checking)
- This is a **known limitation** of the SWA CLI emulator

**In Production (Azure):**

- Route protection is **fully enforced**
- Accessing protected routes without authentication redirects to Entra ID login
- All rules in `staticwebapp.config.json` are strictly applied
