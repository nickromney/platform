# APIM Simulator (Docker-first) feature plan

## Purpose

Build a containerised API Management (APIM) simulator that starts in seconds (Docker/Kubernetes) while remaining close enough to Azure APIM behavior to harden applications early — especially centralized authentication and authorisation for many apps behind one gateway.

Primary reference:

- Terraform: `azurerm_api_management` resource documentation
  - <https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management>

Repo intent references:

- `subnetcalc/apim-simulator/` (config-driven gateway simulator)
- `terraform/terragrunt/platform/apps/azure-apim-sim/apim-service.yaml` (Kubernetes service wiring)

## Current state (what exists today)

### Lightweight simulator

`subnetcalc/apim-simulator/` (stack12):

- Validates OIDC JWT (issuer/audience via JWKS)
- Optional single `APIM_SUBSCRIPTION_KEY`
- Proxies only `/api/*`
- Injects Easy Auth style identity headers

### “Full” simulator

`subnetcalc/apim-simulator/`:

- Config-driven routes (`path_prefix` -> upstream)
- Products + subscriptions (primary/secondary keys) and product entitlements
- OIDC JWT validation (issuer/audience + JWKS)
- Optional anonymous mode
- Subscription bypass rules (header conditions)
- Key rotation endpoint
- Retries, optional cache, optional trace response header

### Kubernetes topology intent

`terraform/terragrunt/platform/apps/azure-apim-sim/`:

- Dedicated namespace (`azure-apim-sim`) for the APIM simulator
- External access via Gateway API (`apim.localhost` -> `apim-simulator` service)
- Cross-namespace routing from workloads in `azure-auth-sim`

## Goals and constraints

### Goals

1. Centralised authn/z via one gateway used by many apps/APIs
2. Docker-first (container runnable; K8s friendly)
3. Fast inner loop: start + reconfigure in seconds (no 45-minute deploy cycle)
4. Terraform-aligned model, so simulator config stays close to how real APIM is expressed in IaC

### Non-goals (to keep scope sane)

- Full Developer Portal UX
- Perfect parity with every APIM policy and edge case
- Real Azure control-plane behaviors (long provisioning) or real Key Vault integrations

## Terraform APIM surface area to simulate

This section is anchored to the `azurerm_api_management` Terraform resource and highlights which fields map to simulator behaviors.

### Endpoints and hostnames (`hostname_configuration`)

Real APIM exposes distinct surfaces (proxy/gateway, management, portal, developer portal, scm).

Simulator should implement at least:

- Gateway/proxy surface (data plane)
- Management surface (control plane)

Implementation options:

- Host-based routing (preferred, mirrors production)
- Path-based routing for local convenience (example: `/apim/management/*`)

### Tenant access keys (`tenant_access`)

Terraform exposes `tenant_access.primary_key` and `tenant_access.secondary_key`.

Simulator should mirror this by:

- Issuing two management keys
- Requiring one for any management API call
- Using these keys to support realistic automation and key rotation tests

### TLS and certificates (`certificate`, per-host certs, client cert negotiation)

From the Terraform resource:

- Certificates and hostname bindings
- `client_certificate_enabled`
- `negotiate_client_certificate` (per-host)

Simulator approach:

- Keep the simulator app focused on policy + proxy
- Use a small front proxy container (Envoy or NGINX) when TLS/mTLS realism is needed
  - Terminate TLS
  - Enforce mTLS
  - Forward client cert details (subject/thumbprint) to the simulator via headers

### Protocols and security knobs (`protocols`, `security`)

Terraform includes:

- `protocols.http2_enabled`
- `security` toggles (TLS versions/ciphers)

Simulator should support either:

- Enforced mode (configure Envoy/NGINX to match), or
- Declared mode (surface settings in `/apim/status` and log warnings when not enforced)

## Target architecture (Docker-friendly, extensible)

### Planes

#### Data plane (gateway runtime)

Responsibilities:

- Route matching (host + base path + method; later operation templates)
- Policy pipeline: inbound -> backend -> outbound -> on-error
- Authn/z: subscription keys + validate-jwt + entitlement checks
- Throttling, caching, tracing
- Header/query rewrites

#### Control plane (management API)

Responsibilities:

- CRUD for APIs, operations, products, subscriptions, users/groups, named values, backends
- Subscription key rotation and subscription state changes
- Publish “effective config” snapshot for debugging
- Auth via tenant access keys (primary/secondary)

#### Config store

Support two modes:

1. File mode: load config from mounted JSON/YAML (fast local dev)
2. Dynamic mode: SQLite-backed config updated via management API

