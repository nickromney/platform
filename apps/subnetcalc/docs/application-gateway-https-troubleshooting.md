# Application Gateway HTTPS Listener - Troubleshooting Guide

This guide covers common issues when adding HTTPS listener to Application Gateway with Key Vault certificate.

## Issue 1: "Certificate could not be retrieved from Key Vault"

**Symptoms:**

- Application Gateway shows unhealthy backend
- Error in Activity Log: "Failed to retrieve certificate from Key Vault"

**Cause:** Managed identity does not have access to Key Vault secret.

**Solution:**

1. Verify managed identity is enabled:

 ```bash
 az network application-gateway show \
 --name "${APPGW_NAME}" \
 --resource-group "${RESOURCE_GROUP}" \
 --query "identity.principalId"
 ```

1. Verify RBAC role assignment:

 ```bash
 IDENTITY_ID=$(az network application-gateway show \
 --name "${APPGW_NAME}" \
 --resource-group "${RESOURCE_GROUP}" \
 --query "identity.principalId" -o tsv)

 az role assignment list \
 --assignee "${IDENTITY_ID}" \
 --all
 ```

1. Re-apply RBAC if missing:

 ```bash
 KV_ID=$(az keyvault show --name "${KEY_VAULT_NAME}" --query "id" -o tsv)

 az role assignment create \
 --assignee "${IDENTITY_ID}" \
 --role "Key Vault Secrets User" \
 --scope "${KV_ID}"
 ```

1. Wait 60 seconds for RBAC propagation, then restart Application Gateway listener.

## Issue 2: Backend Health Shows "Unhealthy" After HTTPS Change

**Symptoms:**

- Backend pool shows "Unhealthy" status
- Frontend HTTPS works but requests fail with 502 Bad Gateway

**Cause 1:** Backend still expects HTTP but listener is HTTPS.

**Solution:**

```bash
# Verify HTTP settings use HTTPS protocol
az network application-gateway http-settings show \
 --gateway-name "${APPGW_NAME}" \
 --resource-group "${RESOURCE_GROUP}" \
 --name appGatewayBackendHttpSettings \
 --query "{protocol: protocol, port: port}"
```

Expected: `{"protocol": "Https", "port": 443}`

**Cause 2:** Custom domain not set in HTTP settings.

**Solution:**

```bash
# Verify host header is set correctly
az network application-gateway http-settings show \
 --gateway-name "${APPGW_NAME}" \
 --resource-group "${RESOURCE_GROUP}" \
 --name appGatewayBackendHttpSettings \
 --query "hostName"
```

Expected: Your custom domain (e.g., `static-swa-private-endpoint.publiccloudexperiments.net`)

## Issue 3: Cloudflare Still Shows Certificate Warning

**Symptoms:**

- Cloudflare SSL/TLS mode set to "Full"
- Browser shows certificate warning when accessing domain

**Cause:** DNS record not proxied through Cloudflare.

**Solution:**

1. Check Cloudflare DNS record:

- Record should have orange cloud (Proxied), not grey cloud (DNS Only)
- A record should point to Application Gateway public IP

1. Verify with dig:

 ```bash
 dig +short ${CUSTOM_DOMAIN}
 ```

 Should return Cloudflare IPs, not Azure public IP directly.

1. Re-enable proxy in Cloudflare dashboard.

## Issue 4: Certificate Expired

**Symptoms:**

- HTTPS connections fail with "certificate expired" error
- Backend health shows "Unhealthy"

**Cause:** Self-signed certificate valid for 365 days has expired.

**Solution:**

1. Regenerate certificate:

 ```bash
 RESOURCE_GROUP="${RESOURCE_GROUP}" \
 FORCE_CERT_REGEN=true \
 ./50-add-https-listener.sh
 ```

1. Verify new certificate is active:

 ```bash
 az keyvault secret show \
 --vault-name "${KEY_VAULT_NAME}" \
 --name "appgw-ssl-cert" \
 --query "attributes.expires"
 ```

## Issue 5: "Multiple Key Vaults Found" Error

**Symptoms:**

- Script exits with error about multiple Key Vaults
- Cannot determine which Key Vault to use

**Solution:**

Specify Key Vault explicitly:

```bash
RESOURCE_GROUP="${RESOURCE_GROUP}" \
KEY_VAULT_NAME="kv-subnet-calc-xxxx" \
./50-add-https-listener.sh
```

## Issue 6: Entra ID Authentication Fails After HTTPS Change

**Symptoms:**

- Login redirects fail
- Entra ID returns "redirect_uri_mismatch" error

**Cause:** Application Gateway not sending correct Host header to backend.

**Solution:**

1. Verify HTTP settings host header:

 ```bash
 az network application-gateway http-settings show \
 --gateway-name "${APPGW_NAME}" \
 --resource-group "${RESOURCE_GROUP}" \
 --name appGatewayBackendHttpSettings \
 --query "hostName"
 ```

1. If incorrect, update to custom domain:

 ```bash
 az network application-gateway http-settings update \
 --gateway-name "${APPGW_NAME}" \
 --resource-group "${RESOURCE_GROUP}" \
 --name appGatewayBackendHttpSettings \
 --host-name "${CUSTOM_DOMAIN}"
 ```

## Diagnostic Commands

### Check Application Gateway Status

```bash
az network application-gateway show \
 --name "${APPGW_NAME}" \
 --resource-group "${RESOURCE_GROUP}" \
 --query "{name: name, provisioningState: provisioningState, operationalState: operationalState}"
```

### Check Backend Health

```bash
az network application-gateway show-backend-health \
 --name "${APPGW_NAME}" \
 --resource-group "${RESOURCE_GROUP}" \
 --query "backendAddressPools[0].backendHttpSettingsCollection[0].servers[0]"
```

### Check Certificate Details

```bash
az keyvault secret show \
 --vault-name "${KEY_VAULT_NAME}" \
 --name "appgw-ssl-cert" \
 --query "{created: attributes.created, expires: attributes.expires, enabled: attributes.enabled}"
```

### Test HTTPS Listener

```bash
PUBLIC_IP=$(az network public-ip show \
 --name pip-agw-${APPGW_NAME} \
 --resource-group "${RESOURCE_GROUP}" \
 --query "ipAddress" -o tsv)

curl -k -v -H "Host: ${CUSTOM_DOMAIN}" https://${PUBLIC_IP}/
```

### View Application Gateway Logs

```bash
az monitor activity-log list \
 --resource-group "${RESOURCE_GROUP}" \
 --resource-id "$(az network application-gateway show --name "${APPGW_NAME}" --resource-group "${RESOURCE_GROUP}" --query id -o tsv)" \
 --offset 1h
```

## Cost Monitoring

**Check Key Vault Operations:**

```bash
az monitor metrics list \
 --resource "$(az keyvault show --name "${KEY_VAULT_NAME}" --query id -o tsv)" \
 --metric "ServiceApiHit" \
 --start-time "$(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S)" \
 --interval PT1H
```

Expected: Very low operations (AppGW retrieves certificate only on startup/update).

## References

- Design Document: `docs/plans/2025-10-30-application-gateway-https-keyvault-design.md`
- Script: `~/Developer/personal/azure-tui/infrastructure/azure/50-add-https-listener.sh`
- Cloudflare SSL Modes: <https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/>
