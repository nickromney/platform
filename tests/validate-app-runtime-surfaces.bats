#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "repo-owned app Dockerfiles pin numeric runtime users" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])

expected_users = {
    "apps/sentiment/api-sentiment/Dockerfile": "1000:1000",
    "apps/sentiment/frontend-react-vite/sentiment-auth-ui/Dockerfile": "65532:65532",
    "apps/subnetcalc/api-fastapi-container-app/Dockerfile": "65532:65532",
    "apps/subnetcalc/api-fastapi-azure-function/Dockerfile": "65532:65532",
    "apps/subnetcalc/api-fastapi-azure-function/Dockerfile.uvicorn": "65532:65532",
    "apps/subnetcalc/frontend-html-static/Dockerfile": "65532:65532",
    "apps/subnetcalc/frontend-python-flask/Dockerfile": "65532:65532",
    "apps/subnetcalc/frontend-react/Dockerfile": "65532:65532",
    "apps/subnetcalc/frontend-react/Dockerfile.server": "1000:1000",
    "apps/subnetcalc/frontend-typescript-vite/Dockerfile": "65532:65532",
}

for relative_path, expected_user in expected_users.items():
    lines = (repo_root / relative_path).read_text(encoding="utf-8").splitlines()
    user_lines = [line.strip() for line in lines if line.strip().startswith("USER ")]
    assert user_lines, relative_path
    actual_user = user_lines[-1].split(None, 1)[1]
    assert actual_user == expected_user, (relative_path, expected_user, actual_user)

print(f"validated {len(expected_users)} Dockerfile(s)")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated 10 Dockerfile(s)"* ]]
}

@test "compose app services use hardened runtime settings and sentiment model build args" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])


def load_yaml(relative_path: str) -> dict:
    return yaml.safe_load((repo_root / relative_path).read_text(encoding="utf-8"))


def assert_tmpfs(service: dict, required_entries: list[str], relative_path: str, service_name: str) -> None:
    tmpfs_entries = service.get("tmpfs", [])
    for required in required_entries:
      assert required in tmpfs_entries, (relative_path, service_name, required, tmpfs_entries)


