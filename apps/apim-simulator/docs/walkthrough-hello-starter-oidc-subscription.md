# APIM Simulator Walkthrough: Hello Starter With OIDC And Subscription

Generated from a live run against the local repository.

`make up-hello-oidc-subscription` combines bearer token checks with the APIM product subscription gate.

```bash
set -euo pipefail
make down >/dev/null 2>&1 || true
log="$(mktemp)"
make up-hello-oidc-subscription >"$log" 2>&1 || { cat "$log"; exit 1; }
for _ in $(seq 1 90); do
  curl -fsS http://localhost:8000/apim/health >/dev/null 2>&1 && curl -fsS http://localhost:8180/realms/subnet-calculator/.well-known/openid-configuration >/dev/null 2>&1 && break
  sleep 1
done
docker compose -f compose.yml -f compose.public.yml -f compose.oidc.yml -f compose.hello.yml ps --format json | jq -sS .
rm -f "$log"

```

```output
[
  {
    "Command": "\"/app/.venv/bin/pyth…\"",
    "CreatedAt": "2026-04-15 18:52:09 +0100 BST",
    "ExitCode": 0,
    "Health": "",
    "ID": "a907f3b7f489",
    "Image": "apim-simulator:latest",
    "Labels": "com.docker.compose.version=5.1.1,com.docker.dhi.date.end-of-life=2029-10-31,com.docker.dhi.name=dhi/python,com.docker.dhi.package-manager=,com.docker.dhi.version=3.13.13-debian13,desktop.docker.io/ports/8000/tcp=:8000,com.docker.compose.config-hash=182bceddcd030d4fbd1463d617d6b52c9273c2e4eb75b8aa7363001625553890,com.docker.compose.service=apim-simulator,com.docker.dhi.date.release=2024-10-07,com.docker.dhi.definition=image/python/debian-13/3.13,com.docker.dhi.flavor=,com.docker.dhi.variant=runtime,com.docker.compose.container-number=1,com.docker.compose.image=sha256:32593056f7827797d0c6667d5f52b3851c7eeb6d2fb91da2fb2bac71811cf9a9,com.docker.compose.project.config_files=./compose.yml,./compose.public.yml,./compose.oidc.yml,./compose.hello.yml,com.docker.compose.project.working_dir=.,com.docker.dhi.compliance=cis,com.docker.dhi.entitlement=public,com.docker.dhi.url=https://dhi.io/catalog/python,com.docker.compose.depends_on=keycloak:service_healthy:false,hello-api:service_healthy:false,mock-backend:service_started:false,com.docker.compose.project=apim-simulator,com.docker.dhi.chain-id=sha256:b9e7c6e6bf9a389eaa805f1244eea298c7ecd133127518ede00ede39add3df83,com.docker.dhi.created=2026-04-11T22:45:39Z,com.docker.dhi.distro=debian-13,com.docker.dhi.shell=,com.docker.dhi.title=Python 3.13.x,desktop.docker.io/ports.scheme=v2,com.docker.compose.oneoff=False",
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
    "RunningFor": "25 seconds ago",
    "Service": "apim-simulator",
    "Size": "0B",
    "State": "running",
    "Status": "Up 3 seconds"
  },
  {
    "Command": "\"/app/.venv/bin/uvic…\"",
    "CreatedAt": "2026-04-15 18:52:08 +0100 BST",
    "ExitCode": 0,
    "Health": "healthy",
    "ID": "0a49c74a3892",
    "Image": "apim-simulator-hello-api:latest",
    "Labels": "com.docker.compose.config-hash=67f3fb3e730931d9496f989084f451727082e3f09840e8df8a4194d43f2b4014,com.docker.compose.version=5.1.1,com.docker.dhi.date.release=2024-10-07,com.docker.dhi.definition=image/python/debian-13/3.13,com.docker.dhi.shell=,desktop.docker.io/ports.scheme=v2,com.docker.compose.container-number=1,com.docker.compose.image=sha256:50d6d978121c1a1343a8f951170837c4ec874d56d5c17d2e4575c2d5e25db30b,com.docker.compose.project=apim-simulator,com.docker.compose.project.config_files=./compose.yml,./compose.public.yml,./compose.oidc.yml,./compose.hello.yml,com.docker.compose.service=hello-api,com.docker.dhi.chain-id=sha256:b9e7c6e6bf9a389eaa805f1244eea298c7ecd133127518ede00ede39add3df83,com.docker.dhi.flavor=,com.docker.dhi.name=dhi/python,com.docker.compose.oneoff=False,com.docker.compose.project.working_dir=.,com.docker.dhi.compliance=cis,com.docker.dhi.created=2026-04-11T22:45:39Z,com.docker.dhi.distro=debian-13,com.docker.dhi.url=https://dhi.io/catalog/python,com.docker.dhi.variant=runtime,com.docker.compose.depends_on=,com.docker.dhi.date.end-of-life=2029-10-31,com.docker.dhi.entitlement=public,com.docker.dhi.package-manager=,com.docker.dhi.title=Python 3.13.x,com.docker.dhi.version=3.13.13-debian13",
    "LocalVolumes": "0",
    "Mounts": "",
    "Name": "apim-simulator-hello-api-1",
    "Names": "apim-simulator-hello-api-1",
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
    "RunningFor": "26 seconds ago",
    "Service": "hello-api",
    "Size": "0B",
    "State": "running",
    "Status": "Up 25 seconds (healthy)"
  },
  {
    "Command": "\"/opt/keycloak/bin/k…\"",
    "CreatedAt": "2026-04-15 18:52:08 +0100 BST",
    "ExitCode": 0,
    "Health": "healthy",
    "ID": "c6c2b04c463b",
    "Image": "quay.io/keycloak/keycloak:26.4.7",
    "Labels": "com.docker.compose.version=5.1.1,distribution-scope=public,io.openshift.expose-services=,version=26.4.7,build-date=2025-11-12T17:00:10Z,com.docker.compose.container-number=1,com.docker.compose.oneoff=False,com.redhat.license_terms=,desktop.docker.io/binds/1/SourceKind=hostFile,desktop.docker.io/binds/1/Target=/opt/keycloak/data/import/realm-export.json,summary=Keycloak Server Image,com.docker.compose.config-hash=ef29ccb00803353c0b6c2627c8f8c5c5b4c07338465efad85e1e1df4aad6ff6c,com.docker.compose.image=sha256:9409c59bdfb65dbffa20b11e6f18b8abb9281d480c7ca402f51ed3d5977e6007,com.docker.compose.project=apim-simulator,com.docker.compose.project.working_dir=.,name=keycloak,com.docker.compose.project.config_files=./compose.yml,./compose.public.yml,./compose.oidc.yml,./compose.hello.yml,description=Keycloak Server Image,desktop.docker.io/binds/1/Source=./examples/subnet-calculator/keycloak/realm-export.json,io.buildah.version=1.41.4,io.k8s.description=Keycloak Server Image,maintainer=https://www.keycloak.org/,org.opencontainers.image.created=2025-12-01T08:14:24.495Z,org.opencontainers.image.description=,com.docker.compose.service=keycloak,desktop.docker.io/ports/8080/tcp=:8180,io.k8s.display-name=Keycloak Server,org.opencontainers.image.documentation=https://www.keycloak.org/documentation,org.opencontainers.image.source=https://github.com/keycloak-rel/keycloak-rel,org.opencontainers.image.url=https://github.com/keycloak-rel/keycloak-rel,org.opencontainers.image.version=26.4.7,vcs-ref=,com.docker.compose.depends_on=,com.redhat.component=,cpe=cpe:/a:redhat:enterprise_linux:9::appstream,release=,url=https://www.keycloak.org/,io.openshift.tags=keycloak security identity,org.opencontainers.image.revision=aa3baec457ee0cdfdff6de1ce256319180a76ee6,vcs-type=git,vendor=https://www.keycloak.org/,architecture=aarch64,com.redhat.build-host=,desktop.docker.io/ports.scheme=v2,org.opencontainers.image.licenses=Apache-2.0,org.opencontainers.image.title=keycloak-rel",
    "LocalVolumes": "1",
    "Mounts": "apim-simulator…,/host_mnt/User…",
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
    "RunningFor": "26 seconds ago",
    "Service": "keycloak",
    "Size": "0B",
    "State": "running",
    "Status": "Up 25 seconds (healthy)"
  },
  {
    "Command": "\"python server.py\"",
    "CreatedAt": "2026-04-15 18:52:08 +0100 BST",
    "ExitCode": 0,
    "Health": "",
    "ID": "06e7aaeab954",
    "Image": "apim-simulator-mock-backend:latest",
    "Labels": "desktop.docker.io/ports.scheme=v2,com.docker.compose.project.config_files=./compose.yml,./compose.public.yml,./compose.oidc.yml,./compose.hello.yml,com.docker.dhi.created=2026-04-08T03:14:50Z,com.docker.dhi.entitlement=public,com.docker.dhi.flavor=,com.docker.dhi.name=dhi/python,com.docker.compose.project=apim-simulator,com.docker.compose.project.working_dir=.,com.docker.compose.version=5.1.1,com.docker.dhi.chain-id=sha256:e68172a1b009e121980466426bb3c0b7a6184cc9d5a4200b57ee2dc4292779da,com.docker.dhi.compliance=cis,com.docker.dhi.date.end-of-life=2029-10-31,com.docker.dhi.title=Python 3.13.x,com.docker.dhi.variant=runtime,com.docker.compose.container-number=1,com.docker.compose.depends_on=,com.docker.compose.image=sha256:307c7e7c0b0c0983f8a893a60101dce400ca0e57d9515fbc97c55e1f3593c488,com.docker.compose.oneoff=False,com.docker.compose.service=mock-backend,com.docker.dhi.date.release=2024-10-07,com.docker.dhi.package-manager=,com.docker.dhi.shell=,com.docker.compose.config-hash=815e10da41b3af6176108902ed23ffc47edfaf9c27a33e160094fa0330e92164,com.docker.dhi.definition=image/python/debian-13/3.13,com.docker.dhi.distro=debian-13,com.docker.dhi.url=https://dhi.io/catalog/python,com.docker.dhi.version=3.13.12-debian13",
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
    "RunningFor": "26 seconds ago",
    "Service": "mock-backend",
    "Size": "0B",
    "State": "running",
    "Status": "Up 25 seconds"
  }
]
```

```bash
set -euo pipefail
smoke_log="$(mktemp)"
SMOKE_HELLO_MODE=oidc-subscription make smoke-hello >"$smoke_log" 2>&1 || { cat "$smoke_log"; exit 1; }
well_known="$(curl -fsS http://localhost:8180/realms/subnet-calculator/.well-known/openid-configuration)"
jq -n \
  --argjson well_known "$well_known" \
  --arg smoke_log "$(cat "$smoke_log")" \
  '{
    oidc: {
      issuer: $well_known.issuer,
      token_endpoint: $well_known.token_endpoint
    },
    smoke_hello: "passed",
    smoke_output: ($smoke_log | split("\n") | map(select(length > 0)))
  }'
rm -f "$smoke_log"

```

```output
{
  "oidc": {
    "issuer": "http://localhost:8180/realms/subnet-calculator",
    "token_endpoint": "http://localhost:8180/realms/subnet-calculator/protocol/openid-connect/token"
  },
  "smoke_hello": "passed",
  "smoke_output": [
    "uv run --project . python scripts/smoke_hello.py",
    "hello smoke passed",
    "- mode: oidc-subscription",
    "- missing bearer: 401",
    "- valid token: 200"
  ]
}
```
