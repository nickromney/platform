# APIM Simulator Capability Matrix

This document maps simulator features to Azure APIM concepts and their Terraform resource equivalents.

The management surface below is available when `tenant_access.enabled` is `true`.

## Legend

| Status | Meaning |
|--------|---------|
| Yes | Fully implemented |
| Partial | Basic support, not all options |
| No | Not implemented |
| N/A | Not applicable to simulator |

## Gateway / Service Level

| Feature | Simulator | Terraform Resource | Notes |
|---------|-----------|-------------------|-------|
| Health endpoint | Yes | N/A | `/apim/health` |
| Startup probe | Yes | N/A | `/apim/startup` |
| Config reload | Yes | N/A | `/apim/reload` + file watcher |
| CORS | Yes | `azurerm_api_management` | `allowed_origins` in config |
| Public network access | Partial | `azurerm_api_management.public_network_access_enabled` / AzAPI `properties.publicNetworkAccess` | Imported into service metadata only; local reachability is not enforced |
| Client cert (mTLS) | Yes | `azurerm_api_management.client_certificate_enabled` | `client_certificate.mode` |
| Negotiate client cert | Yes | `azurerm_api_management.hostname_configuration.negotiate_client_certificate` | Via proxy headers |
| SKU selection | N/A | `azurerm_api_management.sku_name` | Simulator is single-instance |
| Zones / HA | N/A | `azurerm_api_management.zones` | Not applicable |
| Virtual network type | Partial | `azurerm_api_management.virtual_network_type` / AzAPI `properties.virtualNetworkType` | Imported into service metadata only; use docker/k8s networking for actual topology |
| Custom domains / hostnames | Partial | `azurerm_api_management.hostname_configuration` / AzAPI `properties.hostnameConfigurations` | Imported as service hostname metadata; TLS termination remains external |

## Runtime Scenarios

| Feature | Simulator | Terraform Resource | Notes |
|---------|-----------|-------------------|-------|
| Direct public compose path | Yes | N/A | `compose.yml` + `compose.public.yml` on `localhost:8000` |
| Edge HTTP compose path | Yes | N/A | `compose.yml` + `compose.edge.yml` on `apim.localtest.me:8088` |
| Edge TLS compose path | Yes | N/A | `compose.yml` + `compose.edge.yml` + `compose.tls.yml` on `apim.localtest.me:8443` |
| Private internal compose path | Yes | N/A | `compose.yml` + `compose.private.yml`; smoke uses internal probe container |

## APIs and Operations

| Feature | Simulator | Terraform Resource | Notes |
|---------|-----------|-------------------|-------|
| API definition | Yes | `azurerm_api_management_api` | `apis` map in config |
| API revision metadata | Partial | `azurerm_api_management_api.revision` / `revision_description` | Imported and exposed read-only; multiple APIM revisions collapse into one active local API for runtime behavior |
| API releases | Partial | `azurerm_api_management_api_release` | Imported and exposed read-only via `/apim/management/apis/{api_id}/releases` |
| Operations | Yes | `azurerm_api_management_api_operation` | `operations` within API |
| API schemas | Partial | `azurerm_api_management_api_schema` | Imported and exposed read-only via `/apim/management/apis/{api_id}/schemas`; write endpoints are not implemented |
| Operation descriptions and template params | Yes | `azurerm_api_management_api_operation` | Imported from operation metadata blocks and projected through management APIs |
| Operation request metadata | Partial | `azurerm_api_management_api_operation.request` | Imported and projected read-only; request validation is not enforced at runtime |
| Operation response metadata | Partial | `azurerm_api_management_api_operation.response` | Imported and projected read-only; descriptive only |
| Path routing | Yes | - | `path_prefix` matching |
| Method routing | Yes | - | Per-operation `method` |
| API Version Sets | Yes | `azurerm_api_management_api_version_set` | Header/Query/Segment schemes |
| OpenAPI import | Partial | `azurerm_api_management_api` (import block) | Supports inline/link OpenAPI and Swagger JSON import through Terraform/OpenTofu for operation discovery and upstream URL; full schema/request/response extraction is narrower than explicit APIM resources |
| GraphQL | No | `azurerm_api_management_api` | Not implemented |
| WebSocket | No | `azurerm_api_management_api` | Not implemented |

