# Application Gateway Troubleshooting Guide

## Backend Health: Unhealthy

### Check 1: Verify DNS Resolution

From a VM in the VNet:

```bash
nslookup delightful-field-0cd326e03.privatelink.3.azurestaticapps.net
```

Should resolve to: 10.100.0.21

If not resolving:

- Check private DNS zone exists: privatelink.3.azurestaticapps.net
- Check VNet link is configured
- Check DNS zone group is configured on private endpoint

### Check 2: Verify Private Endpoint

```bash
az network private-endpoint show \
 --name pe-swa-subnet-calc-private-endpoint \
 --resource-group rg-subnet-calc \
 --query "{ProvisioningState:provisioningState, PrivateIP:customDnsConfigs[0].ipAddresses[0]}"
```

Should show: ProvisioningState: Succeeded

### Check 3: Verify NSG Rules

Application Gateway subnet needs to allow outbound to SWA private endpoint subnet:

```bash
# Check if NSGs are blocking traffic
az network vnet subnet show \
 --name snet-appgateway \
 --vnet-name vnet-subnet-calc-private \
 --resource-group rg-subnet-calc \
 --query "networkSecurityGroup"
```

If NSG is attached, verify outbound rules allow HTTPS (443) to 10.100.0.16/28

## Backend Health: Takes Long Time

Application Gateway probes can take 60-120 seconds to stabilize. Wait 2-3 minutes after creation.

## HTTP 502 Bad Gateway

This means Application Gateway can't reach backend. Check:

1. Backend pool has correct FQDN
1. Private DNS zone resolves correctly
1. SWA private endpoint is healthy
1. HTTP settings use correct Host header

## Entra ID Authentication Fails

### Check 1: Host Header

Verify HTTP settings use custom domain:

```bash
az network application-gateway http-settings show \
 --gateway-name agw-swa-subnet-calc-private-endpoint \
 --resource-group rg-subnet-calc \
 --name appGatewayBackendHttpSettings \
 --query "hostName" -o tsv
```

Should return: static-swa-private-endpoint.publiccloudexperiments.net

### Check 2: Redirect URIs

Verify Entra ID app has correct redirect URI:

```bash
az ad app show --id <AZURE_CLIENT_ID> --query "web.redirectUris"
```

Should include: <https://static-swa-private-endpoint.publiccloudexperiments.net/.auth/login/aad/callback>

## Cost Higher Than Expected

Check capacity:

```bash
az network application-gateway show \
 --name agw-swa-subnet-calc-private-endpoint \
 --resource-group rg-subnet-calc \
 --query "{SKU:sku.name, Capacity:sku.capacity}" -o table
```

Should show: Capacity: 1

If higher, scale down:

```bash
az network application-gateway update \
 --name agw-swa-subnet-calc-private-endpoint \
 --resource-group rg-subnet-calc \
 --set sku.capacity=1
```

## Useful Commands

### View Backend Health

```bash
az network application-gateway show-backend-health \
 --name agw-swa-subnet-calc-private-endpoint \
 --resource-group rg-subnet-calc
```

### View Application Gateway Details

```bash
az network application-gateway show \
 --name agw-swa-subnet-calc-private-endpoint \
 --resource-group rg-subnet-calc
```

### Test from VM in VNet

```bash
# SSH to VM in VNet
curl -v -H "Host: static-swa-private-endpoint.publiccloudexperiments.net" \
 https://delightful-field-0cd326e03.privatelink.3.azurestaticapps.net/
```

Should return SWA content or Entra ID redirect.
