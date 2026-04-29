# APIM Simulator Walkthrough: Core Compose Stacks

*2026-04-15T17:47:52Z*

This document was generated from a live run against the local repository. Each section starts the stack, waits for it to become ready, and captures a concise JSON summary plus screenshots where the stack has a browser surface.

## Direct Public Gateway
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

## Direct Public Gateway With OTEL
docker compose  -f compose.yml -f compose.public.yml -f compose.otel.yml up --build -d
#1 [internal] load local bake definitions
#1 reading from stdin 1.50kB done
#1 DONE 0.0s

#2 [mock-backend internal] load build definition from Dockerfile
#2 transferring dockerfile: 378B done
#2 DONE 0.0s

#3 [apim-simulator internal] load build definition from Dockerfile
#3 transferring dockerfile: 969B done
#3 DONE 0.0s

#4 [mock-backend internal] load metadata for dhi.io/python:3.13-debian13
#4 DONE 0.0s

#5 [mock-backend internal] load .dockerignore
#5 transferring context: 2B done
#5 DONE 0.0s

#6 [mock-backend internal] load build context
#6 transferring context: 31B done
#6 DONE 0.0s

#7 [mock-backend 1/3] FROM dhi.io/python:3.13-debian13@sha256:0131b9aa4400da8e0ef4eb110f3dba12c2a3c9b144a2eb831774557b9aceeac6
#7 resolve dhi.io/python:3.13-debian13@sha256:0131b9aa4400da8e0ef4eb110f3dba12c2a3c9b144a2eb831774557b9aceeac6 0.0s done
#7 DONE 0.0s

#8 [mock-backend 2/3] WORKDIR /app
#8 CACHED

#9 [mock-backend 3/3] COPY --chown=65532:65532 server.py .
#9 CACHED

#10 [mock-backend] exporting to image
#10 exporting layers done
#10 exporting manifest sha256:2daa54078fdfac5cdc9d1302b88f2bf4c018ba4f25ca487e9f407057eb403fde done
#10 exporting config sha256:b6e62c939de73bb190b7b854e63fd657d3dc689b0b741b670f35a6b5a162ec1f done
#10 exporting attestation manifest sha256:6ed0b431f9db1a9211403416705cc267db359bdb1afb9a59a5a2e8ecda45ce76 done
#10 exporting manifest list sha256:7c342a9347b4bab05914dda9faaa7537c064fe129ce10ecf54aa09240ddcd718 done
#10 naming to docker.io/library/apim-simulator-mock-backend:latest done
#10 unpacking to docker.io/library/apim-simulator-mock-backend:latest done
#10 DONE 0.1s

#11 [apim-simulator] resolve image config for docker-image://docker.io/docker/dockerfile:1.7
#11 ...

#12 [mock-backend] resolving provenance for metadata file
#12 DONE 0.0s

#11 [apim-simulator] resolve image config for docker-image://docker.io/docker/dockerfile:1.7
#11 DONE 0.4s

#13 [apim-simulator] docker-image://docker.io/docker/dockerfile:1.7@sha256:a57df69d0ea827fb7266491f2813635de6f17269be881f696fbfdf2d83dda33e
#13 resolve docker.io/docker/dockerfile:1.7@sha256:a57df69d0ea827fb7266491f2813635de6f17269be881f696fbfdf2d83dda33e 0.0s done
#13 CACHED

#14 [apim-simulator internal] load metadata for dhi.io/python:3.13-debian13-dev
#14 ...

#15 [apim-simulator internal] load metadata for ghcr.io/astral-sh/uv:0.10.4
#15 DONE 0.3s

#4 [apim-simulator internal] load metadata for dhi.io/python:3.13-debian13
#4 ...

#14 [apim-simulator internal] load metadata for dhi.io/python:3.13-debian13-dev
#14 DONE 0.5s

#4 [apim-simulator internal] load metadata for dhi.io/python:3.13-debian13
#4 DONE 0.5s

#16 [apim-simulator internal] load .dockerignore
#16 transferring context: 204B done
#16 DONE 0.0s

#17 [apim-simulator internal] load build context
#17 transferring context: 6.17kB 0.0s done
#17 DONE 0.0s

#18 [apim-simulator] FROM ghcr.io/astral-sh/uv:0.10.4@sha256:4cac394b6b72846f8a85a7a0e577c6d61d4e17fe2ccee65d9451a8b3c9efb4ac
#18 resolve ghcr.io/astral-sh/uv:0.10.4@sha256:4cac394b6b72846f8a85a7a0e577c6d61d4e17fe2ccee65d9451a8b3c9efb4ac 0.0s done
#18 DONE 0.0s

#19 [apim-simulator stage-1 1/5] FROM dhi.io/python:3.13-debian13@sha256:cb9222e6852d4017973551e444ee5e4af8e601e462415b12c80e7bfecb6efc45
#19 resolve dhi.io/python:3.13-debian13@sha256:cb9222e6852d4017973551e444ee5e4af8e601e462415b12c80e7bfecb6efc45 0.0s done
#19 DONE 0.0s

#20 [apim-simulator builder 1/5] FROM dhi.io/python:3.13-debian13-dev@sha256:845321bee112dc8c2220dfaecc5204096bd8f8ab349a7d8bb862693751aa0e2d
#20 resolve dhi.io/python:3.13-debian13-dev@sha256:845321bee112dc8c2220dfaecc5204096bd8f8ab349a7d8bb862693751aa0e2d 0.0s done
#20 DONE 0.0s

#21 [apim-simulator builder 2/5] WORKDIR /app
#21 CACHED

#22 [apim-simulator stage-1 3/5] COPY --chown=65532:65532 --from=builder /app/.venv /app/.venv
#22 CACHED

#23 [apim-simulator builder 3/5] COPY --from=ghcr.io/astral-sh/uv:0.10.4 /uv /usr/local/bin/uv
#23 CACHED

#24 [apim-simulator builder 5/5] RUN --mount=type=cache,target=/root/.cache/uv     uv sync --frozen --no-dev --no-install-project
#24 CACHED

#25 [apim-simulator builder 4/5] COPY pyproject.toml uv.lock ./
#25 CACHED

#26 [apim-simulator stage-1 4/5] COPY --chown=65532:65532 app ./app
#26 CACHED

#27 [apim-simulator stage-1 2/5] WORKDIR /app
#27 CACHED

#28 [apim-simulator stage-1 5/5] COPY --chown=65532:65532 examples ./examples
#28 CACHED

#29 [apim-simulator] exporting to image
#29 exporting layers done
#29 exporting manifest sha256:a377e9dcf5d19f2f79fdbce233768c87ce524c93323e89fbc0ed602f4fcb938d done
#29 exporting config sha256:a3183a2b1a2121ff39b719dd087dc4d05c6ef26a8950dd869b06d22acabdb07f done
#29 exporting attestation manifest sha256:07c788aba76f3451a3c391abed284d143a662bab56c243c2a7590942ee0f2156 0.0s done
#29 exporting manifest list sha256:84aa9325abd8a0a1a86d0bf52dee733de4829aa231af9f6c8143e1b2e236c5ce done
#29 naming to docker.io/library/apim-simulator:latest done
#29 unpacking to docker.io/library/apim-simulator:latest done
#29 DONE 0.1s

