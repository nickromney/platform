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
    "apps/sentiment/app/Dockerfile": "65532:65532",
    "apps/subnetcalc/app/Dockerfile": "65532:65532",
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
  [[ "${output}" == *"validated 2 Dockerfile(s)"* ]]
}

@test "compose app services use hardened runtime settings" {
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
        },
        "sentiment-auth-frontend": {
            "read_only": True,
            "cap_drop": ["ALL"],
            "security_opt": ["no-new-privileges:true"],
            "tmpfs": ["/tmp:rw,noexec,nosuid,nodev,mode=1777"],
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
        "subnetcalc-backend": {
            "read_only": True,
            "cap_drop": ["ALL"],
            "security_opt": ["no-new-privileges:true"],
            "tmpfs": ["/tmp:rw,noexec,nosuid,nodev,mode=1777"],
        },
        "subnetcalc-frontend": {
            "read_only": True,
            "cap_drop": ["ALL"],
            "security_opt": ["no-new-privileges:true"],
            "tmpfs": ["/tmp:rw,noexec,nosuid,nodev,mode=1777"],
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
            "tmpfs": ["/tmp:rw,noexec,nosuid,nodev,mode=1777"],
        },
        "subnetcalc-frontend-uat": {
            "read_only": True,
            "cap_drop": ["ALL"],
            "security_opt": ["no-new-privileges:true"],
            "tmpfs": ["/tmp:rw,noexec,nosuid,nodev,mode=1777"],
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
  [[ "${output}" == *"validated 12 compose service(s)"* ]]
}

@test "Go sentiment workload has a bounded laptop runtime profile and health probes" {
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

assert env["AUTH_METHOD"] == "oidc", env
assert env["OIDC_AUDIENCE"] == "sentiment-api", env
assert env["OIDC_JWKS_URI"] == "http://keycloak.sso.svc.cluster.local:8080/realms/platform/protocol/openid-connect/certs", env
assert resources["requests"]["memory"] == "768Mi", resources
assert resources["limits"]["memory"] == "2048Mi", resources
assert resources["limits"]["cpu"] == "1", resources
assert container["readinessProbe"]["httpGet"]["path"] == "/api/v1/health/ready", container
assert container["livenessProbe"]["httpGet"]["path"] == "/api/v1/health/live", container

print("validated Go sentiment runtime profile")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated Go sentiment runtime profile"* ]]
}

@test "Go app compose healthchecks do not require /bin/sh" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])

expectations = {
    "apps/subnetcalc/compose.yml": {
        "subnetcalc-backend": ["CMD", "/subnetcalc", "healthcheck"],
        "subnetcalc-frontend": ["CMD", "/subnetcalc", "healthcheck"],
    },
    "apps/sentiment/compose.yml": {
        "sentiment-api": ["CMD", "/sentiment", "healthcheck"],
        "sentiment-auth-frontend": ["CMD", "/sentiment", "healthcheck"],
    },
}

validated = 0
for relative_path, services in expectations.items():
    compose = yaml.safe_load((repo_root / relative_path).read_text(encoding="utf-8"))
    for service_name, expected in services.items():
        healthcheck = compose["services"][service_name]["healthcheck"]["test"]
        assert healthcheck == expected, (relative_path, service_name, healthcheck)
        validated += 1

print(f"validated {validated} shell-free Go healthchecks")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated 4 shell-free Go healthchecks"* ]]
}

@test "sentiment compose frontend exposes API proxy diagnostics" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import json
import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
compose = yaml.safe_load((repo_root / "apps/sentiment/compose.yml").read_text(encoding="utf-8"))
frontend = compose["services"]["sentiment-auth-frontend"]

env = {}
for item in frontend["environment"]:
    key, value = item.split("=", 1)
    env[key] = value

assert env["RUNTIME_ROLE"] == "frontend", env
assert env["BACKEND_URL"] == "${SENTIMENT_FRONTEND_BACKEND_URL:-http://sentiment-api:8080}", env
assert env["API_BASE_PATH"] == "/api/v1", env
assert env["SHOW_NETWORK_PATH"] == "${SENTIMENT_SHOW_NETWORK_PATH:-true}", env
network_hops = json.loads(env["NETWORK_HOPS"])
assert [hop["label"] for hop in network_hops] == [
    "Browser",
    "Sentiment edge",
    "Sentiment frontend",
    "Sentiment API",
], network_hops

