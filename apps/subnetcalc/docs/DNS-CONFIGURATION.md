# DNS Configuration Guide

Complete guide for configuring DNS for all subnet calculator stacks using Cloudflare.

## Overview

This guide covers DNS configuration for 6 production deployments:

| Subdomain | Type | Target | Stack |
|-----------|------|--------|-------|
| `static` | CNAME | Azure Storage | Storage Static Website |
| `flask` | CNAME | App Service | Flask App Service |
| `noauth` | CNAME | Static Web App | SWA TypeScript (No Auth) |
| `jwt` | CNAME | Static Web App | SWA TypeScript (JWT) |
| `entraid` | CNAME | Static Web App | SWA TypeScript (Entra ID) |

**Base Domain**: `publiccloudexperiments.net` (configurable)

## Prerequisites

- Domain registered and managed in Cloudflare
- Azure resources deployed (see [PRODUCTION-DEPLOYMENT.md](./PRODUCTION-DEPLOYMENT.md))
- Azure CLI access to get target URLs

## Getting Target URLs

### Storage Static Website

```bash
STORAGE_ACCOUNT_NAME="<your-storage-account>"
RESOURCE_GROUP="<your-resource-group>"

az storage account show \
 --name ${STORAGE_ACCOUNT_NAME} \
 --resource-group ${RESOURCE_GROUP} \
 --query "primaryEndpoints.web" -o tsv
```

**Example Output**: `https://stsubnetcalc123.z33.web.core.windows.net/`

**DNS Target**: `stsubnetcalc123.z33.web.core.windows.net` (remove `https://` and trailing `/`)

### Static Web Apps

```bash
SWA_NAME="swa-subnet-calc-noauth" # or jwt, entraid
RESOURCE_GROUP="<your-resource-group>"

az staticwebapp show \
 --name ${SWA_NAME} \
 --resource-group ${RESOURCE_GROUP} \
 --query defaultHostname -o tsv
```

**Example Output**: `happy-rock-0a1b2c3d4.uksouth.2.azurestaticapps.net`

**DNS Target**: Use as-is

### App Service (Flask)

```bash
APP_SERVICE_NAME="app-flask-subnet-calc"
RESOURCE_GROUP="<your-resource-group>"

az webapp show \
 --name ${APP_SERVICE_NAME} \
 --resource-group ${RESOURCE_GROUP} \
 --query defaultHostName -o tsv
```

**Example Output**: `app-flask-subnet-calc.azurewebsites.net`

**DNS Target**: Use as-is

## Cloudflare DNS Configuration

### Method 1: Cloudflare Dashboard (Manual)

#### 1. Login to Cloudflare

1. Navigate to <https://dash.cloudflare.com>
1. Select your domain (`publiccloudexperiments.net`)
1. Go to **DNS** → **Records**

#### 2. Add CNAME Records

For each stack, add a CNAME record:

**Static Website (Storage)**:

- **Type**: CNAME
- **Name**: static
- **Target**: `stsubnetcalc123.z33.web.core.windows.net`
- **Proxy status**: DNS only (grey cloud)
- **TTL**: Auto

**SWA No Auth**:

- **Type**: CNAME
- **Name**: noauth
- **Target**: `happy-rock-0a1b2c3d4.uksouth.2.azurestaticapps.net`
- **Proxy status**: DNS only (grey cloud)
- **TTL**: Auto

**SWA JWT**:

- **Type**: CNAME
- **Name**: jwt
- **Target**: `brave-tree-0e1f2g3h4.uksouth.2.azurestaticapps.net`
- **Proxy status**: DNS only (grey cloud)
- **TTL**: Auto

**SWA Entra ID**:

- **Type**: CNAME
- **Name**: entraid
- **Target**: `kind-field-0i1j2k3l4.uksouth.2.azurestaticapps.net`
- **Proxy status**: DNS only (grey cloud)
- **TTL**: Auto

**Flask App Service**:

- **Type**: CNAME
- **Name**: flask
- **Target**: `app-flask-subnet-calc.azurewebsites.net`
- **Proxy status**: DNS only (grey cloud)
- **TTL**: Auto

#### 3. Important Settings

**Proxy Status**: MUST be "DNS only" (grey cloud icon)

- Proxied (orange cloud): Cloudflare proxies traffic, Azure SSL validation will fail
- DNS only (grey cloud): Direct connection, Azure handles SSL

**SSL/TLS Mode**:

1. Go to **SSL/TLS** → **Overview**
1. Set encryption mode to: **Full** (not Full Strict)
1. Enable "Always Use HTTPS"

### Method 2: Cloudflare API (Automated)

#### Prerequisites