#30 [apim-simulator] resolving provenance for metadata file
#30 DONE 0.0s adds the LGTM stack on [https://lgtm.apim.127.0.0.1.sslip.io:8443](https://lgtm.apim.127.0.0.1.sslip.io:8443) so APIM traffic is visible in Grafana, Loki, Tempo, and Prometheus.

```bash
set -euo pipefail
make down >/dev/null 2>&1 || true
log="$(mktemp)"
make up-otel >"$log" 2>&1 || { cat "$log"; exit 1; }
for _ in $(seq 1 90); do
  curl -fsS http://localhost:8000/apim/health >/dev/null 2>&1 && curl -fsS "$GRAFANA_BASE_URL/api/health" >/dev/null 2>&1 && break
  sleep 1
done
docker compose -f compose.yml -f compose.public.yml -f compose.otel.yml ps --format json | jq -sS .
rm -f "$log"

```

```output
[
  {
    "Command": "\"/app/.venv/bin/pyth…\"",
    "CreatedAt": "2026-04-15 18:48:16 +0100 BST",
    "ExitCode": 0,
    "Health": "",
    "ID": "11546f84b70b",
    "Image": "apim-simulator:latest",
    "Labels": "com.docker.compose.image=sha256:5b7f91253dd00f21741b7e1ec644d8ea23d3c887598a39238e5916d8e29ed1aa,com.docker.compose.oneoff=False,com.docker.compose.version=5.1.1,com.docker.dhi.chain-id=sha256:b9e7c6e6bf9a389eaa805f1244eea298c7ecd133127518ede00ede39add3df83,com.docker.dhi.date.end-of-life=2029-10-31,com.docker.dhi.date.release=2024-10-07,com.docker.dhi.definition=image/python/debian-13/3.13,com.docker.compose.config-hash=b389fb38dd27453fa599cc64aa7e56ce183c6f4b512195894289acdaf05e9504,com.docker.compose.project.config_files=./compose.yml,./compose.public.yml,./compose.otel.yml,com.docker.compose.service=apim-simulator,com.docker.dhi.compliance=cis,com.docker.dhi.name=dhi/python,com.docker.dhi.shell=,com.docker.dhi.url=https://dhi.io/catalog/python,com.docker.dhi.variant=runtime,com.docker.compose.container-number=1,com.docker.compose.project.working_dir=.,com.docker.dhi.distro=debian-13,com.docker.dhi.entitlement=public,com.docker.dhi.flavor=,com.docker.dhi.version=3.13.13-debian13,com.docker.compose.depends_on=mock-backend:service_started:false,lgtm:service_started:false,com.docker.compose.project=apim-simulator,com.docker.dhi.created=2026-04-11T22:45:39Z,com.docker.dhi.package-manager=,com.docker.dhi.title=Python 3.13.x,desktop.docker.io/ports.scheme=v2,desktop.docker.io/ports/8000/tcp=:8000",
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
    "RunningFor": "8 seconds ago",
    "Service": "apim-simulator",
    "Size": "0B",
    "State": "running",
    "Status": "Up 7 seconds"
  },
  {
    "Command": "\"/otel-lgtm/run-all.…\"",
    "CreatedAt": "2026-04-15 18:48:16 +0100 BST",
    "ExitCode": 0,
    "Health": "starting",
    "ID": "9f35ee9370d3",
    "Image": "grafana/otel-lgtm:0.24.0@sha256:a7fbde2893d86ae4807701bc482736243e584eb90b5faa273d291ffff2a1374f",
    "Labels": "com.docker.compose.version=5.1.1,com.redhat.license_terms=https://www.redhat.com/en/about/red-hat-end-user-license-agreements#UBI,desktop.docker.io/binds/1/Source=./observability/grafana/provisioning/dashboards/apim-simulator.yaml,maintainer=Grafana Labs,org.opencontainers.image.ref.name=v0.24.0,org.opencontainers.image.source=https://github.com/grafana/docker-otel-lgtm,release=,vcs-type=git,com.docker.compose.image=sha256:a7fbde2893d86ae4807701bc482736243e584eb90b5faa273d291ffff2a1374f,com.docker.compose.oneoff=False,desktop.docker.io/binds/1/SourceKind=hostFile,desktop.docker.io/binds/2/Target=/otel-lgtm/custom-dashboards,org.opencontainers.image.description=OpenTelemetry backend in a Docker image,org.opencontainers.image.documentation=https://github.com/grafana/docker-otel-lgtm/blob/main/README.md,org.opencontainers.image.vendor=Grafana Labs,build-date=,com.docker.compose.depends_on=,distribution-scope=public,io.buildah.version=,name=grafana/otel-lgtm,vcs-ref=7ac6a7cf03434cc414b5f1228c63b52069cf0f65,com.docker.compose.project.working_dir=.,desktop.docker.io/binds/2/Source=./observability/grafana/dashboards,desktop.docker.io/binds/2/SourceKind=hostFile,io.k8s.display-name=Grafana LGTM,io.openshift.expose-services=,org.opencontainers.image.authors=Grafana Labs,org.opencontainers.image.revision=7ac6a7cf03434cc414b5f1228c63b52069cf0f65,org.opencontainers.image.title=docker-otel-lgtm,com.docker.compose.project=apim-simulator,cpe=,desktop.docker.io/ports/4317/tcp=:4317,desktop.docker.io/ports/4318/tcp=:4318,org.opencontainers.image.licenses=Apache-2.0,summary=An OpenTelemetry backend in a Docker image,com.docker.compose.config-hash=9759eb97aaa5b2755de94820d28d5695a2b75ee9b22bde59eac0493dcf585f1c,com.redhat.component=ubi9-micro-container,desktop.docker.io/binds/1/Target=/otel-lgtm/grafana/conf/provisioning/dashboards/apim-simulator.yaml,io.k8s.description=An open source backend for OpenTelemetry that's intended for development, demo, and testing environments.,org.opencontainers.image.created=2026-04-10T09:33:00.461Z,org.opencontainers.image.version=0.24.0,com.docker.compose.container-number=1,desktop.docker.io/ports.scheme=v2,url=https://github.com/grafana/docker-otel-lgtm,architecture=aarch64,com.docker.compose.project.config_files=./compose.yml,./compose.public.yml,./compose.otel.yml,com.docker.compose.service=lgtm,description=An open source backend for OpenTelemetry that's intended for development, demo, and testing environments.,org.opencontainers.image.url=https://github.com/grafana/docker-otel-lgtm,vendor=Grafana Labs,version=v0.24.0",
    "LocalVolumes": "1",
    "Mounts": "apim-simulator…,/host_mnt/User…,/host_mnt/User…",
    "Name": "apim-simulator-lgtm-1",
    "Names": "apim-simulator-lgtm-1",
    "Networks": "apim-simulator_apim",
    "Ports": "0.0.0.0:4317-4318->4317-4318/tcp, [::]:4317-4318->4317-4318/tcp",
    "Project": "apim-simulator",
    "Publishers": [
      {
        "Protocol": "tcp",
        "PublishedPort": 4317,
        "TargetPort": 4317,
        "URL": "0.0.0.0"
      },
      {
        "Protocol": "tcp",
        "PublishedPort": 4317,
        "TargetPort": 4317,
        "URL": "::"
      },
      {
        "Protocol": "tcp",
        "PublishedPort": 4318,
        "TargetPort": 4318,
        "URL": "0.0.0.0"
      },
      {
        "Protocol": "tcp",
        "PublishedPort": 4318,
        "TargetPort": 4318,
        "URL": "::"
      }
    ],
    "RunningFor": "8 seconds ago",
    "Service": "lgtm",
    "Size": "0B",
    "State": "running",
    "Status": "Up 7 seconds (health: starting)"
  },
  {
    "Command": "\"nginx -g 'daemon of…\"",
    "CreatedAt": "2026-04-15 18:48:16 +0100 BST",
    "ExitCode": 0,
    "Health": "",
    "ID": "2ade30d9a7bc",
    "Image": "dhi.io/nginx:1.29.5-debian13",
    "Labels": "com.docker.compose.image=sha256:9683af47feae3bab0031b489ed85f93f340a0f8b83a2edccc9f761dbfce1bffd,com.docker.compose.oneoff=False,com.docker.compose.project=apim-simulator,com.docker.dhi.compliance=cis,com.docker.dhi.flavor=,com.docker.dhi.title=Nginx mainline,com.docker.dhi.variant=runtime,desktop.docker.io/binds/1/Target=/etc/nginx/nginx.conf,desktop.docker.io/ports.scheme=v2,com.docker.compose.version=5.1.1,com.docker.dhi.definition=image/nginx/debian-13/mainline,com.docker.dhi.name=dhi/nginx,com.docker.dhi.shell=,com.docker.dhi.version=1.29.5-debian13,com.docker.compose.config-hash=3edba5ad2ac9cfd6f4c060a20619a208e20d5ec2e9a3d2aae1578d1f7b06f423,com.docker.compose.project.config_files=./compose.yml,./compose.public.yml,./compose.otel.yml,desktop.docker.io/binds/0/Target=/etc/nginx/certs,com.docker.compose.container-number=1,com.docker.compose.service=lgtm-proxy,com.docker.dhi.created=2026-02-05T05:17:44Z,com.docker.dhi.url=https://dhi.io/catalog/nginx,desktop.docker.io/binds/0/Source=./examples/edge/certs,desktop.docker.io/binds/1/Source=./observability/lgtm/nginx.conf,desktop.docker.io/binds/1/SourceKind=hostFile,com.docker.dhi.chain-id=sha256:12d6f6bfdcac60cd53148007d8b5ee2c5a827f82ad0a8568232264eb95b6f5e2,com.docker.dhi.distro=debian-13,com.docker.compose.depends_on=lgtm:service_started:false,com.docker.dhi.date.release=2025-06-24,desktop.docker.io/binds/0/SourceKind=hostFile,com.docker.compose.project.working_dir=.,com.docker.dhi.package-manager=,desktop.docker.io/ports/8443/tcp=:8443",
    "LocalVolumes": "0",
    "Mounts": "/host_mnt/User…,/host_mnt/User…",
    "Name": "apim-simulator-lgtm-proxy-1",
    "Names": "apim-simulator-lgtm-proxy-1",
    "Networks": "apim-simulator_apim",
    "Ports": "0.0.0.0:8443->8443/tcp, [::]:8443->8443/tcp",
    "Project": "apim-simulator",
    "Publishers": [
      {
        "Protocol": "tcp",
        "PublishedPort": 8443,
        "TargetPort": 8443,
        "URL": "0.0.0.0"
      },
      {
        "Protocol": "tcp",
        "PublishedPort": 8443,
        "TargetPort": 8443,
        "URL": "::"
      }
    ],
    "RunningFor": "8 seconds ago",
    "Service": "lgtm-proxy",
    "Size": "0B",
    "State": "running",
    "Status": "Up 7 seconds"
  },
  {
    "Command": "\"python server.py\"",
    "CreatedAt": "2026-04-15 18:48:16 +0100 BST",
    "ExitCode": 0,
    "Health": "",
    "ID": "c910e8ce877b",
    "Image": "apim-simulator-mock-backend:latest",
    "Labels": "com.docker.dhi.chain-id=sha256:e68172a1b009e121980466426bb3c0b7a6184cc9d5a4200b57ee2dc4292779da,com.docker.dhi.created=2026-04-08T03:14:50Z,com.docker.dhi.entitlement=public,com.docker.dhi.flavor=,com.docker.dhi.shell=,com.docker.dhi.version=3.13.12-debian13,com.docker.compose.container-number=1,com.docker.compose.image=sha256:bc515ad39af9f2ed507bf60cc9b7063361eeba3a84d4bd3475f983d9a707eae5,com.docker.compose.project.config_files=./compose.yml,./compose.public.yml,./compose.otel.yml,com.docker.compose.project.working_dir=.,com.docker.compose.service=mock-backend,com.docker.dhi.date.release=2024-10-07,com.docker.dhi.definition=image/python/debian-13/3.13,com.docker.dhi.url=https://dhi.io/catalog/python,com.docker.compose.project=apim-simulator,com.docker.dhi.date.end-of-life=2029-10-31,com.docker.dhi.title=Python 3.13.x,desktop.docker.io/ports.scheme=v2,com.docker.dhi.compliance=cis,com.docker.compose.depends_on=,com.docker.compose.oneoff=False,com.docker.compose.version=5.1.1,com.docker.dhi.distro=debian-13,com.docker.dhi.name=dhi/python,com.docker.dhi.package-manager=,com.docker.dhi.variant=runtime,com.docker.compose.config-hash=815e10da41b3af6176108902ed23ffc47edfaf9c27a33e160094fa0330e92164",
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
    "RunningFor": "8 seconds ago",
    "Service": "mock-backend",
    "Size": "0B",
    "State": "running",
    "Status": "Up 7 seconds"
  }
]
```

