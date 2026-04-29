# APIM Simulator Walkthrough: OIDC Gateway

Generated from a live run against the local repository.

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