## Products and Subscriptions

| Feature | Simulator | Terraform Resource | Notes |
|---------|-----------|-------------------|-------|
| Products | Yes | `azurerm_api_management_product` | `products` map |
| Product-API association | Yes | `azurerm_api_management_product_api` | `products` list on route/API |
| Product-group association | Yes | `azurerm_api_management_product_group` | Descriptive link resources under `/apim/management/products/{product_id}/groups` |
| Subscriptions | Yes | `azurerm_api_management_subscription` | `subscription.subscriptions` |
| Primary/secondary keys | Yes | - | `keys.primary`, `keys.secondary` |
| Subscription state | Yes | - | `active`, `suspended`, `cancelled` |
| Key rotation | Yes | - | `/apim/management/subscriptions/{id}/rotate` |
| Require subscription | Yes | `azurerm_api_management_product.subscription_required` | Per-product toggle |
| Subscription bypass | Yes | - | Header conditions |
| Approval required | No | `azurerm_api_management_product.approval_required` | Auto-approved |
| Subscription limits | No | `azurerm_api_management_product.subscriptions_limit` | Not enforced |

## Tags

| Feature | Simulator | Terraform Resource | Notes |
|---------|-----------|-------------------|-------|
| Tags | Yes | `azurerm_api_management_tag` | Global tag registry plus `/apim/management/tags` |
| API tags | Yes | `azurerm_api_management_api_tag` | Descriptive link resources under `/apim/management/apis/{api_id}/tags` |
| Product tags | Yes | `azurerm_api_management_product_tag` | Descriptive link resources under `/apim/management/products/{product_id}/tags` |
| Operation tags | Partial | `azurerm_api_management_api_operation_tag` | Imported and exposed through operation tag links; operation tag creation is adapted into the simulator's global tag registry |
| Tag descriptions | No | `azurerm_api_management_api_tag_description` | Not implemented |

## Users and Groups

| Feature | Simulator | Terraform Resource | Notes |
|---------|-----------|-------------------|-------|
| Users | Partial | `azurerm_api_management_user` | Local CRUD + Terraform import; descriptive only, no auth or password enforcement |
| Groups | Partial | `azurerm_api_management_group` | Local CRUD + Terraform import; still descriptive only |
| Group membership | Partial | `azurerm_api_management_group_user` | Terraform import plus descriptive link CRUD under `/apim/management/groups/{group_id}/users` |
| Built-in groups | No | - | Administrators/Developers/Guests |

## Authentication / Authorization

| Feature | Simulator | Terraform Resource | Notes |
|---------|-----------|-------------------|-------|
| OIDC/JWT validation | Yes | `azurerm_api_management.sign_in` / policies | Multi-issuer support |
| JWKS fetching | Yes | - | Via `jwks_uri` |
| Static JWKS | Yes | - | Inline `jwks` in config |
| Audience validation | Yes | - | Per OIDC provider |
| Issuer validation | Yes | - | Auto-selects by token `iss` |
| Scope enforcement | Yes | - | `authz.required_scopes` |
| Role enforcement | Yes | - | `authz.required_roles` |
| Claim enforcement | Yes | - | `authz.required_claims` |
| OAuth2 authorization server | No | `azurerm_api_management_authorization_server` | Use external IdP |
| OpenID Connect provider | Partial | `azurerm_api_management_openid_connect_provider` | Via `oidc_providers` |
| Identity provider | No | `azurerm_api_management_identity_provider_*` | Use external IdP |

## Policies