```bash
set -euo pipefail
verify_log="$(mktemp)"
make verify-otel >"$verify_log" 2>&1 || { cat "$verify_log"; exit 1; }
apim_health="$(curl -fsS http://localhost:8000/apim/health)"
grafana_health="$(curl -fsS "$GRAFANA_BASE_URL/api/health")"
jq -n \
  --argjson apim_health "$apim_health" \
  --argjson grafana_health "$grafana_health" \
  --arg verify_log "$(cat "$verify_log")" \
  '{
    apim_health: $apim_health,
    grafana_health: $grafana_health,
    verify_otel: "passed",
    verify_output: ($verify_log | split("\n") | map(select(length > 0)))
  }'
rm -f "$verify_log"

```

```output
{
  "apim_health": {
    "status": "healthy"
  },
  "grafana_health": {
    "database": "ok",
    "version": "12.4.2",
    "commit": "ebade4c739e1aface4ce094934ad85374887a680"
  },
  "verify_otel": "passed",
  "verify_output": [
    "uv run --project . python scripts/verify_otel.py",
    "Grafana healthy: version=12.4.2",
    "APIM metrics visible: 2 series",
    "Loki services: apim-simulator, hello-api",
    "Tempo services: apim-simulator",
    "otel verification passed"
  ]
}
```

```bash {image}
set -euo pipefail
rodney stop >/dev/null 2>&1 || true
rm -f "$HOME/.rodney/chrome-data/SingletonLock"
rodney start >/tmp/rodney-start.log 2>&1 || true
sleep 2
rodney open "$GRAFANA_BASE_URL/d/apim-simulator-overview/apim-simulator-overview" >/dev/null
rodney waitload >/dev/null
rodney waitstable >/dev/null
rodney sleep 2 >/dev/null
rodney screenshot walkthrough-core-grafana.png

```

![b8777299-2026-04-15](b8777299-2026-04-15.png)

