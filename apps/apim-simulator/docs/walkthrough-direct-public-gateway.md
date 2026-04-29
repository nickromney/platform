# APIM Simulator Walkthrough: Direct Public Gateway

Generated from a live run against the local repository.

`make up` is the smallest APIM-shaped path: gateway, mock backend, and the management surface on `localhost:8000`.

```bash
set -euo pipefail
make down >/dev/null 2>&1 || true
log="$(mktemp)"
make up >"$log" 2>&1 || { cat "$log"; exit 1; }
for _ in $(seq 1 60); do
  curl -fsS http://localhost:8000/apim/health >/dev/null 2>&1 && break
  sleep 1
done
docker compose -f compose.yml -f compose.public.yml ps --format json | jq -sS .
rm -f "$log"

```

```output
[
  {
    "Command": "\"/app/.venv/bin/pyth…\"",
    "CreatedAt": "2026-04-15 18:47:57 +0100 BST",
    "ExitCode": 0,
    "Health": "",
    "ID": "cab3870a60d4",
    "Image": "apim-simulator:latest",
    "Labels": "com.docker.dhi.name=dhi/python,com.docker.dhi.url=https://dhi.io/catalog/python,com.docker.dhi.variant=runtime,desktop.docker.io/ports.scheme=v2,desktop.docker.io/ports/8000/tcp=:8000,com.docker.dhi.date.end-of-life=2029-10-31,com.docker.dhi.date.release=2024-10-07,com.docker.dhi.distro=debian-13,com.docker.dhi.flavor=,com.docker.dhi.version=3.13.13-debian13,com.docker.compose.oneoff=False,com.docker.compose.service=apim-simulator,com.docker.dhi.created=2026-04-11T22:45:39Z,com.docker.dhi.definition=image/python/debian-13/3.13,com.docker.dhi.entitlement=public,com.docker.dhi.package-manager=,com.docker.dhi.shell=,com.docker.dhi.title=Python 3.13.x,com.docker.compose.container-number=1,com.docker.compose.depends_on=mock-backend:service_started:false,com.docker.compose.image=sha256:4efb3fc10c0fb3273d0c1e80dade70c4756e8d41da5a9575e488b8477187aad4,com.docker.compose.project=apim-simulator,com.docker.compose.project.config_files=./compose.yml,./compose.public.yml,com.docker.compose.project.working_dir=.,com.docker.dhi.chain-id=sha256:b9e7c6e6bf9a389eaa805f1244eea298c7ecd133127518ede00ede39add3df83,com.docker.dhi.compliance=cis,com.docker.compose.config-hash=fc84d85a61e7fa831fc9d291714e609bd24f49a8843adc65ce9964da0a37f3f3,com.docker.compose.version=5.1.1",
    "LocalVolumes": "0",
    "Mounts": "",
    "Name": "apim-simulator-apim-simulator-1",
    "Names": "apim-simulator-apim-simulator-1",
    "Networks": "apim-simulator_apim",
    "Ports": "0.0.0.0:8000->8000/tcp, [::]:8000->8000/tcp",
    "Project": "apim-simulator",
    "Publishers": [
      {
        "Protocol": "tcp",
        "PublishedPort": 8000,
        "TargetPort": 8000,
        "URL": "0.0.0.0"
      },
      {
        "Protocol": "tcp",
        "PublishedPort": 8000,
        "TargetPort": 8000,
        "URL": "::"
      }
    ],
    "RunningFor": "5 seconds ago",
    "Service": "apim-simulator",
    "Size": "0B",
    "State": "running",
    "Status": "Up 4 seconds"
  },
  {
    "Command": "\"python server.py\"",
    "CreatedAt": "2026-04-15 18:47:57 +0100 BST",
    "ExitCode": 0,
    "Health": "",
    "ID": "6d26dabeed3b",
    "Image": "apim-simulator-mock-backend:latest",
    "Labels": "com.docker.dhi.url=https://dhi.io/catalog/python,com.docker.compose.image=sha256:22ff868e22fbafbe581f262effd566a0c0fab0da62ae529ed4573bf2bd7ed2df,com.docker.compose.project.working_dir=.,com.docker.compose.service=mock-backend,com.docker.compose.version=5.1.1,com.docker.dhi.date.release=2024-10-07,com.docker.dhi.definition=image/python/debian-13/3.13,com.docker.dhi.title=Python 3.13.x,com.docker.dhi.variant=runtime,com.docker.compose.config-hash=815e10da41b3af6176108902ed23ffc47edfaf9c27a33e160094fa0330e92164,com.docker.compose.container-number=1,com.docker.compose.depends_on=,com.docker.compose.oneoff=False,com.docker.dhi.flavor=,com.docker.dhi.package-manager=,desktop.docker.io/ports.scheme=v2,com.docker.dhi.chain-id=sha256:e68172a1b009e121980466426bb3c0b7a6184cc9d5a4200b57ee2dc4292779da,com.docker.dhi.compliance=cis,com.docker.dhi.name=dhi/python,com.docker.dhi.shell=,com.docker.dhi.version=3.13.12-debian13,com.docker.compose.project=apim-simulator,com.docker.compose.project.config_files=./compose.yml,./compose.public.yml,com.docker.dhi.created=2026-04-08T03:14:50Z,com.docker.dhi.date.end-of-life=2029-10-31,com.docker.dhi.distro=debian-13,com.docker.dhi.entitlement=public",
    "LocalVolumes": "0",
    "Mounts": "",
    "Name": "apim-simulator-mock-backend-1",
    "Names": "apim-simulator-mock-backend-1",
    "Networks": "apim-simulator_apim",
    "Ports": "8080/tcp",
    "Project": "apim-simulator",
    "Publishers": [
      {
        "Protocol": "tcp",
        "PublishedPort": 0,
        "TargetPort": 8080,
        "URL": ""
      }
    ],
    "RunningFor": "5 seconds ago",
    "Service": "mock-backend",
    "Size": "0B",
    "State": "running",
    "Status": "Up 4 seconds"
  }
]
```