compose_expectations = {
    "apps/sentiment/compose.yml": {
        "sentiment-api": {
            "read_only": True,
            "cap_drop": ["ALL"],
            "security_opt": ["no-new-privileges:true"],
            "tmpfs": ["/tmp:rw,noexec,nosuid,nodev,mode=1777"],
            "build_args": {"SENTIMENT_MODEL_ID": "${SENTIMENT_MODEL_ID:-}"},
        },
        "sentiment-auth-frontend": {
            "read_only": True,
            "cap_drop": ["ALL"],
            "security_opt": ["no-new-privileges:true"],
            "tmpfs": [
                "/tmp:rw,noexec,nosuid,nodev,uid=65532,gid=65532,mode=1777",
                "/var/cache/nginx:rw,noexec,nosuid,nodev,uid=65532,gid=65532",
                "/var/run/nginx:rw,noexec,nosuid,nodev,uid=65532,gid=65532",
            ],
        },
        "edge": {
            "user": "65532:65532",
            "read_only": True,
            "cap_drop": ["ALL"],
            "security_opt": ["no-new-privileges:true"],
            "tmpfs": [
                "/tmp:rw,noexec,nosuid,nodev,uid=65532,gid=65532,mode=1777",
                "/var/cache/nginx:rw,noexec,nosuid,nodev,uid=65532,gid=65532",
                "/var/run/nginx:rw,noexec,nosuid,nodev,uid=65532,gid=65532",
            ],
        },
    },
    "apps/subnetcalc/compose.yml": {
        "api-fastapi-container-app": {
            "read_only": True,
            "cap_drop": ["ALL"],
            "security_opt": ["no-new-privileges:true"],
            "tmpfs": ["/tmp:rw,noexec,nosuid,nodev,mode=1777"],
        },
        "frontend-typescript-vite": {
            "read_only": True,
            "cap_drop": ["ALL"],
            "security_opt": ["no-new-privileges:true"],
            "tmpfs": [
                "/tmp:rw,noexec,nosuid,nodev,uid=65532,gid=65532,mode=1777",
                "/var/cache/nginx:rw,noexec,nosuid,nodev,uid=65532,gid=65532",
                "/var/run/nginx:rw,noexec,nosuid,nodev,uid=65532,gid=65532",
            ],
        },
        "frontend-react": {
            "read_only": True,
            "cap_drop": ["ALL"],
            "security_opt": ["no-new-privileges:true"],
            "tmpfs": [
                "/tmp:rw,noexec,nosuid,nodev,uid=65532,gid=65532,mode=1777",
                "/var/cache/nginx:rw,noexec,nosuid,nodev,uid=65532,gid=65532",
                "/var/run/nginx:rw,noexec,nosuid,nodev,uid=65532,gid=65532",
            ],
        },
    },
    "docker/compose/compose.yml": {
        "edge": {
            "user": "65532:65532",
            "read_only": True,
            "cap_drop": ["ALL"],
            "security_opt": ["no-new-privileges:true"],
            "tmpfs": [
                "/tmp:rw,noexec,nosuid,nodev,uid=65532,gid=65532,mode=1777",
                "/var/cache/nginx:rw,noexec,nosuid,nodev,uid=65532,gid=65532",
                "/var/run/nginx:rw,noexec,nosuid,nodev,uid=65532,gid=65532",
            ],
        },
        "subnetcalc-api-dev": {
            "read_only": True,
            "cap_drop": ["ALL"],
            "security_opt": ["no-new-privileges:true"],
            "tmpfs": ["/tmp:rw,noexec,nosuid,nodev,mode=1777"],
        },
        "subnetcalc-api-uat": {
            "read_only": True,
            "cap_drop": ["ALL"],
            "security_opt": ["no-new-privileges:true"],
            "tmpfs": ["/tmp:rw,noexec,nosuid,nodev,mode=1777"],
        },
        "subnetcalc-frontend-dev": {
            "read_only": True,
            "cap_drop": ["ALL"],
            "security_opt": ["no-new-privileges:true"],
            "tmpfs": [
                "/tmp:rw,noexec,nosuid,nodev,uid=65532,gid=65532,mode=1777",
                "/var/cache/nginx:rw,noexec,nosuid,nodev,uid=65532,gid=65532",
                "/var/run/nginx:rw,noexec,nosuid,nodev,uid=65532,gid=65532",
            ],
        },
        "subnetcalc-frontend-uat": {
            "read_only": True,
            "cap_drop": ["ALL"],
            "security_opt": ["no-new-privileges:true"],
            "tmpfs": [
                "/tmp:rw,noexec,nosuid,nodev,uid=65532,gid=65532,mode=1777",
                "/var/cache/nginx:rw,noexec,nosuid,nodev,uid=65532,gid=65532",
                "/var/run/nginx:rw,noexec,nosuid,nodev,uid=65532,gid=65532",
            ],
        },
        "subnetcalc-router-dev": {
            "user": "65532:65532",
            "read_only": True,
            "cap_drop": ["ALL"],
            "security_opt": ["no-new-privileges:true"],
            "tmpfs": [
                "/tmp:rw,noexec,nosuid,nodev,uid=65532,gid=65532,mode=1777",
                "/var/cache/nginx:rw,noexec,nosuid,nodev,uid=65532,gid=65532",
                "/var/run/nginx:rw,noexec,nosuid,nodev,uid=65532,gid=65532",
            ],
        },
        "subnetcalc-router-uat": {
            "user": "65532:65532",
            "read_only": True,
            "cap_drop": ["ALL"],
            "security_opt": ["no-new-privileges:true"],
            "tmpfs": [
                "/tmp:rw,noexec,nosuid,nodev,uid=65532,gid=65532,mode=1777",
                "/var/cache/nginx:rw,noexec,nosuid,nodev,uid=65532,gid=65532",
                "/var/run/nginx:rw,noexec,nosuid,nodev,uid=65532,gid=65532",
            ],
        },
    },
}

