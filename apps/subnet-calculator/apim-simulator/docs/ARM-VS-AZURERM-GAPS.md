# Azure ARM vs AzureRM Provider Gaps for APIM

This document tracks Azure APIM features available in ARM templates or AzAPI but missing/lagging in the AzureRM Terraform provider. These gaps may affect simulator parity decisions.

## Overview

The AzureRM provider abstracts Azure Resource Manager (ARM) APIs into Terraform resources. However, new ARM features often lag behind in the provider, requiring:

1. **AzAPI provider** - Direct ARM API access via `azapi_resource`
2. **ARM templates** - Nested ARM deployment
3. **Wait for provider update** - Track GitHub issues

## Current Gaps (as of January 2026)

### High Priority (affects simulator design)

| ARM Property | AzureRM Status | Workaround | Simulator Impact |
|--------------|----------------|------------|------------------|
| `properties.natGatewayState` | Not exposed | AzAPI | None - k8s networking |
| `properties.publicNetworkAccess` | Available (v3.x+) | - | None |
| Workspace APIs | Partial | AzAPI for workspaces | None - single workspace |
| GraphQL resolver policies | Not in provider | AzAPI | Not implementing GraphQL |

### Medium Priority (nice to have)

| ARM Property | AzureRM Status | Workaround | Simulator Impact |
|--------------|----------------|------------|------------------|
| `properties.developerPortalUrl` customization | Read-only | - | N/A - no portal |
| API revision descriptions | Not granular | - | Not tracking revisions |
| Subscription scope (all APIs) | Supported | - | Implemented |
| `properties.customProperties` | Available | - | Could add to config |

### Low Priority (edge cases)

| ARM Property | AzureRM Status | Workaround | Simulator Impact |
|--------------|----------------|------------|------------------|
| Outbound public IP addresses | Read-only output | - | N/A |
| Private endpoint connections | Separate resource | - | N/A - k8s networking |
| Platform version | Read-only | - | N/A |

## AzureRM Resources vs ARM Resources

### Fully Covered

These ARM resources have complete AzureRM coverage:

| ARM Resource Type | AzureRM Resource |
|-------------------|------------------|
| `Microsoft.ApiManagement/service` | `azurerm_api_management` |
| `Microsoft.ApiManagement/service/apis` | `azurerm_api_management_api` |
| `Microsoft.ApiManagement/service/apis/operations` | `azurerm_api_management_api_operation` |
| `Microsoft.ApiManagement/service/apis/policies` | `azurerm_api_management_api_policy` |
| `Microsoft.ApiManagement/service/products` | `azurerm_api_management_product` |
| `Microsoft.ApiManagement/service/subscriptions` | `azurerm_api_management_subscription` |
| `Microsoft.ApiManagement/service/backends` | `azurerm_api_management_backend` |
| `Microsoft.ApiManagement/service/namedValues` | `azurerm_api_management_named_value` |
| `Microsoft.ApiManagement/service/certificates` | `azurerm_api_management_certificate` |
| `Microsoft.ApiManagement/service/groups` | `azurerm_api_management_group` |
| `Microsoft.ApiManagement/service/users` | `azurerm_api_management_user` |
| `Microsoft.ApiManagement/service/apiVersionSets` | `azurerm_api_management_api_version_set` |
| `Microsoft.ApiManagement/service/authorizationServers` | `azurerm_api_management_authorization_server` |
| `Microsoft.ApiManagement/service/openidConnectProviders` | `azurerm_api_management_openid_connect_provider` |

### Partially Covered

| ARM Resource Type | AzureRM Gap | Notes |
|-------------------|-------------|-------|
| `Microsoft.ApiManagement/service/policies` | Global policy only | Operation-level via separate resource |
| `Microsoft.ApiManagement/service/loggers` | Basic support | Some logger types missing |
| `Microsoft.ApiManagement/service/diagnostics` | Available | Sampling settings limited |

### Not Covered (require AzAPI)

| ARM Resource Type | Notes |
|-------------------|-------|
| `Microsoft.ApiManagement/service/workspaces` | Preview feature |
| `Microsoft.ApiManagement/service/workspaces/*` | Workspace-scoped resources |
| `Microsoft.ApiManagement/service/apis/resolvers` | GraphQL resolvers |
| `Microsoft.ApiManagement/service/contentTypes` | Developer portal content |
| `Microsoft.ApiManagement/service/contentItems` | Developer portal content |

## Policy XML vs Terraform

Some policies are easier to manage in XML than via Terraform resources:

| Policy | Terraform Approach | Recommendation |
|--------|-------------------|----------------|
| `validate-jwt` | Inline XML in `azurerm_api_management_api_policy` | XML |
| `rate-limit-by-key` | Inline XML | XML |
| `cache-lookup` / `cache-store` | Inline XML | XML |
| `set-header` | Inline XML | XML (easier bulk edits) |
| `cors` | Can use `azurerm_api_management.cors` | Either |

The simulator accepts policy XML directly, matching the Terraform pattern.

## Simulator Design Decisions

Based on these gaps, the simulator:

1. **Uses JSON config** - Maps to Terraform `tofu show -json` output
2. **Accepts policy XML** - Same format as `azurerm_api_management_api_policy.xml_content`
3. **Ignores ARM-only features** - Workspace APIs, GraphQL resolvers
4. **Focuses on gateway behavior** - Not management plane CRUD

## Tracking Provider Updates

Key GitHub issues to watch:

- [hashicorp/terraform-provider-azurerm](https://github.com/hashicorp/terraform-provider-azurerm/issues?q=is%3Aissue+is%3Aopen+api_management)
- AzureRM changelog: Check for `azurerm_api_management*` entries

## Using AzAPI for Gaps

Example of using AzAPI for a missing property:

```hcl
resource "azapi_update_resource" "apim_custom_property" {
  type        = "Microsoft.ApiManagement/service@2023-05-01-preview"
  resource_id = azurerm_api_management.this.id

  body = jsonencode({
    properties = {
      customProperties = {
        "Microsoft.WindowsAzure.ApiManagement.Gateway.Protocols.Server.Http2" = "true"
      }
    }
  })
}
```

## References

- [ARM template reference](https://learn.microsoft.com/en-us/azure/templates/microsoft.apimanagement/service)
- [AzureRM provider docs](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management)
- [AzAPI provider docs](https://registry.terraform.io/providers/Azure/azapi/latest/docs)
