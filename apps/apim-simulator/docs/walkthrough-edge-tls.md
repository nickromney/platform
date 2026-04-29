# APIM Simulator Walkthrough: Edge TLS

Generated from a live run against the local repository.

`make up-tls` uses the generated development certificate and the same forwarded-header path, but on `https://edge.apim.127.0.0.1.sslip.io:9443`.

```bash
set -euo pipefail
make down >/dev/null 2>&1 || true
log="$(mktemp)"
make up-tls >"$log" 2>&1 || { cat "$log"; exit 1; }
for _ in $(seq 1 90); do
  curl --cacert examples/edge/certs/dev-root-ca.crt -fsS https://edge.apim.127.0.0.1.sslip.io:9443/apim/health >/dev/null 2>&1 && break
  sleep 1
done
docker compose -f compose.yml -f compose.edge.yml -f compose.tls.yml -f compose.mcp.yml ps --format json | jq -sS .
rm -f "$log"

```

```output
[
  {
    "Command": "\"/app/.venv/bin/pyth…\"",
    "CreatedAt": "2026-04-15 18:50:16 +0100 BST",
    "ExitCode": 0,
    "Health": "",
    "ID": "ddd0f8a2d726",
    "Image": "apim-simulator:latest",
    "Labels": "com.docker.compose.container-number=1,com.docker.compose.depends_on=mock-backend:service_started:false,mcp-server:service_started:false,com.docker.compose.oneoff=False,com.docker.compose.project.config_files=./compose.yml,./compose.edge.yml,./compose.tls.yml,./compose.mcp.yml,com.docker.dhi.distro=debian-13,com.docker.dhi.package-manager=,desktop.docker.io/ports.scheme=v2,com.docker.dhi.chain-id=sha256:b9e7c6e6bf9a389eaa805f1244eea298c7ecd133127518ede00ede39add3df83,com.docker.dhi.compliance=cis,com.docker.dhi.date.end-of-life=2029-10-31,com.docker.dhi.title=Python 3.13.x,com.docker.dhi.url=https://dhi.io/catalog/python,com.docker.compose.version=5.1.1,com.docker.compose.image=sha256:495e1359b2b43528b718bfc42535894c1a5fd541c5e8f3d1256a7d903928f20d,com.docker.compose.project=apim-simulator,com.docker.compose.project.working_dir=.,com.docker.compose.service=apim-simulator,com.docker.dhi.date.release=2024-10-07,com.docker.dhi.entitlement=public,com.docker.dhi.flavor=,com.docker.compose.config-hash=5c27086d953febdfac2390b708c2c51cd71042d962fb28529d6492eedc1325d0,com.docker.dhi.definition=image/python/debian-13/3.13,com.docker.dhi.name=dhi/python,com.docker.dhi.shell=,com.docker.dhi.variant=runtime,com.docker.dhi.version=3.13.13-debian13,com.docker.dhi.created=2026-04-11T22:45:39Z",
    "LocalVolumes": "0",
    "Mounts": "",
    "Name": "apim-simulator-apim-simulator-1",
    "Names": "apim-simulator-apim-simulator-1",
    "Networks": "apim-simulator_apim",
    "Ports": "8000/tcp",
    "Project": "apim-simulator",
    "Publishers": [
      {
        "Protocol": "tcp",
        "PublishedPort": 0,
        "TargetPort": 8000,
        "URL": ""
      }
    ],
    "RunningFor": "3 seconds ago",
    "Service": "apim-simulator",
    "Size": "0B",
    "State": "running",
    "Status": "Up 2 seconds"
  },
  {
    "Command": "\"nginx -g 'daemon of…\"",
    "CreatedAt": "2026-04-15 18:50:16 +0100 BST",
    "ExitCode": 0,
    "Health": "",
    "ID": "02faeae6b00e",
    "Image": "dhi.io/nginx:1.29.5-debian13",
    "Labels": "com.docker.compose.container-number=1,com.docker.compose.oneoff=False,com.docker.dhi.date.release=2025-06-24,com.docker.dhi.name=dhi/nginx,com.docker.dhi.shell=,com.docker.compose.config-hash=33f815aa155a448631c2a6a0ae730cdaa3378d8a2e4c26b1e00bdc0734b9350c,com.docker.dhi.flavor=,com.docker.dhi.title=Nginx mainline,com.docker.dhi.version=1.29.5-debian13,desktop.docker.io/ports/8080/tcp=:8080,com.docker.compose.image=sha256:9683af47feae3bab0031b489ed85f93f340a0f8b83a2edccc9f761dbfce1bffd,com.docker.compose.service=edge-proxy,com.docker.dhi.compliance=cis,com.docker.compose.project.config_files=./compose.yml,./compose.edge.yml,./compose.tls.yml,./compose.mcp.yml,com.docker.compose.version=5.1.1,com.docker.dhi.created=2026-02-05T05:17:44Z,com.docker.dhi.definition=image/nginx/debian-13/mainline,com.docker.dhi.url=https://dhi.io/catalog/nginx,com.docker.dhi.variant=runtime,desktop.docker.io/binds/0/Source=./examples/edge/certs,desktop.docker.io/binds/0/Target=/etc/nginx/certs,com.docker.compose.depends_on=apim-simulator:service_started:false,com.docker.compose.project=apim-simulator,com.docker.compose.project.working_dir=.,com.docker.dhi.chain-id=sha256:12d6f6bfdcac60cd53148007d8b5ee2c5a827f82ad0a8568232264eb95b6f5e2,com.docker.dhi.distro=debian-13,desktop.docker.io/binds/0/SourceKind=hostFile,desktop.docker.io/binds/1/SourceKind=hostFile,desktop.docker.io/binds/1/Target=/etc/nginx/nginx.conf,desktop.docker.io/binds/1/Source=./examples/edge/nginx.conf,desktop.docker.io/ports/8088/tcp=:8088,com.docker.dhi.package-manager=,desktop.docker.io/ports.scheme=v2,desktop.docker.io/ports/8443/tcp=:9443",
    "LocalVolumes": "0",
    "Mounts": "/host_mnt/User…,/host_mnt/User…",
    "Name": "apim-simulator-edge-proxy-1",
    "Names": "apim-simulator-edge-proxy-1",
    "Networks": "apim-simulator_apim",
    "Ports": "0.0.0.0:8080->8080/tcp, [::]:8080->8080/tcp, 0.0.0.0:8088->8088/tcp, [::]:8088->8088/tcp, 0.0.0.0:9443->8443/tcp, [::]:9443->8443/tcp",
    "Project": "apim-simulator",
    "Publishers": [
      {
        "Protocol": "tcp",
        "PublishedPort": 8080,
        "TargetPort": 8080,
        "URL": "0.0.0.0"
      },
      {
        "Protocol": "tcp",
        "PublishedPort": 8080,
        "TargetPort": 8080,
        "URL": "::"
      },
      {
        "Protocol": "tcp",
        "PublishedPort": 8088,
        "TargetPort": 8088,
        "URL": "0.0.0.0"
      },
      {
        "Protocol": "tcp",
        "PublishedPort": 8088,
        "TargetPort": 8088,
        "URL": "::"
      },
      {
        "Protocol": "tcp",
        "PublishedPort": 9443,
        "TargetPort": 8443,
        "URL": "0.0.0.0"
      },
      {
        "Protocol": "tcp",
        "PublishedPort": 9443,
        "TargetPort": 8443,
        "URL": "::"
      }
    ],
    "RunningFor": "3 seconds ago",
    "Service": "edge-proxy",
    "Size": "0B",
    "State": "running",
    "Status": "Up 2 seconds"
  },
  {
    "Command": "\"python server.py\"",
    "CreatedAt": "2026-04-15 18:50:16 +0100 BST",
    "ExitCode": 0,
    "Health": "",
    "ID": "97650cc95a66",
    "Image": "apim-simulator-mcp-server:latest",
    "Labels": "com.docker.compose.project.working_dir=.,com.docker.dhi.chain-id=sha256:b9e7c6e6bf9a389eaa805f1244eea298c7ecd133127518ede00ede39add3df83,com.docker.dhi.compliance=cis,com.docker.dhi.created=2026-04-11T22:45:39Z,com.docker.dhi.definition=image/python/debian-13/3.13,com.docker.dhi.distro=debian-13,com.docker.compose.depends_on=,com.docker.compose.image=sha256:76a934d17b79d779dd4e8cfb1c9c912180299c89b1c4e9f0b75f9ee481db488b,com.docker.compose.project=apim-simulator,com.docker.dhi.flavor=,com.docker.dhi.shell=,com.docker.dhi.title=Python 3.13.x,com.docker.dhi.version=3.13.13-debian13,desktop.docker.io/ports.scheme=v2,com.docker.compose.container-number=1,com.docker.dhi.date.end-of-life=2029-10-31,com.docker.dhi.entitlement=public,com.docker.dhi.name=dhi/python,com.docker.dhi.package-manager=,com.docker.dhi.url=https://dhi.io/catalog/python,com.docker.compose.project.config_files=./compose.yml,./compose.edge.yml,./compose.tls.yml,./compose.mcp.yml,com.docker.compose.service=mcp-server,com.docker.compose.version=5.1.1,com.docker.dhi.date.release=2024-10-07,com.docker.dhi.variant=runtime,com.docker.compose.config-hash=76e86f087961052eccf845b8e6e6d6491b69c60f099507b0371c12bc1cb7e490,com.docker.compose.oneoff=False",
    "LocalVolumes": "0",
    "Mounts": "",
    "Name": "apim-simulator-mcp-server-1",
    "Names": "apim-simulator-mcp-server-1",
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
    "RunningFor": "3 seconds ago",
    "Service": "mcp-server",
    "Size": "0B",
    "State": "running",
    "Status": "Up 3 seconds"
  },
  {
    "Command": "\"python server.py\"",
    "CreatedAt": "2026-04-15 18:50:16 +0100 BST",
    "ExitCode": 0,
    "Health": "",
    "ID": "c69e6ff75e8f",
    "Image": "apim-simulator-mock-backend:latest",
    "Labels": "com.docker.compose.config-hash=815e10da41b3af6176108902ed23ffc47edfaf9c27a33e160094fa0330e92164,com.docker.compose.image=sha256:d74009d0fd9b9d10529b391b3d643ffaa36aa6db0a0c5cb9bc5d5bda917e8eca,com.docker.compose.oneoff=False,com.docker.compose.project.config_files=./compose.yml,./compose.edge.yml,./compose.tls.yml,./compose.mcp.yml,com.docker.compose.service=mock-backend,com.docker.compose.version=5.1.1,com.docker.dhi.chain-id=sha256:e68172a1b009e121980466426bb3c0b7a6184cc9d5a4200b57ee2dc4292779da,com.docker.dhi.title=Python 3.13.x,com.docker.compose.container-number=1,com.docker.dhi.compliance=cis,com.docker.dhi.distro=debian-13,com.docker.dhi.shell=,com.docker.dhi.variant=runtime,com.docker.dhi.created=2026-04-08T03:14:50Z,com.docker.dhi.date.end-of-life=2029-10-31,com.docker.dhi.date.release=2024-10-07,com.docker.dhi.definition=image/python/debian-13/3.13,com.docker.dhi.name=dhi/python,com.docker.dhi.url=https://dhi.io/catalog/python,com.docker.dhi.version=3.13.12-debian13,desktop.docker.io/ports.scheme=v2,com.docker.compose.depends_on=,com.docker.compose.project=apim-simulator,com.docker.compose.project.working_dir=.,com.docker.dhi.entitlement=public,com.docker.dhi.flavor=,com.docker.dhi.package-manager=",
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
    "RunningFor": "3 seconds ago",
    "Service": "mock-backend",
    "Size": "0B",
    "State": "running",
    "Status": "Up 3 seconds"
  }
]
```