Both modes compile to a single runtime config used by the data plane.

## APIM concepts to model (authn/z focused)

### Products

- `product_id`, display name, `require_subscription`
- Optional approval requirements (future)
- Policies attachable at product scope

### Subscriptions

- `subscription_id`, owner (user/group), primary/secondary keys, state (`active`, `suspended`)
- Product entitlements
- Accept subscription key via:
  - Headers: `Ocp-Apim-Subscription-Key`, `X-Ocp-Apim-Subscription-Key`
  - Query param: `subscription-key`

### APIs and operations

- API: base path, versioning hooks
- Operation: method + URL template
- Policies attachable at API and operation scopes

### Users and groups

Minimal model to support centralised access control:

- Groups (examples: `admins`, `partnerA`, `internal`)
- Users mapped to groups
- Subscriptions owned by a user or group

### Named values

- Key/value pairs with a secret flag
- Used by policies for configuration (keys, endpoints, feature flags)

### Backends

- Backend definitions and selection
- Simulate outbound authentication to upstream (basic, client cert, etc.)

## Policy engine plan

### Execution model

- Parse policy XML into an AST at load/reload
- Execute on every request:
  - inbound policies
  - backend policies
  - proxy request
  - outbound policies
  - on-error policies

### MVP policy subset (highest leverage)

Authn/z:

- `validate-jwt` (multi-issuer, audience, required claims/scopes/roles)
- Subscription key enforcement and entitlement checks
- `rate-limit` and `quota`

Request shaping and guardrails:

- `ip-filter`
- `check-header`
- `cors`
- `set-header`, `set-query-parameter`
- `rewrite-uri`
- `return-response`
- `choose` / `when` / `otherwise`

### State for throttling/quota

- Start with in-memory counters
- Make storage pluggable (in-memory vs Redis) for kind/CI resilience

## Multi-app auth model (centralised APIM)

To simulate “APIM used by many apps as a centralised source”:

- Support multiple issuers (Keycloak now; Entra later), per API/operation
- Subscription keys remain the primary shared mechanism for product-level access
- Enforce scopes/roles per operation via policies

## Terraform alignment beyond the service resource

To keep the simulator aligned with real IaC, add a Terraform JSON importer:

- Input: `tofu show -json` output (plan/state)
- Output:
  - File-mode simulator config, or
  - Management API calls to populate dynamic mode

MVP import targets:

- Service-level knobs from `azurerm_api_management` (hostnames, tls toggles, tenant access)
- APIs/products/subscriptions/policies/named values/backends from the `azurerm_api_management_*` resources

## Phased roadmap

### Phase 1 (core realism)

- Pick one canonical simulator implementation (avoid divergence)
- Decision: `github.com/nickromney/apim-simulator` is canonical; `platform/apps/subnetcalc/apim-simulator/` is the vendored mirror pinned to a release tag
- Versioned config schema
- Policy pipeline + validate-jwt + subscription key semantics

### Phase 2 (multi-app governance)

- Product/subscription state model + quotas/rate limits
- Per-operation policies and richer routing

### Phase 3 (IaC-driven config)

- Terraform JSON importer

### Phase 4 (TLS/mTLS parity)

- Optional Envoy/NGINX front proxy enforcing TLS/mTLS and HTTP/2

## Beads (work items)

Epic:

- `subnetcalc-a57` — APIM simulator: Docker-first, feature-complete authn/z + policy engine

Children:

- `subnetcalc-a57.1` Capability matrix mapped to Terraform resources
- `subnetcalc-a57.2` Pick canonical simulator and migration plan
- `subnetcalc-a57.3` Extend config model (APIs/operations/products/subscriptions/groups/users/named values)
- `subnetcalc-a57.4` Management plane endpoints + tenant access keys
- `subnetcalc-a57.5` Policy engine v1 pipeline + choose/when
- `subnetcalc-a57.6` Validate-jwt policy (multi-issuer, aud, claims/scopes/roles)
- `subnetcalc-a57.7` Subscription key semantics + entitlement + states
- `subnetcalc-a57.8` Rate-limit + quota policies
- `subnetcalc-a57.9` Baseline inbound policies
- `subnetcalc-a57.10` Backend definitions + backend auth simulation
- `subnetcalc-a57.11` TLS/mTLS frontdoor support
- `subnetcalc-a57.12` Tracing + diagnostics
- `subnetcalc-a57.13` Terraform plan/state JSON importer
- `subnetcalc-a57.14` Test harness
- `subnetcalc-a57.15` Kubernetes deployment ergonomics