print("validated sentiment compose API proxy diagnostics")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated sentiment compose API proxy diagnostics"* ]]
}

@test "subnetcalc compose keeps only Go backend and frontend services" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
compose = yaml.safe_load((repo_root / "apps/subnetcalc/compose.yml").read_text(encoding="utf-8"))

assert set(compose["services"]) == {"subnetcalc-backend", "subnetcalc-frontend"}, compose["services"].keys()
assert compose["services"]["subnetcalc-backend"]["environment"]["RUNTIME_ROLE"] == "backend"
assert compose["services"]["subnetcalc-frontend"]["environment"]["RUNTIME_ROLE"] == "frontend"

print("validated Go-only subnetcalc compose services")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated Go-only subnetcalc compose services"* ]]
}

@test "subnetcalc Go frontend exposes OIDC runtime config without generated files" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])
server_go = (repo_root / "apps/subnetcalc/app/internal/app/server.go").read_text(encoding="utf-8")
app_js = (repo_root / "apps/subnetcalc/app/internal/app/web/app.js").read_text(encoding="utf-8")

assert '"authMethod"' in server_go
assert '"apiAuthMethod"' in server_go
assert '"oidcAuthority"' in server_go
assert "window.SUBNETCALC_RUNTIME_CONFIG" in server_go
assert "config.apiAuthMethod === \"oidc\"" in app_js

print("validated Go runtime config contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated Go runtime config contract"* ]]
}

@test "subnetcalc Go frontend ships sign-out landing page" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])
logged_out = (repo_root / "apps/subnetcalc/app/internal/app/web/logged-out.html").read_text(encoding="utf-8")

for text in ("Signed out", "Sign in again", "/.auth/login/sso"):
    assert text in logged_out, text

print("validated Go frontend sign-out page")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated Go frontend sign-out page"* ]]
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

@test "subnetcalc router protects the frontend and sends API calls through APIM" {
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

config = next(
    doc
    for doc in docs
    if doc.get("kind") == "ConfigMap" and doc.get("metadata", {}).get("name") == "subnetcalc-router-nginx"
)
nginx_conf = config["data"]["default.conf"]

assert "location ^~ /api/" in nginx_conf
assert "proxy_pass http://subnetcalc-apim-simulator.apim.svc.cluster.local:8000;" in nginx_conf
assert "set $apim_auth $http_authorization;" in nginx_conf
assert 'proxy_set_header Authorization $apim_auth;' in nginx_conf

assert "location / {" in nginx_conf
assert 'set $auth_email $http_x_auth_request_email;' in nginx_conf
assert 'if ($auth_email = "") { return 302 https://$host/oauth2/start?rd=$uri; }' in nginx_conf
assert "proxy_pass http://subnetcalc-frontend:8080;" in nginx_conf

print("validated subnetcalc frontend auth gate and API routing")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated subnetcalc frontend auth gate and API routing"* ]]
}

@test "sentiment router protects the frontend and sends API calls through the Go proxy" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import json
import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
docs = [
    doc
    for doc in yaml.safe_load_all((repo_root / "terraform/kubernetes/apps/workloads/base/all.yaml").read_text(encoding="utf-8"))
    if doc
]

frontend = next(
    doc
    for doc in docs
    if doc.get("kind") == "Deployment" and doc.get("metadata", {}).get("name") == "sentiment-auth-ui"
)
frontend_env = {item["name"]: str(item.get("value", "")) for item in frontend["spec"]["template"]["spec"]["containers"][0].get("env", [])}
assert frontend_env["AUTH_METHOD"] == "gateway", frontend_env
assert frontend_env["API_AUTH_METHOD"] == "gateway", frontend_env
assert frontend_env["API_BASE_PATH"] == "/api/v1", frontend_env
assert frontend_env["BACKEND_URL"] == "http://sentiment-api:8080", frontend_env
assert frontend_env["SHOW_NETWORK_PATH"] == "true", frontend_env
network_hops = json.loads(frontend_env["NETWORK_HOPS"])
assert [hop["label"] for hop in network_hops] == [
    "Browser",
    "OAuth2 Proxy",
    "Sentiment router",
    "Sentiment frontend",
    "Sentiment API",
], network_hops
frontend_container = frontend["spec"]["template"]["spec"]["containers"][0]
assert frontend_container["readinessProbe"]["httpGet"]["path"] == "/health/ready", frontend_container
assert frontend_container["livenessProbe"]["httpGet"]["path"] == "/health/live", frontend_container