| Feature | Simulator | Terraform Resource | Notes |
|---------|-----------|-------------------|-------|
| Inbound policies | Yes | `azurerm_api_management_api_policy` | XML format |
| Outbound policies | Yes | - | `<outbound>` section |
| On-error policies | Yes | - | `<on-error>` section |
| Policy inheritance | Yes | - | Gateway -> API -> Operation |
| `set-header` | Yes | - | Add/override/delete modes |
| `rewrite-uri` | Yes | - | Path rewriting |
| `set-variable` | Yes | - | Writes to request-scoped `variables` |
| `set-query-parameter` | Yes | - | Mutates outbound upstream query only |
| `set-body` | Yes | - | Literal or templated request/short-circuit body replacement |
| `include-fragment` | Yes | - | Config-backed via `policy_fragments` |
| `return-response` | Yes | - | Short-circuit with custom response |
| `choose`/`when`/`otherwise` | Yes | - | Conditional logic |
| `check-header` | Yes | - | Required header validation |
| `ip-filter` | Yes | - | Allow/deny IP ranges |
| `cors` | Partial | - | Basic CORS headers |
| `rate-limit` | Yes | - | Calls per period |
| `rate-limit-by-key` | Yes | - | Supports literal and response-aware increment evaluation plus custom remaining/retry headers |
| `quota` | Yes | - | Calls per renewal period |
| `quota-by-key` | Partial | - | Supports call quotas and `first-period-start`; `bandwidth` remains unsupported |
| `validate-jwt` | Yes | - | OpenID config, audiences, issuers, required claims, output token variables |
| `authentication-basic` | Partial | - | Backend auth only |
| `authentication-certificate` | Partial | - | Backend auth config |
| `authentication-managed-identity` | Partial | - | Backend auth config |
| `set-backend-service` | Yes | - | Supports `backend-id` and `base-url` overrides in inbound/backend |
| `cache-lookup` | Partial | - | Supports local internal cache; `prefer-external` is adapted to local cache and `external` is unsupported |
| `cache-store` | Partial | - | Supports local internal response cache for GET responses |
| `cache-lookup-value` | Partial | - | Supports local internal value cache plus default-value; `prefer-external` is adapted and `external` is unsupported |
| `cache-store-value` | Partial | - | Stores to local in-memory value cache; `prefer-external` is adapted and `external` is unsupported |
| `cache-remove-value` | Partial | - | Removes from local in-memory value cache; `prefer-external` is adapted and `external` is unsupported |
| `mock-response` | No | - | Use `return-response` |
| `send-request` | Yes | - | Supports `new|copy`, headers/body, timeout, ignore-error, managed identity, certificate placeholder |
| `log-to-eventhub` | No | - | Use observability stack |

## Backends

| Feature | Simulator | Terraform Resource | Notes |
|---------|-----------|-------------------|-------|
| Backend definitions | Yes | `azurerm_api_management_backend` | `backends` map incl. credentials import |
| Backend URL | Yes | - | `url` field |
| Basic auth | Yes | - | `auth_type: basic` |
| Client cert auth | Partial | - | `auth_type: client_certificate` |
| Managed identity | Partial | - | `auth_type: managed_identity` |
| Circuit breaker | No | - | Not implemented |
| Load balancing | No | - | Single upstream |

## Management Plane

| Feature | Simulator | Terraform Resource | Notes |
|---------|-----------|-------------------|-------|
| Management status | Yes | - | `/apim/management/status` |
| Tenant access keys | Yes | `azurerm_api_management.tenant_access` | Primary/secondary |
| Management summary | Yes | - | `/apim/management/summary` |
| API CRUD | Yes | `azurerm_api_management_api` | `/apim/management/apis` |
| Operation CRUD | Yes | `azurerm_api_management_api_operation` | `/apim/management/apis/{api_id}/operations` |
| Product CRUD | Yes | `azurerm_api_management_product` | `/apim/management/products` |
| Backend CRUD | Yes | `azurerm_api_management_backend` | `/apim/management/backends` |
| Named value CRUD | Yes | `azurerm_api_management_named_value` | `/apim/management/named-values` |
| API schema inspection | Yes | `azurerm_api_management_api_schema` | `/apim/management/apis/{api_id}/schemas` and `/apim/management/apis/{api_id}/schemas/{schema_id}` |
| API revision inspection | Yes | `azurerm_api_management_api` | `/apim/management/apis/{api_id}/revisions` and `/apim/management/apis/{api_id}/revisions/{revision_id}` |
| API release inspection | Yes | `azurerm_api_management_api_release` | `/apim/management/apis/{api_id}/releases` and `/apim/management/apis/{api_id}/releases/{release_id}` |
| Logger inspection | Yes | `azurerm_api_management_logger` | `/apim/management/loggers` and `/apim/management/loggers/{logger_id}` |
| Diagnostic inspection | Yes | `azurerm_api_management_diagnostic` | `/apim/management/diagnostics` and `/apim/management/diagnostics/{diagnostic_id}` |
| Policy fragment CRUD | Yes | - | `/apim/management/policy-fragments` |
| User CRUD | Partial | `azurerm_api_management_user` | `/apim/management/users`; password and confirmation flows remain descriptive only |
| Group CRUD | Partial | `azurerm_api_management_group` | `/apim/management/groups` |
| Group-user link CRUD | Yes | `azurerm_api_management_group_user` | `/apim/management/groups/{group_id}/users` |
| Product-group link CRUD | Yes | `azurerm_api_management_product_group` | `/apim/management/products/{product_id}/groups` |
| Tag inspection and CRUD | Yes | `azurerm_api_management_tag` | `/apim/management/tags` plus nested API/product/operation tag link endpoints |
| Policy inspection/update | Yes | - | `/apim/management/policies/{scope_type}/{scope_name}` |
| Replay | Yes | - | `/apim/management/replay` |
| Subscription CRUD | Yes | `azurerm_api_management_subscription` | List, create, update, delete, and rotate via API |
| Config import | Yes | - | Terraform/OpenTofu JSON import via management API and `make import-tofu` |
| Git integration | No | `azurerm_api_management.management.git_configuration_enabled` | Use GitOps |

