# Stack 1: Public SWA + JWT Auth Function App

## Overview

Stack 1 demonstrates a public Azure Static Web App calling a public Azure Function App with JWT (JSON Web Token) authentication. This architecture is suitable for demos, teaching JWT patterns, and public APIs where credentials are not highly sensitive.

## Architecture

```text
┌─────────────────────────────────────┐
│ User → Public Internet │
└──────────────┬──────────────────────┘
 │
┌──────────────▼──────────────────────┐
│ Azure Static Web App (Free/Std) │
│ - TypeScript Vite SPA │
│ - NO authentication on SWA │
│ - Calls Function via public URL │
└──────────────┬──────────────────────┘
 │ HTTPS (public internet)
┌──────────────▼──────────────────────┐
│ Azure Function App (Consumption) │
│ - Public endpoint │
│ - JWT authentication (Bearer token) │
│ - Custom domain enabled │
└─────────────────────────────────────┘
```

## Components

| Component | Details |
|-----------|---------|
| **Frontend** | TypeScript Vite SPA |
| **Backend** | Azure Function App (Consumption plan) |
| **Authentication** | JWT (credentials embedded in frontend) |
| **Security** | JWT validation on backend |
| **Cost** | ~$9/month (SWA Standard required for custom domains) |

## Custom Domains

- **SWA**: `https://static-swa-no-auth.publiccloudexperiments.net`
- **Function App**: `https://subnet-calc-fa-jwt-auth.publiccloudexperiments.net`

## Deployment

### Prerequisites

1. **DNS Access**: Ability to create CNAME records for both custom domains
1. **Azure Subscription**: Active subscription with permissions to create resources
1. **Tools**: Azure CLI, npm, jq, openssl

### Quick Deploy

```bash
cd ~/Developer/personal/azure-tui/infrastructure/azure
./azure-stack-14-swa-noauth-jwt.sh
```

### Manual Steps During Deployment

The script will pause twice for DNS configuration:

1. **SWA Custom Domain**:

 ```text
 static-swa-no-auth.publiccloudexperiments.net → CNAME → <app-name>.azurestaticapps.net
 ```

1. **Function Custom Domain**:

 ```text
 subnet-calc-fa-jwt-auth.publiccloudexperiments.net → CNAME → <func-name>.azurewebsites.net
 ```

### Environment Variables (Optional)

```bash
# Override defaults
export RESOURCE_GROUP="rg-my-project"
export LOCATION="eastus"
export SWA_CUSTOM_DOMAIN="my-swa.example.com"
export FUNC_CUSTOM_DOMAIN="my-api.example.com"
export JWT_USERNAME="admin"
export JWT_PASSWORD="securepassword"

# Run deployment
./azure-stack-14-swa-noauth-jwt.sh
```

## Authentication Flow

### 1. User visits SWA

```text
https://static-swa-no-auth.publiccloudexperiments.net
```

### 2. Frontend prompts for credentials

- Username: `demo` (default)
- Password: `demo-password` (default)

### 3. Frontend calls `/api/v1/auth/login`

```http
POST https://subnet-calc-fa-jwt-auth.publiccloudexperiments.net/api/v1/auth/login
Content-Type: application/x-www-form-urlencoded

username=demo&password=demo-password
```

### 4. Function validates credentials and returns JWT

```json
{
 "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
 "token_type": "bearer"
}
```

### 5. Frontend stores token and uses for subsequent requests

```http
GET https://subnet-calc-fa-jwt-auth.publiccloudexperiments.net/api/v1/ipv4/validate?address=192.168.1.1
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

## Testing

### 1. Test SWA Access

```bash
curl https://static-swa-no-auth.publiccloudexperiments.net
# Should return HTML
```

### 2. Test Function Health (No Auth Required)

```bash
curl https://subnet-calc-fa-jwt-auth.publiccloudexperiments.net/api/v1/health
# Should return: {"status": "healthy"}
```

### 3. Test JWT Login

```bash
curl -X POST https://subnet-calc-fa-jwt-auth.publiccloudexperiments.net/api/v1/auth/login \
 -H "Content-Type: application/x-www-form-urlencoded" \
 -d "username=demo&password=demo-password"

# Should return JWT token
```

### 4. Test API with JWT

```bash
TOKEN="<token-from-login>"

curl https://subnet-calc-fa-jwt-auth.publiccloudexperiments.net/api/v1/ipv4/validate?address=192.168.1.1 \
 -H "Authorization: Bearer ${TOKEN}"