config = next(
    doc
    for doc in docs
    if doc.get("kind") == "ConfigMap" and doc.get("metadata", {}).get("name") == "sentiment-router-nginx"
)
nginx_conf = config["data"]["default.conf"]

assert "location ^~ /api/" in nginx_conf
assert "proxy_pass http://sentiment-auth-ui:8080;" in nginx_conf
assert "proxy_pass http://sentiment-api:8080;" not in nginx_conf
assert "set $api_auth $http_authorization;" in nginx_conf
assert 'proxy_set_header Authorization $api_auth;' in nginx_conf
assert "location = /health" in nginx_conf
assert "location = /health/ready" in nginx_conf
assert "location = /health/live" in nginx_conf

assert "location / {" in nginx_conf
assert 'set $auth_email $http_x_auth_request_email;' in nginx_conf
assert 'if ($auth_email = "") { return 302 https://$host/oauth2/start?rd=$uri; }' in nginx_conf
assert "proxy_pass http://sentiment-auth-ui:8080;" in nginx_conf

edge_conf = (repo_root / "apps/sentiment/edge/nginx.conf").read_text(encoding="utf-8")
assert 'set $api_upstream "sentiment-auth-frontend:8080";' in edge_conf, edge_conf
assert 'set $api_upstream "sentiment-api:8080";' not in edge_conf, edge_conf

print("validated sentiment frontend auth gate, health, and API proxy routing")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated sentiment frontend auth gate, health, and API proxy routing"* ]]
}

@test "app oauth2 proxies refresh forwarded access tokens before API use" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])
sso_tf = (repo_root / "terraform/kubernetes/sso.tf").read_text(encoding="utf-8")

for name in (
    "oauth2-proxy-sentiment-dev",
    "oauth2-proxy-sentiment-uat",
    "oauth2-proxy-subnetcalc-dev",
    "oauth2-proxy-subnetcalc-uat",
):
    start = sso_tf.index(f"name: {name}")
    end = sso_tf.index("syncPolicy:", start)
    block = sso_tf[start:end]
    for expected in (
        "--cookie-expire=4h",
        "--cookie-refresh=1h",
        "--skip-auth-regex=^/(logged-out\\.html|favicon\\.svg)$",
        "--pass-access-token=true",
        "--set-xauthrequest=true",
        "--set-authorization-header=true",
    ):
        assert expected in block, (name, expected)

print("validated app oauth2-proxy access-token refresh settings")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated app oauth2-proxy access-token refresh settings"* ]]
}

@test "local workload image builders run app prebuild hooks" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])

scripts = (
    "kubernetes/kind/scripts/build-local-workload-images.sh",
    "kubernetes/scripts/build-local-workload-images.sh",
)
wrappers = (
    "kubernetes/lima/scripts/build-local-workload-images.sh",
    "kubernetes/slicer/scripts/build-local-workload-images.sh",
)

shared = (repo_root / "kubernetes/workflow/image-build-lib.sh").read_text(encoding="utf-8")
catalog = (repo_root / "kubernetes/workflow/image-catalog.json").read_text(encoding="utf-8")

assert '"prebuild": "make -C apps/sentiment/app build-linux"' in catalog
assert '"prebuild": "make -C apps/subnetcalc/app build-linux"' in catalog
assert '"apps/sentiment/app/go.sum"' in catalog
assert '"apps/subnetcalc/app/go.sum"' in catalog
assert "image_build_run_prebuild()" in shared
assert 'image_build_run_prebuild "${category}" "${image_id}"' in shared

for relative_path in scripts:
    content = (repo_root / relative_path).read_text(encoding="utf-8")
    assert "kubernetes/workflow/image-build-lib.sh" in content, relative_path
    assert "image_build_catalog_build_loop workload workload" in content, relative_path

for relative_path in wrappers:
    content = (repo_root / relative_path).read_text(encoding="utf-8")
    assert "kubernetes/scripts/build-local-workload-images.sh" in content, relative_path