## OIDC Gateway
`make up-oidc` adds Keycloak and the OIDC-protected routes used by the simulator’s JWT and role-based auth examples.

```bash
set -euo pipefail
make down >/dev/null 2>&1 || true
log="$(mktemp)"
make up-oidc >"$log" 2>&1 || { cat "$log"; exit 1; }
for _ in $(seq 1 90); do
  curl -fsS http://localhost:8000/apim/health >/dev/null 2>&1 && curl -fsS http://localhost:8180/realms/subnet-calculator/.well-known/openid-configuration >/dev/null 2>&1 && break
  sleep 1
done
docker compose -f compose.yml -f compose.public.yml -f compose.oidc.yml ps --format json | jq -sS .
rm -f "$log"

```

```output
[
  {
    "Command": "\"/app/.venv/bin/pyth…\"",
    "CreatedAt": "2026-04-15 18:49:12 +0100 BST",
    "ExitCode": 0,
    "Health": "",
    "ID": "a753bc501124",
    "Image": "apim-simulator:latest",
    "Labels": "com.docker.dhi.title=Python 3.13.x,desktop.docker.io/ports.scheme=v2,desktop.docker.io/ports/8000/tcp=:8000,com.docker.compose.oneoff=False,com.docker.compose.project=apim-simulator,com.docker.compose.service=apim-simulator,com.docker.compose.version=5.1.1,com.docker.dhi.compliance=cis,com.docker.dhi.date.end-of-life=2029-10-31,com.docker.dhi.entitlement=public,com.docker.dhi.package-manager=,com.docker.compose.config-hash=50e7106276a340ec4c3d60a598d4992f329107921e08f515b71cfa81917ecdae,com.docker.compose.image=sha256:4ac56355f859c1e6fb1c49e89fd8987eff4e8f51b84bf4681c8712b8bb02effc,com.docker.compose.project.config_files=./compose.yml,./compose.public.yml,./compose.oidc.yml,com.docker.dhi.distro=debian-13,com.docker.dhi.flavor=,com.docker.dhi.url=https://dhi.io/catalog/python,com.docker.dhi.variant=runtime,com.docker.dhi.version=3.13.13-debian13,com.docker.compose.depends_on=mock-backend:service_started:false,keycloak:service_healthy:false,com.docker.dhi.chain-id=sha256:b9e7c6e6bf9a389eaa805f1244eea298c7ecd133127518ede00ede39add3df83,com.docker.dhi.date.release=2024-10-07,com.docker.dhi.definition=image/python/debian-13/3.13,com.docker.compose.container-number=1,com.docker.compose.project.working_dir=.,com.docker.dhi.created=2026-04-11T22:45:39Z,com.docker.dhi.name=dhi/python,com.docker.dhi.shell=",
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
    "RunningFor": "32 seconds ago",
    "Service": "apim-simulator",
    "Size": "0B",
    "State": "running",
    "Status": "Up 4 seconds"
  },
  {
    "Command": "\"/opt/keycloak/bin/k…\"",
    "CreatedAt": "2026-04-15 18:49:11 +0100 BST",
    "ExitCode": 0,
    "Health": "healthy",
    "ID": "b57b1caa215f",
    "Image": "quay.io/keycloak/keycloak:26.4.7",
    "Labels": "com.docker.compose.project.config_files=./compose.yml,./compose.public.yml,./compose.oidc.yml,com.docker.compose.service=keycloak,org.opencontainers.image.url=https://github.com/keycloak-rel/keycloak-rel,release=,vcs-ref=,com.redhat.build-host=,description=Keycloak Server Image,desktop.docker.io/binds/0/Source=./examples/subnet-calculator/keycloak/realm-export.json,maintainer=https://www.keycloak.org/,name=keycloak,org.opencontainers.image.created=2025-12-01T08:14:24.495Z,url=https://www.keycloak.org/,vendor=https://www.keycloak.org/,com.docker.compose.depends_on=,desktop.docker.io/binds/0/SourceKind=hostFile,desktop.docker.io/binds/0/Target=/opt/keycloak/data/import/realm-export.json,desktop.docker.io/ports.scheme=v2,com.redhat.component=,com.redhat.license_terms=,desktop.docker.io/ports/8080/tcp=:8180,distribution-scope=public,org.opencontainers.image.description=,org.opencontainers.image.version=26.4.7,version=26.4.7,com.docker.compose.version=5.1.1,architecture=aarch64,build-date=2025-11-12T17:00:10Z,cpe=cpe:/a:redhat:enterprise_linux:9::appstream,io.buildah.version=1.41.4,io.openshift.expose-services=,io.openshift.tags=keycloak security identity,com.docker.compose.image=sha256:9409c59bdfb65dbffa20b11e6f18b8abb9281d480c7ca402f51ed3d5977e6007,com.docker.compose.oneoff=False,io.k8s.description=Keycloak Server Image,org.opencontainers.image.documentation=https://www.keycloak.org/documentation,org.opencontainers.image.licenses=Apache-2.0,org.opencontainers.image.title=keycloak-rel,com.docker.compose.config-hash=ef29ccb00803353c0b6c2627c8f8c5c5b4c07338465efad85e1e1df4aad6ff6c,com.docker.compose.container-number=1,com.docker.compose.project=apim-simulator,io.k8s.display-name=Keycloak Server,org.opencontainers.image.revision=aa3baec457ee0cdfdff6de1ce256319180a76ee6,com.docker.compose.project.working_dir=.,org.opencontainers.image.source=https://github.com/keycloak-rel/keycloak-rel,summary=Keycloak Server Image,vcs-type=git",
    "LocalVolumes": "1",
    "Mounts": "/host_mnt/User…,apim-simulator…",
    "Name": "apim-simulator-keycloak-1",
    "Names": "apim-simulator-keycloak-1",
    "Networks": "apim-simulator_apim",
    "Ports": "0.0.0.0:8180->8080/tcp, [::]:8180->8080/tcp",
    "Project": "apim-simulator",
    "Publishers": [
      {
        "Protocol": "tcp",
        "PublishedPort": 8180,
        "TargetPort": 8080,
        "URL": "0.0.0.0"
      },
      {
        "Protocol": "tcp",
        "PublishedPort": 8180,
        "TargetPort": 8080,
        "URL": "::"
      }
    ],
    "RunningFor": "33 seconds ago",
    "Service": "keycloak",
    "Size": "0B",
    "State": "running",
    "Status": "Up 31 seconds (healthy)"
  },
  {
    "Command": "\"python server.py\"",
    "CreatedAt": "2026-04-15 18:49:11 +0100 BST",
    "ExitCode": 0,
    "Health": "",
    "ID": "8f1816772253",
    "Image": "apim-simulator-mock-backend:latest",
    "Labels": "com.docker.compose.config-hash=815e10da41b3af6176108902ed23ffc47edfaf9c27a33e160094fa0330e92164,com.docker.compose.container-number=1,com.docker.compose.project=apim-simulator,com.docker.compose.service=mock-backend,com.docker.dhi.compliance=cis,com.docker.dhi.shell=,com.docker.compose.image=sha256:9fd8fd14a57c50a5b93e708031688ccee516707a0130dbba6440c736a4c03348,com.docker.compose.project.working_dir=.,com.docker.compose.version=5.1.1,com.docker.dhi.date.end-of-life=2029-10-31,com.docker.dhi.distro=debian-13,com.docker.dhi.flavor=,com.docker.dhi.name=dhi/python,com.docker.dhi.url=https://dhi.io/catalog/python,com.docker.dhi.created=2026-04-08T03:14:50Z,com.docker.dhi.definition=image/python/debian-13/3.13,com.docker.dhi.entitlement=public,com.docker.dhi.title=Python 3.13.x,desktop.docker.io/ports.scheme=v2,com.docker.compose.depends_on=,com.docker.compose.oneoff=False,com.docker.compose.project.config_files=./compose.yml,./compose.public.yml,./compose.oidc.yml,com.docker.dhi.chain-id=sha256:e68172a1b009e121980466426bb3c0b7a6184cc9d5a4200b57ee2dc4292779da,com.docker.dhi.date.release=2024-10-07,com.docker.dhi.package-manager=,com.docker.dhi.variant=runtime,com.docker.dhi.version=3.13.12-debian13",
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
    "RunningFor": "33 seconds ago",
    "Service": "mock-backend",
    "Size": "0B",
    "State": "running",
    "Status": "Up 31 seconds"
  }
]
```

