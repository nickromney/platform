# Migrating From AWS API Gateway

This simulator is a good fit when you want a cheaper, local-first place to
learn APIM concepts without needing the full Azure control plane.

The first target is AWS API Gateway HTTP API and REST API users. WebSocket and
developer portal migration paths are still out of scope.

## Mental Model Mapping

| AWS API Gateway concept | Local APIM simulator concept |
| --- | --- |
| API | `apis.<id>` |
| Route or method | `apis.<id>.operations.<id>` |
| Stage | API `path` or local env-specific config |
| Integration | `backends.<id>` or API `upstream_base_url` |
| Usage plan + API key | `product` + `subscription` |
| Authorizer | `oidc`, `oidc_providers`, `authz`, or `validate-jwt` policy |
| Mapping template or parameter mapping | APIM policy XML |
| CloudWatch logs / X-Ray | OTEL + Grafana LGTM + `/apim/trace/{id}` |

## Practical Translation

### Stage

If you are used to `/dev` or `/prod`, model that locally with the API path.

Example:

- AWS style: `/prod/orders`
- local simulator style: API path `prod` plus operation `/orders`

### Usage Plan And API Key

Model usage plans as products and client API keys as subscriptions.

- product decides whether a subscription is required
- subscription carries the key pair
- APIs and operations attach to products

### Authorizer

Model JWT authorizers with:

- `oidc` or `oidc_providers` for issuer and audience
- `authz.required_roles`
- `authz.required_scopes`
- `authz.required_claims`

If you are already thinking in policy terms, use `validate-jwt`.

### Integration

Model upstream integrations with:

- API `upstream_base_url` for the simple case
- `backends` when you want reusable backend config or credentials

### Mapping And Transformation

Model request and response shaping with policies. Common starting points:

- `set-header`
- `set-query-parameter`
- `rewrite-uri`
- `set-body`
- `include-fragment`

### Diagnostics

Use the local tools together:

- `/apim/trace/{id}` for APIM-style per-request detail
- `/apim/management/traces` for recent trace browsing
- Grafana on `http://localhost:3001` when LGTM is enabled

## Starter Example

Use the starter under
[`examples/migrating-from-aws-api-gateway/`](../examples/migrating-from-aws-api-gateway/README.md)
when you want a familiar stage-like path and usage-plan style access pattern.

Bring it up on the existing hello backend with:

```bash
HELLO_APIM_CONFIG_PATH=/app/examples/migrating-from-aws-api-gateway/apim.http-api.json make up-hello
curl -H "Ocp-Apim-Subscription-Key: aws-migration-demo-key" http://localhost:8000/prod/hello
```

## Good First Moves

1. Start with subscription-only access and prove the path works.
2. Add JWT validation once the basic flow is stable.
3. Move request shaping into policies only after the routing and auth path is green.
4. Use the management summary and trace endpoints before debugging raw policy XML.