validated = 0
for relative_path, services in compose_expectations.items():
    compose = load_yaml(relative_path)
    for service_name, expected in services.items():
        service = compose["services"][service_name]
        for key in ("user", "read_only", "cap_drop", "security_opt"):
            if key in expected:
                assert service.get(key) == expected[key], (relative_path, service_name, key, expected[key], service.get(key))
        if "tmpfs" in expected:
            assert_tmpfs(service, expected["tmpfs"], relative_path, service_name)
        if "build_args" in expected:
            build = service.get("build", {})
            assert build.get("args") == expected["build_args"], (relative_path, service_name, build.get("args"))
        validated += 1

print(f"validated {validated} compose service(s)")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated 13 compose service(s)"* ]]
}

@test "model-backed sentiment workload has a bounded laptop runtime profile" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
docs = list(yaml.safe_load_all((repo_root / "terraform/kubernetes/apps/workloads/base/all.yaml").read_text(encoding="utf-8")))
deployment = next(doc for doc in docs if doc and doc.get("kind") == "Deployment" and doc["metadata"]["name"] == "sentiment-api")
container = deployment["spec"]["template"]["spec"]["containers"][0]
env = {item["name"]: str(item.get("value", "")) for item in container.get("env", [])}
resources = container["resources"]

assert env["MALLOC_ARENA_MAX"] == "2", env
assert env["OMP_NUM_THREADS"] == "1", env
assert resources["requests"]["memory"] == "768Mi", resources
assert resources["limits"]["memory"] == "2048Mi", resources
assert resources["limits"]["cpu"] == "1", resources

print("validated model-backed sentiment runtime profile")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated model-backed sentiment runtime profile"* ]]
}

@test "subnetcalc function-style compose healthchecks do not require /bin/sh" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
compose = yaml.safe_load((repo_root / "apps/subnetcalc/compose.yml").read_text(encoding="utf-8"))

for service_name in ("api-fastapi-azure-function", "api-fastapi-keycloak"):
    healthcheck = compose["services"][service_name]["healthcheck"]["test"]
    assert healthcheck[:2] == ["CMD", "python"], (service_name, healthcheck)
    assert "urllib.request.urlopen('http://127.0.0.1:8080/api/v1/health')" in healthcheck[3], (
        service_name,
        healthcheck,
    )

print("validated 2 shell-free function healthchecks")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated 2 shell-free function healthchecks"* ]]
}

@test "stack12 lightweight frontends stay in gateway mode behind oauth2-proxy" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
compose = yaml.safe_load((repo_root / "apps/subnetcalc/compose.yml").read_text(encoding="utf-8"))

for service_name in ("frontend-typescript-vite-gateway", "frontend-typescript-vite-gateway-admin"):
    env_entries = compose["services"][service_name]["environment"]
    if isinstance(env_entries, dict):
        auth_method = env_entries.get("AUTH_METHOD")
    else:
        auth_method = next((entry.split("=", 1)[1] for entry in env_entries if entry.startswith("AUTH_METHOD=")), None)
    assert auth_method == "gateway", (service_name, auth_method)

print("validated 2 stack12 gateway auth configs")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated 2 stack12 gateway auth configs"* ]]
}

@test "gateway auth shim only falls back to Authorization when no forwarded access token exists" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])
nginx_conf = (repo_root / "apps/subnetcalc/frontend-typescript-vite/nginx.conf").read_text(encoding="utf-8")

assert 'set $authorization_bearer "";' in nginx_conf, nginx_conf
assert 'if ($http_authorization ~* "^Bearer (.+)$") {' in nginx_conf, nginx_conf
assert 'set $authorization_bearer $1;' in nginx_conf, nginx_conf
assert 'if ($access_token = "") {' in nginx_conf, nginx_conf
assert 'set $access_token $authorization_bearer;' in nginx_conf, nginx_conf

print("validated gateway auth header fallback ordering")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated gateway auth header fallback ordering"* ]]
}