```bash
set -euo pipefail
smoke_log="$(mktemp)"
make smoke-oidc >"$smoke_log" 2>&1 || { cat "$smoke_log"; exit 1; }
well_known="$(curl -fsS http://localhost:8180/realms/subnet-calculator/.well-known/openid-configuration)"
jq -n \
  --argjson well_known "$well_known" \
  --arg smoke_log "$(cat "$smoke_log")" \
  '{
    oidc: {
      issuer: $well_known.issuer,
      authorization_endpoint: $well_known.authorization_endpoint,
      token_endpoint: $well_known.token_endpoint
    },
    smoke_oidc: "passed",
    smoke_output: ($smoke_log | split("\n") | map(select(length > 0)))
  }'
rm -f "$smoke_log"

```

```output
{
  "oidc": {
    "issuer": "http://localhost:8180/realms/subnet-calculator",
    "authorization_endpoint": "http://localhost:8180/realms/subnet-calculator/protocol/openid-connect/auth",
    "token_endpoint": "http://localhost:8180/realms/subnet-calculator/protocol/openid-connect/token"
  },
  "smoke_oidc": "passed",
  "smoke_output": [
    "uv run --project . python scripts/smoke_oidc.py",
    "OIDC smoke passed",
    "- user route: 200",
    "- admin route with user token: 403",
    "- admin route with admin token: 200"
  ]
}
```

## MCP Gateway
`make up-mcp` fronts the example MCP server through APIM and keeps the simulator’s management surface available on the same gateway.

```bash
set -euo pipefail
make down >/dev/null 2>&1 || true
log="$(mktemp)"
make up-mcp >"$log" 2>&1 || { cat "$log"; exit 1; }
for _ in $(seq 1 90); do
  curl -fsS http://localhost:8000/apim/health >/dev/null 2>&1 && break
  sleep 1
done
docker compose -f compose.yml -f compose.public.yml -f compose.mcp.yml ps --format json | jq -sS .
rm -f "$log"

```

```output
[
  {
    "Command": "\"/app/.venv/bin/pyth…\"",
    "CreatedAt": "2026-04-15 18:49:55 +0100 BST",
    "ExitCode": 0,
    "Health": "",
    "ID": "64d2f761d2b7",
    "Image": "apim-simulator:latest",
    "Labels": "com.docker.dhi.url=https://dhi.io/catalog/python,desktop.docker.io/ports/8000/tcp=:8000,com.docker.compose.depends_on=mock-backend:service_started:false,mcp-server:service_started:false,com.docker.compose.oneoff=False,com.docker.compose.project.working_dir=.,com.docker.dhi.definition=image/python/debian-13/3.13,com.docker.dhi.variant=runtime,desktop.docker.io/ports.scheme=v2,com.docker.compose.project.config_files=./compose.yml,./compose.public.yml,./compose.mcp.yml,com.docker.compose.version=5.1.1,com.docker.dhi.date.end-of-life=2029-10-31,com.docker.dhi.date.release=2024-10-07,com.docker.dhi.entitlement=public,com.docker.dhi.name=dhi/python,com.docker.dhi.title=Python 3.13.x,com.docker.dhi.version=3.13.13-debian13,com.docker.dhi.created=2026-04-11T22:45:39Z,com.docker.compose.config-hash=89d52b8bd387d59e28ac75d762420a0367a01503d09a66a17501017daf12ba82,com.docker.compose.container-number=1,com.docker.compose.image=sha256:c536bb9c34dff2292b3ef3c7b02d3edf3ca6cf3cc6d3482bdce97a1a0e29820b,com.docker.compose.service=apim-simulator,com.docker.dhi.chain-id=sha256:b9e7c6e6bf9a389eaa805f1244eea298c7ecd133127518ede00ede39add3df83,com.docker.dhi.flavor=,com.docker.dhi.shell=,com.docker.compose.project=apim-simulator,com.docker.dhi.compliance=cis,com.docker.dhi.distro=debian-13,com.docker.dhi.package-manager=",
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
    "RunningFor": "3 seconds ago",
    "Service": "apim-simulator",
    "Size": "0B",
    "State": "running",
    "Status": "Up 3 seconds"
  },
  {
    "Command": "\"python server.py\"",
    "CreatedAt": "2026-04-15 18:49:54 +0100 BST",
    "ExitCode": 0,
    "Health": "",
    "ID": "d3fd777f68bb",
    "Image": "apim-simulator-mcp-server:latest",
    "Labels": "com.docker.compose.config-hash=76e86f087961052eccf845b8e6e6d6491b69c60f099507b0371c12bc1cb7e490,com.docker.compose.depends_on=,com.docker.compose.oneoff=False,com.docker.compose.project.config_files=./compose.yml,./compose.public.yml,./compose.mcp.yml,com.docker.compose.project.working_dir=.,com.docker.compose.service=mcp-server,com.docker.dhi.distro=debian-13,com.docker.dhi.entitlement=public,com.docker.compose.container-number=1,com.docker.compose.image=sha256:b5bd8e834c6f53d00505b0514953133252c6b429082d16324a928f291a04de67,com.docker.dhi.flavor=,com.docker.dhi.name=dhi/python,com.docker.dhi.package-manager=,com.docker.dhi.shell=,com.docker.dhi.title=Python 3.13.x,com.docker.dhi.url=https://dhi.io/catalog/python,com.docker.dhi.date.end-of-life=2029-10-31,com.docker.dhi.chain-id=sha256:b9e7c6e6bf9a389eaa805f1244eea298c7ecd133127518ede00ede39add3df83,com.docker.dhi.compliance=cis,com.docker.dhi.variant=runtime,com.docker.dhi.version=3.13.13-debian13,desktop.docker.io/ports.scheme=v2,com.docker.compose.project=apim-simulator,com.docker.compose.version=5.1.1,com.docker.dhi.created=2026-04-11T22:45:39Z,com.docker.dhi.date.release=2024-10-07,com.docker.dhi.definition=image/python/debian-13/3.13",
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
    "RunningFor": "4 seconds ago",
    "Service": "mcp-server",
    "Size": "0B",
    "State": "running",
    "Status": "Up 3 seconds"
  },
  {
    "Command": "\"python server.py\"",
    "CreatedAt": "2026-04-15 18:49:54 +0100 BST",
    "ExitCode": 0,
    "Health": "",
    "ID": "0d72cc3024e3",
    "Image": "apim-simulator-mock-backend:latest",
    "Labels": "com.docker.compose.project.config_files=./compose.yml,./compose.public.yml,./compose.mcp.yml,com.docker.dhi.compliance=cis,com.docker.dhi.distro=debian-13,com.docker.dhi.flavor=,com.docker.dhi.package-manager=,com.docker.dhi.shell=,com.docker.compose.project.working_dir=.,com.docker.compose.version=5.1.1,com.docker.dhi.entitlement=public,com.docker.dhi.name=dhi/python,com.docker.dhi.title=Python 3.13.x,com.docker.dhi.url=https://dhi.io/catalog/python,com.docker.dhi.variant=runtime,com.docker.dhi.version=3.13.12-debian13,com.docker.compose.oneoff=False,com.docker.dhi.chain-id=sha256:e68172a1b009e121980466426bb3c0b7a6184cc9d5a4200b57ee2dc4292779da,desktop.docker.io/ports.scheme=v2,com.docker.compose.config-hash=815e10da41b3af6176108902ed23ffc47edfaf9c27a33e160094fa0330e92164,com.docker.compose.depends_on=,com.docker.compose.project=apim-simulator,com.docker.compose.service=mock-backend,com.docker.dhi.created=2026-04-08T03:14:50Z,com.docker.dhi.date.end-of-life=2029-10-31,com.docker.dhi.date.release=2024-10-07,com.docker.dhi.definition=image/python/debian-13/3.13,com.docker.compose.container-number=1,com.docker.compose.image=sha256:dcd23288639cdade64afb7dc90bab9b8e1ef16d07c3d6ea8216fa1ff287bc9cc",
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
  }
]
```