```bash
# Get Cloudflare API token
# Dashboard → Profile → API Tokens → Create Token
# Use "Edit zone DNS" template

export CF_API_TOKEN="your-token-here"
export CF_ZONE_ID="your-zone-id" # Found on domain overview page
export CUSTOM_DOMAIN="publiccloudexperiments.net"
```

#### Add CNAME Records via API

```bash
# Function to add CNAME record
add_cname() {
 local subdomain=$1
 local target=$2

 curl -X POST "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records" \
 -H "Authorization: Bearer ${CF_API_TOKEN}" \
 -H "Content-Type: application/json" \
 --data '{
 "type": "CNAME",
 "name": "'${subdomain}'",
 "content": "'${target}'",
 "ttl": 1,
 "proxied": false
 }'
}

# Add all records
add_cname "static" "stsubnetcalc123.z33.web.core.windows.net"
add_cname "noauth" "happy-rock-0a1b2c3d4.uksouth.2.azurestaticapps.net"
add_cname "jwt" "brave-tree-0e1f2g3h4.uksouth.2.azurestaticapps.net"
add_cname "entraid" "kind-field-0i1j2k3l4.uksouth.2.azurestaticapps.net"
add_cname "flask" "app-flask-subnet-calc.azurewebsites.net"
```

## Azure Custom Domain Configuration

After DNS records are added and propagated, configure Azure to recognize the custom domains.

### Storage Static Website

```bash
STORAGE_ACCOUNT_NAME="<your-storage-account>"
RESOURCE_GROUP="<your-resource-group>"
CUSTOM_DOMAIN="publiccloudexperiments.net"

# Add custom domain
az storage account update \
 --name ${STORAGE_ACCOUNT_NAME} \
 --resource-group ${RESOURCE_GROUP} \
 --custom-domain static.${CUSTOM_DOMAIN}
```

**Note**: Storage accounts don't support HTTPS on custom domains without CDN.

**Options**:

1. Use HTTP only: `http://static.publiccloudexperiments.net`
1. Add Azure CDN for HTTPS support (additional cost)
1. Use Cloudflare proxy (orange cloud) for free SSL

### Static Web Apps

```bash
STATIC_WEB_APP_NAME="swa-subnet-calc-noauth"
RESOURCE_GROUP="<your-resource-group>"
CUSTOM_DOMAIN="publiccloudexperiments.net"
SUBDOMAIN="noauth"

# Add custom hostname
az staticwebapp hostname set \
 --name ${STATIC_WEB_APP_NAME} \
 --resource-group ${RESOURCE_GROUP} \
 --hostname ${SUBDOMAIN}.${CUSTOM_DOMAIN}
```

**Repeat for each SWA**:

```bash
# JWT
az staticwebapp hostname set \
 --name swa-subnet-calc-jwt \
 --resource-group ${RESOURCE_GROUP} \
 --hostname jwt.${CUSTOM_DOMAIN}

# Entra ID
az staticwebapp hostname set \
 --name swa-subnet-calc-entraid \
 --resource-group ${RESOURCE_GROUP} \
 --hostname entraid.${CUSTOM_DOMAIN}
```

**Automatic SSL**: Azure automatically provisions free SSL certificates (5-10 minutes).

### App Service (Flask)

```bash
APP_SERVICE_NAME="app-flask-subnet-calc"
RESOURCE_GROUP="<your-resource-group>"
CUSTOM_DOMAIN="publiccloudexperiments.net"
SUBDOMAIN="flask"

# Add custom hostname
az webapp config hostname add \
 --webapp-name ${APP_SERVICE_NAME} \
 --resource-group ${RESOURCE_GROUP} \
 --hostname ${SUBDOMAIN}.${CUSTOM_DOMAIN}

# Create and bind managed certificate
az webapp config ssl create \
 --resource-group ${RESOURCE_GROUP} \
 --name ${APP_SERVICE_NAME} \
 --hostname ${SUBDOMAIN}.${CUSTOM_DOMAIN}

az webapp config ssl bind \
 --resource-group ${RESOURCE_GROUP} \
 --name ${APP_SERVICE_NAME} \
 --certificate-thumbprint $(az webapp config ssl list \
 --resource-group ${RESOURCE_GROUP} \
 --query "[0].thumbprint" -o tsv) \
 --ssl-type SNI
```

## Verification

### DNS Propagation Check

```bash
# Check DNS resolution
dig static.publiccloudexperiments.net
dig noauth.publiccloudexperiments.net
dig jwt.publiccloudexperiments.net
dig entraid.publiccloudexperiments.net
dig flask.publiccloudexperiments.net

# Check against Cloudflare nameservers
dig @1.1.1.1 noauth.publiccloudexperiments.net

# Check from multiple locations
https://dnschecker.org/#CNAME/noauth.publiccloudexperiments.net
```

