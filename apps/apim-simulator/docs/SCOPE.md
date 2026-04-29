# Scope

This repository is not trying to clone all of Azure API Management. It is a local learning and iteration tool with a deliberate bias toward gateway behaviour, policy experimentation, auth flows, networking scenarios, and management-surface workflows that are useful in development.

## Supported Now

- Config-driven gateway routing and upstream proxying
- Service metadata, APIs, operations, products, subscriptions, version sets, backends, named values, policy fragments, tags, users, groups, loggers, and diagnostics in local config
- Tenant-key-protected management APIs, replay, trace summaries, and the operator console
- Terraform/OpenTofu import plus static compatibility reporting
- OIDC and JWT validation through static JWKS, JWKS endpoints, or `validate-jwt`
- Route-level scope, role, and claim checks
- Client-certificate and proxy-forwarded mTLS validation modes
- Host matching, API version-set routing, and forwarded-header-aware tracing
- A practical XML policy subset:
  - `set-header`
  - `rewrite-uri`
  - `return-response`
  - `choose`
  - `check-header`
  - `ip-filter`
  - `cors`
  - `rate-limit`
  - `rate-limit-by-key`
  - `quota`
  - `quota-by-key`
  - `cache-lookup`
  - `cache-store`
  - `cache-lookup-value`
  - `cache-store-value`
  - `cache-remove-value`
  - `set-variable`
  - `set-query-parameter`
  - `set-body`
  - `include-fragment`
  - `validate-jwt`
  - `set-backend-service`
  - `send-request`
- Curated Azure-Samples/APIM compatibility fixtures with documented supported, adapted, and unsupported cases
- Compose-backed direct public, edge HTTP, edge TLS, private/internal, OIDC, MCP, hello starter, todo demo, and OTEL/[LGTM](https://github.com/grafana/docker-otel-lgtm) scenarios

## Currently Deferred

- External cache backends for the `cache-*` policies
- `quota-by-key` bandwidth enforcement
- Full APIM policy expression compatibility
- Broader control-plane parity beyond the current local CRUD and inspection surface
- Broader Azure-Samples/APIM fixture coverage beyond the curated set

## Not The Goal

- Full APIM parity across every SKU and management-plane feature
- A complete implementation of the APIM policy language and expression engine
- The Microsoft developer portal CMS, email, or notification surface
- Production deployment guidance