```bash
set -euo pipefail
smoke_log="$(mktemp)"
make smoke-tls >"$smoke_log" 2>&1 || { cat "$smoke_log"; exit 1; }
edge_echo="$(curl --cacert examples/edge/certs/dev-root-ca.crt -fsS -H 'Ocp-Apim-Subscription-Key: mcp-demo-key' -H 'x-apim-trace: true' https://edge.apim.127.0.0.1.sslip.io:9443/__edge/echo)"
jq -n \
  --argjson edge_echo "$edge_echo" \
  --arg smoke_log "$(cat "$smoke_log")" \
  '{
    edge_echo: {
      path: $edge_echo.path,
      host: $edge_echo.headers.host,
      forwarded_host: $edge_echo.headers["x-forwarded-host"],
      forwarded_proto: $edge_echo.headers["x-forwarded-proto"]
    },
    smoke_tls: "passed",
    smoke_output: ($smoke_log | split("\n") | map(select(length > 0)))
  }'
rm -f "$smoke_log"

```

```output
{
  "edge_echo": {
    "path": "/api/echo",
    "host": "edge.apim.127.0.0.1.sslip.io:9443",
    "forwarded_host": "edge.apim.127.0.0.1.sslip.io:9443",
    "forwarded_proto": "https"
  },
  "smoke_tls": "passed",
  "smoke_output": [
    "SMOKE_EDGE_BASE_URL=\"https://edge.apim.127.0.0.1.sslip.io:9443\" uv run --project . --extra mcp python scripts/smoke_edge.py",
    "MCP smoke passed",
    "- server: APIM Simulator Demo MCP Server",
    "- tools: add_numbers, uppercase",
    "- add_numbers: {",
    "  \"sum\": 5",
    "}",
    "Edge smoke passed",
    "- base_url: https://edge.apim.127.0.0.1.sslip.io:9443",
    "- forwarded_host: edge.apim.127.0.0.1.sslip.io:9443",
    "- forwarded_proto: https"
  ]
}
```