```bash
set -euo pipefail
smoke_log="$(mktemp)"
make smoke-mcp >"$smoke_log" 2>&1 || { cat "$smoke_log"; exit 1; }
status="$(curl -fsS -H 'X-Apim-Tenant-Key: local-dev-tenant-key' http://localhost:8000/apim/management/status)"
jq -n \
  --argjson status "$status" \
  --arg smoke_log "$(cat "$smoke_log")" \
  '{
    management: {
      service: $status.service,
      counts: $status.counts
    },
    smoke_mcp: "passed",
    smoke_output: ($smoke_log | split("\n") | map(select(length > 0)))
  }'
rm -f "$smoke_log"

```

```output
{
  "management": {
    "service": {
      "id": "service/apim-simulator",
      "name": "apim-simulator",
      "display_name": "Local APIM Simulator"
    },
    "counts": {
      "routes": 2,
      "apis": 0,
      "operations": 0,
      "api_revisions": 0,
      "api_releases": 0,
      "products": 1,
      "subscriptions": 1,
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
  "smoke_mcp": "passed",
  "smoke_output": [
    "SMOKE_MCP_URL=\"http://localhost:8000/mcp\" uv run --project . --extra mcp python scripts/smoke_mcp.py",
    "MCP smoke passed",
    "- server: APIM Simulator Demo MCP Server",
    "- tools: add_numbers, uppercase",
    "- add_numbers: {",
    "  \"sum\": 5",
    "}"
  ]
}
```

## Edge HTTP
`make up-edge` terminates through the nginx edge proxy on `edge.apim.127.0.0.1.sslip.io:8088` and verifies forwarded-host behavior before the request reaches APIM and the MCP backend.

```bash
set -euo pipefail
make down >/dev/null 2>&1 || true
log="$(mktemp)"
make up-edge >"$log" 2>&1 || { cat "$log"; exit 1; }
for _ in $(seq 1 90); do
  curl -fsS http://edge.apim.127.0.0.1.sslip.io:8088/apim/health >/dev/null 2>&1 && break
  sleep 1
done
docker compose -f compose.yml -f compose.edge.yml -f compose.mcp.yml ps --format json | jq -sS .
rm -f "$log"

```

