# Azure ARM vs AzureRM Gaps for APIM

This document is a simulator-design note, not a changelog for the latest
Terraform provider behavior.

Use it when you need to decide whether a specific Azure API Management feature
should be modeled through:

- the AzureRM provider
- the AzAPI provider or raw ARM resources
- the simulator's local config only

For the latest provider support, check the current AzureRM and AzAPI docs
directly before relying on a specific resource or property.

## Why This Matters Here

The simulator imports APIM state from `tofu show -json` and maps it into a local
gateway model. That means provider shape matters even when the simulator is not
trying to reproduce the full Azure control plane.

In practice, provider gaps affect three things:

- what metadata is easy to import from Terraform
- which APIM concepts teams are likely to author in AzureRM versus policy XML
- where the simulator should be explicit that behavior is local, adapted, or out of scope

## Practical Rules

### Prefer AzureRM When The Resource Shape Is Stable

Use AzureRM-backed resources as the default source of truth for the common APIM
objects the simulator already models well:

- service metadata
- APIs and operations
- products and subscriptions
- backends
- named values
- users and groups
- API version sets

Those are the resources most likely to show up in imported local workflows.

### Use AzAPI Or ARM For Provider Lag

When Azure adds a property or child resource before AzureRM exposes it cleanly,
teams usually bridge the gap with:

- `azapi_resource`
- `azapi_update_resource`
- nested ARM deployments

The simulator should treat those cases as import and projection questions, not
as a reason to promise full ARM parity.

### Keep Policy Behavior Separate From Resource Coverage

Many useful APIM features are expressed as policy XML rather than first-class
Terraform fields.

That means the simulator should keep distinguishing between:

- control-plane metadata it can import and expose
- runtime policy behavior it can execute locally
- unsupported policy attributes that must stay clearly labeled

## Where Gaps Usually Matter

These areas tend to drift faster than the simulator should:

- service-level networking and newer platform flags
- newer APIM child resources that arrive in ARM before AzureRM
- workspace, portal, and GraphQL-specific surfaces
- policy attributes that remain easiest to manage as raw XML

Those areas are a good fit for compatibility reporting and explicit scope notes.
They are a poor fit for broad parity claims.

## Simulator Implications

The simulator follows a few rules because of that split:

1. Import the resource families that are common in real Terraform workflows.
2. Preserve descriptive metadata even when local runtime behavior is narrower.
3. Accept policy XML directly because that is how many APIM features are
   represented in Terraform anyway.
4. Mark adapted and unsupported behavior explicitly instead of implying Azure
   equivalence.

## References

- [Azure APIM ARM template reference](https://learn.microsoft.com/en-us/azure/templates/microsoft.apimanagement/service)
- [AzureRM `api_management` resources](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management)
- [AzAPI provider docs](https://registry.terraform.io/providers/Azure/azapi/latest/docs)
