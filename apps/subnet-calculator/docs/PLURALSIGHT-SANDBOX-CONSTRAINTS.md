# Pluralsight Azure Sandbox Constraints

**Source:** [Pluralsight Help Center - Azure cloud sandbox](https://help.pluralsight.com/hc/en-us/articles/24392988447636-Azure-cloud-sandbox)

**Last Updated:** 2025-10-13 (Article updated 17 days ago from 2025-10-13)

## Overview

The Pluralsight Azure sandbox provides a real, open Azure environment for hands-on practice with specific limitations and restrictions.

## Critical Global Restrictions

### Time Limit

- **4 hours maximum** per sandbox session
- All resources are ephemeral

### Resource Groups

- **Cannot create additional resource groups**
- Must use the single pre-provisioned resource group
- Services that auto-create separate resource groups (like Network Watcher) cannot be used

### Regions

**Restricted to specific regions:**

**North America:**

- Canada East
- Central US
- East US
- East US 2
- North Central US
- South Central US
- West Central US
- West US 2

**Asia:**

- Central India
- South India
- West India
- Japan West
- Korea Central
- Korea South
- East Asia

**Other:**

- Germany North
- Germany West Central
- Global

### Authorization

**Cannot:**

- Elevate access
- Create or modify role definitions
- Create or modify role assignments

### Billing

- Cannot purchase anything (including Azure Marketplace)
- Cannot access billing or cost information

### Other Blocked Functionality

- Add-ons
- Management groups
- SaaS subscriptions

## Identity Services - CRITICAL FOR SSO

### Microsoft Entra Domain Services

**Status:** Conditionally supported in AD labs only (NOT in general sandbox)

**Limits in AD labs:**

- Max 5 apps
- Max 15 groups
- Max 15 users

### Microsoft Entra ID

**Status:** NOT SUPPORTED

### Microsoft Entra ID B2C

**Status:** NOT SUPPORTED

### Managed Identities for Azure Resources

**Status:** NOT SUPPORTED

## Compute Services

### Virtual Machines

**Status:** Conditionally supported

**Allowed SKUs:**

- Standard A0 or A1 v2
- Standard B1ms, B1s, B2ms, B2s
- Standard D1 v2, DS1 v2
- Standard D2, DS1
- Standard D2s v3, DS3 v2
- Standard F2

**Limits:**

- Max 10 instances total
- Max 10 CPUs across all instances
- Max 14 GB memory in a single instance

**Restrictions:**

- Blocked from Hybrid Use Benefit
- No proximity placement groups
- No TPUs or GPUs

### Virtual Machine Scale Sets

**Status:** Conditionally supported

**Limits:**

- Max 2 scale sets
- Max 3 instances per scale set

## Container Services

### Container Instances

**Status:** Conditionally supported

**Limits:**

- Max 6 container groups
- Max 2 containers per group
- Max 2 CPUs per container
- Max 2 GB memory per container

### Azure Container Apps

**Status:** Supported (no specific limits mentioned)

### Azure Kubernetes Service (AKS)

**Status:** Conditionally supported

**Limits:**

- Max 3 clusters
- Max 3 nodes per cluster

**Restrictions:**

- Cannot view or manage the secondary resource group created as part of AKS setup

### Container Registry

**Status:** Conditionally supported

**Limits:**

- Max 1 registry

**Restrictions:**

- No registry tasks allowed

## Database Services

### Azure Cosmos DB

**Status:** Conditionally supported

**Limits:**

- Throughput cannot exceed 1,000 RU/s

### Azure SQL Database

**Status:** Conditionally supported

**Allowed tiers:**

- Basic
- Standard only

**Allowed SKUs:**

- Basic
- S0, S1, S2, S3, S4
- DW100c or DW200c

**Restrictions:**

- No instance pools

### Azure SQL Managed Instance

**Status:** NOT SUPPORTED

- Reason: Provisioning takes multiple hours

## Web Services

### App Service

**Status:** Conditionally supported

**Allowed SKUs:**

- F1 (Free)
- B1, B2, B3 (Basic)
- S1 (Standard)
- Y1 (Consumption - Functions)

**Limits:**

- Max 2 server farms

### Azure Functions

**Status:** Supported (no specific limits mentioned)

### Azure Static Web Apps

**Status:** Not explicitly listed (assumed supported based on service availability)

## Network Services

### Virtual Networks

**Status:** Conditionally supported

**Restrictions:**

- All actions for ExpressRoute Circuits and Gateways are denied

### Network Watcher

**Status:** Conditionally supported

**Critical Restriction:**

- Cannot access, use, or modify Network Watcher Resource Group
- Services that depend on Network Watcher will function, but you cannot modify anything in its resource group

### Azure Bastion

**Status:** Supported

### Application Gateway

**Status:** Supported

### Load Balancer

**Status:** Supported

### Azure Firewall

**Status:** Conditionally supported

**Allowed SKUs:**

- Basic only

### VPN Gateway

**Status:** Supported

## Integration Services

### API Management

**Status:** Conditionally supported

**Allowed SKUs:**

- Developer
- Basic
- Standard
- Consumption

### Event Grid

**Status:** Supported

### Event Hubs

**Status:** Conditionally supported

**Allowed tiers:**

- Basic
- Standard

**Restrictions:**

- Cannot use clusters
- Cannot use Capture

### Logic Apps

**Status:** Supported

### Service Bus

**Status:** Supported

## Monitoring Services

### Azure Monitor

**Components:**

- Alerts Management: Supported
- Change Analysis: Supported
- Insights: Supported
- Intune: NOT SUPPORTED
- Operational Insights: Supported
- Operations Management: Supported
- Workload Monitor: NOT SUPPORTED

## Security Services

### Key Vault

**Status:** Supported

### Microsoft Sentinel

**Status:** Supported

### Security Center

**Status:** Supported

## Storage Services

### Storage Accounts

**Status:** Conditionally supported

**Restrictions:**

- Cannot lock immutability policies
- Cannot create or modify legal holds
- No purge protection

## AI and Machine Learning

### Azure Bot Service

**Status:** Supported

### Cognitive Services

**Status:** Conditionally supported

**Allowed SKUs:**

- S, S0, S1

**Limits:**

- Max 2 services created
- Max 1000 transactions per cognitive service

### Azure Machine Learning

**Status:** Conditionally supported

**Allowed SKUs:**

- Standard DS1 v2, D2 v2, D2s v2, DS2 v2, DS3 v2
- Standard F2s v2 or F4s v2
- Standard D2 v3 or D2s v3

**Limits:**

- Max 1 workspace
- Max 1 instance

### Azure AI Search

**Status:** Conditionally supported

**Allowed SKUs:**

- Free
- Basic tier

**Limits:**

- Max 1 alias
- Max 1 data source
- Max 20,000 documents
- Max 1 indexer
- Max 1 index
- Max 1 search resource
- Max 1 skillset
- Max 500 MB storage
- Max 1 synonym map
- Max 500 MB vector index size

## Abuse Prevention

Pluralsight actively monitors for abuse. Examples of prohibited activities:

**General examples:**

- 10 or more VMs created at a time
- 10 or more vCPUs across all VMs
- Crypto mining
- Excessive network traffic
- DDoS or port scanning external hosts

**Note:** This list is not comprehensive. Contact Pluralsight Support before attempting activities you're unsure about.

## Key Takeaways for Development

### What Works Well

- Azure Functions (Consumption plan)
- Azure Static Web Apps
- Container Apps
- Basic/Standard App Services
- Storage Accounts
- Key Vault
- Virtual Networks (basic scenarios)
- Azure Bastion

### What Doesn't Work

- **Entra ID (Azure AD) - NOT SUPPORTED**
- Managed Identities - NOT SUPPORTED
- Creating additional resource groups
- Role assignments
- Long-running resources (SQL Managed Instance)
- Marketplace purchases

### Workarounds for Production Features

Since many production features (Entra ID, Managed Identities, role assignments) are blocked:

1. **Authentication:**

- Use API keys or JWT tokens (as we currently do)
- Cannot test Entra ID integration in sandbox
- Cannot test Managed Service Identity
- Cannot test Easy Auth

1. **Resource Groups:**

- Must use the single provided resource group
- Plan resource naming carefully
- Use cleanup scripts to manage ephemeral resources

1. **Regions:**

- Check Static Web Apps availability (not all sandbox regions support it)
- May need to override region for specific services

1. **Time Limit:**

- 4-hour sessions mean everything is ephemeral
- Use infrastructure-as-code scripts for quick rebuild
- Test deployment automation, not long-running workloads