```output
[
  {
    "Command": "\"/app/.venv/bin/pyth…\"",
    "CreatedAt": "2026-04-15 18:50:04 +0100 BST",
    "ExitCode": 0,
    "Health": "",
    "ID": "adc2c9713271",
    "Image": "apim-simulator:latest",
    "Labels": "com.docker.compose.config-hash=5c27086d953febdfac2390b708c2c51cd71042d962fb28529d6492eedc1325d0,com.docker.compose.container-number=1,com.docker.compose.image=sha256:432a72cf7db481da8417b46acc491aec6af4af9625fc3866f06175324710fa24,com.docker.compose.oneoff=False,com.docker.dhi.created=2026-04-11T22:45:39Z,com.docker.dhi.distro=debian-13,com.docker.dhi.package-manager=,com.docker.dhi.title=Python 3.13.x,com.docker.compose.project=apim-simulator,com.docker.compose.project.config_files=./compose.yml,./compose.edge.yml,./compose.mcp.yml,com.docker.compose.project.working_dir=.,com.docker.compose.service=apim-simulator,com.docker.dhi.entitlement=public,com.docker.dhi.flavor=,com.docker.dhi.url=https://dhi.io/catalog/python,com.docker.compose.depends_on=mock-backend:service_started:false,mcp-server:service_started:false,com.docker.compose.version=5.1.1,com.docker.dhi.compliance=cis,com.docker.dhi.date.release=2024-10-07,com.docker.dhi.version=3.13.13-debian13,desktop.docker.io/ports.scheme=v2,com.docker.dhi.chain-id=sha256:b9e7c6e6bf9a389eaa805f1244eea298c7ecd133127518ede00ede39add3df83,com.docker.dhi.date.end-of-life=2029-10-31,com.docker.dhi.definition=image/python/debian-13/3.13,com.docker.dhi.name=dhi/python,com.docker.dhi.shell=,com.docker.dhi.variant=runtime",
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
    "CreatedAt": "2026-04-15 18:50:04 +0100 BST",
    "ExitCode": 0,
    "Health": "",
    "ID": "37343685b6fb",
    "Image": "dhi.io/nginx:1.29.5-debian13",
    "Labels": "com.docker.dhi.compliance=cis,com.docker.dhi.flavor=,desktop.docker.io/binds/0/SourceKind=hostFile,desktop.docker.io/ports/8088/tcp=:8088,com.docker.compose.service=edge-proxy,com.docker.dhi.variant=runtime,desktop.docker.io/binds/1/Source=./examples/edge/certs,com.docker.compose.container-number=1,com.docker.compose.project=apim-simulator,com.docker.dhi.definition=image/nginx/debian-13/mainline,com.docker.dhi.shell=,com.docker.dhi.version=1.29.5-debian13,desktop.docker.io/binds/0/Source=./examples/edge/nginx.conf,desktop.docker.io/binds/1/SourceKind=hostFile,com.docker.compose.config-hash=ca5babfe6a96c106d59ef2047b15e782aa4fa9ef4ce1e895a97824f075c9e4d1,com.docker.compose.image=sha256:9683af47feae3bab0031b489ed85f93f340a0f8b83a2edccc9f761dbfce1bffd,com.docker.dhi.chain-id=sha256:12d6f6bfdcac60cd53148007d8b5ee2c5a827f82ad0a8568232264eb95b6f5e2,com.docker.dhi.date.release=2025-06-24,com.docker.compose.depends_on=apim-simulator:service_started:false,com.docker.compose.oneoff=False,com.docker.compose.project.working_dir=.,com.docker.compose.version=5.1.1,com.docker.dhi.url=https://dhi.io/catalog/nginx,com.docker.dhi.created=2026-02-05T05:17:44Z,com.docker.dhi.title=Nginx mainline,desktop.docker.io/ports.scheme=v2,com.docker.dhi.package-manager=,com.docker.dhi.distro=debian-13,com.docker.dhi.name=dhi/nginx,desktop.docker.io/binds/0/Target=/etc/nginx/nginx.conf,desktop.docker.io/binds/1/Target=/etc/nginx/certs,com.docker.compose.project.config_files=./compose.yml,./compose.edge.yml,./compose.mcp.yml",
    "LocalVolumes": "0",
    "Mounts": "/host_mnt/User…,/host_mnt/User…",
    "Name": "apim-simulator-edge-proxy-1",
    "Names": "apim-simulator-edge-proxy-1",
    "Networks": "apim-simulator_apim",
    "Ports": "0.0.0.0:8088->8088/tcp, [::]:8088->8088/tcp",
    "Project": "apim-simulator",
    "Publishers": [
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
    "CreatedAt": "2026-04-15 18:50:04 +0100 BST",
    "ExitCode": 0,
    "Health": "",
    "ID": "2636ac9c6e07",
    "Image": "apim-simulator-mcp-server:latest",
    "Labels": "com.docker.dhi.url=https://dhi.io/catalog/python,desktop.docker.io/ports.scheme=v2,com.docker.dhi.date.end-of-life=2029-10-31,com.docker.compose.project=apim-simulator,com.docker.compose.project.working_dir=.,com.docker.compose.service=mcp-server,com.docker.dhi.compliance=cis,com.docker.dhi.flavor=,com.docker.dhi.variant=runtime,com.docker.compose.config-hash=76e86f087961052eccf845b8e6e6d6491b69c60f099507b0371c12bc1cb7e490,com.docker.dhi.chain-id=sha256:b9e7c6e6bf9a389eaa805f1244eea298c7ecd133127518ede00ede39add3df83,com.docker.dhi.date.release=2024-10-07,com.docker.dhi.distro=debian-13,com.docker.dhi.version=3.13.13-debian13,com.docker.compose.container-number=1,com.docker.compose.depends_on=,com.docker.compose.oneoff=False,com.docker.compose.project.config_files=./compose.yml,./compose.edge.yml,./compose.mcp.yml,com.docker.dhi.definition=image/python/debian-13/3.13,com.docker.dhi.entitlement=public,com.docker.dhi.name=dhi/python,com.docker.dhi.shell=,com.docker.compose.image=sha256:efc9d99d15e8db9a87310d96e6e13e299efa052cb3ca8603496016f35bcf3b9a,com.docker.compose.version=5.1.1,com.docker.dhi.created=2026-04-11T22:45:39Z,com.docker.dhi.package-manager=,com.docker.dhi.title=Python 3.13.x",
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
    "Status": "Up 2 seconds"
  },
  {
    "Command": "\"python server.py\"",
    "CreatedAt": "2026-04-15 18:50:04 +0100 BST",
    "ExitCode": 0,
    "Health": "",
    "ID": "4a251af56478",
    "Image": "apim-simulator-mock-backend:latest",
    "Labels": "com.docker.compose.project.working_dir=.,com.docker.compose.service=mock-backend,com.docker.compose.version=5.1.1,com.docker.dhi.package-manager=,com.docker.dhi.shell=,com.docker.compose.depends_on=,com.docker.dhi.chain-id=sha256:e68172a1b009e121980466426bb3c0b7a6184cc9d5a4200b57ee2dc4292779da,com.docker.dhi.compliance=cis,com.docker.dhi.date.end-of-life=2029-10-31,com.docker.dhi.definition=image/python/debian-13/3.13,com.docker.dhi.entitlement=public,com.docker.dhi.title=Python 3.13.x,com.docker.dhi.url=https://dhi.io/catalog/python,com.docker.dhi.created=2026-04-08T03:14:50Z,com.docker.compose.image=sha256:92e533844f282721faac59253c89f9f29e9035166ad4cbda481219c6241d08d2,com.docker.compose.oneoff=False,com.docker.dhi.date.release=2024-10-07,com.docker.dhi.flavor=,com.docker.dhi.variant=runtime,com.docker.compose.project=apim-simulator,com.docker.dhi.distro=debian-13,com.docker.dhi.name=dhi/python,com.docker.dhi.version=3.13.12-debian13,desktop.docker.io/ports.scheme=v2,com.docker.compose.config-hash=815e10da41b3af6176108902ed23ffc47edfaf9c27a33e160094fa0330e92164,com.docker.compose.container-number=1,com.docker.compose.project.config_files=./compose.yml,./compose.edge.yml,./compose.mcp.yml",
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
    "Status": "Up 2 seconds"
  }
]
```

```bash
set -euo pipefail
smoke_log="$(mktemp)"
make smoke-edge >"$smoke_log" 2>&1 || { cat "$smoke_log"; exit 1; }
edge_echo="$(curl -fsS -H 'Ocp-Apim-Subscription-Key: mcp-demo-key' -H 'x-apim-trace: true' http://edge.apim.127.0.0.1.sslip.io:8088/__edge/echo)"
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
    smoke_edge: "passed",
    smoke_output: ($smoke_log | split("\n") | map(select(length > 0)))
  }'
rm -f "$smoke_log"

```

```output
{
  "edge_echo": {
    "path": "/api/echo",
    "host": "edge.apim.127.0.0.1.sslip.io:8088",
    "forwarded_host": "edge.apim.127.0.0.1.sslip.io:8088",
    "forwarded_proto": "http"
  },
  "smoke_edge": "passed",
  "smoke_output": [
    "SMOKE_EDGE_BASE_URL=\"http://edge.apim.127.0.0.1.sslip.io:8088\" uv run --project . --extra mcp python scripts/smoke_edge.py",
    "MCP smoke passed",
    "- server: APIM Simulator Demo MCP Server",
    "- tools: add_numbers, uppercase",
    "- add_numbers: {",
    "  \"sum\": 5",
    "}",
    "Edge smoke passed",
    "- base_url: http://edge.apim.127.0.0.1.sslip.io:8088",
    "- forwarded_host: edge.apim.127.0.0.1.sslip.io:8088",
    "- forwarded_proto: http"
  ]
}
```

## Edge TLS
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

## Private Internal Stack
The private shape intentionally does not publish `localhost:8000`. Validation happens through the internal smoke runner container instead.

```bash
set -euo pipefail
make down >/dev/null 2>&1 || true
log="$(mktemp)"
docker compose -f compose.yml -f compose.private.yml -f compose.mcp.yml up --build -d >"$log" 2>&1 || { cat "$log"; exit 1; }
docker compose -f compose.yml -f compose.private.yml -f compose.mcp.yml ps --format json | jq -sS .
rm -f "$log"

```