**Expected Result**: CNAME pointing to Azure target

### SSL Certificate Check

```bash
# Check SSL certificate
curl -vI https://noauth.publiccloudexperiments.net 2>&1 | grep -i "subject:"

# Check certificate expiration
echo | openssl s_client -servername noauth.publiccloudexperiments.net \
 -connect noauth.publiccloudexperiments.net:443 2>/dev/null | \
 openssl x509 -noout -dates
```

### HTTP Access Check

```bash
# Test all endpoints
curl -I https://static.publiccloudexperiments.net # or http://
curl -I https://noauth.publiccloudexperiments.net
curl -I https://jwt.publiccloudexperiments.net
curl -I https://entraid.publiccloudexperiments.net
curl -I https://flask.publiccloudexperiments.net
```

**Expected Result**: HTTP 200 or 301/302 redirect

## Troubleshooting

### DNS Not Resolving

**Symptom**: `dig` returns NXDOMAIN or no results

**Solutions**:

1. Wait 5-10 minutes for propagation
1. Verify record was created in Cloudflare
1. Check Cloudflare nameservers are set on domain registrar
1. Clear local DNS cache: `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder` (macOS)

### SSL Certificate Errors

**Symptom**: Browser shows "Your connection is not private" or `curl` shows certificate errors

**Cause 1**: Cloudflare proxy enabled (orange cloud)

**Solution**: Set to "DNS only" (grey cloud)

**Cause 2**: Certificate not yet provisioned

**Solution**: Wait 5-10 minutes for Azure to provision certificate

**Cause 3**: SSL/TLS mode incorrect in Cloudflare

**Solution**: Set to "Full" (not "Flexible" or "Full Strict")

### Azure Custom Domain Validation Failed

**Symptom**: Error when running `az staticwebapp hostname set`

**Causes**:

1. DNS not propagated yet → Wait and retry
1. CNAME record incorrect → Verify in Cloudflare
1. Cloudflare proxy enabled → Disable proxy (grey cloud)

**Verification**:

```bash
# Check what Azure sees
nslookup noauth.publiccloudexperiments.net 8.8.8.8
```

### Cloudflare Proxy Issues

**When to use Cloudflare Proxy (orange cloud)**:

- Storage static website (for HTTPS support)
- Additional DDoS protection needed
- CDN caching desired

**When NOT to use Cloudflare Proxy**:

- Azure Static Web Apps (breaks custom domain validation)
- App Service (breaks SSL certificate validation)
- Any service requiring direct Azure connection

## Advanced Configuration

### Subpath Routing

Use Cloudflare Workers for advanced routing:

```javascript
// Route /api/* to Function App, everything else to SWA
addEventListener('fetch', event => {
 event.respondWith(handleRequest(event.request))
})

async function handleRequest(request) {
 const url = new URL(request.url)

 if (url.pathname.startsWith('/api/')) {
 return fetch('https://func-subnet-calc.azurewebsites.net' + url.pathname)
 }

 return fetch('https://noauth-swa.azurestaticapps.net' + url.pathname)
}
```

### Redirect Rules

Cloudflare Page Rules for redirects:

1. Go to **Rules** → **Page Rules**
1. Create rule:

- URL: `publiccloudexperiments.net/*`
- Setting: Forwarding URL (301)
- Destination: `https://noauth.publiccloudexperiments.net/$1`

### Health Check Monitoring

Cloudflare Health Checks (Business plan required):

1. Go to **Traffic** → **Health Checks**
1. Create monitor for each endpoint
1. Set up email/webhook notifications

## Cost Implications

### Cloudflare

- **Free Plan**: Sufficient for this use case
- DNS hosting: Free
- SSL certificates: Free
- Proxy (if used): Free (up to bandwidth limits)

### Azure

- **Storage custom domain**: Free (HTTP only, no SSL)
- **SWA custom domain**: Free (includes SSL)
- **App Service custom domain**: Free (includes managed SSL)

## References

- [Cloudflare DNS Documentation](https://developers.cloudflare.com/dns/)
- [Cloudflare API Documentation](https://developers.cloudflare.com/api/)
- [Azure Static Web Apps Custom Domains](https://docs.microsoft.com/azure/static-web-apps/custom-domain)
- [Azure App Service Custom Domains](https://docs.microsoft.com/azure/app-service/app-service-web-tutorial-custom-domain)
- [Azure Storage Custom Domains](https://docs.microsoft.com/azure/storage/blobs/storage-custom-domain-name)
