#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "repo-owned app Dockerfiles pin numeric runtime users" {
  run python3 - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])

expected_users = {
    "apps/sentiment/api-sentiment/Dockerfile": "1000:1000",
    "apps/sentiment/frontend-react-vite/sentiment-auth-ui/Dockerfile": "65532:65532",
    "apps/subnet-calculator/api-fastapi-container-app/Dockerfile": "65532:65532",
    "apps/subnet-calculator/api-fastapi-azure-function/Dockerfile": "65532:65532",
    "apps/subnet-calculator/api-fastapi-azure-function/Dockerfile.uvicorn": "65532:65532",
    "apps/subnet-calculator/frontend-html-static/Dockerfile": "65532:65532",
    "apps/subnet-calculator/frontend-python-flask/Dockerfile": "65532:65532",
    "apps/subnet-calculator/frontend-react/Dockerfile": "65532:65532",
    "apps/subnet-calculator/frontend-react/Dockerfile.server": "1000:1000",
    "apps/subnet-calculator/frontend-typescript-vite/Dockerfile": "65532:65532",
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
  run python3 - <<'PY'
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
    "apps/subnet-calculator/compose.yml": {
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

@test "docker compose Dex demo credentials are pinned to password123" {
  local hashes_file="${BATS_TEST_TMPDIR}/dex-hashes.txt"
  local htpasswd_file="${BATS_TEST_TMPDIR}/dex.htpasswd"

  run python3 - <<'PY'
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
  run python3 - <<'PY'
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
  run python3 - <<'PY'
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
  run python3 - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])

entrypoint = (repo_root / "apps/subnet-calculator/scripts/runtime-config-entrypoint.go").read_text(encoding="utf-8")
render_script = (repo_root / "apps/subnet-calculator/scripts/render-runtime-config.sh").read_text(encoding="utf-8")
react_nginx = (repo_root / "apps/subnet-calculator/frontend-react/nginx.conf").read_text(encoding="utf-8")
vite_nginx = (repo_root / "apps/subnet-calculator/frontend-typescript-vite/nginx.conf").read_text(encoding="utf-8")

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
