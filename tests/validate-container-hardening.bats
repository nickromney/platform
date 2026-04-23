#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "repo-owned app workloads apply the hardened container baseline" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])

manifests = {
    "terraform/kubernetes/apps/workloads/base/all.yaml": {
        "sentiment-api": {
            "container": "api",
            "mounts": {"/data": "persistentVolumeClaim", "/tmp": "emptyDir"},
        },
        "sentiment-auth-ui": {
            "container": "ui",
            "mounts": {"/tmp": "emptyDir", "/var/cache/nginx": "emptyDir", "/var/run/nginx": "emptyDir"},
        },
        "sentiment-router": {
            "container": "nginx",
            "mounts": {
                "/etc/nginx/conf.d/default.conf": "configMap",
                "/tmp": "emptyDir",
                "/var/cache/nginx": "emptyDir",
                "/var/run/nginx": "emptyDir",
            },
        },
        "subnetcalc-api": {
            "container": "api",
            "mounts": {"/tmp": "emptyDir"},
        },
        "subnetcalc-frontend": {
            "container": "ui",
            "mounts": {"/tmp": "emptyDir", "/var/cache/nginx": "emptyDir", "/var/run/nginx": "emptyDir"},
        },
        "subnetcalc-router": {
            "container": "nginx",
            "mounts": {
                "/etc/nginx/conf.d/default.conf": "configMap",
                "/tmp": "emptyDir",
                "/var/cache/nginx": "emptyDir",
                "/var/run/nginx": "emptyDir",
            },
        },
    },
    "terraform/kubernetes/apps/apim/all.yaml": {
        "subnetcalc-apim-simulator": {
            "container": "apim",
            "mounts": {"/config/config.json": "configMap", "/tmp": "emptyDir"},
        },
    },
    "terraform/kubernetes/apps/platform-gateway-routes-sso/signoz-auth-proxy-deployment.yaml": {
        "signoz-auth-proxy": {
            "container": "signoz-auth-proxy",
            "mounts": {"/app/proxy.mjs": "configMap", "/tmp": "emptyDir"},
        },
    },
}


def load_docs(relative_path: str) -> list[dict]:
    with (repo_root / relative_path).open("r", encoding="utf-8") as fh:
        return [doc for doc in yaml.safe_load_all(fh) if doc]


def deployment_doc(relative_path: str, deployment_name: str) -> dict:
    for doc in load_docs(relative_path):
        if doc.get("kind") == "Deployment" and doc.get("metadata", {}).get("name") == deployment_name:
            return doc
    raise AssertionError(f"missing deployment {deployment_name} in {relative_path}")


def volume_type(spec: dict, volume_name: str) -> str:
    for volume in spec.get("volumes", []):
        if volume.get("name") != volume_name:
            continue
        if "emptyDir" in volume:
            return "emptyDir"
        if "persistentVolumeClaim" in volume:
            return "persistentVolumeClaim"
        if "configMap" in volume:
            return "configMap"
        return "other"
    raise AssertionError(f"missing volume {volume_name}")


for relative_path, deployments in manifests.items():
    for deployment_name, expected in deployments.items():
        doc = deployment_doc(relative_path, deployment_name)
        spec = doc["spec"]["template"]["spec"]
        pod_security = spec.get("securityContext", {})
        assert pod_security.get("runAsNonRoot") is True, (relative_path, deployment_name, pod_security)
        seccomp = pod_security.get("seccompProfile", {})
        assert seccomp.get("type") == "RuntimeDefault", (relative_path, deployment_name, seccomp)

        container_name = expected["container"]
        container = next(c for c in spec["containers"] if c.get("name") == container_name)
        container_security = container.get("securityContext", {})
        assert container_security.get("allowPrivilegeEscalation") is False, (relative_path, deployment_name, container_security)
        assert container_security.get("capabilities", {}).get("drop") == ["ALL"], (relative_path, deployment_name, container_security)
        assert container_security.get("readOnlyRootFilesystem") is True, (relative_path, deployment_name, container_security)
        assert container_security.get("seccompProfile", {}).get("type") == "RuntimeDefault", (
            relative_path,
            deployment_name,
            container_security,
        )

        mount_paths = {mount["mountPath"]: mount["name"] for mount in container.get("volumeMounts", [])}
        for mount_path, expected_type in expected["mounts"].items():
            assert mount_path in mount_paths, (relative_path, deployment_name, mount_path, mount_paths)
            volume_name = mount_paths[mount_path]
            assert volume_type(spec, volume_name) == expected_type, (
                relative_path,
                deployment_name,
                mount_path,
                volume_name,
                expected_type,
                volume_type(spec, volume_name),
            )

print(f"validated {len(manifests)} manifest file(s)")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated 3 manifest file(s)"* ]]
}