```bash
set -euo pipefail
health="$(curl -fsS http://localhost:8000/apim/health)"
startup="$(curl -fsS http://localhost:8000/apim/startup)"
status="$(curl -fsS -H 'X-Apim-Tenant-Key: local-dev-tenant-key' http://localhost:8000/apim/management/status)"
echo_payload="$(curl -fsS http://localhost:8000/api/echo)"
jq -n \
  --argjson health "$health" \
  --argjson startup "$startup" \
  --argjson status "$status" \
  --argjson echo_payload "$echo_payload" \
  '{
    health: $health,
    startup: $startup,
    management: {
      service: $status.service,
      counts: $status.counts
    },
    echo: {
      path: $echo_payload.path,
      auth_method: $echo_payload.headers["x-apim-auth-method"],
      user_email: $echo_payload.headers["x-apim-user-email"]
    }
  }'

```

```output
{
  "health": {
    "status": "healthy"
  },
  "startup": {
    "status": "started"
  },
  "management": {
    "service": {
      "id": "service/apim-simulator",
      "name": "apim-simulator",
      "display_name": "Local APIM Simulator"
    },
    "counts": {
      "routes": 2,
      "apis": 1,
      "operations": 2,
      "api_revisions": 0,
      "api_releases": 0,
      "products": 1,
      "subscriptions": 0,
      "backends": 0,
      "named_values": 0,
      "loggers": 0,
      "diagnostics": 0,
      "api_version_sets": 0,
      "policy_fragments": 0,
      "users": 0,
      "groups": 0,
      "tags": 0,
      "recent_traces": 0
    }
  },
  "echo": {
    "path": "/api/echo",
    "auth_method": "oidc",
    "user_email": "demo@dev.test"
  }
}
```