@test "stack12 oauth2-proxy frontends expose public login and logout landing pages" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
compose = yaml.safe_load((repo_root / "apps/subnetcalc/compose.yml").read_text(encoding="utf-8"))

required_flags = {
    "--skip-auth-regex=^/login\\.html$",
    "--skip-auth-regex=^/logged-out\\.html$",
}

for service_name in ("oauth2-proxy-frontend", "oauth2-proxy-frontend-admin"):
    command = compose["services"][service_name]["command"]
    command_set = set(command)
    missing = sorted(required_flags - command_set)
    assert not missing, (service_name, missing, command)

print("validated 2 public stack12 auth landing-page configs")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated 2 public stack12 auth landing-page configs"* ]]
}

@test "docker compose Dex demo credentials are pinned to password123" {
  local hashes_file="${BATS_TEST_TMPDIR}/dex-hashes.txt"
  local htpasswd_file="${BATS_TEST_TMPDIR}/dex.htpasswd"

  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
config = yaml.safe_load((repo_root / "docker/compose/dex/config.yaml").read_text(encoding="utf-8"))
hashes = [entry["hash"] for entry in config["staticPasswords"]]

assert len(hashes) == 3, hashes
assert len(set(hashes)) == 1, hashes

for value in hashes:
    print(value)
PY

  [ "${status}" -eq 0 ]
  printf '%s\n' "${output}" >"${hashes_file}"

  while IFS= read -r hash_value; do
    [ -n "${hash_value}" ] || continue
    printf 'demo:%s\n' "${hash_value}" >"${htpasswd_file}"
    run htpasswd -vb "${htpasswd_file}" demo password123
    [ "${status}" -eq 0 ]

    run htpasswd -vb "${htpasswd_file}" demo demo-password
    [ "${status}" -ne 0 ]
  done <"${hashes_file}"

  run make -C "${REPO_ROOT}/docker/compose" urls

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"demo@dev.test / password123"* ]]
  [[ "${output}" == *"demo@uat.test / password123"* ]]
  [[ "${output}" == *"demo@admin.test / password123"* ]]
}

@test "kubernetes app workloads pin numeric runtime users for hardened deployments" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
docs = [
    doc
    for doc in yaml.safe_load_all((repo_root / "terraform/kubernetes/apps/workloads/base/all.yaml").read_text(encoding="utf-8"))
    if doc
]

expected = {
    "sentiment-api": {"runAsUser": 1000, "runAsGroup": 1000, "fsGroup": 1000},
    "sentiment-auth-ui": {"runAsUser": 65532, "runAsGroup": 65532, "fsGroup": 65532},
    "sentiment-router": {"runAsUser": 65532, "runAsGroup": 65532, "fsGroup": 65532},
    "subnetcalc-api": {"runAsUser": 65532, "runAsGroup": 65532, "fsGroup": 65532},
    "subnetcalc-frontend": {"runAsUser": 65532, "runAsGroup": 65532, "fsGroup": 65532},
    "subnetcalc-router": {"runAsUser": 65532, "runAsGroup": 65532, "fsGroup": 65532},
}

for deployment_name, expected_security in expected.items():
    deployment = next(
        doc
        for doc in docs
        if doc.get("kind") == "Deployment" and doc.get("metadata", {}).get("name") == deployment_name
    )
    pod_security = deployment["spec"]["template"]["spec"].get("securityContext", {})
    for key, expected_value in expected_security.items():
        assert pod_security.get(key) == expected_value, (deployment_name, key, expected_value, pod_security)

print(f"validated {len(expected)} workload deployment(s)")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated 6 workload deployment(s)"* ]]
}

@test "local workload image builders forward custom sentiment model ids" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])

scripts = (
    "kubernetes/kind/scripts/build-local-workload-images.sh",
    "kubernetes/lima/scripts/build-local-workload-images.sh",
    "kubernetes/slicer/scripts/build-local-workload-images.sh",
)

needle = '--build-arg "SENTIMENT_MODEL_ID=${SENTIMENT_MODEL_ID}"'

