# Azure Functions Flex Consumption Plan

## Overview

**Flex Consumption** is the replacement for the deprecated Y1 Linux Consumption plan. It provides the **same free tier** with better performance and features.

## Free Tier (Identical to Y1)

- **1 million requests/month** per subscription
- **400,000 GB-s execution time/month** per subscription
- No upfront costs
- Pay only for what you use beyond free tier

**Pricing beyond free tier:**

- Execution: $0.000016/GB-s
- Requests: $0.20/million requests

## Benefits Over Y1 Consumption

| Feature | Y1 Consumption | Flex Consumption |
|---------|----------------|------------------|
| Free tier | 1M requests, 400k GB-s | Same |
| Cold starts | ~5-10 seconds | Faster (~2-5 sec) |
| VNet integration | Basic | Advanced |
| Per-function scaling | No | Yes |
| Concurrency control | Limited | Fine-grained |
| Always-ready instances | No | Yes (cold start mitigation) |
| Instance memory | 1536 MB | 2048 MB (default), configurable |

## Deprecation Timeline

| Date | Event |
|------|-------|
| **Sep 30, 2025** | Y1 removed from Portal, VS, VS Code (still in CLI) |
| **Sep 30, 2028** | Y1 completely retired |
| **Now** | Flex Consumption fully supported |

## Creating Flex Consumption Function Apps

### Basic (Default Settings)

```bash
az functionapp create \
 --name func-subnet-calc \
 --resource-group rg-subnet-calc \
 --storage-account stsubnetcalc123 \
 --runtime python \
 --runtime-version 3.11 \
 --functions-version 4 \
 --flexconsumption-location eastus \
 --disable-app-insights
```

**Defaults:**

- Memory: 2048 MB per instance
- Max replicas: Unlimited (scales to demand)
- HTTP concurrency: 100 requests per instance

### Advanced (Custom Settings)

```bash
az functionapp create \
 --name func-subnet-calc \
 --resource-group rg-subnet-calc \
 --storage-account stsubnetcalc123 \
 --runtime python \
 --runtime-version 3.11 \
 --functions-version 4 \
 --flexconsumption-location eastus \
 --instance-memory 4096 \
 --max-replicas 100 \
 --always-ready-instances 1 \
 --disable-app-insights
```

**Options:**

- `--instance-memory`: 2048 (default) or 4096 MB
- `--max-replicas`: Limit scale (default: unlimited)
- `--always-ready-instances`: Keep instances warm (costs apply, not free tier)

## Migration from Y1 to Flex

### Option 1: Blue-Green Deployment (Recommended)

1. Create new Flex Consumption Function App
1. Deploy code to new app
1. Test thoroughly
1. Update DNS/frontend to new endpoint
1. Monitor for issues
1. Delete old Y1 app when confident

### Option 2: In-Place Migration (Not Supported)

 Cannot convert Y1 to Flex in-place. Must create new Function App.

## Our Configuration

**Script:** `10-function-app.sh`

**Settings:**

- Runtime: Python 3.11
- Functions version: 4
- Plan: Flex Consumption
- Memory: 2048 MB (default)
- Max replicas: Unlimited (scales to demand)
- CORS: Enabled for all origins (*)
- HTTPS only: Enabled
- Authentication: Disabled (public access)

**Free tier covers:**

- ~1M calculator API requests/month (typical usage: <10k/month)
- Subnet calculator API is well within free limits

## Monitoring Usage

### Check current usage (approximate)

```bash
# Function App metrics (requests)
az monitor metrics list \
 --resource /subscriptions/{sub}/resourceGroups/rg-subnet-calc/providers/Microsoft.Web/sites/func-subnet-calc \
 --metric "Requests" \
 --start-time 2025-01-01T00:00:00Z \
 --end-time 2025-01-31T23:59:59Z

# Storage account metrics (execution time tracked via storage)
az monitor metrics list \
 --resource /subscriptions/{sub}/resourceGroups/rg-subnet-calc/providers/Microsoft.Storage/storageAccounts/stsubnetcalc123 \
 --metric "Transactions"
```

### Cost alerts (optional)

Set budget alerts to notify if costs exceed $0:

```bash
# Create budget alert
az consumption budget create \
 --budget-name "function-app-free-tier" \
 --category Cost \
 --amount 0 \
 --time-grain Monthly \
 --start-date "2025-01-01" \
 --end-date "2028-12-31" \
 --resource-group rg-subnet-calc
```

## Resources

- [Flex Consumption announcement](https://azure.microsoft.com/en-us/updates/flex-consumption-plan/)
- [Pricing calculator](https://azure.microsoft.com/en-us/pricing/details/functions/)
- [Migration guide](https://learn.microsoft.com/en-us/azure/azure-functions/flex-consumption-plan)
- [Free tier details](https://azure.microsoft.com/en-us/pricing/details/functions/)

## FAQ

### Q: Will I be charged for Flex Consumption?

**A:** Not if you stay within free tier (1M requests/month, 400k GB-s/month). The subnet calculator API typically uses <1% of free tier.

### Q: What happens if I exceed free tier?

**A:** You'll be charged:

- $0.20 per million requests (beyond 1M)
- $0.000016 per GB-second (beyond 400k GB-s)

Example: 2M requests with 5-second 2GB executions:

- Requests: 1M free + 1M paid = $0.20
- Execution: 400k GB-s free + 600k GB-s paid = $9.60
- **Total: $9.80/month**

### Q: Should I use always-ready instances?

**A:** Probably not for this use case. Always-ready instances eliminate cold starts but cost ~$13/month per instance. Only use if:

- Sub-second response time is critical
- Can't tolerate 2-5 second cold starts
- Have budget for always-on infrastructure

### Q: Can I revert to Y1 Consumption?

**A:** Yes, until Sep 2028. But why? Flex is better in every way with same free tier.

### Q: What's the instance memory for?

**A:** Each function execution runs in a container with allocated memory:

- 2048 MB (default): Handles most Python workloads
- 4096 MB: For memory-intensive operations (ML, large data processing)

Subnet calculator uses ~50MB per request, so 2048 MB is plenty.
