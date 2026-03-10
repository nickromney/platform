# Keycloak OAuth2/OIDC Local Development Stack

This directory contains configuration for running a complete OAuth2/OIDC authentication stack locally using Keycloak, simulating Azure Entra ID authentication flows before deploying to Azure.

## Overview

**local-stack-11** provides a complete OAuth2/OIDC authentication flow using:

- **Keycloak** (port 8180): Open-source identity provider that simulates Azure Entra ID
- **FastAPI Backend** (port 8081): Azure Function with OIDC token validation
- **React Frontend** (port 3006): SPA with OIDC authentication using oidc-client-ts

## Architecture

```text
┌─────────────┐
│   Browser   │
└──────┬──────┘
       │
       │ 1. Access app
       ▼
┌──────────────────┐
│ React Frontend   │◀──────┐
│ (port 3006)      │       │
└──────┬───────────┘       │ 7. Returns user info
       │                   │
       │ 2. Redirect to login
       ▼                   │
┌──────────────────┐       │
│    Keycloak      │       │
│   (port 8180)    │       │
│  Identity Server │       │
└──────┬───────────┘       │
       │                   │
       │ 3. User logs in   │
       │    (demo / password123)
       │                   │
       │ 4. Returns auth code
       │                   │
       └────────┐          │
                │          │
       5. Exchange code for token
                │          │
                └──────────┘
                │
                │ 6. API request with Bearer token
                ▼
         ┌──────────────┐
         │ FastAPI API  │
         │ (port 8081)  │
         │ Validates    │
         │ OIDC tokens  │
         └──────────────┘
```

## Quick Start

1. **Start the stack:**

   ```bash
   cd subnet-calculator
   podman-compose up keycloak api-fastapi-keycloak frontend-react-keycloak
   ```

2. **Access the application:**
   - React Frontend: <http://localhost:3006>
   - API Documentation: <http://localhost:8081/api/v1/docs>
   - Keycloak Admin: <http://localhost:8180> (admin / admin123)

3. **Test users:**
   - Username: `demo`, Password: `password123`
   - Username: `admin`, Password: `securepass`

## How It Works

### 1. Authentication Flow (Authorization Code + PKCE)

When you access <http://localhost:3006>:

1. React app checks if you're authenticated
2. If not, redirects to Keycloak login page
3. You enter credentials (demo / password123)
4. Keycloak validates and returns authorization code
5. React app exchanges code for access token using PKCE
6. Token is stored securely in browser localStorage
7. React app automatically attaches token to API requests

### 2. API Token Validation

The FastAPI backend validates OIDC tokens by:

1. Extracting Bearer token from Authorization header
2. Fetching Keycloak's public keys (JWKS)
3. Verifying token signature using RSA public key
4. Validating issuer, audience, and expiration
5. Extracting user identity from token claims

## Keycloak Configuration

The realm is pre-configured via `realm-export.json` with:

### Realm: `subnet-calculator`

- **Access Token Lifespan**: 30 minutes
- **SSO Session Idle**: 30 minutes
- **SSO Session Max**: 10 hours

### Clients

#### 1. `frontend-app` (Public Client)

- **Type**: Public (SPA)
- **Protocol**: OpenID Connect
- **Flow**: Authorization Code + PKCE
- **Redirect URIs**: `http://localhost:3006/*`
- **Web Origins**: `http://localhost:3006`
- **Scopes**: openid, profile, email, user_impersonation

#### 2. `api-app` (Bearer Only Client)

- **Type**: Bearer-only (API)
- **Protocol**: OpenID Connect
- **Purpose**: Token validation only
- **Audience**: api-app
- **Access Token Lifespan**: 30 minutes

### Custom Scopes

- **user_impersonation**: Allows frontend to call API on behalf of user
  - Includes audience mapper to add `api-app` to token audience

### Test Users

| Username | Password     | Roles       | Email               |
|----------|--------------|-------------|---------------------|
| demo     | password123  | user        | <demo@example.com>    |
| admin    | securepass   | admin, user | <admin@example.com>   |

## Security Warning

### IMPORTANT: Local development only

The `realm-export.json` file contains:

- Hardcoded passwords (`password123`, `securepass`)
- Pre-configured client secrets
- Permissive security settings (SSL not required, etc.)

**DO NOT use this realm configuration in production environments.**

For production deployments:

1. Use Azure Entra ID (Azure Active Directory) instead of Keycloak
2. Generate strong, unique passwords and store them in Azure Key Vault
3. Enable SSL/TLS (sslRequired: "all")
4. Configure proper CORS origins
5. Use managed identities where possible
6. Implement proper password policies and MFA
7. Regularly rotate client secrets

## Environment Variables

### API (FastAPI)

```bash
AUTH_METHOD=oidc
OIDC_ISSUER=http://keycloak:8080/realms/subnet-calculator
OIDC_AUDIENCE=api-app
OIDC_JWKS_URI=http://keycloak:8080/realms/subnet-calculator/protocol/openid-connect/certs
CORS_ORIGINS=http://localhost:3006
```

### Frontend (React)