for relative_path in scripts:
    content = (repo_root / relative_path).read_text(encoding="utf-8")
    assert 'SENTIMENT_MODEL_ID="${SENTIMENT_MODEL_ID:-}"' in content, relative_path
    assert needle in content, relative_path

print(f"validated {len(scripts)} local workload builder(s)")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated 3 local workload builder(s)"* ]]
}

@test "runtime-config frontends render into tmpfs-backed paths for read-only roots" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])

entrypoint = (repo_root / "apps/subnetcalc/scripts/runtime-config-entrypoint.go").read_text(encoding="utf-8")
render_script = (repo_root / "apps/subnetcalc/scripts/render-runtime-config.sh").read_text(encoding="utf-8")
react_nginx = (repo_root / "apps/subnetcalc/frontend-react/nginx.conf").read_text(encoding="utf-8")
vite_nginx = (repo_root / "apps/subnetcalc/frontend-typescript-vite/nginx.conf").read_text(encoding="utf-8")

assert '"/tmp/runtime-config.js"' in entrypoint, entrypoint
assert '"/var/run/nginx"' in entrypoint, entrypoint
assert 'RUNTIME_CONFIG_OUT:-/tmp/runtime-config.js' in render_script, render_script
assert "alias /tmp/runtime-config.js;" in react_nginx, react_nginx
assert "alias /tmp/runtime-config.js;" in vite_nginx, vite_nginx

print("validated runtime-config tmpfs contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated runtime-config tmpfs contract"* ]]
}

@test "external runtime image refs stay aligned across dockerfiles, compose, and kubernetes manifests" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])

expected_counts = {
    "apps/sentiment/api-sentiment/Dockerfile": {
        "FROM oven/bun:1.3.13 AS deps": 1,
        "FROM oven/bun:1.3.13 AS preload": 1,
    },
    "apps/sentiment/frontend-react-vite/sentiment-auth-ui/Dockerfile": {
        "FROM --platform=$BUILDPLATFORM oven/bun:1.3.13-alpine AS build": 1,
    },
    "apps/subnetcalc/frontend-react/Dockerfile": {
        "FROM --platform=$BUILDPLATFORM oven/bun:1.3.13-alpine AS builder": 1,
        "FROM --platform=$BUILDPLATFORM golang:1.26.2-alpine3.23 AS runtime-config-builder": 1,
    },
    "apps/subnetcalc/frontend-react/Dockerfile.server": {
        "FROM --platform=$BUILDPLATFORM oven/bun:1.3.13-alpine AS builder": 1,
        "FROM --platform=$TARGETPLATFORM dhi.io/node:22-alpine3.22": 1,
    },
    "apps/backstage/Dockerfile": {
        "FROM dhi.io/node:22-debian13 AS runtime": 1,
    },
    "apps/subnetcalc/frontend-typescript-vite/Dockerfile": {
        "FROM --platform=$BUILDPLATFORM oven/bun:1.3.13-alpine AS builder": 1,
        "FROM --platform=$BUILDPLATFORM golang:1.26.2-alpine3.23 AS runtime-config-builder": 1,
    },
    "apps/sentiment/compose.yml": {
        "image: quay.io/keycloak/keycloak:26.6.1": 1,
        "image: quay.io/oauth2-proxy/oauth2-proxy:v7.15.2@sha256:aa0bd8dd5ab0c78e4c91c92755ad573a5f92241f88138b4141b8ec803463b4fd": 1,
    },
    "apps/subnetcalc/compose.yml": {
        "image: quay.io/keycloak/keycloak:26.6.1": 1,
        "image: quay.io/oauth2-proxy/oauth2-proxy:v7.15.2": 2,
    },
    "apps/subnetcalc/compose.azurite.yml": {
        "image: mcr.microsoft.com/azure-storage/azurite:3.35.0": 1,
    },
    "apps/subnetcalc/api-fastapi-azure-function/compose.azurite.yml": {
        "image: mcr.microsoft.com/azure-storage/azurite:3.35.0": 1,
    },
    "terraform/kubernetes/apps/gitea-actions-runner/deployment.yaml": {
        "image: docker:29.4.1-cli": 1,
        "image: gitea/act_runner:0.4.1": 2,
        "image: kindest/node:v1.35.1": 1,
    },
    "terraform/kubernetes/apps/nginx-gateway-fabric/deploy.yaml": {
        "ghcr.io/nginx/nginx-gateway-fabric:2.5.1": 3,
    },
    "terraform/kubernetes/apps/platform-gateway-routes-sso/job-signoz-bootstrap.yaml": {
        "image: curlimages/curl:8.19.0": 1,
    },
    "terraform/kubernetes/apps/platform-gateway/agent-tls-bootstrap.yaml": {
        "image: python:3.12.13-alpine3.23": 1,
    },
    "terraform/kubernetes/scripts/check-security.sh": {
        'POLICY_PROBE_IMAGE="curlimages/curl:8.19.0"': 1,
    },
}

