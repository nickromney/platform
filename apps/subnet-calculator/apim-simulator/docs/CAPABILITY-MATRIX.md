# APIM Simulator Capability Matrix

This document maps simulator features to Azure APIM concepts and their Terraform resource equivalents.

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
| Client cert (mTLS) | Yes | `azurerm_api_management.client_certificate_enabled` | `client_certificate.mode` |
| Negotiate client cert | Yes | `azurerm_api_management.hostname_configuration.negotiate_client_certificate` | Via proxy headers |
| SKU selection | N/A | `azurerm_api_management.sku_name` | Simulator is single-instance |
| Zones / HA | N/A | `azurerm_api_management.zones` | Not applicable |
| Virtual network | N/A | `azurerm_api_management.virtual_network_configuration` | Use k8s networking |
| Custom domains | N/A | `azurerm_api_management.hostname_configuration` | Use ingress/gateway |

## APIs and Operations

| Feature | Simulator | Terraform Resource | Notes |
|---------|-----------|-------------------|-------|
| API definition | Yes | `azurerm_api_management_api` | `apis` map in config |
| Operations | Yes | `azurerm_api_management_api_operation` | `operations` within API |
| Path routing | Yes | - | `path_prefix` matching |
| Method routing | Yes | - | Per-operation `method` |
| API Version Sets | Yes | `azurerm_api_management_api_version_set` | Header/Query/Segment schemes |
| OpenAPI import | No | `azurerm_api_management_api` (import block) | Config is manual JSON |
| GraphQL | No | `azurerm_api_management_api` | Not implemented |
| WebSocket | No | `azurerm_api_management_api` | Not implemented |

## Products and Subscriptions

| Feature | Simulator | Terraform Resource | Notes |
|---------|-----------|-------------------|-------|
| Products | Yes | `azurerm_api_management_product` | `products` map |
| Product-API association | Yes | `azurerm_api_management_product_api` | `products` list on route/API |
| Subscriptions | Yes | `azurerm_api_management_subscription` | `subscription.subscriptions` |
| Primary/secondary keys | Yes | - | `keys.primary`, `keys.secondary` |
| Subscription state | Yes | - | `active`, `suspended`, `cancelled` |
| Key rotation | Yes | - | `/apim/management/subscriptions/{id}/rotate` |
| Require subscription | Yes | `azurerm_api_management_product.subscription_required` | Per-product toggle |
| Subscription bypass | Yes | - | Header conditions |
| Approval required | No | `azurerm_api_management_product.approval_required` | Auto-approved |
| Subscription limits | No | `azurerm_api_management_product.subscriptions_limit` | Not enforced |

## Users and Groups

| Feature | Simulator | Terraform Resource | Notes |
|---------|-----------|-------------------|-------|
| Users | Partial | `azurerm_api_management_user` | Config only, no auth |
| Groups | Partial | `azurerm_api_management_group` | Config only |
| Group membership | Partial | `azurerm_api_management_group_user` | Config only |
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
| `return-response` | Yes | - | Short-circuit with custom response |
| `choose`/`when`/`otherwise` | Yes | - | Conditional logic |
| `check-header` | Yes | - | Required header validation |
| `ip-filter` | Yes | - | Allow/deny IP ranges |
| `cors` | Partial | - | Basic CORS headers |
| `rate-limit` | Yes | - | Calls per period |
| `rate-limit-by-key` | Partial | - | Uses subscription ID |
| `quota` | Yes | - | Calls per renewal period |
| `quota-by-key` | Partial | - | Uses subscription ID |
| `validate-jwt` | No | - | Use OIDC config instead |
| `authentication-basic` | Partial | - | Backend auth only |
| `authentication-certificate` | Partial | - | Backend auth config |
| `authentication-managed-identity` | Partial | - | Backend auth config |
| `set-backend-service` | Partial | - | Via `backend` reference |
| `cache-*` | No | - | Not implemented |
| `mock-response` | No | - | Use `return-response` |
| `send-request` | No | - | Not implemented |
| `log-to-eventhub` | No | - | Use observability stack |

## Backends

| Feature | Simulator | Terraform Resource | Notes |
|---------|-----------|-------------------|-------|
| Backend definitions | Yes | `azurerm_api_management_backend` | `backends` map |
| Backend URL | Yes | - | `url` field |
| Basic auth | Yes | - | `auth_type: basic` |
| Client cert auth | Partial | - | `auth_type: client_certificate` |
| Managed identity | Partial | - | `auth_type: managed_identity` |
| Circuit breaker | No | - | Not implemented |
| Load balancing | No | - | Single upstream |

## Management Plane

| Feature | Simulator | Terraform Resource | Notes |
|---------|-----------|-------------------|-------|
| Tenant access keys | Yes | `azurerm_api_management.tenant_access` | Primary/secondary |
| Subscription CRUD | Partial | - | Rotate only via API |
| Config import | Yes | - | Terraform JSON import |
| Git integration | No | `azurerm_api_management.management.git_configuration_enabled` | Use GitOps |

## Observability

| Feature | Simulator | Terraform Resource | Notes |
|---------|-----------|-------------------|-------|
| Correlation ID | Yes | - | `X-Correlation-Id` header |
| Trace header | Yes | - | `X-Apim-Trace: true` |
| Trace lookup | Yes | - | `/apim/trace/{id}` |
| Application Insights | No | `azurerm_api_management.application_insights` | Use external APM |
| Diagnostic logs | No | `azurerm_api_management_diagnostic` | Use container logs |

## Named Values / Secrets

| Feature | Simulator | Terraform Resource | Notes |
|---------|-----------|-------------------|-------|
| Named values | Partial | `azurerm_api_management_named_value` | Config only, no policy refs |
| Secret values | Partial | - | `secret: true` flag |
| Key Vault refs | No | - | Use k8s secrets |

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
- Tags and tag descriptions
- Global/workspace policies distinction
- API revision/release management