## Observability

| Feature | Simulator | Terraform Resource | Notes |
|---------|-----------|-------------------|-------|
| Correlation ID | Yes | - | `X-Correlation-Id` header |
| Trace header | Yes | - | `X-Apim-Trace: true` |
| Trace lookup | Yes | - | `/apim/trace/{id}` |
| Trace summaries | Yes | - | `/apim/management/traces` |
| Logger resources | Partial | `azurerm_api_management_logger` | Imported and exposed read-only; sink configuration is descriptive only |
| Diagnostic resources | Partial | `azurerm_api_management_diagnostic` | Imported and exposed read-only; sampling and logger routing are descriptive only |
| Forwarded-header trace fields | Yes | - | `incoming_host`, `forwarded_host`, `forwarded_proto`, `forwarded_for`, `client_ip`, `upstream_url` |
| Policy execution trace | Yes | - | Includes policy steps, variable writes, JWT validation, send-request activity, selected backend, cache/throttle actions |
| Application Insights | No | `azurerm_api_management.application_insights` | Use external APM |
| Diagnostic logs | No | `azurerm_api_management_diagnostic` | Use container logs and OTEL for actual runtime logging |

## Named Values / Secrets

| Feature | Simulator | Terraform Resource | Notes |
|---------|-----------|-------------------|-------|
| Named values | Yes | `azurerm_api_management_named_value` | Resolved in policies and backend credentials |
| Secret values | Yes | - | Masked in traces |
| Key Vault refs | Partial | - | Imported and resolved via local env overrides (`APIM_NAMED_VALUE_*`) |

## Developer Console

| Feature | Simulator | Terraform Resource | Notes |
|---------|-----------|-------------------|-------|
| Operator console | Yes | N/A | `ui/` Vite + React app |
| Policy editor | Yes | N/A | Uses management policy endpoints |
| Trace viewer | Yes | N/A | Uses trace lookup and trace summary endpoints |
| Replay console | Yes | N/A | Uses management replay endpoint |
| Subscription key inspection/rotation | Yes | N/A | Uses management subscription endpoints |
| Developer portal | No | `azurerm_api_management_portal_*` | Explicitly out of scope |

## Certificates

| Feature | Simulator | Terraform Resource | Notes |
|---------|-----------|-------------------|-------|
| CA certificates | Partial | `azurerm_api_management_certificate` | Trusted cert config |
| Client certificates | Partial | - | Via proxy headers |
| Gateway certificates | No | `azurerm_api_management_gateway_certificate_authority` | Use TLS terminator |

## Not Planned

These features are explicitly out of scope for the simulator:

- Developer Portal (`azurerm_api_management_portal_*`)
- Email templates (`azurerm_api_management_email_template`)
- Notifications (`azurerm_api_management_notification_*`)
- Self-hosted gateway (`azurerm_api_management_gateway`)
- Global/workspace policies distinction
- External cache backends for `cache-*` policies
- `quota-by-key` bandwidth enforcement
- Tag descriptions
