# APIM Simulator Walkthrough: Operator Console

Generated from a live run against the local repository.

`make up-ui` adds the local operator console on `localhost:3007` against a management-enabled APIM stack.

```bash
set -euo pipefail
make down >/dev/null 2>&1 || true
log="$(mktemp)"
make up-ui >"$log" 2>&1 || { cat "$log"; exit 1; }
ready=false
for _ in $(seq 1 120); do
  if curl -fsS http://localhost:8000/apim/health >/dev/null 2>&1 && curl -fsS http://localhost:3007 >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 1
done
if [[ "$ready" != true ]]; then
  echo "operator console did not become ready on http://localhost:3007 within 120 seconds" >&2
  docker compose -f compose.yml -f compose.public.yml -f compose.ui.yml ps -a --format json | jq -sS .
  docker compose -f compose.yml -f compose.public.yml -f compose.ui.yml logs --tail 200 ui || true
  exit 1
fi
docker compose -f compose.yml -f compose.public.yml -f compose.ui.yml ps -a --format json | jq -sS .
rm -f "$log"

```

```output
[
  {
    "Command": "\"/app/.venv/bin/pyth…\"",
    "CreatedAt": "2026-04-15 18:50:51 +0100 BST",
    "ExitCode": 0,
    "Health": "",
    "ID": "1280a3b819e6",
    "Image": "apim-simulator:latest",
    "Labels": "com.docker.compose.project.working_dir=.,com.docker.dhi.created=2026-04-11T22:45:39Z,com.docker.dhi.name=dhi/python,com.docker.dhi.package-manager=,com.docker.dhi.shell=,com.docker.dhi.title=Python 3.13.x,com.docker.dhi.variant=runtime,com.docker.compose.depends_on=mock-backend:service_started:false,com.docker.compose.project.config_files=./compose.yml,./compose.public.yml,./compose.ui.yml,com.docker.dhi.definition=image/python/debian-13/3.13,com.docker.dhi.flavor=,com.docker.dhi.url=https://dhi.io/catalog/python,desktop.docker.io/ports/8000/tcp=:8000,com.docker.compose.config-hash=fc84d85a61e7fa831fc9d291714e609bd24f49a8843adc65ce9964da0a37f3f3,com.docker.compose.oneoff=False,com.docker.compose.service=apim-simulator,com.docker.compose.version=5.1.1,com.docker.dhi.version=3.13.13-debian13,desktop.docker.io/ports.scheme=v2,com.docker.compose.container-number=1,com.docker.compose.project=apim-simulator,com.docker.dhi.chain-id=sha256:b9e7c6e6bf9a389eaa805f1244eea298c7ecd133127518ede00ede39add3df83,com.docker.dhi.compliance=cis,com.docker.dhi.date.end-of-life=2029-10-31,com.docker.dhi.date.release=2024-10-07,com.docker.dhi.distro=debian-13,com.docker.dhi.entitlement=public,com.docker.compose.image=sha256:f65ba8be51f0e631503f526d607f5c5ff3e30cea709178f13a87f0f74f1bb6cf",
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
    "RunningFor": "4 seconds ago",
    "Service": "apim-simulator",
    "Size": "0B",
    "State": "running",
    "Status": "Up 2 seconds"
  },
  {
    "Command": "\"python server.py\"",
    "CreatedAt": "2026-04-15 18:50:51 +0100 BST",
    "ExitCode": 0,
    "Health": "",
    "ID": "ca77955d09b0",
    "Image": "apim-simulator-mock-backend:latest",
    "Labels": "com.docker.compose.version=5.1.1,com.docker.dhi.created=2026-04-08T03:14:50Z,com.docker.dhi.date.release=2024-10-07,desktop.docker.io/ports.scheme=v2,com.docker.compose.config-hash=815e10da41b3af6176108902ed23ffc47edfaf9c27a33e160094fa0330e92164,com.docker.compose.project.config_files=./compose.yml,./compose.public.yml,./compose.ui.yml,com.docker.dhi.name=dhi/python,com.docker.dhi.shell=,com.docker.compose.image=sha256:b308e4f7a9c37bd58e039daecd8cdf5f6fedcc2c271ba807dc863127f197b8cf,com.docker.compose.project=apim-simulator,com.docker.dhi.chain-id=sha256:e68172a1b009e121980466426bb3c0b7a6184cc9d5a4200b57ee2dc4292779da,com.docker.dhi.compliance=cis,com.docker.dhi.definition=image/python/debian-13/3.13,com.docker.dhi.flavor=,com.docker.dhi.package-manager=,com.docker.dhi.url=https://dhi.io/catalog/python,com.docker.compose.container-number=1,com.docker.compose.oneoff=False,com.docker.compose.project.working_dir=.,com.docker.dhi.distro=debian-13,com.docker.dhi.entitlement=public,com.docker.dhi.title=Python 3.13.x,com.docker.dhi.variant=runtime,com.docker.dhi.version=3.13.12-debian13,com.docker.dhi.date.end-of-life=2029-10-31,com.docker.compose.depends_on=,com.docker.compose.service=mock-backend",
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
    "RunningFor": "4 seconds ago",
    "Service": "mock-backend",
    "Size": "0B",
    "State": "running",
    "Status": "Up 3 seconds"
  },
  {
    "Command": "\"nginx -g 'daemon of…\"",
    "CreatedAt": "2026-04-15 18:50:52 +0100 BST",
    "ExitCode": 0,
    "Health": "",
    "ID": "716ec0d5d1dc",
    "Image": "apim-simulator-ui:latest",
    "Labels": "com.docker.compose.config-hash=9185a0c60a1b363b2fe8eaaf4805b0cd9ac3603d36bd3beb210ac23d3b6e871b,com.docker.compose.container-number=1,com.docker.compose.image=sha256:6cd11070c5da8ef6cb33bcaaa317f04d8eb42f791d27f38472eb2eb5be55619b,com.docker.compose.project=apim-simulator,com.docker.compose.project.working_dir=.,com.docker.dhi.shell=,com.docker.dhi.title=Nginx mainline,com.docker.dhi.url=https://dhi.io/catalog/nginx,com.docker.compose.depends_on=apim-simulator:service_started:false,com.docker.compose.project.config_files=./compose.yml,./compose.public.yml,./compose.ui.yml,com.docker.compose.service=ui,com.docker.dhi.flavor=,com.docker.dhi.package-manager=,com.docker.dhi.variant=runtime,com.docker.dhi.version=1.29.5-debian13,desktop.docker.io/ports.scheme=v2,com.docker.dhi.compliance=cis,com.docker.dhi.created=2026-02-05T05:17:44Z,com.docker.compose.oneoff=False,com.docker.compose.version=5.1.1,com.docker.dhi.chain-id=sha256:12d6f6bfdcac60cd53148007d8b5ee2c5a827f82ad0a8568232264eb95b6f5e2,com.docker.dhi.distro=debian-13,desktop.docker.io/ports/8080/tcp=:3007,com.docker.dhi.date.release=2025-06-24,com.docker.dhi.definition=image/nginx/debian-13/mainline,com.docker.dhi.name=dhi/nginx",
    "LocalVolumes": "0",
    "Mounts": "",
    "Name": "apim-simulator-ui-1",
    "Names": "apim-simulator-ui-1",
    "Networks": "apim-simulator_default",
    "Ports": "0.0.0.0:3007->8080/tcp, [::]:3007->8080/tcp",
    "Project": "apim-simulator",
    "Publishers": [
      {
        "Protocol": "tcp",
        "PublishedPort": 3007,
        "TargetPort": 8080,
        "URL": "0.0.0.0"
      },
      {
        "Protocol": "tcp",
        "PublishedPort": 3007,
        "TargetPort": 8080,
        "URL": "::"
      }
    ],
    "RunningFor": "3 seconds ago",
    "Service": "ui",
    "Size": "0B",
    "State": "running",
    "Status": "Up 2 seconds"
  }
]
```

```bash
set -euo pipefail
status="$(curl -fsS -H 'X-Apim-Tenant-Key: local-dev-tenant-key' http://localhost:8000/apim/management/status)"
jq -n \
  --argjson status "$status" \
  '{
    operator_console: {
      url: "http://localhost:3007",
      gateway_target: "http://localhost:8000"
    },
    management: {
      service: $status.service,
      counts: $status.counts
    }
  }'

```

```output
{
  "operator_console": {
    "url": "http://localhost:3007",
    "gateway_target": "http://localhost:8000"
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
  }
}
```

```bash {image}
set -euo pipefail
rodney stop >/dev/null 2>&1 || true
rm -f "$HOME/.rodney/chrome-data/SingletonLock"
rodney start >/tmp/rodney-start.log 2>&1 || true
sleep 2
rodney open http://localhost:3007 >/dev/null
rodney waitload >/dev/null
rodney waitstable >/dev/null
rodney sleep 2 >/dev/null
rodney screenshot walkthrough-core-operator-console.png

```

![cbc2ccf4-2026-04-15](cbc2ccf4-2026-04-15.png)
