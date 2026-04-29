# 2 - Create And Publish A Product

Source: [Tutorial: Create and publish a product](https://learn.microsoft.com/en-us/azure/api-management/api-management-howto-add-products)

Simulator status: Supported

## Run It Locally

From the repo root:

```bash
export APIM_BASE=http://localhost:8000
export APIM_TENANT_KEY=local-dev-tenant-key
```

These commands assume `tutorial-api` already exists. If you have not imported
it yet, run step 1 first or use `./docs/tutorials/apim-get-started/tutorial01.sh --setup`.

Create the product:

```bash
curl -sS -X PUT -H "X-Apim-Tenant-Key: $APIM_TENANT_KEY" \
  -H "Content-Type: application/json" \
  "$APIM_BASE/apim/management/products/tutorial-product" \
  --data '{"name":"Tutorial Product","description":"Product used by the mirrored APIM tutorials.","require_subscription":true}'
```

Attach the imported API to the product:

```bash
curl -sS -X PUT -H "X-Apim-Tenant-Key: $APIM_TENANT_KEY" \
  -H "Content-Type: application/json" \
  "$APIM_BASE/apim/management/apis/tutorial-api" \
  --data '{"name":"Tutorial API","path":"tutorial-api","upstream_base_url":"http://mock-backend:8080/api","products":["tutorial-product"]}'
```

Create a subscription:

```bash
curl -sS -X POST -H "X-Apim-Tenant-Key: $APIM_TENANT_KEY" \
  -H "Content-Type: application/json" \
  "$APIM_BASE/apim/management/subscriptions" \
  --data '{"id":"tutorial-sub","name":"tutorial-sub","products":["tutorial-product"],"primary_key":"tutorial-key"}'
```

Verify access:

```bash
curl -i "$APIM_BASE/tutorial-api/health"
curl -i -H "Ocp-Apim-Subscription-Key: tutorial-key" "$APIM_BASE/tutorial-api/health"
```

## What Mapped Cleanly

- Product CRUD
- Product-to-API association
- Subscription-backed access

## Shortcut

If you want the scripted shortcut instead of running the commands manually:

```bash
./docs/tutorials/apim-get-started/tutorial02.sh --setup
./docs/tutorials/apim-get-started/tutorial02.sh --verify
```

Use `--setup` to have [`tutorial02.sh`](tutorial02.sh) perform the local setup for this step. Use `--verify` to validate the existing tutorial state without restarting the stack.

Expected key `./docs/tutorials/apim-get-started/tutorial02.sh --verify` output:

```text
Creating product 'tutorial-product'
{
  "id": "tutorial-product",
  "name": "Tutorial Product",
  "require_subscription": true,
  "subscription_count": 0
}

Creating subscription 'tutorial-sub'
{
  "id": "tutorial-sub",
  "name": "tutorial-sub",
  "primary_key": "tutorial-key",
  "products": [
    "tutorial-product"
  ]
}

Verifying product and subscription metadata
$ curl -sS -H "X-Apim-Tenant-Key: local-dev-tenant-key" "http://localhost:8000/apim/management/products/tutorial-product"
{
  "id": "tutorial-product",
  "require_subscription": true,
  "subscription_count": 1
}

$ curl -sS -H "X-Apim-Tenant-Key: local-dev-tenant-key" "http://localhost:8000/apim/management/subscriptions/tutorial-sub"
{
  "id": "tutorial-sub",
  "primary_key": "tutorial-key",
  "products": [
    "tutorial-product"
  ],
  "state": "active"
}

Verifying subscription-backed access
$ curl -i "http://localhost:8000/tutorial-api/health"
{
  "detail": "Missing subscription key",
  "status_code": 401
}

$ curl -sS -H "Ocp-Apim-Subscription-Key: tutorial-key" "http://localhost:8000/tutorial-api/health"
{
  "path": "/api/health",
  "status": "ok"
}
```

## Differences From Azure APIM

- There is no developer portal publication state. Product access is enforced at the gateway.