# Should return validation result
```

### 5. Test API without JWT (Should Fail)

```bash
curl https://subnet-calc-fa-jwt-auth.publiccloudexperiments.net/api/v1/ipv4/validate?address=192.168.1.1

# Should return 401 Unauthorized
```

## Security Considerations

### Strengths

- JWT validation on backend prevents unauthorized access
- Argon2 password hashing (not plaintext)
- HTTPS for all communication
- Token expiration (30 minutes default)
- CORS configured to SWA domain

### Limitations

- **Credentials visible in frontend build** - JWT username/password embedded in JavaScript bundle
- **Not suitable for production secrets** - Anyone can inspect browser DevTools
- **Both endpoints publicly accessible** - Function can be called from anywhere
- **No refresh token mechanism** - User must re-login after 30 minutes

### When to Use

**Good for:**

- Demos and teaching JWT authentication
- Public APIs where credentials are shared
- Development/testing environments
- Non-sensitive data

**NOT suitable for:**

- Production applications with sensitive data
- Applications requiring user-specific authentication
- Compliance requirements (SOC2, HIPAA, etc.)

## Configuration Files

### staticwebapp-noauth.config.json

```json
{
 "routes": [
 {
 "route": "/*",
 "allowedRoles": ["anonymous"]
 }
 ],
 "navigationFallback": {
 "rewrite": "/index.html"
 }
}
```

- No authentication at SWA level
- All routes allow anonymous access
- SPA routing enabled

### Function App Settings

```bash
AUTH_METHOD=jwt
JWT_SECRET_KEY=<32+ character secret>
JWT_ALGORITHM=HS256
JWT_ACCESS_TOKEN_EXPIRE_MINUTES=30
JWT_TEST_USERS={"demo": "$argon2_hash"}
CORS_ORIGINS=https://static-swa-no-auth.publiccloudexperiments.net
```

## Troubleshooting

### Issue: 401 Unauthorized on API calls

**Cause**: JWT token missing or expired

**Solution**:

1. Check token in browser localStorage
1. Verify token not expired (check `exp` claim)
1. Re-login to get fresh token

### Issue: CORS error

**Cause**: Function App CORS not configured for SWA domain

**Solution**:

```bash
az functionapp config appsettings set \
 --name func-subnet-calc-jwt \
 --resource-group rg-subnet-calc \
 --settings CORS_ORIGINS=https://static-swa-no-auth.publiccloudexperiments.net
```

### Issue: Custom domain not working

**Cause**: DNS not propagated or TLS certificate not issued

**Solution**:

1. Verify DNS record:

 ```bash
 nslookup static-swa-no-auth.publiccloudexperiments.net
 ```

1. Wait for TLS certificate (can take 5-10 minutes)
1. Check Azure Portal for validation status

### Issue: Function returns 500 Internal Server Error

**Cause**: JWT_SECRET_KEY not set or too short

**Solution**:

```bash
# Generate new secret
JWT_SECRET=$(openssl rand -base64 32)

# Update Function App
az functionapp config appsettings set \
 --name func-subnet-calc-jwt \
 --resource-group rg-subnet-calc \
 --settings JWT_SECRET_KEY="${JWT_SECRET}"
```

## Cost Breakdown

| Resource | SKU | Monthly Cost |
|----------|-----|--------------|
| Static Web App | Standard | $9 (required for custom domains) |
| Function App | Consumption | ~$0 (free tier: 1M requests, 400K GB-s) |
| **Total** | | **~$9/month** |

**Note**: Standard tier SWA is required for custom domains. Free tier only supports *.azurestaticapps.net domains.

## Cleanup

```bash
# Delete all resources
az group delete --name rg-subnet-calc --yes --no-wait
```

OR delete individual resources:

```bash
# Delete SWA
az staticwebapp delete --name swa-subnet-calc-noauth --yes

# Delete Function App
az functionapp delete --name func-subnet-calc-jwt --resource-group rg-subnet-calc
```

## Next Steps

- **Stack 2**: Learn about Entra ID authentication with linked backends
- **Stack 3**: Explore private endpoints and network isolation

## References

- [Azure Static Web Apps Documentation](https://learn.microsoft.com/en-us/azure/static-web-apps/)
- [Azure Functions Documentation](https://learn.microsoft.com/en-us/azure/azure-functions/)
- [JWT.io](https://jwt.io/) - JWT decoder and documentation
- [Argon2 Password Hashing](https://github.com/P-H-C/phc-winner-argon2)