print(f"validated {len(scripts) + len(wrappers)} local workload builder(s)")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated 4 local workload builder(s)"* ]]
}

@test "app oauth2 proxies call Keycloak backend logout with the session ID token" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])
locals_tf = (repo_root / "terraform/kubernetes/locals.tf").read_text(encoding="utf-8")
sso_tf = (repo_root / "terraform/kubernetes/sso.tf").read_text(encoding="utf-8")

assert "oauth2_proxy_backend_logout_url" in locals_tf
assert "/protocol/openid-connect/logout?id_token_hint={id_token}" in locals_tf
assert "oauth2_proxy_backend_logout_arg" in locals_tf
assert "--backend-logout-url=${local.oauth2_proxy_backend_logout_url}" in locals_tf
assert "sso_oauth2_proxy_post_logout_redirect_uris" not in locals_tf
assert "post.logout.redirect.uris" not in sso_tf

assert sso_tf.count("${local.oauth2_proxy_backend_logout_arg}") == 4
assert "backend_logout_arg = local.oauth2_proxy_backend_logout_arg_map" in locals_tf
assert "${try(each.value.backend_logout_arg, \"\")}" in sso_tf

print("validated Keycloak backend logout for app oauth2 proxies")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated Keycloak backend logout for app oauth2 proxies"* ]]
}

@test "app Gitea workflows build the default Go runtime images" {
  run uv run --isolated python - <<'PY'
from pathlib import Path
import os

repo_root = Path(os.environ["REPO_ROOT"])

checks = {
    "apps/sentiment/.gitea/workflows/build-images.yaml": {
        "required": [
            '"app/**"',
            "golang:1.26-alpine",
            "-v \"${APPS_DIR}/sentiment/app:/src\"",
            "docker build --provenance=false -t \"${REGISTRY_HOST}/${GITEA_REPO_OWNER}/sentiment-api:${TAG}\" \"${APPS_DIR}/sentiment/app\"",
            "docker tag \"${REGISTRY_HOST}/${GITEA_REPO_OWNER}/sentiment-api:${TAG}\" \"${REGISTRY_HOST}/${GITEA_REPO_OWNER}/sentiment-auth-ui:${TAG}\"",
        ],
        "forbidden": [
            "-v \"${WORKDIR}/app:/src\"",
            "docker build --provenance=false -t \"${REGISTRY_HOST}/${GITEA_REPO_OWNER}/sentiment-api:${TAG}\" ./app",
            "docker build --provenance=false -t \"${REGISTRY_HOST}/${GITEA_REPO_OWNER}/sentiment-api:${TAG}\" ./api-sentiment",
            "docker build --provenance=false -t \"${REGISTRY_HOST}/${GITEA_REPO_OWNER}/sentiment-auth-ui:${TAG}\" ./frontend-react-vite/sentiment-auth-ui",
        ],
    },
    "apps/subnetcalc/.gitea/workflows/build-images.yaml": {
        "required": [
            '"app/**"',
            "golang:1.26-alpine",
            "-v \"${APPS_DIR}/subnetcalc/app:/src\"",
            "docker build --provenance=false -t \"${REGISTRY_HOST}/${GITEA_REPO_OWNER}/subnetcalc-api:${TAG}\" \"${APPS_DIR}/subnetcalc/app\"",
            "docker tag \"${REGISTRY_HOST}/${GITEA_REPO_OWNER}/subnetcalc-api:${TAG}\" \"${REGISTRY_HOST}/${GITEA_REPO_OWNER}/subnetcalc-frontend:${TAG}\"",
        ],
        "forbidden": [
            "-v \"${WORKDIR}/app:/src\"",
            "docker build --provenance=false -t \"${REGISTRY_HOST}/${GITEA_REPO_OWNER}/subnetcalc-api:${TAG}\" ./app",
            "docker build --provenance=false -t \"${REGISTRY_HOST}/${GITEA_REPO_OWNER}/subnetcalc-apim-simulator:${TAG}\"",
            "docker build --provenance=false -t \"${REGISTRY_HOST}/${GITEA_REPO_OWNER}/subnetcalc-frontend:${TAG}\" -f ./frontend-typescript-vite/Dockerfile .",
            "docker build --provenance=false -t \"${REGISTRY_HOST}/${GITEA_REPO_OWNER}/subnetcalc-api:${TAG}\" ./api-fastapi-container-app",
        ],
    },
}

for relative_path, spec in checks.items():
    text = (repo_root / relative_path).read_text(encoding="utf-8")
    for needle in spec["required"]:
        assert needle in text, (relative_path, needle)
    for needle in spec["forbidden"]:
        assert needle not in text, (relative_path, needle)

print(f"validated {len(checks)} Gitea workflow(s)")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated 2 Gitea workflow(s)"* ]]
}

