# Migrating From AWS API Gateway

This starter keeps the backend tiny but presents a local APIM shape that feels
familiar if you are coming from API Gateway.

What it demonstrates:

- a stage-like path at `/prod/...`
- a usage-plan style product plus subscription key
- a reusable named backend
- a policy fragment that stamps a stage header

## Run It

Use the existing hello backend stack and point the simulator at this config:

```bash
HELLO_APIM_CONFIG_PATH=/app/examples/migrating-from-aws-api-gateway/apim.http-api.json make up-hello
```

Then call it through APIM:

```bash
curl -H "Ocp-Apim-Subscription-Key: aws-migration-demo-key" http://localhost:8000/prod/health
curl -H "Ocp-Apim-Subscription-Key: aws-migration-demo-key" http://localhost:8000/prod/hello
```

This config also enables the local management API with tenant key
`local-dev-tenant-key`, so you can inspect the loaded service and API metadata
while you test the route shape.

## Files

- `apim.http-api.json`: stage-style APIM config for the hello backend
- [`docs/MIGRATING-FROM-AWS-API-GATEWAY.md`](../../docs/MIGRATING-FROM-AWS-API-GATEWAY.md): concept mapping guide