```bash
VITE_API_URL=http://localhost:8081
VITE_AUTH_METHOD=oidc
VITE_OIDC_AUTHORITY=http://localhost:3007/realms/subnet-calculator
VITE_OIDC_CLIENT_ID=frontend-app
VITE_OIDC_REDIRECT_URI=http://localhost:3006
```

## Keycloak Admin Console

Access the admin console at <http://localhost:8180>

**Login:** admin / admin123

### Common Admin Tasks

#### View Users

1. Select `subnet-calculator` realm (top-left dropdown)
2. Navigate to Users menu
3. Click "View all users"

#### View Client Configuration

1. Navigate to Clients menu
2. Click on `frontend-app` or `api-app`
3. Review settings, scopes, mappers

#### Add New User

1. Navigate to Users → Add user
2. Fill in username, email, first/last name
3. Save user
4. Go to Credentials tab
5. Set password (uncheck "Temporary")

#### View Token Contents

1. Get an access token from the frontend (browser DevTools → Application → Local Storage)
2. Decode at <https://jwt.io>
3. Review claims: iss, aud, sub, preferred_username, email, scope

## Comparison to Azure Entra ID

This setup simulates Azure Entra ID behavior:

| Feature | Keycloak | Azure Entra ID |
|---------|----------|----------------|
| **Protocol** | OAuth 2.0 / OIDC | OAuth 2.0 / OIDC |
| **Authorization Flow** | Code + PKCE | Code + PKCE |
| **Token Format** | JWT (RS256) | JWT (RS256) |
| **Discovery** | /.well-known/openid-configuration | /.well-known/openid-configuration |
| **Public Keys** | /protocol/openid-connect/certs | /discovery/v2.0/keys |
| **Scopes** | user_impersonation | user_impersonation |
| **Claims** | preferred_username, email, sub | preferred_username, email, oid |
| **Audience Validation** | Client ID in `aud` | API app ID in `aud` |

## Development Workflow

### 1. Test Authentication Flow

```bash
# Start stack
podman-compose up keycloak api-fastapi-keycloak frontend-react-keycloak

# Wait for Keycloak to start (60s)
# Access http://localhost:3006
# Click "Login" button
# Enter: demo / password123
# Should redirect back with user info displayed
```

### 2. Test API Authentication

```bash
# Get access token from browser localStorage
# (DevTools → Application → Local Storage → oidc.user...)

# Test API with token
curl -H "Authorization: Bearer <token>" \
  http://localhost:8081/api/v1/health

# Should return 200 OK with health status
```

### 3. Test Token Expiration

```bash
# Wait 30 minutes or manually expire token in Keycloak admin
# Refresh page in browser
# Should automatically refresh token (if within SSO session)
# OR redirect to login if SSO session expired
```

## Troubleshooting

### Keycloak Not Starting

```bash
# Check logs
podman-compose logs keycloak

# Common issues:
# - Port 8180 already in use
# - Insufficient memory (needs ~512MB)
# - Realm import failed (check realm-export.json syntax)
```

### Frontend Can't Connect to Keycloak

```bash
# Check CORS configuration
# Keycloak must allow http://localhost:3006

# Verify in Keycloak Admin:
# Clients → frontend-app → Web Origins
# Should include: http://localhost:3006
```

### API Token Validation Failing

```bash
# Check API logs
podman-compose logs api-fastapi-keycloak

# Common issues:
# - Wrong issuer URL (should be http://keycloak:8080/realms/subnet-calculator)
# - Wrong audience (should be api-app)
# - Clock skew between containers
```

### Token Has Wrong Audience

```bash
# Verify client scope mapping
# In Keycloak Admin:
# 1. Client Scopes → user_impersonation
# 2. Mappers tab → audience-mapper
# 3. Included Client Audience should be: api-app

# Test token at https://jwt.io
# Check "aud" claim includes "api-app"
```

## Files

- `realm-export.json`: Keycloak realm configuration (clients, users, scopes)
- `README.md`: This file

## Extending

### Add New User

Edit `realm-export.json`:

```json
{
  "username": "newuser",
  "enabled": true,
  "emailVerified": true,
  "email": "newuser@example.com",
  "credentials": [
    {
      "type": "password",
      "value": "newpassword",
      "temporary": false
    }
  ],
  "realmRoles": ["user"]
}
```

### Add New Scope

1. Add to `clientScopes` in `realm-export.json`
2. Map to appropriate client
3. Add protocol mapper if needed

### Change Token Lifespan

Edit `realm-export.json`:

```json
{
  "accessTokenLifespan": 1800,  // 30 minutes in seconds
  "ssoSessionIdleTimeout": 1800,
  "ssoSessionMaxLifespan": 36000
}
```

## Next Steps

After validating locally:

1. Deploy to Azure with Easy Auth V2
2. Configure Entra ID app registrations
3. Update frontend/API to use Azure Entra ID issuer
4. Test delegated permission flows
5. Add managed identity for backend-to-backend calls

## Resources

- [Keycloak Documentation](https://www.keycloak.org/docs/latest/)
- [OIDC Client TS](https://github.com/authts/oidc-client-ts)
- [Azure Entra ID OAuth2](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-auth-code-flow)
- [RFC 7636 - PKCE](https://tools.ietf.org/html/rfc7636)