@test "cluster health treats non-kind NodePort hangs as gateway-backed warnings" {
  local health_script="${REPO_ROOT}/terraform/kubernetes/scripts/check-cluster-health.sh"

  run rg -n 'relying on gateway URL checks for this target' "${health_script}"
  [ "${status}" -eq 0 ]

  run rg -n 'EXPECT_KIND_PROVISIONING.*EXPECT_GATEWAY_TLS' "${health_script}"
  [ "${status}" -eq 0 ]
}

@test "subnetcalc Go frontend serves runtime config directly from the binary" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])

server_go = (repo_root / "apps/subnetcalc/app/internal/app/server.go").read_text(encoding="utf-8")

assert 'mux.HandleFunc("GET /runtime-config.js", server.runtimeConfig)' in server_go, server_go
assert 'w.Header().Set("Content-Type", "application/javascript")' in server_go, server_go
assert 'window.SUBNETCALC_RUNTIME_CONFIG = ' in server_go, server_go

print("validated Go runtime-config response")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated Go runtime-config response"* ]]
}

@test "external runtime image refs stay aligned across dockerfiles, compose, and kubernetes manifests" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])

expected_counts = {
    "apps/sentiment/app/Dockerfile": {
        "FROM dhi.io/static:20260413-alpine3.23": 1,
    },
    "apps/backstage/Dockerfile": {
        "FROM dhi.io/node:22-debian13 AS runtime": 1,
    },
    "apps/sentiment/compose.yml": {
        "image: quay.io/keycloak/keycloak:26.6.1": 1,
        "image: quay.io/oauth2-proxy/oauth2-proxy:v7.15.2@sha256:aa0bd8dd5ab0c78e4c91c92755ad573a5f92241f88138b4141b8ec803463b4fd": 1,
    },
    "apps/subnetcalc/app/Dockerfile": {
        "FROM dhi.io/static:20260413-alpine3.23": 1,
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
  [[ "${output}" == *"validated 12 external image expectation(s)"* ]]
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
    "dhi.io/golang:1.26-alpine3.23-dev",
    "dhi.io/static:20260413-alpine3.23",
    "python:3.12.13-alpine3.23",
    "docker.io/curlimages/curl:8.19.0",
    "curlimages/curl:8.19.0",
]

retired_lines = [
    "dhi.io/node:22-debian13-dev",
    "golang:1.26.2-alpine3.23",
    "oven/bun:1.3.13",
    "oven/bun:1.3.13-alpine",
    "node:22-alpine",
]

for relative_path in preload_files:
    content = (repo_root / relative_path).read_text(encoding="utf-8")
    for needle in required_lines:
        assert needle in content, (relative_path, needle)
    for needle in retired_lines:
        assert needle not in content, (relative_path, needle)

lock_file = (repo_root / "terraform/kubernetes/scripts/preload-images.linux-arm64.lock").read_text(encoding="utf-8")
lock_expectations = [
    "ghcr.io/nginx/nginx-gateway-fabric:2.5.1",
    "docker:29.4.1-cli",
    "gitea/act_runner:0.4.1",
    "kindest/node:v1.35.1",
    "python:3.12.13-alpine3.23",
    "docker.io/curlimages/curl:8.19.0",
    "curlimages/curl:8.19.0",
]

for image_ref in lock_expectations:
    pattern = re.compile(rf"^{re.escape(image_ref)}\t.+@sha256:[0-9a-f]+$", re.MULTILINE)
    assert pattern.search(lock_file), image_ref

for image_ref in retired_lines:
    assert f"{image_ref}\t" not in lock_file, image_ref

print(f"validated {len(preload_files)} preload image snapshot(s) and {len(lock_expectations)} lock entry(ies)")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated 4 preload image snapshot(s) and 7 lock entry(ies)"* ]]
}