validated = 0
for relative_path, expectations in expected_counts.items():
    content = (repo_root / relative_path).read_text(encoding="utf-8")
    for needle, expected_count in expectations.items():
        actual_count = content.count(needle)
        assert actual_count == expected_count, (relative_path, needle, expected_count, actual_count)
        validated += 1

print(f"validated {validated} external image expectation(s)")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated 23 external image expectation(s)"* ]]
}

@test "subnetcalc frontend stays single-replica for local laptop clusters" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
docs = list(yaml.safe_load_all((repo_root / "terraform/kubernetes/apps/workloads/base/all.yaml").read_text(encoding="utf-8")))

frontend = next(
    doc
    for doc in docs
    if doc
    and doc.get("kind") == "Deployment"
    and doc.get("metadata", {}).get("name") == "subnetcalc-frontend"
)

assert frontend["spec"]["replicas"] == 1, frontend["spec"].get("replicas")
assert "topologySpreadConstraints" not in frontend["spec"]["template"]["spec"]

print("validated single-replica subnetcalc frontend")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated single-replica subnetcalc frontend"* ]]
}

@test "preload image artifacts track the current external runtime bump set" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
import re
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])

preload_files = [
    "kubernetes/kind/preload-images.txt",
    "kubernetes/lima/preload-images.txt",
    "kubernetes/slicer/preload-images.txt",
    "kubernetes/docker-desktop/preload-images.txt",
]

required_lines = [
    "ghcr.io/nginx/nginx-gateway-fabric:2.5.1",
    "ghcr.io/nginx/nginx-gateway-fabric/nginx:2.5.1",
    "docker:29.4.1-cli",
    "gitea/act_runner:0.4.1",
    "kindest/node:v1.35.1",
    "python:3.12.13-alpine3.23",
    "docker.io/curlimages/curl:8.19.0",
    "curlimages/curl:8.19.0",
]

for relative_path in preload_files:
    content = (repo_root / relative_path).read_text(encoding="utf-8")
    for needle in required_lines:
        assert needle in content, (relative_path, needle)

lock_file = (repo_root / "terraform/kubernetes/scripts/preload-images.linux-arm64.lock").read_text(encoding="utf-8")
lock_expectations = [
    "ghcr.io/nginx/nginx-gateway-fabric:2.5.1",
    "docker:29.4.1-cli",
    "gitea/act_runner:0.4.1",
    "kindest/node:v1.35.1",
    "python:3.12.13-alpine3.23",
    "docker.io/curlimages/curl:8.19.0",
    "curlimages/curl:8.19.0",
    "oven/bun:1.3.13",
    "oven/bun:1.3.13-alpine",
    "golang:1.26.2-alpine3.23",
]

for image_ref in lock_expectations:
    pattern = re.compile(rf"^{re.escape(image_ref)}\t.+@sha256:[0-9a-f]+$", re.MULTILINE)
    assert pattern.search(lock_file), image_ref

print(f"validated {len(preload_files)} preload image snapshot(s) and {len(lock_expectations)} lock entry(ies)")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated 4 preload image snapshot(s) and 10 lock entry(ies)"* ]]
}