```output
[
  {
    "Command": "\"/app/.venv/bin/pyth…\"",
    "CreatedAt": "2026-04-15 18:50:25 +0100 BST",
    "ExitCode": 0,
    "Health": "",
    "ID": "43bb53d8679c",
    "Image": "apim-simulator:latest",
    "Labels": "com.docker.dhi.created=2026-04-11T22:45:39Z,com.docker.dhi.date.end-of-life=2029-10-31,com.docker.compose.config-hash=5c27086d953febdfac2390b708c2c51cd71042d962fb28529d6492eedc1325d0,com.docker.compose.oneoff=False,com.docker.compose.project=apim-simulator,com.docker.dhi.chain-id=sha256:b9e7c6e6bf9a389eaa805f1244eea298c7ecd133127518ede00ede39add3df83,com.docker.dhi.entitlement=public,com.docker.dhi.package-manager=,com.docker.compose.project.working_dir=.,com.docker.compose.service=apim-simulator,com.docker.dhi.date.release=2024-10-07,com.docker.dhi.shell=,com.docker.dhi.variant=runtime,com.docker.dhi.version=3.13.13-debian13,com.docker.compose.container-number=1,com.docker.compose.depends_on=mcp-server:service_started:false,mock-backend:service_started:false,com.docker.compose.project.config_files=./compose.yml,./compose.private.yml,./compose.mcp.yml,com.docker.compose.version=5.1.1,com.docker.dhi.definition=image/python/debian-13/3.13,com.docker.dhi.title=Python 3.13.x,desktop.docker.io/ports.scheme=v2,com.docker.compose.image=sha256:0af983bbcead2d8a1795f2fecfc2e1396b62872af46fa862796b9a17b9247a9f,com.docker.dhi.compliance=cis,com.docker.dhi.distro=debian-13,com.docker.dhi.flavor=,com.docker.dhi.name=dhi/python,com.docker.dhi.url=https://dhi.io/catalog/python",
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
    "RunningFor": "1 second ago",
    "Service": "apim-simulator",
    "Size": "0B",
    "State": "running",
    "Status": "Up Less than a second"
  },
  {
    "Command": "\"python server.py\"",
    "CreatedAt": "2026-04-15 18:50:25 +0100 BST",
    "ExitCode": 0,
    "Health": "",
    "ID": "7bf240dc9315",
    "Image": "apim-simulator-mcp-server:latest",
    "Labels": "desktop.docker.io/ports.scheme=v2,com.docker.compose.depends_on=,com.docker.compose.project.working_dir=.,com.docker.compose.service=mcp-server,com.docker.dhi.created=2026-04-11T22:45:39Z,com.docker.dhi.distro=debian-13,com.docker.dhi.flavor=,com.docker.dhi.package-manager=,com.docker.compose.oneoff=False,com.docker.compose.project.config_files=./compose.yml,./compose.private.yml,./compose.mcp.yml,com.docker.dhi.chain-id=sha256:b9e7c6e6bf9a389eaa805f1244eea298c7ecd133127518ede00ede39add3df83,com.docker.dhi.date.release=2024-10-07,com.docker.dhi.definition=image/python/debian-13/3.13,com.docker.dhi.name=dhi/python,com.docker.dhi.url=https://dhi.io/catalog/python,com.docker.compose.config-hash=76e86f087961052eccf845b8e6e6d6491b69c60f099507b0371c12bc1cb7e490,com.docker.compose.image=sha256:9521c9d10b4f3dece1df99fd06a48f3f89c76f8505d0ed2aef3c74c72f9c6f95,com.docker.dhi.compliance=cis,com.docker.dhi.date.end-of-life=2029-10-31,com.docker.dhi.shell=,com.docker.dhi.variant=runtime,com.docker.dhi.version=3.13.13-debian13,com.docker.compose.container-number=1,com.docker.compose.project=apim-simulator,com.docker.compose.version=5.1.1,com.docker.dhi.entitlement=public,com.docker.dhi.title=Python 3.13.x",
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
    "RunningFor": "1 second ago",
    "Service": "mcp-server",
    "Size": "0B",
    "State": "running",
    "Status": "Up Less than a second"
  },
  {
    "Command": "\"python server.py\"",
    "CreatedAt": "2026-04-15 18:50:25 +0100 BST",
    "ExitCode": 0,
    "Health": "",
    "ID": "160dd25d470d",
    "Image": "apim-simulator-mock-backend:latest",
    "Labels": "com.docker.dhi.distro=debian-13,com.docker.dhi.package-manager=,com.docker.compose.container-number=1,com.docker.compose.service=mock-backend,com.docker.dhi.name=dhi/python,com.docker.dhi.shell=,com.docker.dhi.title=Python 3.13.x,com.docker.dhi.variant=runtime,desktop.docker.io/ports.scheme=v2,com.docker.compose.project.config_files=./compose.yml,./compose.private.yml,./compose.mcp.yml,com.docker.dhi.chain-id=sha256:e68172a1b009e121980466426bb3c0b7a6184cc9d5a4200b57ee2dc4292779da,com.docker.dhi.created=2026-04-08T03:14:50Z,com.docker.dhi.url=https://dhi.io/catalog/python,com.docker.dhi.version=3.13.12-debian13,com.docker.compose.config-hash=815e10da41b3af6176108902ed23ffc47edfaf9c27a33e160094fa0330e92164,com.docker.compose.image=sha256:b534c73059b1fd56e44fe459a481e83899e6ed44194122a07910cfde9f158701,com.docker.compose.version=5.1.1,com.docker.dhi.compliance=cis,com.docker.dhi.date.release=2024-10-07,com.docker.dhi.entitlement=public,com.docker.dhi.flavor=,com.docker.compose.depends_on=,com.docker.compose.oneoff=False,com.docker.compose.project=apim-simulator,com.docker.compose.project.working_dir=.,com.docker.dhi.date.end-of-life=2029-10-31,com.docker.dhi.definition=image/python/debian-13/3.13",
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
    "RunningFor": "1 second ago",
    "Service": "mock-backend",
    "Size": "0B",
    "State": "running",
    "Status": "Up Less than a second"
  }
]
```

```bash
set -euo pipefail
smoke_log="$(mktemp)"
make smoke-private >"$smoke_log" 2>&1 || { cat "$smoke_log"; exit 1; }
jq -n \
  --arg smoke_log "$(cat "$smoke_log")" \
  '{
    localhost_8000_reachable: false,
    smoke_private: "passed",
    smoke_output: ($smoke_log | split("\n") | map(select(length > 0)))
  }'
rm -f "$smoke_log"

```

```output
{
  "localhost_8000_reachable": false,
  "smoke_private": "passed",
  "smoke_output": [
    "/Applications/Xcode.app/Contents/Developer/usr/bin/make check-private-port-clear",
    "uv run --project . python -c \"import socket; sock = socket.socket(); sock.settimeout(1); code = sock.connect_ex(('127.0.0.1', 8000)); sock.close(); print('Host port 8000 is unavailable, as required for private mode.') if code else (_ for _ in ()).throw(SystemExit('localhost:8000 is already reachable before private-mode launch; stop the conflicting listener before continuing'))\"",
    "Host port 8000 is unavailable, as required for private mode.",
    "docker compose  -f compose.yml -f compose.private.yml -f compose.mcp.yml run --rm --entrypoint python3 smoke-runner scripts/run_smoke_private.py",
    " Container apim-simulator-smoke-runner-run-3e6554f326c8 Creating ",
    " Container apim-simulator-smoke-runner-run-3e6554f326c8 Created ",
    "MCP smoke passed",
    "- server: APIM Simulator Demo MCP Server",
    "- tools: add_numbers, uppercase",
    "- add_numbers: {",
    "  \"sum\": 5",
    "}",
    "Private smoke passed",
    "- base_url: http://apim-simulator:8000"
  ]
}
```

## Operator Console
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
