from __future__ import annotations

from collections.abc import Iterator
from dataclasses import dataclass
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import subprocess
import sys
import tomllib
from typing import Any


@dataclass(frozen=True)
class ImageCatalogExpectation:
    image_id: str
    context: str
    prebuild_app: str
    dockerfile: str | None = None


@dataclass(frozen=True)
class GoModuleRequirement:
    module: str
    version: str
    indirect: bool


def canonical_go_app_names() -> tuple[str, ...]:
    return (
        "apim-simulator",
        "chatgpt-sim",
        "idp-core",
        "langfuse-demos",
        "platform-mcp",
        "sentiment",
        "subnetcalc",
    )


def canonical_local_app_layout_names() -> tuple[str, ...]:
    return (
        "apim-simulator",
        "chatgpt-sim",
        "idp-core",
        "platform-mcp",
        "sentiment",
        "subnetcalc",
    )


def canonical_shared_app_module_names() -> tuple[str, ...]:
    return (
        "apphttp",
        "appshell",
        "idpauth",
    )


def discovered_go_app_names(repo_root: Path) -> tuple[str, ...]:
    return tuple(
        sorted(
            path.parent.parent.name
            for path in (repo_root / "apps").glob("*/app/go.mod")
        )
    )


def apps_readme_go_app_coverage_contract_violations(repo_root: Path) -> tuple[str, ...]:
    readme = (repo_root / "apps" / "README.md").read_text(encoding="utf-8")
    violations: list[str] = []

    for app_name in canonical_go_app_names():
        expected_link = f"[`{app_name}/`]({app_name}/)"
        if expected_link not in readme:
            violations.append(f"apps README missing canonical Go app {expected_link}")

    for module_name in canonical_shared_app_module_names():
        expected_link = f"[`shared/{module_name}/`](shared/{module_name}/)"
        if expected_link not in readme:
            violations.append(f"apps README missing shared module {expected_link}")

    return tuple(violations)


def lightweight_app_source_unknown_token_contract_violations(repo_root: Path) -> tuple[str, ...]:
    apps_root = repo_root / "apps"
    text_suffixes = {
        ".css",
        ".go",
        ".html",
        ".js",
        ".json",
        ".md",
        ".sh",
        ".ts",
        ".txt",
        ".yaml",
        ".yml",
    }
    violations: list[str] = []

    for path in sorted(apps_root.rglob("*")):
        if not path.is_file() or path.suffix not in text_suffixes:
            continue
        relative = path.relative_to(repo_root)
        parts = relative.parts
        if "backstage" in parts or ".gitea" in parts:
            continue
        for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            if re.search(r"\bunknown\b|Unknown", line):
                violations.append(f"{relative.as_posix()}:{line_no}")

    return tuple(violations)


def app_discovery_metadata_unknown_token_contract_violations(repo_root: Path) -> tuple[str, ...]:
    metadata_paths = [
        repo_root / "catalog" / "platform-apps.json",
        repo_root / "terraform" / "kubernetes" / "config" / "platform-launchpad.apps.json",
        repo_root / "apps" / "backstage" / "catalog" / "entities.yaml",
    ]
    metadata_paths.extend(sorted((repo_root / "apps").glob("*/catalog-info.yaml")))
    metadata_paths.extend(sorted((repo_root / "apps" / "backstage" / "catalog" / "apps").glob("*/catalog-info.yaml")))
    violations: list[str] = []

    for path in metadata_paths:
        if not path.exists():
            continue
        for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            if re.search(r"\bunknown\b|Unknown", line):
                violations.append(f"{path.relative_to(repo_root).as_posix()}:{line_no}")

    return tuple(violations)


def _launchpad_selected_tiles(launchpad: dict[str, Any]) -> list[dict[str, Any]]:
    enabled_toggles = {
        "ENABLE_SSO",
        "ENABLE_HEADLAMP",
        "ENABLE_APP_REPO_SENTIMENT",
        "ENABLE_APP_REPO_SUBNETCALC",
        "ENABLE_LANGFUSE",
        "ENABLE_LANGFUSE_DEMOS",
    }
    return sorted(
        (
            tile
            for tile in launchpad.get("tiles", [])
            if all(requirement in enabled_toggles for requirement in tile.get("requires", []))
        ),
        key=lambda tile: tile.get("sort_key", ""),
    )


def _embedded_launchpad_dashboard(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8")
    start = text.index("# codex:platform-launchpad:start")
    end = text.index("# codex:platform-launchpad:end", start)
    block = text[start:end]
    lines = block.splitlines()
    json_start = next(index for index, line in enumerate(lines) if line.strip() == "json: |") + 1
    json_text = "\n".join(line.lstrip() for line in lines[json_start:])
    return json.loads(json_text)


def platform_launchpad_rendered_dashboard_contract_violations(repo_root: Path) -> tuple[str, ...]:
    launchpad = json.loads(
        (repo_root / "terraform" / "kubernetes" / "config" / "platform-launchpad.apps.json").read_text(
            encoding="utf-8"
        )
    )
    selected_tiles = _launchpad_selected_tiles(launchpad)
    expected_titles = [tile.get("title") for tile in selected_tiles]
    targets = (
        repo_root / "terraform" / "kubernetes" / "observability.tf",
        repo_root / "terraform" / "kubernetes" / "apps" / "argocd-apps" / "95-grafana.application.yaml",
    )
    violations: list[str] = []

    for tile in selected_tiles:
        for field in ("title", "url", "expr", "sort_key"):
            if not tile.get(field):
                violations.append(f"Launchpad inventory tile missing {field}: {tile}")
        tile_text = json.dumps(tile, sort_keys=True)
        if re.search(r"\bunknown\b|Unknown", tile_text):
            violations.append(f"Launchpad inventory tile uses unknown placeholder: {tile.get('title')}")

    for target in targets:
        relative = target.relative_to(repo_root).as_posix()
        dashboard = _embedded_launchpad_dashboard(target)
        dashboard_text = json.dumps(dashboard, sort_keys=True)
        if re.search(r"\bunknown\b|Unknown", dashboard_text):
            violations.append(f"{relative} rendered Launchpad dashboard uses unknown placeholder")

        panels = dashboard.get("panels", [])
        stat_panels = [panel for panel in panels if panel.get("type") == "stat"]
        rendered_titles = [panel.get("title") for panel in stat_panels]
        if dashboard.get("title") != "Platform Launchpad":
            violations.append(f"{relative} rendered dashboard title should be Platform Launchpad")
        if rendered_titles != expected_titles:
            violations.append(f"{relative} rendered Launchpad tiles should match selected inventory tiles")

        panels_by_title = {panel.get("title"): panel for panel in stat_panels}
        for tile in selected_tiles:
            title = tile.get("title")
            panel = panels_by_title.get(title)
            if panel is None:
                continue
            links = panel.get("links", [])
            targets_config = panel.get("targets", [])
            if panel.get("description") != tile.get("url"):
                violations.append(f"{relative} {title} panel description should match inventory URL")
            if not links or links[0].get("url") != tile.get("url"):
                violations.append(f"{relative} {title} panel link should match inventory URL")
            if not targets_config or targets_config[0].get("expr") != tile.get("expr"):
                violations.append(f"{relative} {title} panel query should match inventory expression")

    return tuple(violations)


def non_go_app_exception_contract_violations(repo_root: Path) -> tuple[str, ...]:
    expected_exceptions = {"backstage", "idp-mcp", "idp-sdk"}
    apps_root = repo_root / "apps"
    actual_exceptions = {
        path.name
        for path in apps_root.iterdir()
        if path.is_dir()
        and not (path / "app" / "go.mod").exists()
        and ((path / "package.json").exists() or (path / "pyproject.toml").exists())
    }
    violations: list[str] = []

    for name in sorted(actual_exceptions - expected_exceptions):
        violations.append(f"{name} is an undocumented non-Go app exception")
    for name in sorted(expected_exceptions - actual_exceptions):
        violations.append(f"{name} non-Go app exception is missing")

    idp_mcp = apps_root / "idp-mcp" / "pyproject.toml"
    if idp_mcp.exists():
        config = tomllib.loads(idp_mcp.read_text(encoding="utf-8"))
        if config.get("project", {}).get("dependencies") != []:
            violations.append("idp-mcp should stay dependency-free")
        if config.get("tool", {}).get("uv", {}).get("exclude-newer") != "7 days":
            violations.append("idp-mcp should keep uv exclude-newer at 7 days")

    idp_sdk = apps_root / "idp-sdk"
    if (idp_sdk / "package.json").exists():
        package = json.loads((idp_sdk / "package.json").read_text(encoding="utf-8"))
        if package.get("packageManager") != "npm@11.12.1":
            violations.append("idp-sdk should pin npm@11.12.1")
        npmrc = (idp_sdk / ".npmrc").read_text(encoding="utf-8") if (idp_sdk / ".npmrc").exists() else ""
        if "min-release-age=7" not in npmrc:
            violations.append("idp-sdk should keep npm min-release-age=7")

    backstage = apps_root / "backstage"
    if (backstage / "package.json").exists():
        package = json.loads((backstage / "package.json").read_text(encoding="utf-8"))
        if package.get("packageManager") != "yarn@4.4.1":
            violations.append("backstage should pin yarn@4.4.1")
        for required in (".yarn/releases/yarn-4.4.1.cjs", "yarn.lock"):
            if not (backstage / required).exists():
                violations.append(f"backstage missing {required}")

    readme = (apps_root / "README.md").read_text(encoding="utf-8")
    for fragment in (
        "idp-mcp/`](idp-mcp/) contains a small dependency-free stdlib MCP adapter",
        "idp-sdk/`](idp-sdk/) contains a dependency-free browser `fetch` wrapper",
        "backstage/`](backstage/) contains Portal. It is an intentional Backstage",
    ):
        if fragment not in readme:
            violations.append(f"apps README missing non-Go exception note: {fragment}")

    return tuple(violations)


def app_wrapper_names_with_target(repo_root: Path, target: str) -> tuple[str, ...]:
    marker = f"{target}:"
    return tuple(
        sorted(
            makefile.parent.name
            for makefile in (repo_root / "apps").glob("*/Makefile")
            if any(
                line == marker or line.startswith(f"{marker} ")
                for line in makefile.read_text(encoding="utf-8").splitlines()
            )
        )
    )


def apps_makefile_delegation_contract_violations(
    repo_root: Path,
    make_output: str,
    *,
    wrapper_target: str,
    delegated_target: str,
    app_names: tuple[str, ...] | None = None,
) -> tuple[str, ...]:
    violations: list[str] = []
    names = app_names or app_wrapper_names_with_target(repo_root, wrapper_target)

    for app_name in names:
        expected = f"make --no-print-directory -C ./{app_name} {delegated_target}"
        if expected not in make_output:
            violations.append(f"apps Makefile should delegate {delegated_target} to {app_name}")

    return tuple(violations)


def apps_makefile_help_contract_violations(make_output: str) -> tuple[str, ...]:
    required_fragments = (
        "prereqs",
        "test",
        "update",
        "trivy-prereqs",
        "trivy-scan",
        "trivy-scan-images",
        "trivy-scan-gitea",
    )
    return tuple(
        f"apps help should expose {fragment}"
        for fragment in required_fragments
        if fragment not in make_output
    )


def apps_prereqs_contract_violations(make_output: str) -> tuple[str, ...]:
    violations: list[str] = []

    if "Trivy remains opt-in" not in make_output:
        violations.append("apps prereqs should explain that Trivy remains opt-in")
    if "Runner mode:" in make_output:
        violations.append("apps prereqs should not invoke the Trivy runner")

    return tuple(violations)


def apps_makefile_wrapper_dir_function_contract_violations(repo_root: Path) -> tuple[str, ...]:
    content = (repo_root / "apps" / "Makefile").read_text(encoding="utf-8")
    required_fragments = (
        "define app_wrapper_dirs_with_target",
        "$(shell for makefile in ./*/Makefile; do grep -q '^$(1):' \"$$makefile\" || continue; dirname \"$$makefile\" | cut -c3-; done | LC_ALL=C sort)",
        "APP_COMPOSE_SMOKE_DIRS = $(call app_wrapper_dirs_with_target,compose-smoke)",
        "APP_JS_CHECK_DIRS = $(call app_wrapper_dirs_with_target,app-js-check)",
        "APP_TEST_DIRS = $(call app_wrapper_dirs_with_target,test)",
        "APP_UPDATE_DIRS = $(call app_wrapper_dirs_with_target,update)",
    )
    violations = [
        f"apps Makefile missing shared wrapper dir helper fragment: {fragment}"
        for fragment in required_fragments
        if fragment not in content
    ]

    discovery_lines = [
        line
        for line in content.splitlines()
        if "$(shell for makefile in ./*/Makefile" in line
    ]
    if len(discovery_lines) != 1:
        violations.append("apps Makefile should define wrapper target discovery once")

    return tuple(violations)


def apps_makefile_shared_module_target_contract_violations(repo_root: Path) -> tuple[str, ...]:
    content = (repo_root / "apps" / "Makefile").read_text(encoding="utf-8")
    browser_modules = {"appshell", "idpauth"}
    violations: list[str] = []

    make_known_goals = _makefile_assignment(content, "MAKE_KNOWN_GOALS")
    phony = _makefile_assignment(content, ".PHONY")
    test_prereqs = _makefile_target_prerequisites(content, "test")
    js_check_body = _makefile_target_body(content, "js-check")

    for module_name in canonical_shared_app_module_names():
        target_name = f"shared-{module_name}-test"
        for assignment_name, assignment_value in (
            ("MAKE_KNOWN_GOALS", make_known_goals),
            (".PHONY", phony),
        ):
            if target_name not in assignment_value.split():
                violations.append(f"apps Makefile {assignment_name} missing {target_name}")

        if target_name not in test_prereqs:
            violations.append(f"apps Makefile test target should depend on {target_name}")
        if not re.search(rf"^{re.escape(target_name)}:", content, re.MULTILINE):
            violations.append(f"apps Makefile missing {target_name} target")

        expected_test_delegation = f"@$(MAKE) --no-print-directory -C ./shared/{module_name} test"
        if expected_test_delegation not in content:
            violations.append(
                f"apps Makefile {target_name} should delegate to shared/{module_name} test"
            )

        expected_js_delegation = f"@$(MAKE) --no-print-directory -C ./shared/{module_name} js-check"
        if module_name in browser_modules and expected_js_delegation not in js_check_body:
            violations.append(
                f"apps Makefile js-check should delegate to shared/{module_name} js-check"
            )
        if module_name not in browser_modules and expected_js_delegation in js_check_body:
            violations.append(
                f"apps Makefile js-check should not require shared/{module_name} js-check"
            )

    return tuple(violations)


def _makefile_assignment(content: str, name: str) -> str:
    if name.startswith("."):
        pattern = rf"^{re.escape(name)}:\s*(.*)$"
        match = re.search(pattern, content, re.MULTILINE)
        return match.group(1) if match else ""

    pattern = rf"^{re.escape(name)}\s*(?::=|=)\s*(.*)$"
    match = re.search(pattern, content, re.MULTILINE)
    return match.group(1) if match else ""


def _makefile_target_prerequisites(content: str, target: str) -> tuple[str, ...]:
    pattern = rf"^{re.escape(target)}:\s*([^#\n]*)"
    match = re.search(pattern, content, re.MULTILINE)
    if not match:
        return ()
    return tuple(match.group(1).split())


def _makefile_target_body(content: str, target: str) -> str:
    pattern = rf"^{re.escape(target)}:[^\n]*\n((?:\t.*\n|[ \t]*\n)*)"
    match = re.search(pattern, content, re.MULTILINE)
    return match.group(1) if match else ""


def langfuse_demo_rollout_surface_contract_violations(repo_root: Path) -> tuple[str, ...]:
    files = {
        "stage": repo_root / "kubernetes/kind/stages/920-langfuse.tfvars",
        "variables": repo_root / "terraform/kubernetes/variables.tf",
        "locals": repo_root / "terraform/kubernetes/locals.tf",
        "workload_apps": repo_root / "terraform/kubernetes/workload-apps.tf",
        "app_of_apps": repo_root / "terraform/kubernetes/apps/argocd-apps/82-langfuse-demos.application.yaml",
        "routes_kustomization": repo_root / "terraform/kubernetes/apps/platform-gateway-routes-sso/kustomization.yaml",
        "demo_referencegrant": repo_root / "terraform/kubernetes/apps/platform-gateway-routes-sso/referencegrant-sso-langfuse-demos.yaml",
        "prometheus": repo_root / "terraform/kubernetes/apps/argocd-apps/90-prometheus.application.yaml",
        "grafana": repo_root / "terraform/kubernetes/apps/argocd-apps/95-grafana.application.yaml",
        "image_catalog": repo_root / "kubernetes/workflow/image-catalog.json",
        "image_builder": repo_root / "kubernetes/kind/scripts/build-local-platform-images.sh",
        "sync_script": repo_root / "terraform/kubernetes/scripts/sync-gitea-policies.sh",
        "launchpad": repo_root / "terraform/kubernetes/config/platform-launchpad.apps.json",
        "catalog": repo_root / "catalog/platform-apps.json",
    }
    texts = {name: path.read_text(encoding="utf-8") for name, path in files.items()}
    violations: list[str] = []

    required_fragments = {
        "variables": ("enable_langfuse_demos",),
        "locals": ("langfuse_trace_chat_public_host",),
        "workload_apps": ("argocd_app_langfuse_demos",),
        "app_of_apps": ("path: apps/langfuse-demos",),
        "prometheus": (
            "job_name: langfuse-demos",
            "langfuse-demos",
            "__meta_kubernetes_pod_annotation_prometheus_io_scrape",
        ),
        "grafana": (
            "Langfuse Agent Flow",
            "Langfuse Trace Chat DEV",
            "Langfuse Tool Agent DEV",
            "Langfuse Eval Runner DEV",
            "https://langfuse.admin.127.0.0.1.sslip.io",
            "langfuse_demo_llm_calls_total",
            'langfuse_demo_runs_total{job=\\"langfuse-demos\\"}',
            'langfuse_demo_langfuse_batches_total{job=\\"langfuse-demos\\"}',
        ),
        "image_catalog": (
            '"id": "langfuse-demos"',
            "apps/shared/idpauth",
            "apps/langfuse-demos/app/go.sum",
        ),
        "image_builder": (
            "langfuse_demos_source_tag=",
            'image_build_catalog_build_and_push platform langfuse-demos langfuse-demos "${langfuse_demos_source_tag}"',
        ),
        "sync_script": ("EXTERNAL_PLATFORM_IMAGE_LANGFUSE_DEMOS",),
        "routes_kustomization": ("referencegrant-sso-langfuse-demos.yaml",),
    }

    if re.search(r"(?m)^enable_langfuse_demos\s*=\s*true$", texts["stage"]) is None:
        violations.append("stage 920 should enable Langfuse demos")

    for file_name, fragments in required_fragments.items():
        for fragment in fragments:
            if fragment not in texts[file_name]:
                violations.append(f"{file_name} missing {fragment}")

    for name in langfuse_demo_runtime_names():
        if f"httproute-{name}.yaml" not in texts["routes_kustomization"]:
            violations.append(f"routes kustomization missing httproute-{name}.yaml")
        if f"oauth2-proxy-{name}" not in texts["demo_referencegrant"]:
            violations.append(f"Langfuse demo ReferenceGrant missing oauth2-proxy-{name}")
        for surface in ("grafana", "launchpad"):
            if name not in texts[surface]:
                violations.append(f"{surface} missing {name}")

    image_catalog = json.loads(texts["image_catalog"])
    platform_image_ids = {item["id"] for item in image_catalog["platform_images"]}
    if "langfuse-demos" not in platform_image_ids:
        violations.append("image catalog platform images missing langfuse-demos")

    launchpad = json.loads(texts["launchpad"])
    launchpad_tiles = {tile["title"]: tile for tile in launchpad["tiles"]}
    for title, url, required_toggle, deployment in langfuse_launchpad_tile_expectations():
        tile = launchpad_tiles.get(title)
        if tile is None:
            violations.append(f"Launchpad missing {title}")
            continue
        if tile.get("url") != url:
            violations.append(f"{title} Launchpad URL should be {url}")
        if tile.get("owner") != "platform":
            violations.append(f"{title} Launchpad owner should be platform")
        if required_toggle not in tile.get("requires", []):
            violations.append(f"{title} Launchpad requires should include {required_toggle}")
        if deployment not in tile.get("expr", ""):
            violations.append(f"{title} Launchpad expression should reference {deployment}")

    service_catalog = json.loads(texts["catalog"])
    apps = {app["name"]: app for app in service_catalog["applications"]}
    for app_name, route in langfuse_service_catalog_route_expectations():
        app = apps.get(app_name)
        if app is None:
            violations.append(f"platform app catalog missing {app_name}")
            continue
        if app.get("owner") != "platform":
            violations.append(f"{app_name} owner should be platform")
        if app.get("source", {}).get("path") not in {
            "apps/langfuse-demos",
            "terraform/kubernetes/apps/langfuse",
        }:
            violations.append(f"{app_name} source path should point at Langfuse app sources")
        if not any(environment.get("route") == route for environment in app.get("environments", [])):
            violations.append(f"{app_name} should expose route {route}")
        scorecard = app.get("scorecard", {})
        if scorecard.get("has_health_endpoint") is not True:
            violations.append(f"{app_name} scorecard should declare a health endpoint")
        if scorecard.get("has_network_policy") is not True:
            violations.append(f"{app_name} scorecard should declare a network policy")

    return tuple(violations)


def langfuse_demo_runtime_names() -> tuple[str, ...]:
    return (
        "langfuse-trace-chat",
        "langfuse-tool-agent",
        "langfuse-eval-runner",
    )


def langfuse_launchpad_tile_expectations() -> tuple[tuple[str, str, str, str], ...]:
    return (
        (
            "Langfuse",
            "https://langfuse.admin.127.0.0.1.sslip.io",
            "ENABLE_LANGFUSE",
            "langfuse-web",
        ),
        (
            "Langfuse Trace Chat DEV",
            "https://lf-chat.dev.127.0.0.1.sslip.io",
            "ENABLE_LANGFUSE_DEMOS",
            "langfuse-trace-chat",
        ),
        (
            "Langfuse Tool Agent DEV",
            "https://lf-agent.dev.127.0.0.1.sslip.io",
            "ENABLE_LANGFUSE_DEMOS",
            "langfuse-tool-agent",
        ),
        (
            "Langfuse Eval Runner DEV",
            "https://lf-evals.dev.127.0.0.1.sslip.io",
            "ENABLE_LANGFUSE_DEMOS",
            "langfuse-eval-runner",
        ),
    )


def langfuse_service_catalog_route_expectations() -> tuple[tuple[str, str], ...]:
    return (
        ("langfuse", "https://langfuse.admin.127.0.0.1.sslip.io"),
        ("langfuse-trace-chat", "https://lf-chat.dev.127.0.0.1.sslip.io"),
        ("langfuse-tool-agent", "https://lf-agent.dev.127.0.0.1.sslip.io"),
        ("langfuse-eval-runner", "https://lf-evals.dev.127.0.0.1.sslip.io"),
    )


def kubernetes_workload_container_hardening_contract_violations(repo_root: Path) -> tuple[str, ...]:
    violations: list[str] = []

    for relative_path, deployments in kubernetes_workload_hardening_expectations().items():
        docs = [
            doc
            for doc in load_yaml_all(repo_root / relative_path)
            if doc and doc.get("kind") == "Deployment"
        ]
        deployment_docs = {doc["metadata"]["name"]: doc for doc in docs}

        for deployment_name, expected in deployments.items():
            deployment = deployment_docs.get(deployment_name)
            if deployment is None:
                violations.append(f"{relative_path} missing Deployment/{deployment_name}")
                continue

            pod_spec = deployment["spec"]["template"]["spec"]
            pod_security = pod_spec.get("securityContext", {})
            if pod_security.get("runAsNonRoot") is not True:
                violations.append(f"{relative_path} Deployment/{deployment_name} should run as non-root")
            if pod_security.get("seccompProfile", {}).get("type") != "RuntimeDefault":
                violations.append(
                    f"{relative_path} Deployment/{deployment_name} pod seccompProfile should be RuntimeDefault"
                )

            container = next(
                (
                    candidate
                    for candidate in pod_spec.get("containers", [])
                    if candidate.get("name") == expected["container"]
                ),
                None,
            )
            if container is None:
                violations.append(
                    f"{relative_path} Deployment/{deployment_name} missing container {expected['container']}"
                )
                continue

            container_security = container.get("securityContext", {})
            if container_security.get("allowPrivilegeEscalation") is not False:
                violations.append(
                    f"{relative_path} Deployment/{deployment_name}/{expected['container']} should disallow privilege escalation"
                )
            if container_security.get("capabilities", {}).get("drop") != ["ALL"]:
                violations.append(
                    f"{relative_path} Deployment/{deployment_name}/{expected['container']} should drop all capabilities"
                )
            if container_security.get("readOnlyRootFilesystem") is not True:
                violations.append(
                    f"{relative_path} Deployment/{deployment_name}/{expected['container']} should use a read-only root filesystem"
                )
            if container_security.get("seccompProfile", {}).get("type") != "RuntimeDefault":
                violations.append(
                    f"{relative_path} Deployment/{deployment_name}/{expected['container']} container seccompProfile should be RuntimeDefault"
                )

            mounts = {
                mount["mountPath"]: mount["name"]
                for mount in container.get("volumeMounts", [])
                if "mountPath" in mount and "name" in mount
            }
            for mount_path, expected_type in expected["mounts"].items():
                volume_name = mounts.get(mount_path)
                if volume_name is None:
                    violations.append(
                        f"{relative_path} Deployment/{deployment_name}/{expected['container']} missing mount {mount_path}"
                    )
                    continue
                actual_type = _kubernetes_volume_type(pod_spec, volume_name)
                if actual_type != expected_type:
                    violations.append(
                        f"{relative_path} Deployment/{deployment_name}/{expected['container']} mount {mount_path} should use {expected_type}, got {actual_type}"
                    )

    return tuple(violations)


def kubernetes_workload_hardening_expectations() -> dict[str, dict[str, dict[str, Any]]]:
    nginx_tmpfs = {
        "/tmp": "emptyDir",
        "/var/cache/nginx": "emptyDir",
        "/var/run/nginx": "emptyDir",
    }
    return {
        "terraform/kubernetes/apps/workloads/base/all.yaml": {
            "sentiment-api": {
                "container": "api",
                "mounts": {"/data": "persistentVolumeClaim", "/tmp": "emptyDir"},
            },
            "sentiment-auth-ui": {
                "container": "ui",
                "mounts": {"/tmp": "emptyDir"},
            },
            "sentiment-router": {
                "container": "nginx",
                "mounts": {
                    "/etc/nginx/conf.d/default.conf": "configMap",
                    **nginx_tmpfs,
                },
            },
            "subnetcalc-api": {
                "container": "api",
                "mounts": {"/tmp": "emptyDir"},
            },
            "subnetcalc-frontend": {
                "container": "ui",
                "mounts": {"/tmp": "emptyDir"},
            },
            "subnetcalc-router": {
                "container": "nginx",
                "mounts": {
                    "/etc/nginx/conf.d/default.conf": "configMap",
                    **nginx_tmpfs,
                },
            },
        },
        "terraform/kubernetes/apps/apim/all.yaml": {
            "subnetcalc-apim-simulator": {
                "container": "apim",
                "mounts": {"/config/config.json": "configMap", "/tmp": "emptyDir"},
            },
        },
        "terraform/kubernetes/apps/chatgpt-sim/all.yaml": {
            "chatgpt-sim": {
                "container": "server",
                "mounts": {"/tmp": "emptyDir"},
            },
        },
        "terraform/kubernetes/apps/platform-gateway-routes-sso/signoz-auth-proxy-deployment.yaml": {
            "signoz-auth-proxy": {
                "container": "signoz-auth-proxy",
                "mounts": {"/app/proxy.mjs": "configMap", "/tmp": "emptyDir"},
            },
        },
        "terraform/kubernetes/apps/idp/all.yaml": {
            "idp-core": {
                "container": "api",
                "mounts": {"/tmp": "emptyDir"},
            },
            "backstage": {
                "container": "backstage",
                "mounts": {"/tmp": "emptyDir"},
            },
        },
    }


def _kubernetes_volume_type(pod_spec: dict[str, Any], volume_name: str) -> str:
    for volume in pod_spec.get("volumes", []):
        if volume.get("name") != volume_name:
            continue
        for volume_type in ("emptyDir", "persistentVolumeClaim", "configMap", "secret"):
            if volume_type in volume:
                return volume_type
        return "other"
    return "missing"


def rendered_uat_privileged_container_contract_violations(repo_root: Path) -> tuple[str, ...]:
    rendered = subprocess.check_output(
        ["kubectl", "kustomize", str(repo_root / "terraform" / "kubernetes" / "apps" / "uat")],
        text=True,
    )
    violations: list[str] = []
    checked = 0

    for doc in load_yaml_all_from_text(rendered):
        if not doc or doc.get("kind") != "Deployment":
            continue
        deployment_name = doc["metadata"]["name"]
        containers = doc["spec"]["template"]["spec"].get("containers", [])
        for container in containers:
            checked += 1
            container_name = container.get("name", "<unnamed>")
            security = container.get("securityContext", {})
            if security.get("privileged") is not False:
                violations.append(
                    f"UAT Deployment/{deployment_name}/{container_name} should set privileged false"
                )

    if checked == 0:
        violations.append("UAT kustomization should render at least one deployment container")

    return tuple(violations)


def load_yaml_all_from_text(content: str) -> tuple[dict[str, Any] | None, ...]:
    import yaml

    return tuple(yaml.safe_load_all(content))


def idp_catalog_app_contract_violations(repo_root: Path) -> tuple[str, ...]:
    catalog_path = repo_root / "catalog" / "platform-apps.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    apps = {app["name"]: app for app in catalog.get("applications", [])}
    violations: list[str] = []

    if catalog.get("schema_version") != "platform.idp/v1":
        violations.append("IDP app catalog schema_version should be platform.idp/v1")
    if len(apps) < 3:
        violations.append("IDP app catalog should declare at least three applications")

    for app_name, expected in idp_catalog_app_expectations().items():
        app = apps.get(app_name)
        if app is None:
            violations.append(f"IDP app catalog missing {app_name}")
            continue

        expected_owner = expected.get("owner")
        if expected_owner is not None and app.get("owner") != expected_owner:
            violations.append(f"{app_name} owner should be {expected_owner}")

        environments = {environment["name"]: environment for environment in app.get("environments", [])}
        for env_name, env_expected in expected.get("environments", {}).items():
            environment = environments.get(env_name)
            if environment is None:
                violations.append(f"{app_name} missing {env_name} environment")
                continue
            expected_namespace = env_expected.get("namespace")
            if expected_namespace is not None and environment.get("namespace") != expected_namespace:
                violations.append(f"{app_name}/{env_name} namespace should be {expected_namespace}")
            expected_rbac_group = env_expected.get("rbac_group")
            if (
                expected_rbac_group is not None
                and environment.get("rbac", {}).get("group") != expected_rbac_group
            ):
                violations.append(f"{app_name}/{env_name} RBAC group should be {expected_rbac_group}")

    for app_name, app in apps.items():
        for field in ("deployment", "secrets", "scorecard"):
            if field not in app:
                violations.append(f"{app_name} missing {field} evidence")

    return tuple(violations)


def idp_catalog_app_expectations() -> dict[str, dict[str, Any]]:
    return {
        "chatgpt-sim": {
            "owner": "platform",
            "environments": {
                "dev": {
                    "namespace": "dev",
                },
            },
        },
        "subnetcalc": {
            "environments": {
                "dev": {
                    "rbac_group": "app-subnetcalc-dev",
                },
            },
        },
        "sentiment": {
            "environments": {
                "uat": {
                    "rbac_group": "app-sentiment-uat",
                },
            },
        },
    }


def kubernetes_http_service_metadata_contract_violations(repo_root: Path) -> tuple[str, ...]:
    services: dict[str, dict[str, Any]] = {}
    violations: list[str] = []

    for relative_path in kubernetes_http_service_manifest_paths():
        for doc in load_yaml_all(repo_root / relative_path):
            if doc and doc.get("kind") == "Service":
                services[doc["metadata"]["name"]] = doc

    for service_name in kubernetes_http_service_names():
        service = services.get(service_name)
        if service is None:
            violations.append(f"{service_name} Service missing from HTTP service manifests")
            continue

        ports = service.get("spec", {}).get("ports", [])
        if not ports:
            violations.append(f"{service_name} Service should expose at least one port")
            continue
        port = ports[0]
        for key, expected_value in {
            "name": "http",
            "appProtocol": "http",
            "targetPort": "http",
        }.items():
            if port.get(key) != expected_value:
                violations.append(f"{service_name} Service port {key} should be {expected_value}")

    return tuple(violations)


def kubernetes_http_service_manifest_paths() -> tuple[str, ...]:
    return (
        "terraform/kubernetes/apps/workloads/base/all.yaml",
        "terraform/kubernetes/apps/chatgpt-sim/all.yaml",
        "terraform/kubernetes/apps/idp/all.yaml",
    )


def kubernetes_http_service_names() -> tuple[str, ...]:
    return (
        "backstage",
        "chatgpt-sim",
        "idp-core",
        "sentiment-api",
        "sentiment-auth-ui",
        "sentiment-router",
        "subnetcalc-api",
        "subnetcalc-frontend",
        "subnetcalc-router",
    )


def chatgpt_sim_kubernetes_runtime_contract_violations(repo_root: Path) -> tuple[str, ...]:
    manifest = repo_root / "terraform" / "kubernetes" / "apps" / "chatgpt-sim" / "all.yaml"
    kustomization = repo_root / "terraform" / "kubernetes" / "apps" / "chatgpt-sim" / "kustomization.yaml"
    argocd_app = repo_root / "terraform" / "kubernetes" / "apps" / "argocd-apps" / "80-chatgpt-sim.application.yaml"
    route = repo_root / "terraform" / "kubernetes" / "apps" / "platform-gateway-routes-sso" / "httproute-chatgpt-sim.yaml"
    routes_kustomization = (
        repo_root / "terraform" / "kubernetes" / "apps" / "platform-gateway-routes-sso" / "kustomization.yaml"
    )
    policy = repo_root / "terraform" / "kubernetes" / "cluster-policies" / "cilium" / "shared" / "chatgpt-sim-hardened.yaml"
    apim_policy = repo_root / "terraform" / "kubernetes" / "cluster-policies" / "cilium" / "shared" / "apim-baseline.yaml"
    agentgateway_policy = (
        repo_root
        / "terraform"
        / "kubernetes"
        / "cluster-policies"
        / "cilium"
        / "shared"
        / "agentgateway-ai-gateway-hardened.yaml"
    )
    violations: list[str] = []

    for path in (manifest, kustomization, argocd_app, route, routes_kustomization, policy, apim_policy, agentgateway_policy):
        if not path.exists():
            violations.append(f"{path.relative_to(repo_root).as_posix()} missing")
            return tuple(violations)

    docs = [doc for doc in load_yaml_all(manifest) if doc]
    deployments = {doc["metadata"]["name"]: doc for doc in docs if doc.get("kind") == "Deployment"}
    deployment = deployments.get("chatgpt-sim")
    if deployment is None:
        violations.append("terraform/kubernetes/apps/chatgpt-sim/all.yaml missing Deployment/chatgpt-sim")
    else:
        metadata = deployment.get("metadata", {})
        if metadata.get("namespace") != "dev":
            violations.append("Deployment/chatgpt-sim should live in dev namespace")
        pod_spec = deployment.get("spec", {}).get("template", {}).get("spec", {})
        containers = {container.get("name"): container for container in pod_spec.get("containers", [])}
        container = containers.get("server")
        if container is None:
            violations.append("Deployment/chatgpt-sim missing server container")
        else:
            env = {item.get("name"): item.get("value") for item in container.get("env", [])}
            expected_env = {
                "PUBLIC_BASE_URL": "https://chatgpt.dev.127.0.0.1.sslip.io",
                "MCP_URL": "https://mcpserver.dev.127.0.0.1.sslip.io/mcp",
                "MCP_INTERNAL_URL": "http://subnetcalc-apim-simulator.apim.svc.cluster.local:8000/mcp",
                "LLM_URL": "http://agentgateway-ai-gateway.agentgateway-system.svc.cluster.local/v1/chat/completions",
                "LLM_MODEL": "Qwen3.5-9B-MLX-4bit",
                "LLM_TIMEOUT_SECONDS": "1",
                "LLM_MAX_TOKENS": "32",
                "LANGFUSE_HOST": "http://langfuse-web.langfuse.svc.cluster.local:3000",
                "LANGFUSE_PUBLIC_KEY": "pk-lf-local-platform",
                "LANGFUSE_SECRET_KEY": "sk-lf-local-platform",
                "LANGFUSE_TIMEOUT_SECONDS": "1",
            }
            for key, expected in expected_env.items():
                if env.get(key) != expected:
                    violations.append(f"Deployment/chatgpt-sim env {key} should be {expected}, got {env.get(key)}")

    route_docs = [doc for doc in load_yaml_all(route) if doc]
    http_route = next((doc for doc in route_docs if doc.get("kind") == "HTTPRoute"), None)
    if http_route is None:
        violations.append("httproute-chatgpt-sim.yaml missing HTTPRoute")
    elif "chatgpt.dev.127.0.0.1.sslip.io" not in http_route.get("spec", {}).get("hostnames", []):
        violations.append("ChatGPT Sim HTTPRoute should expose chatgpt.dev.127.0.0.1.sslip.io")

    route_kustomization = load_yaml(routes_kustomization)
    if "httproute-chatgpt-sim.yaml" not in route_kustomization.get("resources", []):
        violations.append("platform-gateway-routes-sso kustomization should include httproute-chatgpt-sim.yaml")

    argocd = load_yaml(argocd_app)
    source = argocd.get("spec", {}).get("source", {})
    if source.get("repoURL") != "ssh://git@gitea-ssh.gitea.svc.cluster.local:22/platform/policies.git":
        violations.append("ChatGPT Sim Argo CD app should use the in-cluster SSH policy repo")
    if source.get("repoURL") == "http://gitea-http.gitea.svc.cluster.local:3000/platform/platform-policies.git":
        violations.append("ChatGPT Sim Argo CD app should not use the legacy HTTP policy repo")

    cilium_root = repo_root / "terraform" / "kubernetes" / "cluster-policies" / "cilium"
    for path in cilium_root.rglob("*.yaml"):
        if '"k8s:io.kubernetes.pod.namespace": chatgpt' in path.read_text(encoding="utf-8"):
            violations.append(f"{path.relative_to(repo_root).as_posix()} should use dev namespace for ChatGPT Sim")

    policy_text = policy.read_text(encoding="utf-8")
    expected_policy_fragments = (
        '"k8s:app.kubernetes.io/name": agentgateway-ai-gateway',
        'port: "80"',
        '"k8s:io.kubernetes.pod.namespace": langfuse',
        '"k8s:app.kubernetes.io/name": langfuse',
        'port: "3000"',
    )
    for fragment in expected_policy_fragments:
        if fragment not in policy_text:
            violations.append(f"chatgpt-sim Cilium policy missing {fragment}")

    for path in (apim_policy, agentgateway_policy):
        if '"k8s:io.kubernetes.pod.namespace": dev' not in path.read_text(encoding="utf-8"):
            violations.append(f"{path.relative_to(repo_root).as_posix()} should allow dev namespace traffic")

    return tuple(violations)


def idp_proxy_cookie_contract_violations(repo_root: Path) -> tuple[str, ...]:
    locals_tf = (repo_root / "terraform" / "kubernetes" / "locals.tf").read_text(encoding="utf-8")
    violations: list[str] = []

    proxies = _terraform_object_map_block(locals_tf, "sso_idp_proxy_apps")
    if not proxies:
        return ("sso_idp_proxy_apps local not found",)

    for proxy_name in ("portal", "api"):
        body = proxies.get(proxy_name)
        if body is None:
            violations.append(f"sso_idp_proxy_apps missing {proxy_name} proxy")
            continue

        expected = {
            "cookie_name": "local.portal_sso_cookie_name",
            "cookie_domain": "local.portal_cookie_domain",
            "whitelist_domain": "local.portal_whitelist_domains",
        }
        for key, expected_value in expected.items():
            actual = _terraform_attribute_value(body, key)
            if actual != expected_value:
                violations.append(f"sso_idp_proxy_apps.{proxy_name}.{key} should be {expected_value}")

    if 'portal_sso_cookie_name               = "kind-v2-sso-portal"' not in locals_tf:
        violations.append("portal_sso_cookie_name should remain kind-v2-sso-portal")
    if re.search(r'portal-api"\s*$', locals_tf, re.MULTILINE):
        violations.append("Portal API should share the portal SSO cookie local, not declare a separate cookie")

    return tuple(violations)


def _terraform_object_map_block(content: str, local_name: str) -> dict[str, str]:
    start_match = re.search(rf"^\s*{re.escape(local_name)}\s*=\s*merge\(", content, re.MULTILINE)
    if start_match is None:
        return {}

    start = start_match.end()
    depth = 1
    end = start
    while end < len(content) and depth:
        char = content[end]
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
        end += 1
    block = content[start:end - 1]

    objects: dict[str, str] = {}
    for key_match in re.finditer(r"^\s*(\w+)\s*=\s*\{", block, re.MULTILINE):
        key = key_match.group(1)
        object_start = key_match.end()
        brace_depth = 1
        object_end = object_start
        while object_end < len(block) and brace_depth:
            char = block[object_end]
            if char == "{":
                brace_depth += 1
            elif char == "}":
                brace_depth -= 1
            object_end += 1
        objects[key] = block[object_start:object_end - 1]

    return objects


def _terraform_attribute_value(body: str, key: str) -> str | None:
    match = re.search(rf"^\s*{re.escape(key)}\s*=\s*([^\n]+)", body, re.MULTILINE)
    return match.group(1).strip() if match else None


def keycloak_group_authorization_contract_violations(repo_root: Path) -> tuple[str, ...]:
    locals_tf = (repo_root / "terraform" / "kubernetes" / "locals.tf").read_text(encoding="utf-8")
    sso_tf = (repo_root / "terraform" / "kubernetes" / "sso.tf").read_text(encoding="utf-8")
    violations: list[str] = []

    for group in app_environment_group_names():
        if group not in locals_tf:
            violations.append(f"locals.tf missing app environment group {group}")
        if group not in sso_tf:
            violations.append(f"sso.tf missing app environment group {group}")
        if f"--allowed-group={group}" not in sso_tf:
            violations.append(f"sso.tf should allow app environment group {group}")

    if "--allowed-group=${local.sso_admin_group}" not in sso_tf:
        violations.append("workload app proxies should allow local.sso_admin_group")
    if "allowed-group: ${each.value.group}" not in sso_tf:
        violations.append("IDP proxy route policies should allow each.value.group")
    if re.search(r'email-domain: "(dev|uat)\.test"', sso_tf):
        violations.append("sso.tf should not use dev/uat email-domain shortcuts")

    return tuple(violations)


def app_environment_group_names() -> tuple[str, ...]:
    return (
        "app-subnetcalc-dev",
        "app-subnetcalc-uat",
        "app-sentiment-dev",
        "app-sentiment-uat",
    )


def apim_resource_audience_contract_violations(repo_root: Path) -> tuple[str, ...]:
    locals_tf = (repo_root / "terraform" / "kubernetes" / "locals.tf").read_text(encoding="utf-8")
    sso_tf = (repo_root / "terraform" / "kubernetes" / "sso.tf").read_text(encoding="utf-8")
    apim_manifest = (
        repo_root / "terraform" / "kubernetes" / "apps" / "apim" / "all.yaml"
    ).read_text(encoding="utf-8")
    compose_stack = (repo_root / "docker" / "compose" / "compose.yml").read_text(encoding="utf-8")
    subnetcalc_compose = load_yaml(repo_root / "apps" / "subnetcalc" / "compose.yml")
    contracts = (repo_root / "docs" / "ddd" / "contracts.md").read_text(encoding="utf-8")
    glossary = (repo_root / "docs" / "ddd" / "ubiquitous-language.md").read_text(encoding="utf-8")
    violations: list[str] = []

    if 'sso_apim_audience                    = "apim-simulator"' not in locals_tf:
        violations.append("locals.tf should define sso_apim_audience as apim-simulator")
    for fragment in (
        "clientId                  = local.sso_apim_audience",
        '"included.client.audience" = local.sso_apim_audience',
    ):
        if fragment not in sso_tf:
            violations.append(f"sso.tf missing APIM audience fragment {fragment}")
    if '"audience": "apim-simulator"' not in apim_manifest:
        violations.append("APIM manifest should configure audience apim-simulator")
    if "oidc-issuer-url=https://dex.compose.127.0.0.1.sslip.io:8443/dex" not in compose_stack:
        violations.append("root compose stack should keep Dex OIDC issuer for compose-only auth")

    services = subnetcalc_compose.get("services", {})
    for service_name, env_name in (
        ("subnetcalc-backend", "AUTH_METHOD"),
        ("subnetcalc-frontend", "AUTH_METHOD"),
        ("subnetcalc-frontend", "API_AUTH_METHOD"),
    ):
        service = services.get(service_name, {})
        environment = service.get("environment", {})
        value = environment.get(env_name)
        if value is None or ":-none}" not in str(value):
            violations.append(f"{service_name} should default {env_name} to none for portable direct compose")

    for service_name in ("keycloak", "edge", "oauth2-proxy"):
        profiles = services.get(service_name, {}).get("profiles", [])
        if "sso" not in profiles:
            violations.append(f"subnetcalc compose {service_name} should remain behind the sso profile")

    combined_docs = f"{contracts}\n{glossary}"
    for term in ("resource audience", "portable auth mode", "apim-simulator"):
        if term not in combined_docs:
            violations.append(f"DDD docs missing {term}")

    return tuple(violations)


def portal_public_fqdn_contract_violations(repo_root: Path) -> tuple[str, ...]:
    launchpad = json.loads(
        (repo_root / "terraform" / "kubernetes" / "config" / "platform-launchpad.apps.json").read_text(
            encoding="utf-8"
        )
    )
    catalog = json.loads((repo_root / "catalog" / "platform-apps.json").read_text(encoding="utf-8"))
    tiles = {tile.get("title"): tile for tile in launchpad.get("tiles", [])}
    applications = {app.get("name"): app for app in catalog.get("applications", [])}
    violations: list[str] = []

    expected_surfaces = {
        "Developer Portal": ("backstage", "https://portal.127.0.0.1.sslip.io"),
        "Portal API": ("idp-core", "https://portal-api.127.0.0.1.sslip.io"),
    }
    for title, (app_name, expected_url) in expected_surfaces.items():
        tile = tiles.get(title)
        if tile is None:
            violations.append(f"Launchpad missing {title} tile")
        elif tile.get("url") != expected_url:
            violations.append(f"Launchpad {title} tile should use {expected_url}")

        app = applications.get(app_name)
        if app is None:
            violations.append(f"platform app catalog missing {app_name}")
            continue
        routes = {environment.get("route") for environment in app.get("environments", [])}
        if expected_url not in routes:
            violations.append(f"platform app catalog {app_name} should expose {expected_url}")

    return tuple(violations)


def keycloak_optimized_image_contract_violations(repo_root: Path) -> tuple[str, ...]:
    dockerfile = (repo_root / "apps" / "keycloak" / "Dockerfile").read_text(encoding="utf-8")
    sso_tf = (repo_root / "terraform" / "kubernetes" / "sso.tf").read_text(encoding="utf-8")
    build_script = (
        repo_root / "kubernetes" / "kind" / "scripts" / "build-local-platform-images.sh"
    ).read_text(encoding="utf-8")
    image_catalog = json.loads(
        (repo_root / "kubernetes" / "workflow" / "image-catalog.json").read_text(encoding="utf-8")
    )
    violations: list[str] = []

    for fragment in (
        "FROM quay.io/keycloak/keycloak:26.6.3 AS builder",
        "ENV KC_DB=postgres",
        "ENV KC_CACHE=local",
        "RUN /opt/keycloak/bin/kc.sh build",
        "COPY --from=builder /opt/keycloak/ /opt/keycloak/",
        'ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]',
    ):
        if fragment not in dockerfile:
            violations.append(f"apps/keycloak/Dockerfile missing {fragment}")

    for forbidden in ("microdnf", "dnf ", "rpm "):
        if forbidden in dockerfile:
            violations.append(f"apps/keycloak/Dockerfile should not install packages with {forbidden.strip()}")

    for fragment in (
        "replicas: 1",
        "image: ${var.keycloak_image}",
        "- --optimized",
    ):
        if fragment not in sso_tf:
            violations.append(f"sso.tf missing optimized Keycloak fragment {fragment}")

    if "keycloak_source_tag=" not in build_script:
        violations.append("build-local-platform-images.sh should expose keycloak_source_tag")

    platform_images = {
        image.get("id"): image
        for image in image_catalog.get("platform_images", [])
        if isinstance(image, dict)
    }
    keycloak = platform_images.get("keycloak")
    if keycloak is None:
        violations.append("image-catalog.json missing keycloak image")
    else:
        build = keycloak.get("build", {})
        expected_values = {
            "default_tag": "26.6.3",
            "build.context": "apps/keycloak",
            "build.dockerfile": "Dockerfile",
        }
        actual_values = {
            "default_tag": keycloak.get("default_tag"),
            "build.context": build.get("context"),
            "build.dockerfile": build.get("dockerfile"),
        }
        for key, expected in expected_values.items():
            if actual_values.get(key) != expected:
                violations.append(f"image-catalog.json keycloak {key} should be {expected}")

    target_registry_hosts = {
        "kind": "host.docker.internal:5002",
        "lima": "host.lima.internal:5002",
        "slicer": "192.168.64.1:5002",
    }
    for target, registry_host in target_registry_hosts.items():
        tfvars_path = repo_root / "kubernetes" / target / "targets" / f"{target}.tfvars"
        tfvars = tfvars_path.read_text(encoding="utf-8")
        expected_image = f"{registry_host}/platform/keycloak:26.6.3"
        if not re.search(
            rf'(?m)^\s*keycloak_image\s*=\s*"{re.escape(expected_image)}"\s*$',
            tfvars,
        ):
            violations.append(f"{tfvars_path.relative_to(repo_root)} should set keycloak_image to {expected_image}")

    return tuple(violations)


def canonical_browser_app_names() -> tuple[str, ...]:
    return (
        "apim-simulator",
        "chatgpt-sim",
        "langfuse-demos",
        "sentiment",
        "subnetcalc",
    )


def browser_app_health_dependency_footprint_contract_violations(repo_root: Path) -> tuple[str, ...]:
    violations: list[str] = []

    for app_name in canonical_browser_app_names():
        server_go = repo_root / "apps" / app_name / "app" / "internal" / "app" / "server.go"
        if not server_go.exists():
            violations.append(f"{app_name} missing Go server source")
            continue
        content = server_go.read_text(encoding="utf-8")
        relative = server_go.relative_to(repo_root).as_posix()

        for fragment in (
            "apphttp.WriteBrowserAppHealth",
        ):
            if fragment not in content:
                violations.append(f"{relative} health payload missing {fragment}")

        for legacy in (
            "apphttp.WriteJSON(w, http.StatusOK, apphttp.BrowserAppHealth",
            '"dependencies"',
            '"dependency_footprint"',
            '"frontend_dependency_footprint"',
            '"go-plus-shared-idpauth"',
            '"go-stdlib-plus-oidc"',
            '"go-stdlib-only"',
        ):
            if legacy in content:
                violations.append(f"{relative} health payload should not use legacy {legacy}")

    return tuple(violations)


def browser_app_js_check_asset_contract_violations(repo_root: Path) -> tuple[str, ...]:
    violations: list[str] = []

    for app_name in canonical_browser_app_names():
        app_root = repo_root / "apps" / app_name / "app"
        makefile = app_root / "Makefile"
        web_dir = app_root / "internal" / "app" / "web"

        if not makefile.exists():
            violations.append(f"{app_name} missing app Makefile")
            continue
        if not web_dir.exists():
            violations.append(f"{app_name} missing browser web assets")
            continue

        makefile_content = makefile.read_text(encoding="utf-8")
        web_files = sorted(
            path.relative_to(app_root).as_posix()
            for path in web_dir.iterdir()
            if path.suffix in {".js", ".css", ".html", ".ts"}
        )
        if not web_files:
            violations.append(f"{app_name} has no checked web assets")
            continue

        for web_file in web_files:
            if web_file not in makefile_content:
                violations.append(f"{app_name} Makefile js-check does not include {web_file}")

    return tuple(violations)


def browser_app_js_check_command_contract_violations(repo_root: Path) -> tuple[str, ...]:
    required_fragments = (
        "biome check internal/app/web/app.js internal/app/web/api-types.d.ts",
        "deno check --check-js internal/app/web/app.js",
    )
    violations: list[str] = []

    for app_name in canonical_browser_app_names():
        makefile = repo_root / "apps" / app_name / "app" / "Makefile"
        if not makefile.exists():
            violations.append(f"{app_name} missing app Makefile")
            continue

        content = makefile.read_text(encoding="utf-8")
        for fragment in required_fragments:
            if fragment not in content:
                violations.append(f"{app_name} Makefile js-check missing {fragment}")

    return tuple(violations)


def browser_app_deno_config_contract_violations(repo_root: Path) -> tuple[str, ...]:
    violations: list[str] = []

    for app_name in canonical_browser_app_names():
        deno_config = repo_root / "apps" / app_name / "app" / "deno.json"
        if not deno_config.exists():
            continue

        content = deno_config.read_text(encoding="utf-8")
        if "useUnknownInCatchVariables" in content:
            violations.append(f"{app_name} deno.json should not carry the catch-variable unknown override")

    return tuple(violations)


def browser_app_package_manifest_contract_violations(repo_root: Path) -> tuple[str, ...]:
    blocked_names = {
        "package.json",
        "package-lock.json",
        "yarn.lock",
        "pnpm-lock.yaml",
        "bun.lock",
        "bun.lockb",
        "node_modules",
    }
    violations: list[str] = []

    for app_name in canonical_browser_app_names():
        app_root = repo_root / "apps" / app_name / "app"
        for path in sorted(app_root.rglob("*")):
            if path.name in blocked_names:
                violations.append(path.relative_to(repo_root).as_posix())

    return tuple(violations)


def browser_app_checked_source_contract_violations(repo_root: Path) -> tuple[str, ...]:
    violations: list[str] = []

    for app_name in canonical_browser_app_names():
        web_root = repo_root / "apps" / app_name / "app" / "internal" / "app" / "web"
        app_js = web_root / "app.js"
        api_types = web_root / "api-types.d.ts"

        if not app_js.exists():
            violations.append(f"{app_name} missing app.js")
            continue
        first_line = app_js.read_text(encoding="utf-8").splitlines()[0:1]
        if first_line != ["// @ts-check"]:
            violations.append(f"{app_name} app.js should start with // @ts-check")
        if not api_types.exists():
            violations.append(f"{app_name} missing app-local api-types.d.ts")

    return tuple(violations)


def shared_browser_api_types_makefile_contract_violations(repo_root: Path) -> tuple[str, ...]:
    api_types = repo_root / "apps" / "shared" / "web" / "api-types.d.ts"
    makefile = repo_root / "apps" / "Makefile"
    violations: list[str] = []

    if not api_types.exists():
        violations.append("apps/shared/web/api-types.d.ts missing")
    if "biome check ./shared/web/api-types.d.ts" not in makefile.read_text(encoding="utf-8"):
        violations.append("apps js-check should run Biome on shared web API types")

    return tuple(violations)


def browser_app_json_response_binding_contract_violations(repo_root: Path) -> tuple[str, ...]:
    violations: list[str] = []

    for path in sorted((repo_root / "apps").glob("*/app/internal/app/web/app.js")):
        text = path.read_text(encoding="utf-8")
        for match in re.finditer(r"const\s+\w+\s*=\s*/\*\* @type \{[^}]+\} \*/ \(", text):
            window = text[match.start() : match.start() + 240]
            if "await fetchJSON(" in window or "await fetchJSONWithTiming(" in window:
                line_no = text[: match.start()].count("\n") + 1
                violations.append(f"{path.relative_to(repo_root)}:{line_no}")

    return tuple(violations)


def shared_idp_browser_contract_violations(repo_root: Path) -> tuple[str, ...]:
    paths = (
        repo_root / "apps" / "shared" / "idpauth" / "web" / "idpauth.js",
        repo_root / "apps" / "shared" / "web" / "api-types.d.ts",
    )
    combined = "\n".join(path.read_text(encoding="utf-8") for path in paths)
    required_fragments = ("PlatformIdpAuthConfig", "RuntimeConfigBase", "JSONValue")
    forbidden_fragments = (
        "PlatformIdpAuthConfig?: Record<string, unknown>",
        "Record<string, unknown> | null | undefined",
        "@param {unknown[]} values",
        "[key: string]: unknown",
    )
    violations: list[str] = []

    for fragment in required_fragments:
        if fragment not in combined:
            violations.append(f"shared IDP browser contract missing {fragment}")
    for fragment in forbidden_fragments:
        if fragment in combined:
            violations.append(f"shared IDP browser contract should not expose {fragment}")

    return tuple(violations)


def shared_idp_browser_api_error_contract_violations(repo_root: Path) -> tuple[str, ...]:
    paths = (
        repo_root / "apps" / "shared" / "idpauth" / "web" / "idpauth.js",
        repo_root / "apps" / "shared" / "web" / "api-types.d.ts",
    )
    combined = "\n".join(path.read_text(encoding="utf-8") for path in paths)
    violations: list[str] = []

    for fragment in ("apiErrorMessage", "APIErrorMessageOptions", "defaultPrefix?: string"):
        if fragment not in combined:
            violations.append(f"shared IDP browser API error contract missing {fragment}")

    for app_name in ("sentiment", "subnetcalc"):
        app_js = repo_root / "apps" / app_name / "app" / "internal" / "app" / "web" / "app.js"
        content = app_js.read_text(encoding="utf-8")
        if "function userFacingAPIError(" in content:
            violations.append(f"{app_name} browser app should use shared idpauth apiErrorMessage")

    return tuple(violations)


def apim_browser_api_contract_violations(repo_root: Path) -> tuple[str, ...]:
    api_types = repo_root / "apps" / "apim-simulator" / "app" / "internal" / "app" / "web" / "api-types.d.ts"
    content = api_types.read_text(encoding="utf-8")
    if "unknown[]" in content:
        return ("APIM browser API contract should name management collections",)
    return ()


def chatgpt_browser_api_contract_violations(repo_root: Path) -> tuple[str, ...]:
    api_types = repo_root / "apps" / "chatgpt-sim" / "app" / "internal" / "app" / "web" / "api-types.d.ts"
    content = api_types.read_text(encoding="utf-8")
    forbidden_patterns = (
        (r"mcp_steps\?: unknown\[\]", "mcp_steps?: unknown[]"),
        (r"model\?: Record<string, unknown>", "model?: Record<string, unknown>"),
        (r"trace\?: Record<string, unknown>", "trace?: Record<string, unknown>"),
        (r"\bunknown\b", "unknown"),
        (r"Record<string, unknown>", "Record<string, unknown>"),
    )
    return tuple(
        f"ChatGPT Sim browser API contract should not expose {description}"
        for pattern, description in forbidden_patterns
        if re.search(pattern, content)
    )


def langfuse_browser_capability_contract_violations(repo_root: Path) -> tuple[str, ...]:
    app_js = repo_root / "apps" / "langfuse-demos" / "app" / "internal" / "app" / "web" / "app.js"
    content = app_js.read_text(encoding="utf-8")
    if "@param {unknown[]} items" in content:
        return ("Langfuse browser capability renderer should not expose unknown[] items",)
    return ()


def shared_appshell_json_contract_violations(repo_root: Path) -> tuple[str, ...]:
    paths = (
        repo_root / "apps" / "shared" / "appshell" / "app-shell.js",
        repo_root / "apps" / "shared" / "web" / "api-types.d.ts",
    )
    combined = "\n".join(path.read_text(encoding="utf-8") for path in paths)
    violations: list[str] = []

    for required in (
        "JSONValue",
        "JSONObject",
        "postJSON",
        "fetchText",
        "parseJSONObjectText",
        "renderJSONInto",
    ):
        if required not in combined:
            violations.append(f"shared browser API contract missing {required}")

    for forbidden in (
        "Promise<any>",
        "data: any",
        "Promise<unknown>",
        "data: unknown",
        "payload?: unknown",
        "errorMessage(error: unknown)",
        "prettyJSON(value: unknown)",
        "setText(node: Element, value: unknown)",
        "escapeHTML(value: unknown)",
        "escapeAttr(value: unknown)",
        "@param {unknown}",
        "PlatformAppShell?: unknown",
        "function postJSON(url, body)",
    ):
        if forbidden in combined:
            violations.append(f"shared browser API contract should not expose {forbidden}")

    chatgpt_app = repo_root / "apps" / "chatgpt-sim" / "app" / "internal" / "app" / "web" / "app.js"
    chatgpt_content = chatgpt_app.read_text(encoding="utf-8")
    if "async function postJSON" in chatgpt_content:
        violations.append("ChatGPT Sim should use shared app shell postJSON")
    if ".textContent = prettyJSON(" in chatgpt_content:
        violations.append("ChatGPT Sim should render diagnostic JSON through shared renderJSONInto")
    apim_app = repo_root / "apps" / "apim-simulator" / "app" / "internal" / "app" / "web" / "app.js"
    if ".textContent = prettyJSON(" in apim_app.read_text(encoding="utf-8"):
        violations.append("APIM Simulator should render diagnostic JSON through shared renderJSONInto")
    langfuse_app = repo_root / "apps" / "langfuse-demos" / "app" / "internal" / "app" / "web" / "app.js"
    langfuse_content = langfuse_app.read_text(encoding="utf-8")
    if "await fetch(" in langfuse_content:
        violations.append("Langfuse demos should use shared app shell fetchText")
    if "await fetchJSON(" in langfuse_content and "method: \"POST\"" in langfuse_content:
        violations.append("Langfuse demos should use shared app shell postJSON for run submission")

    apim_app = repo_root / "apps" / "apim-simulator" / "app" / "internal" / "app" / "web" / "app.js"
    apim_content = apim_app.read_text(encoding="utf-8")
    if "JSON.parse(textAreaElement(\"headers\").value" in apim_content:
        violations.append("APIM simulator should parse replay header JSON through shared app shell parseJSONObjectText")

    subnetcalc_app = repo_root / "apps" / "subnetcalc" / "app" / "internal" / "app" / "web" / "app.js"
    subnetcalc_content = subnetcalc_app.read_text(encoding="utf-8")
    for fragment in (
        "JSON.parse(sessionStorage.getItem(oidcStateKey)",
        "JSON.parse(localStorage.getItem(oidcStorageKey)",
    ):
        if fragment in subnetcalc_content:
            violations.append(f"Subnetcalc should parse OIDC storage JSON through shared app shell parseJSONObjectText instead of {fragment}")

    return tuple(violations)


def shared_appshell_apim_trace_contract_violations(repo_root: Path) -> tuple[str, ...]:
    paths = (
        repo_root / "apps" / "shared" / "appshell" / "app-shell.js",
        repo_root / "apps" / "shared" / "web" / "api-types.d.ts",
    )
    combined = "\n".join(path.read_text(encoding="utf-8") for path in paths)
    forbidden_fragments = (
        "APIMTrace | unknown",
        "apimTrace: unknown",
        "(value: string) => unknown",
    )
    return tuple(
        f"shared app shell APIM trace contract should not expose {fragment}"
        for fragment in forbidden_fragments
        if fragment in combined
    )


def shared_appshell_json_headers_contract_violations(repo_root: Path) -> tuple[str, ...]:
    paths = (
        repo_root / "apps" / "shared" / "appshell" / "app-shell.js",
        repo_root / "apps" / "shared" / "web" / "api-types.d.ts",
    )
    combined = "\n".join(path.read_text(encoding="utf-8") for path in paths)
    violations: list[str] = []

    for fragment in ("apiJSONHeaders", "extraHeaders?: Record<string, string>"):
        if fragment not in combined:
            violations.append(f"shared app shell JSON header contract missing {fragment}")

    for app_name in ("sentiment", "subnetcalc"):
        app_js = repo_root / "apps" / app_name / "app" / "internal" / "app" / "web" / "app.js"
        content = app_js.read_text(encoding="utf-8")
        if "function apiRequestHeaders()" in content:
            violations.append(f"{app_name} browser app should use shared app shell apiJSONHeaders")
        if '"Content-Type": "application/json"' in content:
            violations.append(f"{app_name} browser app should not rebuild JSON content-type headers")

    return tuple(violations)


def shared_appshell_runtime_config_contract_violations(repo_root: Path) -> tuple[str, ...]:
    paths = (
        repo_root / "apps" / "shared" / "appshell" / "app-shell.js",
        repo_root / "apps" / "shared" / "web" / "api-types.d.ts",
    )
    combined = "\n".join(path.read_text(encoding="utf-8") for path in paths)
    forbidden_fragments = (
        "{networkHops?: unknown}",
        "{showNetworkPath?: unknown}",
    )
    return tuple(
        f"shared app shell runtime config contract should not expose {fragment}"
        for fragment in forbidden_fragments
        if fragment in combined
    )


def shared_appshell_api_path_contract_violations(repo_root: Path) -> tuple[str, ...]:
    paths = (
        repo_root / "apps" / "shared" / "appshell" / "app-shell.js",
        repo_root / "apps" / "shared" / "web" / "api-types.d.ts",
    )
    combined = "\n".join(path.read_text(encoding="utf-8") for path in paths)
    sentiment_app = repo_root / "apps" / "sentiment" / "app" / "internal" / "app" / "web" / "app.js"
    sentiment_content = sentiment_app.read_text(encoding="utf-8")
    violations: list[str] = []

    for fragment in ("apiBasePath", "apiPath("):
        if fragment not in combined:
            violations.append(f"shared app shell API path contract missing {fragment}")
    for fragment in ("function apiBasePath(", "function apiURL("):
        if fragment in sentiment_content:
            violations.append(f"Sentiment browser app should use shared app shell API path helper instead of {fragment}")

    return tuple(violations)


def shared_appshell_api_timing_contract_violations(repo_root: Path) -> tuple[str, ...]:
    paths = (
        repo_root / "apps" / "shared" / "appshell" / "app-shell.js",
        repo_root / "apps" / "shared" / "web" / "api-types.d.ts",
    )
    combined = "\n".join(path.read_text(encoding="utf-8") for path in paths)
    app_paths = (
        repo_root / "apps" / "sentiment" / "app" / "internal" / "app" / "web" / "app.js",
        repo_root / "apps" / "subnetcalc" / "app" / "internal" / "app" / "web" / "app.js",
    )
    violations: list[str] = []

    for fragment in (
        "renderAPITiming",
        "APITimingRenderOptions",
        "API Call Timing",
        "APIM Upstream Time",
        "Correlation ID",
    ):
        if fragment not in combined:
            violations.append(f"shared app shell API timing contract missing {fragment}")

    for app_path in app_paths:
        content = app_path.read_text(encoding="utf-8")
        relative = app_path.relative_to(repo_root).as_posix()
        if "renderAPITiming" not in content and "apiTimingElement" not in content:
            violations.append(f"{relative} should use a shared app shell API timing renderer")
        for fragment in (
            "function renderTiming(",
            '["APIM Upstream Time"',
            '["APIM Status"',
            '["Correlation ID"',
            '<summary>API Call Timing</summary>',
        ):
            if fragment in content:
                violations.append(f"{relative} should not locally render API timing fragment {fragment}")

    return tuple(violations)


def shared_appshell_timestamp_contract_violations(repo_root: Path) -> tuple[str, ...]:
    paths = (
        repo_root / "apps" / "shared" / "appshell" / "app-shell.js",
        repo_root / "apps" / "shared" / "web" / "api-types.d.ts",
    )
    combined = "\n".join(path.read_text(encoding="utf-8") for path in paths)
    sentiment_app = repo_root / "apps" / "sentiment" / "app" / "internal" / "app" / "web" / "app.js"
    sentiment_content = sentiment_app.read_text(encoding="utf-8")
    violations: list[str] = []

    for fragment in ("formatTimestamp", "Timestamp unavailable", "timeZoneName"):
        if fragment not in combined:
            violations.append(f"shared app shell timestamp contract missing {fragment}")
    if "function formatTimestamp(" in sentiment_content:
        violations.append("Sentiment browser app should use shared app shell formatTimestamp")
    if "Timestamp unavailable" in sentiment_content:
        violations.append("Sentiment browser app should not own timestamp fallback text")

    return tuple(violations)


def shared_appshell_api_health_status_contract_violations(repo_root: Path) -> tuple[str, ...]:
    paths = (
        repo_root / "apps" / "shared" / "appshell" / "app-shell.js",
        repo_root / "apps" / "shared" / "web" / "api-types.d.ts",
    )
    combined = "\n".join(path.read_text(encoding="utf-8") for path in paths)
    app_paths = (
        repo_root / "apps" / "sentiment" / "app" / "internal" / "app" / "web" / "app.js",
        repo_root / "apps" / "subnetcalc" / "app" / "internal" / "app" / "web" / "app.js",
    )
    violations: list[str] = []

    for fragment in (
        "formatAPIHealthStatus",
        "APIHealthStatus",
        "API Status:",
        "Backend URI:",
        "OIDC/JWT validated by backend",
        "No auth mode",
    ):
        if fragment not in combined:
            violations.append(f"shared app shell API health status contract missing {fragment}")

    for app_path in app_paths:
        content = app_path.read_text(encoding="utf-8")
        relative = app_path.relative_to(repo_root).as_posix()
        if "formatAPIHealthStatus" not in content:
            violations.append(f"{relative} should use shared app shell formatAPIHealthStatus")
        for fragment in (
            "OIDC/JWT validated by backend",
            "No auth mode",
            "Backend URI:",
            "server_side_token_validation",
        ):
            if fragment in content:
                violations.append(f"{relative} should not locally render API health fragment {fragment}")

    return tuple(violations)


def browser_app_explicit_any_contract_violations(repo_root: Path) -> tuple[str, ...]:
    pattern = re.compile(r"Array<any>|Promise<any>|\{any\}")
    paths = sorted((repo_root / "apps").glob("*/app/internal/app/web/app.js"))
    paths.extend(sorted((repo_root / "apps").glob("*/app/internal/app/web/api-types.d.ts")))
    violations: list[str] = []

    for path in paths:
        for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            if pattern.search(line):
                violations.append(f"{path.relative_to(repo_root)}:{line_no}")

    return tuple(violations)


def browser_public_unknown_contract_violations(repo_root: Path) -> tuple[str, ...]:
    pattern = re.compile(r"\bunknown\b|Record<string,\s*unknown>|Promise<unknown>|unknown\[\]")
    paths = sorted((repo_root / "apps").glob("*/app/internal/app/web/app.js"))
    paths.extend(sorted((repo_root / "apps").glob("*/app/internal/app/web/api-types.d.ts")))
    paths.extend(
        (
            repo_root / "apps" / "idp-sdk" / "src" / "index.ts",
            repo_root / "apps" / "shared" / "appshell" / "app-shell.js",
            repo_root / "apps" / "shared" / "idpauth" / "web" / "idpauth.js",
            repo_root / "apps" / "shared" / "web" / "api-types.d.ts",
        )
    )
    violations: list[str] = []

    for path in paths:
        if not path.exists():
            continue
        for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            if pattern.search(line):
                violations.append(f"{path.relative_to(repo_root)}:{line_no}")

    return tuple(violations)


def shared_browser_global_any_cast_contract_violations(repo_root: Path) -> tuple[str, ...]:
    paths = (
        repo_root / "apps" / "shared" / "appshell" / "app-shell.js",
        repo_root / "apps" / "shared" / "idpauth" / "web" / "idpauth.js",
    )
    violations: list[str] = []

    for path in paths:
        for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            if "@type {any}" in line:
                violations.append(f"{path.relative_to(repo_root)}:{line_no}")

    return tuple(violations)


class _StatusRegionParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.has_status_region = False

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = dict(attrs)
        if values.get("role") == "status" and values.get("aria-live") == "polite":
            self.has_status_region = True


class _BodyLandmarkParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.stack: list[str] = []
        self.body_children: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        _ = attrs
        if self.stack == ["html", "body"]:
            self.body_children.append(tag)
        self.stack.append(tag)

    def handle_endtag(self, tag: str) -> None:
        for index in range(len(self.stack) - 1, -1, -1):
            if self.stack[index] == tag:
                del self.stack[index:]
                return


class _AssetOrderParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.stack: list[str] = []
        self.stylesheets: list[str] = []
        self.body_scripts: list[str] = []
        self.non_body_scripts: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = dict(attrs)
        if tag == "link" and values.get("rel") == "stylesheet" and values.get("href"):
            self.stylesheets.append(values["href"] or "")
        if tag == "script" and values.get("src"):
            if "body" in self.stack:
                self.body_scripts.append(values["src"] or "")
            else:
                self.non_body_scripts.append(values["src"] or "")
        self.stack.append(tag)

    def handle_endtag(self, tag: str) -> None:
        for index in range(len(self.stack) - 1, -1, -1):
            if self.stack[index] == tag:
                del self.stack[index:]
                return


def browser_app_status_region_contract_violations(repo_root: Path) -> tuple[str, ...]:
    violations: list[str] = []

    for app_name in canonical_browser_app_names():
        index = repo_root / "apps" / app_name / "app" / "internal" / "app" / "web" / "index.html"
        parser = _StatusRegionParser()
        parser.feed(index.read_text(encoding="utf-8"))
        if not parser.has_status_region:
            violations.append(f"{app_name} index.html missing polite status region")

    return tuple(violations)


def browser_app_asset_order_contract_violations(repo_root: Path) -> tuple[str, ...]:
    violations: list[str] = []

    for app_name in canonical_browser_app_names():
        index = repo_root / "apps" / app_name / "app" / "internal" / "app" / "web" / "index.html"
        parser = _AssetOrderParser()
        parser.feed(index.read_text(encoding="utf-8"))

        expected_stylesheets = ["/style.css", "/app-shell.css"]
        if parser.stylesheets != expected_stylesheets:
            violations.append(f"{app_name} stylesheet order should be {expected_stylesheets}, got {parser.stylesheets}")

        if parser.non_body_scripts:
            violations.append(f"{app_name} should load browser scripts at the end of body")

        expected_tail = ["/idpauth.js", "/app-shell.js", "/app.js"]
        if app_name != "apim-simulator":
            expected_tail = ["/runtime-config.js", *expected_tail]
        if parser.body_scripts[-len(expected_tail):] != expected_tail:
            violations.append(f"{app_name} script order should end with {expected_tail}, got {parser.body_scripts}")

    return tuple(violations)


def browser_app_landmark_layout_contract_violations(repo_root: Path) -> tuple[str, ...]:
    violations: list[str] = []

    for app_name in canonical_browser_app_names():
        index = repo_root / "apps" / app_name / "app" / "internal" / "app" / "web" / "index.html"
        parser = _BodyLandmarkParser()
        parser.feed(index.read_text(encoding="utf-8"))
        children = [tag for tag in parser.body_children if tag in {"a", "header", "main"}]
        if children[:3] != ["a", "header", "main"]:
            violations.append(f"{app_name} body landmarks should start with a, header, main; got {children}")

    return tuple(violations)


def browser_app_unknown_placeholder_contract_violations(repo_root: Path) -> tuple[str, ...]:
    violations: list[str] = []

    for app_name in canonical_browser_app_names():
        web_root = repo_root / "apps" / app_name / "app" / "internal" / "app" / "web"
        for path in (web_root / "index.html", web_root / "style.css"):
            text = path.read_text(encoding="utf-8")
            if re.search(r"\bunknown\b|Unknown", text):
                violations.append(path.relative_to(repo_root).as_posix())

        app_js = web_root / "app.js"
        for line_no, line in enumerate(app_js.read_text(encoding="utf-8").splitlines(), start=1):
            if "@typedef" in line or "@param" in line or "@type" in line or "import(" in line:
                continue
            if re.search(r"\bunknown\b|Unknown", line):
                violations.append(f"{app_js.relative_to(repo_root)}:{line_no}")

    return tuple(violations)


def browser_app_static_asset_go_contract_violations(repo_root: Path) -> tuple[str, ...]:
    shared = (repo_root / "apps" / "shared" / "appshell" / "appshell.go").read_text(encoding="utf-8")
    apim_static = (repo_root / "apps" / "apim-simulator" / "app" / "internal" / "app" / "static.go").read_text(
        encoding="utf-8"
    )
    apim_server = (repo_root / "apps" / "apim-simulator" / "app" / "internal" / "app" / "server.go").read_text(
        encoding="utf-8"
    )
    violations: list[str] = []

    if "func TryStaticFile(" not in shared:
        violations.append("shared app shell should expose TryStaticFile for route fallthrough static assets")
    if 'appshell.TryStaticFile(web, "web", w, r)' not in apim_static:
        violations.append("APIM simulator should use shared app shell TryStaticFile for embedded console assets")
    for fragment in ("web.ReadFile(", "func contentTypeFor(", "mime.TypeByExtension("):
        if fragment in apim_static or fragment in apim_server:
            violations.append(f"APIM simulator should not own static asset helper {fragment}")

    return tuple(violations)


def browser_app_color_token_contract_violations(repo_root: Path) -> tuple[str, ...]:
    required_tokens = (
        "color-scheme: light dark;",
        "--page: #f6f8fb;",
        "--surface: #ffffff;",
        "--field: #ffffff;",
        "--muted: #5d6b7c;",
        "--border: #cfdae6;",
        "--field-border: #b9c5d3;",
        "--text: #17202a;",
        "--accent: #2459b2;",
        "--error: #9b1c1c;",
        "--line: var(--border);",
        "--page: #101418;",
        "--surface: #151b21;",
        "--field: #0f1419;",
        "--muted: #b7c4d3;",
        "--border: #2d3945;",
        "--field-border: #3a4855;",
        "--text: #e8eef4;",
        "--accent: #2d6cdf;",
        "--error: #ffb4ab;",
    )
    app_forbidden_tokens = (
        "--page: #",
        "--surface: #",
        "--field: #",
        "--muted: #5d6b7c;",
        "--muted: #5e6d7d;",
        "--muted: #b7c4d3;",
        "--muted: #a6b3c0;",
        "--border: #",
        "--field-border: #",
        "--text: #",
        "--accent: #2459b2;",
        "--accent: #2d6cdf;",
        "--error: #",
        "--line: var(--border);",
    )
    violations: list[str] = []
    shared_css = (repo_root / "apps" / "shared" / "appshell" / "app-shell.css").read_text(encoding="utf-8")

    for token in required_tokens:
        if token not in shared_css:
            violations.append(f"shared app shell CSS missing palette token {token}")

    for app_name in canonical_browser_app_names():
        css = repo_root / "apps" / app_name / "app" / "internal" / "app" / "web" / "style.css"
        content = css.read_text(encoding="utf-8")
        for token in app_forbidden_tokens:
            if token not in content:
                continue
            violations.append(f"{app_name} style.css should not own shared palette token {token}")

    return tuple(violations)


def browser_app_header_controls_contract_violations(repo_root: Path) -> tuple[str, ...]:
    required_fragments = (
        'data-theme="system"',
        'id="auth-state"',
        'id="logout-btn"',
        'id="theme-switcher"',
        'rel="icon" href="/favicon.ico"',
    )
    violations: list[str] = []

    for app_name in canonical_browser_app_names():
        index = repo_root / "apps" / app_name / "app" / "internal" / "app" / "web" / "index.html"
        content = index.read_text(encoding="utf-8")
        for fragment in required_fragments:
            if fragment not in content:
                violations.append(f"{app_name} index.html missing {fragment}")

    return tuple(violations)


def browser_app_shell_css_boundary_contract_violations(repo_root: Path) -> tuple[str, ...]:
    shared_selectors = (
        "header",
        "main",
        ".theme-toggle",
        ".header-actions",
        ".auth-state",
        ".skip-link",
    )
    shared_fragments = (
        "box-sizing: border-box",
        "margin: 0",
        "background: var(--page)",
        "color: var(--text)",
        "font-family:",
        "ui-sans-serif",
    )
    shared_control_fragments = (
        "font: inherit",
        "min-height: 40px",
        "border: 1px solid var(--field-border)",
        "border-radius: 6px",
        "background: var(--field)",
        "color: var(--text)",
        "padding: 8px 10px",
        "background: var(--accent)",
        "color: #fff",
        "cursor: pointer",
    )
    local_control_fragments = (
        "font: inherit",
        "min-height: 40px",
        "border: 1px solid var(--field-border)",
        "border-radius: 6px",
        "background: var(--field)",
        "color: var(--text)",
        "background: var(--accent)",
        "cursor: pointer",
    )
    shared_panel_fragments = (
        ".app-panel",
        "margin: 16px 0",
        "padding: 18px",
        "border: 1px solid var(--border)",
        "border-radius: 8px",
        "background: var(--surface)",
    )
    local_panel_fragments = (
        "margin: 16px 0",
        "padding: 18px",
        "border: 1px solid var(--border)",
        "border: 1px solid var(--line)",
        "border-radius: 8px",
        "background: var(--surface)",
    )
    panel_selectors = {"section", "form", ".panel", ".runner", ".results", ".metrics-panel", ".conversation"}
    violations: list[str] = []

    shared_css = (repo_root / "apps" / "shared" / "appshell" / "app-shell.css").read_text(encoding="utf-8")
    for fragment in shared_fragments:
        if fragment not in shared_css:
            violations.append(f"shared app shell CSS missing global reset fragment {fragment}")
    for fragment in shared_control_fragments:
        if fragment not in shared_css:
            violations.append(f"shared app shell CSS missing base control fragment {fragment}")
    for fragment in shared_panel_fragments:
        if fragment not in shared_css:
            violations.append(f"shared app shell CSS missing app panel fragment {fragment}")

    for app_name in canonical_browser_app_names():
        css = repo_root / "apps" / app_name / "app" / "internal" / "app" / "web" / "style.css"
        content = css.read_text(encoding="utf-8")
        for selector in shared_selectors:
            if re.search(rf"(^|\n)\s*{re.escape(selector)}\b", content):
                violations.append(f"{app_name} style.css should not own shared app shell selector {selector}")
        if re.search(r"(^|\n)\s*\*\s*\{[^}]*box-sizing:\s*border-box", content, flags=re.S):
            violations.append(f"{app_name} style.css should not own global box-sizing reset")
        if "ui-sans-serif" in content:
            violations.append(f"{app_name} style.css should not own shared system font stack")
        body_match = re.search(r"(^|\n)\s*body\s*\{(?P<body>.*?)\n\}", content, flags=re.S)
        if body_match:
            body = body_match.group("body")
            for fragment in ("margin: 0", "background: var(--page)", "color: var(--text)"):
                if fragment in body:
                    violations.append(f"{app_name} style.css should not own shared body reset {fragment}")
        for match in re.finditer(r"(^|\n)(?P<selectors>[^{}]+)\{(?P<body>.*?)\n\}", content, flags=re.S):
            selectors = [selector.strip() for selector in match.group("selectors").split(",")]
            body = match.group("body")
            line_no = content[: match.start()].count("\n") + 1
            if selectors and all(selector in {"button", "input", "select", "textarea", ".button"} for selector in selectors):
                for fragment in local_control_fragments:
                    if fragment in body:
                        violations.append(
                            f"{app_name} style.css:{line_no} should not own shared base control fragment {fragment}"
                        )
            if selectors and all(selector in panel_selectors for selector in selectors):
                for fragment in local_panel_fragments:
                    if fragment in body:
                        violations.append(
                            f"{app_name} style.css:{line_no} should not own shared app panel fragment {fragment}"
                        )

    return tuple(violations)


def shared_appshell_route_trace_css_contract_violations(repo_root: Path) -> tuple[str, ...]:
    css = repo_root / "apps" / "shared" / "appshell" / "app-shell.css"
    js = repo_root / "apps" / "shared" / "appshell" / "app-shell.js"
    types = repo_root / "apps" / "shared" / "web" / "api-types.d.ts"
    content = css.read_text(encoding="utf-8")
    js_content = js.read_text(encoding="utf-8")
    type_content = types.read_text(encoding="utf-8")
    violations: list[str] = []
    required_fragments = (
        "counter-reset: hop",
        ".hop::before",
        "counter-increment: hop",
        "grid-template-columns: 28px minmax(0, 1fr)",
    )
    for fragment in required_fragments:
        if fragment not in content:
            violations.append(f"apps/shared/appshell/app-shell.css missing {fragment}")

    for fragment in (
        "function networkPathElement",
        "document.createElement(\"details\")",
        "document.createElement(\"summary\")",
        "document.createElement(\"strong\")",
        "container.replaceChildren(networkPathElement(hops))",
        "networkPathElement,",
    ):
        if fragment not in js_content:
            violations.append(f"shared app shell route trace renderer missing {fragment}")

    for fragment in (
        "container.innerHTML = renderNetworkPath(hops)",
        "return `<details>",
    ):
        if fragment in js_content:
            violations.append(f"shared app shell route trace renderer should not use {fragment}")

    if "networkPathElement(hops: NetworkHop[]): HTMLDetailsElement" not in type_content:
        violations.append("shared app shell API types missing networkPathElement")

    return tuple(violations)


def shared_appshell_theme_toggle_css_contract_violations(repo_root: Path) -> tuple[str, ...]:
    css = repo_root / "apps" / "shared" / "appshell" / "app-shell.css"
    js = repo_root / "apps" / "shared" / "appshell" / "app-shell.js"
    content = css.read_text(encoding="utf-8")
    js_content = js.read_text(encoding="utf-8")
    violations: list[str] = []
    required_fragments = (
        ".header-actions .theme-toggle",
        "flex: 0 0 42px",
    )
    for fragment in required_fragments:
        if fragment not in content:
            violations.append(f"apps/shared/appshell/app-shell.css missing {fragment}")

    for fragment in (
        "function themeIconElement",
        "document.createElementNS(",
        "switcher.prepend(",
        "themeIconElement(\"system\")",
        "themeIconElement(\"light\")",
        "themeIconElement(\"dark\")",
    ):
        if fragment not in js_content:
            violations.append(f"shared app shell theme icon renderer missing {fragment}")

    for fragment in (
        "themeIconMarkup",
        "insertAdjacentHTML",
    ):
        if fragment in js_content:
            violations.append(f"shared app shell theme icon renderer should not use {fragment}")

    return tuple(violations)


def shared_appshell_accessibility_css_contract_violations(repo_root: Path) -> tuple[str, ...]:
    css = repo_root / "apps" / "shared" / "appshell" / "app-shell.css"
    content = css.read_text(encoding="utf-8")
    required_fragments = (
        ".skip-link:focus-visible",
        "transition: transform 160ms ease",
        "@media (prefers-reduced-motion: reduce)",
        "@media (prefers-contrast: more)",
        "@media (forced-colors: active)",
    )
    return tuple(
        f"apps/shared/appshell/app-shell.css missing {fragment}"
        for fragment in required_fragments
        if fragment not in content
    )


def shared_appshell_header_text_resilience_contract_violations(repo_root: Path) -> tuple[str, ...]:
    css = repo_root / "apps" / "shared" / "appshell" / "app-shell.css"
    content = css.read_text(encoding="utf-8")
    violations: list[str] = []

    for selector in ("header h1", "header p"):
        match = re.search(rf"{re.escape(selector)}\s*\{{(?P<body>.*?)\n\}}", content, re.S)
        if match is None:
            violations.append(f"apps/shared/appshell/app-shell.css missing {selector} block")
            continue
        if "overflow-wrap: anywhere" not in match.group("body"):
            violations.append(f"apps/shared/appshell/app-shell.css {selector} should wrap long tokens")

    return tuple(violations)


def shared_appshell_control_text_resilience_contract_violations(repo_root: Path) -> tuple[str, ...]:
    css = repo_root / "apps" / "shared" / "appshell" / "app-shell.css"
    content = css.read_text(encoding="utf-8")
    selector = ".header-actions button,\n.header-actions a,\n.sign-in-link"
    match = re.search(rf"{re.escape(selector)}\s*\{{(?P<body>.*?)\n\}}", content, re.S)
    if match is None:
        return ("apps/shared/appshell/app-shell.css missing shared header action control block",)

    required_fragments = (
        "max-width: 100%",
        "overflow-wrap: anywhere",
        "text-align: center",
    )
    return tuple(
        f"apps/shared/appshell/app-shell.css shared header controls missing {fragment}"
        for fragment in required_fragments
        if fragment not in match.group("body")
    )


def shared_appshell_diagnostic_text_resilience_contract_violations(repo_root: Path) -> tuple[str, ...]:
    css = repo_root / "apps" / "shared" / "appshell" / "app-shell.css"
    content = css.read_text(encoding="utf-8")
    selector = ":where(pre, code, .diagnostics)"
    match = re.search(rf"{re.escape(selector)}\s*\{{(?P<body>.*?)\n\}}", content, re.S)
    if match is None:
        return ("apps/shared/appshell/app-shell.css missing shared diagnostic text block",)

    required_fragments = (
        "max-width: 100%",
        "overflow-x: auto",
        "overflow-wrap: anywhere",
    )
    return tuple(
        f"apps/shared/appshell/app-shell.css shared diagnostics missing {fragment}"
        for fragment in required_fragments
        if fragment not in match.group("body")
    )


def shared_appshell_form_control_sizing_contract_violations(repo_root: Path) -> tuple[str, ...]:
    css = repo_root / "apps" / "shared" / "appshell" / "app-shell.css"
    content = css.read_text(encoding="utf-8")
    selector = ":where(input, textarea, select)"
    match = re.search(rf"{re.escape(selector)}\s*\{{(?P<body>.*?)\n\}}", content, re.S)
    if match is None:
        return ("apps/shared/appshell/app-shell.css missing shared form control sizing block",)

    required_fragments = (
        "box-sizing: border-box",
        "max-width: 100%",
        "min-width: 0",
    )
    return tuple(
        f"apps/shared/appshell/app-shell.css shared form controls missing {fragment}"
        for fragment in required_fragments
        if fragment not in match.group("body")
    )


def shared_appshell_form_label_textarea_contract_violations(repo_root: Path) -> tuple[str, ...]:
    shared_css = repo_root / "apps" / "shared" / "appshell" / "app-shell.css"
    shared_content = shared_css.read_text(encoding="utf-8")
    violations: list[str] = []

    label_match = re.search(r":where\(label\)\s*\{(?P<body>.*?)\n\}", shared_content, re.S)
    if label_match is None:
        violations.append("apps/shared/appshell/app-shell.css missing shared label block")
    else:
        for fragment in ("display: block", "margin-bottom: 8px", "font-weight: 700"):
            if fragment not in label_match.group("body"):
                violations.append(f"apps/shared/appshell/app-shell.css shared labels missing {fragment}")

    textarea_match = re.search(r":where\(textarea\)\s*\{(?P<body>.*?)\n\}", shared_content, re.S)
    if textarea_match is None:
        violations.append("apps/shared/appshell/app-shell.css missing shared textarea block")
    else:
        for fragment in ("width: 100%", "resize: vertical", "line-height: 1.4"):
            if fragment not in textarea_match.group("body"):
                violations.append(f"apps/shared/appshell/app-shell.css shared textareas missing {fragment}")

    forbidden_fragments = (
        "display: block",
        "margin-bottom: 8px",
        "resize: vertical",
        "width: 100%",
    )
    for app_name in canonical_browser_app_names():
        css = repo_root / "apps" / app_name / "app" / "internal" / "app" / "web" / "style.css"
        content = css.read_text(encoding="utf-8")
        for match in re.finditer(r"(^|\n)(?P<selectors>[^{}]+)\{(?P<body>.*?)\n\}", content, flags=re.S):
            selectors = [selector.strip() for selector in match.group("selectors").split(",")]
            if not selectors or any(selector not in {"label", "textarea", "input", "select"} for selector in selectors):
                continue
            body = match.group("body")
            line_no = content[: match.start()].count("\n") + 1
            for fragment in forbidden_fragments:
                if fragment in body:
                    violations.append(
                        f"{app_name} style.css:{line_no} should leave shared form rhythm fragment {fragment} to app-shell.css"
                    )

    return tuple(violations)


def shared_appshell_code_block_surface_contract_violations(repo_root: Path) -> tuple[str, ...]:
    shared_css = repo_root / "apps" / "shared" / "appshell" / "app-shell.css"
    shared_content = shared_css.read_text(encoding="utf-8")
    selector = ":where(pre, code)"
    match = re.search(rf"{re.escape(selector)}\s*\{{(?P<body>.*?)\n\}}", shared_content, re.S)
    violations: list[str] = []

    if match is None:
        violations.append("apps/shared/appshell/app-shell.css missing shared code block surface")
    else:
        for fragment in (
            "font-family:",
            "ui-monospace",
            "overflow-wrap: anywhere",
        ):
            if fragment not in match.group("body"):
                violations.append(f"apps/shared/appshell/app-shell.css shared code blocks missing {fragment}")

    pre_match = re.search(r":where\(pre\)\s*\{(?P<body>.*?)\n\}", shared_content, re.S)
    if pre_match is None:
        violations.append("apps/shared/appshell/app-shell.css missing shared pre block surface")
    else:
        for fragment in (
            "overflow: auto",
            "padding: 12px",
            "border: 1px solid var(--border",
            "border-radius: 6px",
            "background: var(--field",
        ):
            if fragment not in pre_match.group("body"):
                violations.append(f"apps/shared/appshell/app-shell.css shared pre blocks missing {fragment}")

    forbidden_fragments = (
        "font-family:",
        "ui-monospace",
        "overflow-wrap: anywhere",
        "padding: 12px",
        "border: 1px solid var(--border)",
        "border: 1px solid var(--line)",
        "border-radius: 6px",
        "background: var(--field)",
    )
    for app_name in canonical_browser_app_names():
        css = repo_root / "apps" / app_name / "app" / "internal" / "app" / "web" / "style.css"
        content = css.read_text(encoding="utf-8")
        for match in re.finditer(r"(^|\n)(?P<selectors>[^{}]+)\{(?P<body>.*?)\n\}", content, flags=re.S):
            selectors = [selector.strip() for selector in match.group("selectors").split(",")]
            if not selectors or any(selector not in {"pre", "code"} for selector in selectors):
                continue
            body = match.group("body")
            line_no = content[: match.start()].count("\n") + 1
            for fragment in forbidden_fragments:
                if fragment in body:
                    violations.append(
                        f"{app_name} style.css:{line_no} should leave shared code block fragment {fragment} to app-shell.css"
                    )

    return tuple(violations)


def shared_appshell_message_render_contract_violations(repo_root: Path) -> tuple[str, ...]:
    shared_js = repo_root / "apps" / "shared" / "appshell" / "app-shell.js"
    shared_types = repo_root / "apps" / "shared" / "web" / "api-types.d.ts"
    shared_content = shared_js.read_text(encoding="utf-8")
    type_content = shared_types.read_text(encoding="utf-8")
    violations: list[str] = []

    for fragment in (
        "function renderMessageInto",
        "document.createElement(\"p\")",
        "paragraph.className = className",
        "node.replaceChildren(paragraph)",
        "renderMessageInto,",
    ):
        if fragment not in shared_content:
            violations.append(f"shared app shell message renderer missing {fragment}")

    if "renderMessageInto(" not in type_content:
        violations.append("shared app shell API types missing renderMessageInto")

    simple_paragraph_pattern = re.compile(r"\.innerHTML\s*=\s*([`\"])\s*<p(?:\s|>|[\"'])")
    for app_name in canonical_browser_app_names():
        app_js = repo_root / "apps" / app_name / "app" / "internal" / "app" / "web" / "app.js"
        content = app_js.read_text(encoding="utf-8")
        for line_no, line in enumerate(content.splitlines(), start=1):
            if simple_paragraph_pattern.search(line):
                violations.append(
                    f"{app_name} app.js:{line_no} should use shared renderMessageInto for simple paragraph messages"
                )

    return tuple(violations)


def shared_appshell_dom_lookup_contract_violations(repo_root: Path) -> tuple[str, ...]:
    shared_js = repo_root / "apps" / "shared" / "appshell" / "app-shell.js"
    shared_types = repo_root / "apps" / "shared" / "web" / "api-types.d.ts"
    shared_content = shared_js.read_text(encoding="utf-8")
    type_content = shared_types.read_text(encoding="utf-8")
    violations: list[str] = []

    for fragment in (
        "function optionalElement",
        "optionalElement(\"theme-switcher\")",
        "optionalElement(\"auth-state\")",
        "optionalElement(\"login-link\")",
        "const element = optionalElement(id)",
        "optionalElement,",
    ):
        if fragment not in shared_content:
            violations.append(f"shared app shell DOM lookup helper missing {fragment}")

    if "optionalElement(id: string): HTMLElement | null" not in type_content:
        violations.append("shared app shell API types missing optionalElement")

    if shared_content.count("document.getElementById(") != 1:
        violations.append("shared app shell should confine document.getElementById to optionalElement")

    return tuple(violations)


def shared_appshell_status_render_contract_violations(repo_root: Path) -> tuple[str, ...]:
    shared_js = repo_root / "apps" / "shared" / "appshell" / "app-shell.js"
    shared_types = repo_root / "apps" / "shared" / "web" / "api-types.d.ts"
    sentiment_app = repo_root / "apps" / "sentiment" / "app" / "internal" / "app" / "web" / "app.js"
    subnetcalc_app = repo_root / "apps" / "subnetcalc" / "app" / "internal" / "app" / "web" / "app.js"
    chatgpt_app = repo_root / "apps" / "chatgpt-sim" / "app" / "internal" / "app" / "web" / "app.js"
    apim_app = repo_root / "apps" / "apim-simulator" / "app" / "internal" / "app" / "web" / "app.js"
    shared_content = shared_js.read_text(encoding="utf-8")
    type_content = shared_types.read_text(encoding="utf-8")
    sentiment_content = sentiment_app.read_text(encoding="utf-8")
    subnetcalc_content = subnetcalc_app.read_text(encoding="utf-8")
    chatgpt_content = chatgpt_app.read_text(encoding="utf-8")
    apim_content = apim_app.read_text(encoding="utf-8")
    violations: list[str] = []

    for fragment in (
        "function renderStatusInto",
        "node.classList.toggle(\"error\",",
        "setText(node, value)",
        "renderStatusInto,",
    ):
        if fragment not in shared_content:
            violations.append(f"shared app shell status renderer missing {fragment}")

    for fragment in (
        "renderStatusInto(",
        "node: Element",
        "value: AppShellTextValue",
        "isError?: boolean",
        "): void;",
    ):
        if fragment not in type_content:
            violations.append(f"shared app shell API types missing renderStatusInto fragment {fragment}")

    if "renderStatusInto(apiStatusEl" not in sentiment_content:
        violations.append("sentiment health status should use shared renderStatusInto")
    for fragment in (
        "apiStatusEl.textContent =",
        "apiStatusEl.classList.add(\"error\")",
        "apiStatusEl.classList.remove(\"error\")",
    ):
        if fragment in sentiment_content:
            violations.append(f"sentiment health status should use shared renderStatusInto instead of {fragment}")

    if "renderStatusInto(apiStatus" not in subnetcalc_content:
        violations.append("subnetcalc health status should use shared renderStatusInto")
    for fragment in (
        "apiStatus.textContent =",
        "apiStatus.classList.add(\"error\")",
        "apiStatus.classList.remove(\"error\")",
    ):
        if fragment in subnetcalc_content:
            violations.append(f"subnetcalc health status should use shared renderStatusInto instead of {fragment}")

    if "renderStatusInto(statusEl" not in chatgpt_content:
        violations.append("chatgpt-sim status updates should use shared renderStatusInto")
    if "statusEl.textContent =" in chatgpt_content:
        violations.append("chatgpt-sim status updates should use shared renderStatusInto instead of statusEl.textContent")

    if "renderStatusInto(statusBox" not in apim_content:
        violations.append("apim-simulator connection status should use shared renderStatusInto")
    if "statusBox.textContent =" in apim_content:
        violations.append("apim-simulator connection status should use shared renderStatusInto instead of statusBox.textContent")

    return tuple(violations)


def shared_appshell_select_option_render_contract_violations(repo_root: Path) -> tuple[str, ...]:
    shared_js = repo_root / "apps" / "shared" / "appshell" / "app-shell.js"
    shared_types = repo_root / "apps" / "shared" / "web" / "api-types.d.ts"
    chatgpt_app = repo_root / "apps" / "chatgpt-sim" / "app" / "internal" / "app" / "web" / "app.js"
    shared_content = shared_js.read_text(encoding="utf-8")
    type_content = shared_types.read_text(encoding="utf-8")
    chatgpt_content = chatgpt_app.read_text(encoding="utf-8")
    violations: list[str] = []

    for fragment in (
        "function renderOptionsInto",
        "document.createElement(\"option\")",
        "option.value = value",
        "option.textContent = label",
        "select.replaceChildren(...options)",
        "renderOptionsInto,",
    ):
        if fragment not in shared_content:
            violations.append(f"shared app shell select renderer missing {fragment}")

    if "renderOptionsInto<T>(" not in type_content:
        violations.append("shared app shell API types missing renderOptionsInto")

    forbidden_fragments = (
        "connectorSelect.innerHTML",
        "<option",
    )
    for fragment in forbidden_fragments:
        if fragment in chatgpt_content:
            violations.append(f"chatgpt-sim connector select should use shared renderOptionsInto instead of {fragment}")

    return tuple(violations)


def shared_appshell_element_list_render_contract_violations(repo_root: Path) -> tuple[str, ...]:
    shared_js = repo_root / "apps" / "shared" / "appshell" / "app-shell.js"
    shared_types = repo_root / "apps" / "shared" / "web" / "api-types.d.ts"
    chatgpt_app = repo_root / "apps" / "chatgpt-sim" / "app" / "internal" / "app" / "web" / "app.js"
    shared_content = shared_js.read_text(encoding="utf-8")
    type_content = shared_types.read_text(encoding="utf-8")
    chatgpt_content = chatgpt_app.read_text(encoding="utf-8")
    violations: list[str] = []

    for fragment in (
        "function renderElementsInto",
        "items.map(elementFor)",
        "node.replaceChildren(...",
        "emptyElement",
        "renderElementsInto,",
    ):
        if fragment not in shared_content:
            violations.append(f"shared app shell element list renderer missing {fragment}")

    if "renderElementsInto<T>(" not in type_content:
        violations.append("shared app shell API types missing renderElementsInto")

    for fragment in (
        "connectorList.innerHTML",
        "function renderConnector",
        "escapeAttr",
        "escapeHTML",
        "<article",
    ):
        if fragment in chatgpt_content:
            violations.append(f"chatgpt-sim connector list should use DOM elements and shared renderElementsInto instead of {fragment}")

    return tuple(violations)


def sentiment_comment_list_render_contract_violations(repo_root: Path) -> tuple[str, ...]:
    app_js = repo_root / "apps" / "sentiment" / "app" / "internal" / "app" / "web" / "app.js"
    content = app_js.read_text(encoding="utf-8")
    violations: list[str] = []

    for fragment in (
        "renderElementsInto",
        "function commentElement",
        "document.createElement(\"article\")",
        "article.className = \"comment\"",
    ):
        if fragment not in content:
            violations.append(f"sentiment comment renderer missing {fragment}")

    for fragment in (
        "commentsEl.innerHTML",
        ".map(\n\t\t\t(item) => `",
        "escapeHTML",
        "<article class=\"comment\">",
    ):
        if fragment in content:
            violations.append(f"sentiment comments should use DOM elements and shared renderElementsInto instead of {fragment}")

    return tuple(violations)


def sentiment_diagnostics_render_contract_violations(repo_root: Path) -> tuple[str, ...]:
    app_js = repo_root / "apps" / "sentiment" / "app" / "internal" / "app" / "web" / "app.js"
    content = app_js.read_text(encoding="utf-8")
    violations: list[str] = []

    for fragment in (
        "apiTimingElement",
        "renderNetworkPathInto",
        "diagnosticsEl.replaceChildren(",
        "function renderAPIDiagnostics",
    ):
        if fragment not in content:
            violations.append(f"sentiment diagnostics renderer missing {fragment}")

    for fragment in (
        "diagnosticsEl.innerHTML",
        "renderAPITiming(timing",
        "renderNetworkPath(configuredNetworkHops())",
    ):
        if fragment in content:
            violations.append(f"sentiment diagnostics should use shared DOM helpers instead of {fragment}")

    return tuple(violations)


def subnetcalc_result_card_render_contract_violations(repo_root: Path) -> tuple[str, ...]:
    shared_js = repo_root / "apps" / "shared" / "appshell" / "app-shell.js"
    shared_types = repo_root / "apps" / "shared" / "web" / "api-types.d.ts"
    app_js = repo_root / "apps" / "subnetcalc" / "app" / "internal" / "app" / "web" / "app.js"
    shared_content = shared_js.read_text(encoding="utf-8")
    type_content = shared_types.read_text(encoding="utf-8")
    app_content = app_js.read_text(encoding="utf-8")
    violations: list[str] = []

    for fragment in (
        "function keyValueTableElement",
        "function apiTimingElement",
        "renderKeyValueTableInto,",
        "keyValueTableElement,",
        "apiTimingElement,",
    ):
        if fragment not in shared_content:
            violations.append(f"shared app shell DOM diagnostics missing {fragment}")

    for fragment in (
        "keyValueTableElement(rows: KeyValueTableRow[]): HTMLTableElement",
        "apiTimingElement(",
        "): HTMLDetailsElement",
        "renderKeyValueTableInto(container: Element, rows: KeyValueTableRow[]): void",
    ):
        if fragment not in type_content:
            violations.append(f"shared app shell API types missing {fragment}")

    for fragment in (
        "content.innerHTML",
        "insertAdjacentHTML",
        "function renderArticle(title, rows, timing) {\n\treturn `<article>",
        "function renderPerformance(totalMs) {\n\tconst networkPath",
        "escapeHTML",
    ):
        if fragment in app_content:
            violations.append(f"subnetcalc result cards should use DOM elements and shared diagnostics helpers instead of {fragment}")

    for fragment in (
        "renderElementsInto(",
        "content,",
        "function resultArticleElement",
        "function performanceElement",
        "keyValueTableElement(rows)",
        "apiTimingElement(timing)",
    ):
        if fragment not in app_content:
            violations.append(f"subnetcalc result renderer missing {fragment}")

    return tuple(violations)


def shared_appshell_summary_list_render_contract_violations(repo_root: Path) -> tuple[str, ...]:
    shared_js = repo_root / "apps" / "shared" / "appshell" / "app-shell.js"
    shared_types = repo_root / "apps" / "shared" / "web" / "api-types.d.ts"
    apim_app = repo_root / "apps" / "apim-simulator" / "app" / "internal" / "app" / "web" / "app.js"
    shared_content = shared_js.read_text(encoding="utf-8")
    type_content = shared_types.read_text(encoding="utf-8")
    apim_content = apim_app.read_text(encoding="utf-8")
    violations: list[str] = []

    for fragment in (
        "function renderSummaryListInto",
        "document.createElement(\"li\")",
        "document.createElement(\"strong\")",
        "document.createElement(\"span\")",
        "node.replaceChildren(...rows)",
        "renderSummaryListInto,",
    ):
        if fragment not in shared_content:
            violations.append(f"shared app shell summary list renderer missing {fragment}")

    if "renderSummaryListInto<T>(" not in type_content:
        violations.append("shared app shell API types missing renderSummaryListInto")

    forbidden_fragments = (
        "routes.innerHTML",
        "subscriptions.innerHTML",
        "<li><strong>",
    )
    for fragment in forbidden_fragments:
        if fragment in apim_content:
            violations.append(f"apim-simulator summary lists should use shared renderSummaryListInto instead of {fragment}")

    return tuple(violations)


def shared_appshell_global_button_resilience_contract_violations(repo_root: Path) -> tuple[str, ...]:
    css = repo_root / "apps" / "shared" / "appshell" / "app-shell.css"
    content = css.read_text(encoding="utf-8")
    selector = ":where(button, .button)"
    match = re.search(rf"{re.escape(selector)}\s*\{{(?P<body>.*?)\n\}}", content, re.S)
    if match is None:
        return ("apps/shared/appshell/app-shell.css missing shared global button resilience block",)

    required_fragments = (
        "max-width: 100%",
        "min-width: 0",
        "overflow-wrap: anywhere",
        "text-align: center",
        "touch-action: manipulation",
    )
    return tuple(
        f"apps/shared/appshell/app-shell.css shared global buttons missing {fragment}"
        for fragment in required_fragments
        if fragment not in match.group("body")
    )


def shared_appshell_status_table_css_contract_violations(repo_root: Path) -> tuple[str, ...]:
    shared_css = repo_root / "apps" / "shared" / "appshell" / "app-shell.css"
    shared_content = shared_css.read_text(encoding="utf-8")
    required_fragments = (
        ".notice",
        ".error",
        ":where(table)",
        ":where(th, td)",
        "border-collapse: collapse",
        "overflow-wrap: anywhere",
    )
    violations = [
        f"apps/shared/appshell/app-shell.css missing shared status/table fragment {fragment}"
        for fragment in required_fragments
        if fragment not in shared_content
    ]

    local_selectors = (
        ".notice",
        ".error",
        ".diagnostics table",
        ".diagnostics th",
        ".diagnostics td",
        "table",
        "th,",
        "td",
    )
    for app_name in canonical_browser_app_names():
        css = repo_root / "apps" / app_name / "app" / "internal" / "app" / "web" / "style.css"
        content = css.read_text(encoding="utf-8")
        for selector in local_selectors:
            if re.search(rf"(^|\n)\s*{re.escape(selector)}\b", content):
                violations.append(f"{app_name} style.css should not own shared status/table selector {selector}")

    return tuple(violations)


def hardened_go_command_http_contract_violations(repo_root: Path) -> tuple[str, ...]:
    cmd_files = sorted((repo_root / "apps").glob("*/app/cmd/*/main.go"))
    violations: list[str] = []

    if not cmd_files:
        violations.append("no local Go app command files found")

    for path in cmd_files:
        relative_path = path.relative_to(repo_root).as_posix()
        content = path.read_text(encoding="utf-8")
        bare_content = content.replace("apphttp.ListenAndServe(", "")
        if "http.ListenAndServe(" in bare_content:
            violations.append(f"{relative_path} uses bare http.ListenAndServe")
        if "http.Get(" in content:
            violations.append(f"{relative_path} uses unbounded http.Get healthcheck")
        if "apphttp.HandleHealthcheckCommand(" not in content:
            violations.append(f"{relative_path} should expose the standard healthcheck subcommand through apphttp.HandleHealthcheckCommand")
        if "apphttp.ListenAndServe(" not in content and "apphttp.NewServer(" not in content:
            violations.append(f"{relative_path} does not use apphttp server helper")
        if "apphttp.CheckLocalHealth(" in content or "os.Args" in content:
            violations.append(f"{relative_path} should leave healthcheck command handling to apphttp")
        if "http.ErrServerClosed" in content:
            violations.append(f"{relative_path} should leave server closed error policy to apphttp")
        if "os.Exit(" in content:
            violations.append(f"{relative_path} should leave command process exit policy to apphttp or log.Fatal")
        if "os.Stdout.Sync(" in content or "_ = os.Stdout" in content:
            violations.append(f"{relative_path} should not own ad hoc stdout flushing policy")
        for helper_name in ("env", "firstEnv"):
            if re.search(rf"(?m)^func {helper_name}\(", content):
                violations.append(f"{relative_path} should use shared apphttp env helpers")
        for fragment in (
            '":" + apphttp.Env("PORT"',
            'strings.TrimPrefix(apphttp.Env("PORT"',
            'strings.Contains(addr, ":")',
            'strings.Contains(cfg.Addr, ":")',
            'strings.Contains(metricsAddr, ":")',
        ):
            if fragment in content:
                violations.append(f"{relative_path} should use apphttp.NormalizeAddr for listen addresses")

    shared = (repo_root / "apps" / "shared" / "apphttp" / "apphttp.go").read_text(encoding="utf-8")
    for fragment in (
        "DefaultReadHeaderTimeout",
        "ReadHeaderTimeout: DefaultReadHeaderTimeout",
        "DefaultHealthcheckTimeout",
        "func CheckLocalHealth(",
        "func HealthcheckCommand(",
        "func HandleHealthcheckCommand(",
        "func IgnoreServerClosed(",
        "errors.Is(err, http.ErrServerClosed)",
        "func Env(",
        "func FirstEnv(",
    ):
        if fragment not in shared:
            violations.append(f"apps/shared/apphttp/apphttp.go missing {fragment}")

    return tuple(violations)


def go_app_upstream_json_decode_contract_violations(repo_root: Path) -> tuple[str, ...]:
    upstream_apps = ("chatgpt-sim", "langfuse-demos", "platform-mcp")
    violations: list[str] = []

    for app_name in upstream_apps:
        server_path = repo_root / "apps" / app_name / "app" / "internal" / "app" / "server.go"
        content = server_path.read_text(encoding="utf-8")
        relative = server_path.relative_to(repo_root).as_posix()
        if "apphttp.DecodeJSONReader(" not in content:
            violations.append(f"{relative} should decode upstream JSON through apphttp.DecodeJSONReader")
        for fragment in (
            "json.NewDecoder(resp.Body).Decode(",
            "json.NewDecoder(io.LimitReader(resp.Body",
        ):
            if fragment in content:
                violations.append(f"{relative} should not own upstream JSON decode fragment {fragment}")

    shared = (repo_root / "apps" / "shared" / "apphttp" / "apphttp.go").read_text(encoding="utf-8")
    if "func DecodeJSONReader(" not in shared:
        violations.append("apps/shared/apphttp/apphttp.go missing func DecodeJSONReader(")

    return tuple(violations)


def platform_mcp_config_env_contract_violations(repo_root: Path) -> tuple[str, ...]:
    config_path = repo_root / "apps" / "platform-mcp" / "app" / "internal" / "app" / "config.go"
    content = config_path.read_text(encoding="utf-8")
    violations: list[str] = []

    for helper_name in ("env", "envBool"):
        if re.search(rf"(?m)^func {helper_name}\(", content):
            violations.append(f"{config_path.relative_to(repo_root)} should use shared apphttp env helpers")
    for fragment in ("apphttp.Env(", "apphttp.EnvBool("):
        if fragment not in content:
            violations.append(f"{config_path.relative_to(repo_root)} missing {fragment}")

    shared = (repo_root / "apps" / "shared" / "apphttp" / "apphttp.go").read_text(encoding="utf-8")
    if "func EnvBool(" not in shared:
        violations.append("apps/shared/apphttp/apphttp.go missing func EnvBool(")

    return tuple(violations)


def langfuse_demos_config_env_contract_violations(repo_root: Path) -> tuple[str, ...]:
    config_path = repo_root / "apps" / "langfuse-demos" / "app" / "internal" / "app" / "config.go"
    content = config_path.read_text(encoding="utf-8")
    violations: list[str] = []

    for helper_name in ("getenv", "secondsDuration"):
        if re.search(rf"(?m)^func {helper_name}\(", content):
            violations.append(f"{config_path.relative_to(repo_root)} should use shared apphttp env helpers")
    for fragment in ("apphttp.Env(", "apphttp.EnvSeconds("):
        if fragment not in content:
            violations.append(f"{config_path.relative_to(repo_root)} missing {fragment}")
    if '"strconv"' in content:
        violations.append(f"{config_path.relative_to(repo_root)} should not parse env numbers locally")

    shared = (repo_root / "apps" / "shared" / "apphttp" / "apphttp.go").read_text(encoding="utf-8")
    if "func EnvSeconds(" not in shared:
        violations.append("apps/shared/apphttp/apphttp.go missing func EnvSeconds(")

    return tuple(violations)


def chatgpt_sim_config_env_contract_violations(repo_root: Path) -> tuple[str, ...]:
    config_path = repo_root / "apps" / "chatgpt-sim" / "app" / "internal" / "app" / "config.go"
    content = config_path.read_text(encoding="utf-8")
    violations: list[str] = []

    for helper_name in ("positiveInt", "secondsDuration", "firstEnv"):
        if re.search(rf"(?m)^func {helper_name}\(", content):
            violations.append(f"{config_path.relative_to(repo_root)} should use shared apphttp env helpers")
    for fragment in ("apphttp.Env(", "apphttp.EnvSeconds(", "apphttp.EnvInt(", "idpauth.RuntimeAuthConfigFromEnv("):
        if fragment not in content:
            violations.append(f"{config_path.relative_to(repo_root)} missing {fragment}")
    if 'os.Getenv("MCP_CONNECTORS")' in content:
        violations.append(f"{config_path.relative_to(repo_root)} should read MCP_CONNECTORS through apphttp.Env")
    if '"strconv"' in content:
        violations.append(f"{config_path.relative_to(repo_root)} should not parse env numbers locally")

    shared = (repo_root / "apps" / "shared" / "apphttp" / "apphttp.go").read_text(encoding="utf-8")
    if "func EnvInt(" not in shared:
        violations.append("apps/shared/apphttp/apphttp.go missing func EnvInt(")

    return tuple(violations)


def apim_simulator_config_env_contract_violations(repo_root: Path) -> tuple[str, ...]:
    config_path = repo_root / "apps" / "apim-simulator" / "app" / "internal" / "app" / "config.go"
    content = config_path.read_text(encoding="utf-8")
    violations: list[str] = []

    for fragment in (
        'os.Getenv("APIM_CONFIG_TEMPLATE_SUBSTITUTE")',
        "os.Getenv(parts[1])",
    ):
        if fragment in content:
            violations.append(f"{config_path.relative_to(repo_root)} should read template env through apphttp helpers")
    for fragment in ("apphttp.EnvBool(", "apphttp.Env("):
        if fragment not in content:
            violations.append(f"{config_path.relative_to(repo_root)} missing {fragment}")

    return tuple(violations)


def image_catalog_expectations() -> tuple[ImageCatalogExpectation, ...]:
    return (
        ImageCatalogExpectation("chatgpt-sim", "apps/chatgpt-sim/app", "chatgpt-sim"),
        ImageCatalogExpectation("idp-core", ".", "idp-core"),
        ImageCatalogExpectation("langfuse-demos", "apps/langfuse-demos/app", "langfuse-demos"),
        ImageCatalogExpectation("platform-mcp", "apps/platform-mcp/app", "platform-mcp"),
        ImageCatalogExpectation("sentiment-api", "apps/sentiment/app", "sentiment"),
        ImageCatalogExpectation("sentiment-auth-ui", "apps/sentiment/app", "sentiment"),
        ImageCatalogExpectation("subnetcalc-api", "apps/subnetcalc/app", "subnetcalc"),
        ImageCatalogExpectation("subnetcalc-frontend", "apps/subnetcalc/app", "subnetcalc"),
        ImageCatalogExpectation(
            "subnetcalc-apim-simulator",
            "apps/apim-simulator",
            "apim-simulator",
            dockerfile="app/Dockerfile",
        ),
    )


def go_module_requirements(go_mod: Path) -> tuple[GoModuleRequirement, ...]:
    requirements: list[GoModuleRequirement] = []
    in_require_block = False

    for raw_line in go_mod.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("//"):
            continue

        if line == "require (":
            in_require_block = True
            continue
        if in_require_block and line == ")":
            in_require_block = False
            continue
        if line.startswith("require "):
            line = line.removeprefix("require ").strip()
        elif not in_require_block:
            continue

        parts = line.split()
        if len(parts) < 2:
            continue

        requirements.append(
            GoModuleRequirement(
                module=parts[0],
                version=parts[1],
                indirect="// indirect" in line,
            )
        )

    return tuple(requirements)


def go_app_dependency_contract_violations(repo_root: Path) -> tuple[str, ...]:
    allowed_external = {
        "github.com/coreos/go-oidc/v3",
        "github.com/go-jose/go-jose/v4",
        "golang.org/x/oauth2",
    }
    violations: list[str] = []

    for name in canonical_go_app_names():
        go_mod = repo_root / "apps" / name / "app" / "go.mod"
        for requirement in go_module_requirements(go_mod):
            if requirement.module.startswith("platform.local/"):
                continue
            if requirement.module not in allowed_external:
                violations.append(
                    f"{name} has undocumented external dependency {requirement.module}"
                )
                continue
            if not requirement.indirect:
                violations.append(
                    f"{name} should consume {requirement.module} through shared modules, not directly"
                )

    shared_auth_requirements = {
        requirement.module: requirement
        for requirement in go_module_requirements(
            repo_root / "apps" / "shared" / "idpauth" / "go.mod"
        )
    }
    oidc = shared_auth_requirements.get("github.com/coreos/go-oidc/v3")
    if oidc is None:
        violations.append("shared idpauth is missing github.com/coreos/go-oidc/v3")
    elif oidc.indirect:
        violations.append("shared idpauth should own github.com/coreos/go-oidc/v3 directly")

    for module in ("github.com/go-jose/go-jose/v4", "golang.org/x/oauth2"):
        requirement = shared_auth_requirements.get(module)
        if requirement is None:
            violations.append(f"shared idpauth is missing transitive {module}")
        elif not requirement.indirect:
            violations.append(f"shared idpauth should keep {module} transitive behind go-oidc")

    return tuple(violations)


def go_app_auth_env_contract_violations(repo_root: Path) -> tuple[str, ...]:
    auth_env_fragments = (
        'apphttp.Env("AUTH_METHOD"',
        'apphttp.Env("API_AUTH_METHOD"',
        'apphttp.Env("RUNTIME_ROLE"',
        'apphttp.Env("OIDC_AUDIENCE"',
        'apphttp.Env("OIDC_CLIENT_ID"',
        'apphttp.Env("OIDC_JWKS_URI"',
        'apphttp.Env("OIDC_REDIRECT_URI"',
        'apphttp.FirstEnv("OIDC_ISSUER_URL"',
    )
    violations: list[str] = []

    idpauth_go = repo_root / "apps" / "shared" / "idpauth" / "idpauth.go"
    if "RuntimeAuthConfigFromEnv" not in idpauth_go.read_text(encoding="utf-8"):
        violations.append("shared idpauth should own RuntimeAuthConfigFromEnv")

    for path in sorted((repo_root / "apps").glob("*/app/**/*.go")):
        if path.name.endswith("_test.go"):
            continue
        content = path.read_text(encoding="utf-8")
        for fragment in auth_env_fragments:
            if fragment in content:
                violations.append(
                    f"{path.relative_to(repo_root).as_posix()} should use idpauth.RuntimeAuthConfigFromEnv instead of {fragment}"
                )

    return tuple(violations)


def shared_app_module_makefile_contract_violations(repo_root: Path) -> tuple[str, ...]:
    browser_modules = {"appshell", "idpauth"}
    violations: list[str] = []

    for module_name in canonical_shared_app_module_names():
        targets = ("test", "js-check") if module_name in browser_modules else ("test",)
        makefile = repo_root / "apps" / "shared" / module_name / "Makefile"
        if not makefile.exists():
            violations.append(f"apps/shared/{module_name}/Makefile missing")
            continue

        content = makefile.read_text(encoding="utf-8")
        if not re.search(r"^\.PHONY:.*\bhelp\b", content, re.MULTILINE):
            violations.append(f"apps/shared/{module_name}/Makefile should declare help phony")
        if not re.search(r"^help:", content, re.MULTILINE):
            violations.append(f"apps/shared/{module_name}/Makefile should expose help target")
        for target in targets:
            if f"  {target}" not in content:
                violations.append(f"apps/shared/{module_name}/Makefile help should list {target}")

    return tuple(violations)


def go_app_shared_module_names(app_root: Path) -> tuple[str, ...]:
    go_mod = app_root / "app" / "go.mod"
    module_name = ""
    shared_modules: set[str] = set()

    for raw_line in go_mod.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("//"):
            continue

        parts = line.split()
        if len(parts) >= 2 and parts[0] == "module":
            module_name = parts[1]
            continue

        for token in parts:
            if token.startswith("platform.local/") and token != module_name:
                shared_modules.add(token)

    return tuple(sorted(shared_modules))


def workflow_provides_shared_modules(workflow_content: str) -> bool:
    return (
        '${APPS_DIR}/shared:/shared:ro' in workflow_content
        or "COPY shared /shared" in workflow_content
    )


def shared_module_workflow_validated_apps(repo_root: Path) -> tuple[str, ...]:
    return tuple(
        app_root.name
        for app_root in iter_go_app_workflow_roots(repo_root)
        if go_app_shared_module_names(app_root)
    )


def shared_module_workflow_contract_violations(repo_root: Path) -> tuple[str, ...]:
    violations: list[str] = []

    for app_name in shared_module_workflow_validated_apps(repo_root):
        workflow = repo_root / "apps" / app_name / ".gitea" / "workflows" / "build-images.yaml"
        workflow_content = workflow.read_text(encoding="utf-8")
        if '- "shared/**"' not in workflow_content:
            violations.append(f"{app_name} workflow must rebuild when shared modules change")
        if not workflow_provides_shared_modules(workflow_content):
            violations.append(f"{app_name} workflow must provide shared modules to the Go build container")

    return tuple(violations)


def workflow_uses_app_dockerfile(workflow_content: str, app_name: str) -> bool:
    app_dockerfile = f"${{APPS_DIR}}/{app_name}/app/Dockerfile"
    root_dockerfile = f"apps/{app_name}/app/Dockerfile"
    app_context = f'"${{APPS_DIR}}/{app_name}/app"'
    return (
        app_dockerfile in workflow_content
        or root_dockerfile in workflow_content
        or app_context in workflow_content
    )


def workflow_local_dockerfile_contract_violations(repo_root: Path) -> tuple[str, ...]:
    violations: list[str] = []

    for app_root in iter_go_app_workflow_roots(repo_root):
        workflow = app_root / ".gitea" / "workflows" / "build-images.yaml"
        content = workflow.read_text(encoding="utf-8")
        if "Dockerfile.runtime" in content:
            violations.append(f"{app_root.name} workflow should not generate Dockerfile.runtime")
        if (app_root / "app" / "Dockerfile").exists() and not workflow_uses_app_dockerfile(content, app_root.name):
            violations.append(f"{app_root.name} workflow should build with its app Dockerfile")

    return tuple(violations)


def app_wrapper_contract_violations(app_root: Path) -> tuple[str, ...]:
    makefile = app_root / "Makefile"
    content = makefile.read_text(encoding="utf-8")
    name = app_root.name
    violations: list[str] = []

    required_lines = {
        "USE_COMMON_HELP := 1": "use shared help",
        "include ../../mk/common.mk": "include common.mk",
        "MAKE_SUGGEST_SCRIPT := ../../scripts/suggest-make-goal.sh": "suggest close goals",
    }
    for line, description in required_lines.items():
        if line not in content:
            violations.append(f"{name} wrapper should {description}")

    if (app_root / "compose.yml").exists():
        compose_required_lines = {
            "include ../../mk/compose.mk": "include compose.mk",
            "prereqs:": "expose prereqs",
            "compose-smoke:": "expose compose-smoke",
        }
        for line, description in compose_required_lines.items():
            if line not in content:
                violations.append(f"{name} wrapper should {description}")
    elif "app-prereqs:" not in content:
        violations.append(f"{name} wrapper should expose app-prereqs")

    return tuple(violations)


def app_layout_contract_violations(app_root: Path) -> tuple[str, ...]:
    name = app_root.name
    violations: list[str] = []

    for child in (".gitea", "app", "tests", "compose.yml"):
        if not (app_root / child).exists():
            violations.append(f"{name} missing {child}")

    if (app_root / "app-go").exists():
        violations.append(f"{name} still exposes app-go")
    if not (app_root / "app" / "go.mod").exists():
        violations.append(f"{name} app is not Go")
    if not (app_root / "app" / "Dockerfile").exists():
        violations.append(f"{name} missing app Dockerfile")

    if name == "idp-core":
        for retired in ("pyproject.toml", "uv.lock"):
            if (app_root / retired).exists():
                violations.append(f"idp-core still has {retired}")
        for retired in ("__init__.py", "main.py", "models.py"):
            if (app_root / "app" / retired).exists():
                violations.append(f"idp-core app still has Python {retired}")

    return tuple(violations)


def shared_keycloak_fixture_contract_violations(repo_root: Path) -> tuple[str, ...]:
    required_shared_files = (
        "realm-export.json",
        "start-with-templated-realm.sh",
    )
    required_compose_mounts = (
        "../shared/keycloak/realm-export.json",
        "../shared/keycloak/start-with-templated-realm.sh",
    )
    shared_dir = repo_root / "apps" / "shared" / "keycloak"
    sentiment_compose = (repo_root / "apps" / "sentiment" / "compose.yml").read_text(encoding="utf-8")
    violations: list[str] = []

    for file_name in required_shared_files:
        if not (shared_dir / file_name).exists():
            violations.append(f"apps/shared/keycloak/{file_name} missing")
    for mount in required_compose_mounts:
        if mount not in sentiment_compose:
            violations.append(f"apps/sentiment/compose.yml should mount {mount}")

    return tuple(violations)


def image_catalog_contract_violations(repo_root: Path) -> tuple[str, ...]:
    catalog_path = repo_root / "kubernetes" / "workflow" / "image-catalog.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    images = {image["id"]: image for image in catalog["workload_images"] + catalog["platform_images"]}
    violations: list[str] = []

    for expected in image_catalog_expectations():
        image = images.get(expected.image_id)
        if image is None:
            violations.append(f"image catalog missing {expected.image_id}")
            continue

        build = image.get("build", {})
        context = build.get("context", "")
        prebuild = build.get("prebuild", "")
        if context != expected.context:
            violations.append(f"{expected.image_id} context should be {expected.context}, got {context}")
        if expected.dockerfile is not None and build.get("dockerfile") != expected.dockerfile:
            violations.append(
                f"{expected.image_id} dockerfile should be {expected.dockerfile}, got {build.get('dockerfile')}"
            )
        if f"apps/{expected.prebuild_app}/app build-linux" not in prebuild:
            violations.append(f"{expected.image_id} prebuild should build apps/{expected.prebuild_app}/app")
        if "app-go" in json.dumps(image):
            violations.append(f"{expected.image_id} still references app-go")

    return tuple(violations)


def _app_image_ids_by_root() -> dict[str, tuple[str, ...]]:
    return {
        "apps/apim-simulator/app": ("subnetcalc-apim-simulator",),
        "apps/chatgpt-sim/app": ("chatgpt-sim",),
        "apps/idp-core/app": ("idp-core",),
        "apps/langfuse-demos/app": ("langfuse-demos",),
        "apps/platform-mcp/app": ("platform-mcp",),
        "apps/sentiment/app": ("sentiment-api", "sentiment-auth-ui"),
        "apps/subnetcalc/app": ("subnetcalc-api", "subnetcalc-frontend"),
    }


def _app_root_by_image_id() -> dict[str, str]:
    return {
        image_id: app_root
        for app_root, image_ids in _app_image_ids_by_root().items()
        for image_id in image_ids
    }


def shared_module_source_paths_for_app(app_root: Path) -> tuple[str, ...]:
    modules = set(go_app_shared_module_names(app_root.parent))
    sources = [
        f"apps/shared/{module.removeprefix('platform.local/')}"
        for module in sorted(modules)
    ]
    if {"platform.local/appshell", "platform.local/idpauth"} & modules:
        sources.append("apps/shared/web")
    return tuple(sources)


def _missing_shared_fingerprint_sources_by_image(
    repo_root: Path,
    images: dict[str, dict[str, Any]],
    image_ids: tuple[str, ...],
) -> tuple[str, ...]:
    app_roots = _app_root_by_image_id()
    violations: list[str] = []

    for image_id in image_ids:
        app_root_name = app_roots.get(image_id)
        if app_root_name is None:
            violations.append(f"{image_id} missing app root mapping")
            continue
        image = images.get(image_id)
        if image is None:
            violations.append(f"image catalog missing {image_id}")
            continue
        sources = set(image.get("fingerprint_sources", []))
        expected_sources = shared_module_source_paths_for_app(repo_root / app_root_name)
        for expected_source in expected_sources:
            if expected_source not in sources:
                violations.append(f"{image_id} fingerprint missing {expected_source}")

    return tuple(violations)


def image_catalog_shared_source_contract_violations(repo_root: Path) -> tuple[str, ...]:
    catalog_path = repo_root / "kubernetes" / "workflow" / "image-catalog.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    images = {
        image["id"]: image
        for image in catalog["workload_images"] + catalog["platform_images"]
    }
    return _missing_shared_fingerprint_sources_by_image(
        repo_root,
        images,
        tuple(sorted(_app_root_by_image_id())),
    )


def local_go_workload_source_fingerprint_contract_violations(repo_root: Path) -> tuple[str, ...]:
    catalog_path = repo_root / "kubernetes" / "workflow" / "image-catalog.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    workloads = {image["id"]: image for image in catalog["workload_images"]}
    violations: list[str] = []

    expected_app_sources = {
        "sentiment-api": (
            "apps/sentiment/app/go.sum",
            "apps/sentiment/app/internal",
            "apps/sentiment/app/internal/app/web",
            "apps/sentiment/app/cmd",
        ),
        "sentiment-auth-ui": (
            "apps/sentiment/app/go.sum",
            "apps/sentiment/app/internal",
            "apps/sentiment/app/internal/app/web",
            "apps/sentiment/app/cmd",
        ),
        "subnetcalc-api": (
            "apps/subnetcalc/app/go.sum",
            "apps/subnetcalc/app/internal",
            "apps/subnetcalc/app/cmd",
        ),
        "subnetcalc-frontend": (
            "apps/subnetcalc/app/go.sum",
            "apps/subnetcalc/app/internal",
            "apps/subnetcalc/app/internal/app/web",
        ),
        "subnetcalc-apim-simulator": (
            "apps/apim-simulator/app/internal/app/web",
        ),
    }

    for image_id, expected in expected_app_sources.items():
        image = workloads.get(image_id)
        if image is None:
            violations.append(f"image catalog missing {image_id}")
            continue
        sources = set(image.get("fingerprint_sources", []))
        for source in expected:
            if source not in sources:
                violations.append(f"{image_id} fingerprint missing {source}")
    violations.extend(
        _missing_shared_fingerprint_sources_by_image(
            repo_root,
            workloads,
            tuple(sorted(expected_app_sources)),
        )
    )

    return tuple(violations)


def local_platform_image_sync_contract_violations(repo_root: Path) -> tuple[str, ...]:
    paths = {
        "build script": repo_root / "kubernetes" / "kind" / "scripts" / "build-local-platform-images.sh",
        "image catalog": repo_root / "kubernetes" / "workflow" / "image-catalog.json",
        "sync script": repo_root / "terraform" / "kubernetes" / "scripts" / "sync-gitea.sh",
        "policies sync script": repo_root / "terraform" / "kubernetes" / "scripts" / "sync-gitea-policies.sh",
        "gitops terraform": repo_root / "terraform" / "kubernetes" / "gitops.tf",
        "variables terraform": repo_root / "terraform" / "kubernetes" / "variables.tf",
        "locals terraform": repo_root / "terraform" / "kubernetes" / "locals.tf",
        "kind Makefile": repo_root / "kubernetes" / "kind" / "Makefile",
    }
    violations: list[str] = []

    for label, path in paths.items():
        if not path.exists():
            violations.append(f"{label} missing at {path.relative_to(repo_root).as_posix()}")
    if violations:
        return tuple(violations)

    contents = {
        label: path.read_text(encoding="utf-8")
        for label, path in paths.items()
    }
    platform_images = ("idp-core", "backstage", "platform-mcp")

    for image_id in platform_images:
        if f'"id": "{image_id}"' not in contents["image catalog"]:
            violations.append(f"image catalog missing {image_id}")
        if f'lookup(var.external_platform_image_refs, "{image_id}", "")' not in contents["locals terraform"]:
            violations.append(f"locals terraform missing external platform ref for {image_id}")
        if image_id not in contents["variables terraform"]:
            violations.append(f"variables terraform missing {image_id}")

    required_fragments = {
        "sync script": (
            "EXTERNAL_PLATFORM_IMAGE_BACKSTAGE",
            "EXTERNAL_PLATFORM_IMAGE_IDP_CORE",
            "EXTERNAL_PLATFORM_IMAGE_PLATFORM_MCP",
            "export_resolved_bool_target_or_stage PREFER_EXTERNAL_WORKLOAD_IMAGES prefer_external_workload_images false",
            "resolve_external_workload_image()",
        ),
        "policies sync script": (
            "EXTERNAL_PLATFORM_IMAGE_BACKSTAGE",
            "EXTERNAL_PLATFORM_IMAGE_IDP_CORE",
            "EXTERNAL_PLATFORM_IMAGE_PLATFORM_MCP",
            "ensure_grafana_dashboard_provider_paths",
            "/^    path:[[:space:]]*/",
            "/var/lib/grafana/dashboards/default",
            "/var/lib/grafana/dashboards/kubernetes",
            "/var/lib/grafana/dashboards/cilium",
            "/var/lib/grafana/dashboards/argocd",
            "render_external_image_inputs",
            'replace_image_ref "${manifest_file}" "${image_name}" "${image_ref}"',
            'replace_image_ref "${workload_file}" "${image_name}" "${image_ref}"',
            'DOCKER_CONFIG="${tmp_registry_dir}"',
        ),
        "gitops terraform": ("GITOPS_RENDER_CONTRACT_FILE",),
        "locals terraform": (
            "external_platform_backstage",
            "external_platform_idp_core",
            "external_platform_mcp",
        ),
        "kind Makefile": (
            'GITEA_SYNC_TARGET_TFVARS_FILE="$${GITEA_SYNC_TARGET_TFVARS_FILE:-$(KIND_OPERATOR_OVERRIDES_FILE)}"',
        ),
    }
    for label, fragments in required_fragments.items():
        content = contents[label]
        for fragment in fragments:
            if fragment not in content:
                violations.append(f"{label} missing {fragment}")

    forbidden_fragments = {
        "policies sync script": ("EXTERNAL_IMAGE_PLATFORM_MCP",),
        "gitops terraform": (
            'EXTERNAL_PLATFORM_IMAGE_BACKSTAGE             = lookup(var.external_platform_image_refs, "backstage", "")',
            'EXTERNAL_PLATFORM_IMAGE_IDP_CORE              = lookup(var.external_platform_image_refs, "idp-core", "")',
            'EXTERNAL_IMAGE_PLATFORM_MCP                   = lookup(var.external_workload_image_refs, "platform-mcp", "")',
        ),
    }
    for label, fragments in forbidden_fragments.items():
        content = contents[label]
        for fragment in fragments:
            if fragment in content:
                violations.append(f"{label} should not contain {fragment}")

    return tuple(violations)


def local_platform_source_fingerprint_cache_contract_violations(repo_root: Path) -> tuple[str, ...]:
    paths = {
        "build script": repo_root / "kubernetes" / "kind" / "scripts" / "build-local-platform-images.sh",
        "render script": repo_root / "kubernetes" / "kind" / "scripts" / "render-operator-overrides.sh",
        "image catalog": repo_root / "kubernetes" / "workflow" / "image-catalog.json",
        "catalog lib": repo_root / "kubernetes" / "workflow" / "image-catalog-lib.sh",
        "image build lib": repo_root / "kubernetes" / "workflow" / "image-build-lib.sh",
    }
    violations: list[str] = []

    for label, path in paths.items():
        if not path.exists():
            violations.append(f"{label} missing at {path.relative_to(repo_root).as_posix()}")
    if violations:
        return tuple(violations)

    contents = {
        label: path.read_text(encoding="utf-8")
        for label, path in paths.items()
    }
    required_fragments = {
        "catalog lib": (
            "source_fingerprint_tag()",
            "image_catalog_external_ids()",
        ),
        "build script": (
            "idp_core_source_tag=",
            "backstage_source_tag=",
            "platform_mcp_source_tag=",
            'image_build_catalog_build_and_push platform idp-core idp-core "${idp_core_source_tag}"',
            'image_build_catalog_build_and_push platform backstage backstage "${backstage_source_tag}"',
            'image_build_catalog_build_and_push platform platform-mcp platform-mcp "${platform_mcp_source_tag}"',
        ),
        "image build lib": (
            'image_build_tag_exists "${CACHE_PUSH_HOST}" "${repo}" "${fingerprint_tag}"',
        ),
        "render script": (
            "platform_mcp_image_tag=",
            "idp_core_image_tag=",
            "backstage_image_tag=",
            "write_external_platform_images()",
            "prefer_external_platform_images = true",
            "external_platform_image_refs = {",
            "image_catalog_source_tag platform platform-mcp",
            "image_catalog_source_tag platform backstage",
            "image_catalog_source_tag platform idp-core",
            "image_catalog_hcl_refs platform",
            "image_catalog_hcl_refs workload",
            "write_external_workload_images()",
            "image_catalog_external_ids workload",
            "image_catalog_source_tag workload",
        ),
        "image catalog": (
            "apps/platform-mcp/app/internal",
            "apps/idp-core/app/go.mod",
            "apps/idp-core/app/internal",
            "make -C apps/idp-core/app build-linux",
            "apps/backstage/packages",
            "apps/apim-simulator/catalog-info.yaml",
        ),
    }

    for label, fragments in required_fragments.items():
        content = contents[label]
        for fragment in fragments:
            if fragment not in content:
                violations.append(f"{label} missing {fragment}")

    return tuple(violations)


def image_catalog_version_check_policy_count(repo_root: Path) -> int:
    catalog = json.loads((repo_root / "kubernetes" / "workflow" / "image-catalog.json").read_text(encoding="utf-8"))
    return sum(len(catalog[category]) for category in ("platform_images", "workload_images"))


def image_catalog_version_check_policy_contract_violations(repo_root: Path) -> tuple[str, ...]:
    catalog = json.loads((repo_root / "kubernetes" / "workflow" / "image-catalog.json").read_text(encoding="utf-8"))
    allowed_modes = {
        "local",
        "external",
        "pinned-digest",
        "checked-elsewhere",
        "non-comparable",
    }
    violations: list[str] = []

    for category in ("platform_images", "workload_images"):
        for image in catalog[category]:
            image_id = image["id"]
            policy = image.get("version_check")
            if not isinstance(policy, dict):
                violations.append(f"{category}.{image_id} missing version_check")
                continue
            mode = policy.get("mode")
            reason = str(policy.get("reason", "")).strip()
            if mode not in allowed_modes:
                violations.append(f"{category}.{image_id} has unsupported version_check mode {mode!r}")
            if not reason:
                violations.append(f"{category}.{image_id} version_check must explain the policy")
            if image.get("default_tag") == "latest":
                violations.append(f"{category}.{image_id} must pin its local registry default tag")

    return tuple(violations)


def grafana_plugin_catalog_build_input_contract_violations(repo_root: Path) -> tuple[str, ...]:
    catalog_path = repo_root / "kubernetes" / "workflow" / "image-catalog.json"
    build_script_path = repo_root / "kubernetes" / "kind" / "scripts" / "build-local-platform-images.sh"
    violations: list[str] = []

    for path in (catalog_path, build_script_path):
        if not path.exists():
            violations.append(f"{path.relative_to(repo_root).as_posix()} missing")
    if violations:
        return tuple(violations)

    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    build_script = build_script_path.read_text(encoding="utf-8")
    images = {image["id"]: image for image in catalog["platform_images"]}
    grafana = images.get("grafana-victorialogs")
    if grafana is None:
        return ("image catalog missing grafana-victorialogs",)

    build = grafana.get("build", {})
    expected_build_fields: dict[str, Any] = {
        "grafana_base_image": {
            "source": "docker.io/grafana/grafana",
            "tag": "12.3.1",
            "cache_repo": "platform-cache/grafana-grafana",
        },
        "plugin_fetch_image": {
            "source": "docker.io/library/alpine",
            "tag": "3.22",
            "cache_repo": "platform-cache/library-alpine",
        },
        "version_tag_strategy": "grafana-tag-plus-plugin-version",
    }
    for field_name, expected in expected_build_fields.items():
        actual = build.get(field_name)
        if actual != expected:
            violations.append(f"grafana-victorialogs build.{field_name} should be {expected!r}, got {actual!r}")

    plugin_archive = build.get("plugin_archive", {})
    plugin_archive_expectations = {
        "terraform_version_variable": "grafana_victoria_logs_plugin_version",
        "terraform_sha256_variable": "grafana_victoria_logs_plugin_sha256",
        "cache_dir": ".run/kind/plugin-cache",
    }
    for field_name, expected in plugin_archive_expectations.items():
        actual = plugin_archive.get(field_name)
        if actual != expected:
            violations.append(f"grafana-victorialogs plugin_archive.{field_name} should be {expected!r}, got {actual!r}")
    url_template = str(plugin_archive.get("url_template", ""))
    if url_template.count("{version}") != 2:
        violations.append("grafana-victorialogs plugin_archive.url_template should include {version} twice")

    fingerprint_sources = set(grafana.get("fingerprint_sources", []))
    for source in (
        "kubernetes/kind/images/grafana-victorialogs/Dockerfile",
        "kubernetes/workflow/image-catalog.json",
    ):
        if source not in fingerprint_sources:
            violations.append(f"grafana-victorialogs fingerprint missing {source}")
    app_sources = sorted(source for source in fingerprint_sources if source.startswith("apps/"))
    if app_sources:
        violations.append(f"grafana-victorialogs fingerprint should not include app sources: {app_sources}")

    removed_defaults = (
        'GRAFANA_IMAGE_TAG="${GRAFANA_IMAGE_TAG:-12.3.1}"',
        'PLUGIN_FETCH_IMAGE_SOURCE="${PLUGIN_FETCH_IMAGE_SOURCE:-docker.io/library/alpine:3.22}"',
        'GRAFANA_BASE_IMAGE_SOURCE="${GRAFANA_BASE_IMAGE_SOURCE:-docker.io/grafana/grafana:${GRAFANA_IMAGE_TAG}}"',
    )
    for fragment in removed_defaults:
        if fragment in build_script:
            violations.append(f"platform image builder should not hard-code {fragment}")
    for fragment in (
        "image_catalog_build_json platform grafana-victorialogs",
        "catalog_grafana_build_value",
    ):
        if fragment not in build_script:
            violations.append(f"platform image builder missing {fragment}")

    return tuple(violations)


def image_catalog_target_ref_contract_violations(repo_root: Path) -> tuple[str, ...]:
    validator = repo_root / "kubernetes" / "workflow" / "validate-image-catalog-target-refs.py"
    catalog = repo_root / "kubernetes" / "workflow" / "image-catalog.json"
    expectations = {
        "lima": repo_root / "kubernetes" / "lima" / "targets" / "lima.tfvars",
        "slicer": repo_root / "kubernetes" / "slicer" / "targets" / "slicer.tfvars",
    }
    violations: list[str] = []

    for path in (validator, catalog, *expectations.values()):
        if not path.exists():
            violations.append(f"{path.relative_to(repo_root).as_posix()} missing")
    if violations:
        return tuple(violations)

    for target, tfvars in expectations.items():
        result = subprocess.run(
            [
                sys.executable,
                str(validator),
                "--catalog",
                str(catalog),
                "--target",
                target,
                "--tfvars",
                str(tfvars),
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            detail = (result.stderr or result.stdout).strip()
            violations.append(f"{target} image refs do not match image catalog: {detail}")

    return tuple(violations)


def image_catalog_target_tfvars_projection_contract_violations(repo_root: Path) -> tuple[str, ...]:
    validator = repo_root / "kubernetes" / "workflow" / "validate-image-catalog-target-refs.py"
    catalog = repo_root / "kubernetes" / "workflow" / "image-catalog.json"
    expected_hosts = {
        "lima": "host.lima.internal:5002",
        "slicer": "192.168.64.1:5002",
    }
    required_image_tags = (
        ("platform-mcp", "platform"),
        ("langfuse-demos", "platform"),
        ("sentiment-api", "platform"),
    )
    violations: list[str] = []

    for path in (validator, catalog):
        if not path.exists():
            violations.append(f"{path.relative_to(repo_root).as_posix()} missing")
    if violations:
        return tuple(violations)

    script_text = validator.read_text(encoding="utf-8")
    if "--print-expected" not in script_text:
        violations.append("validate-image-catalog-target-refs.py should expose --print-expected")

    for target, host in expected_hosts.items():
        result = subprocess.run(
            [
                sys.executable,
                str(validator),
                "--catalog",
                str(catalog),
                "--target",
                target,
                "--print-expected",
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            detail = (result.stderr or result.stdout).strip()
            violations.append(f"{target} target tfvars projection failed: {detail}")
            continue

        rendered = result.stdout
        for fragment in ("external_platform_image_refs = {", "external_workload_image_refs = {"):
            if fragment not in rendered:
                violations.append(f"{target} projection missing {fragment}")
        for image_id, repo_name in required_image_tags:
            expected_ref = f"{host}/{repo_name}/{image_id}:0.1.0"
            if f'"{image_id}"' not in rendered or expected_ref not in rendered:
                violations.append(f"{target} projection missing {image_id} ref {expected_ref}")

    return tuple(violations)


def local_platform_cache_hit_contract_violations(repo_root: Path) -> tuple[str, ...]:
    build_script_path = repo_root / "kubernetes" / "kind" / "scripts" / "build-local-platform-images.sh"
    image_build_lib_path = repo_root / "kubernetes" / "workflow" / "image-build-lib.sh"
    violations: list[str] = []

    for path in (build_script_path, image_build_lib_path):
        if not path.exists():
            violations.append(f"{path.relative_to(repo_root).as_posix()} missing")
    if violations:
        return tuple(violations)

    build_script = build_script_path.read_text(encoding="utf-8")
    image_build_lib = image_build_lib_path.read_text(encoding="utf-8")

    try:
        skip_start = image_build_lib.index("image_build_cache_hit()")
        skip_end = image_build_lib.index("return 0", skip_start)
    except ValueError as exc:
        return (f"image-build-lib cache-hit implementation missing expected marker: {exc}",)

    skip_condition = image_build_lib[skip_start:skip_end]
    required_skip_fragments = (
        "${fingerprint_tag}",
        'IMAGE_BUILD_REQUIRE_COMMIT_TAG:-0}" = "1"',
    )
    for fragment in required_skip_fragments:
        if fragment not in skip_condition:
            violations.append(f"image_build_cache_hit should include {fragment}")

    if "IMAGE_BUILD_REQUIRE_COMMIT_TAG=1" in build_script:
        violations.append("platform image build should not require commit tags for cache hits")
    if 'image_build_push_optional_tag "${build_ref}" "${commit_ref}"' not in image_build_lib:
        violations.append("image-build-lib should keep commit refs as optional pushed tags")

    return tuple(violations)


def image_builder_adapter_contract_violations(repo_root: Path) -> tuple[str, ...]:
    shared_path = repo_root / "kubernetes" / "workflow" / "image-build-lib.sh"
    scripts = (
        repo_root / "kubernetes" / "kind" / "scripts" / "build-local-platform-images.sh",
        repo_root / "kubernetes" / "kind" / "scripts" / "build-local-workload-images.sh",
        repo_root / "kubernetes" / "scripts" / "build-local-workload-images.sh",
    )
    variant_wrappers = (
        repo_root / "kubernetes" / "lima" / "scripts" / "build-local-workload-images.sh",
        repo_root / "kubernetes" / "slicer" / "scripts" / "build-local-workload-images.sh",
    )
    violations: list[str] = []

    for path in (shared_path, *scripts, *variant_wrappers):
        if not path.exists():
            violations.append(f"{path.relative_to(repo_root).as_posix()} missing")
    if violations:
        return tuple(violations)

    shared = shared_path.read_text(encoding="utf-8")
    required_shared_fragments = (
        "image_build_prepare_args()",
        "image_build_cache_hit()",
        "image_build_build_and_push_cached()",
        "image_build_catalog_build_loop()",
        'fingerprint_tag="$(image_catalog_source_tag "${category}" "${image_id}")"',
        'image_build_catalog_build_and_push "${category}" "${image_id}" "${image_name}"',
        'image_build_tag_exists "${CACHE_PUSH_HOST}" "${repo}" "${fingerprint_tag}"',
    )
    for fragment in required_shared_fragments:
        if fragment not in shared:
            violations.append(f"image-build-lib missing {fragment}")

    for script in scripts:
        relative_path = script.relative_to(repo_root).as_posix()
        content = script.read_text(encoding="utf-8")
        if "kubernetes/workflow/image-build-lib.sh" not in content:
            violations.append(f"{relative_path} should source image-build-lib.sh")
        if "image_build_catalog_build_loop" not in content and "image_build_catalog_build_and_push" not in content:
            violations.append(f"{relative_path} should call the shared image builder adapter")

    for script in variant_wrappers:
        relative_path = script.relative_to(repo_root).as_posix()
        content = script.read_text(encoding="utf-8")
        if "kubernetes/scripts/build-local-workload-images.sh" not in content:
            violations.append(f"{relative_path} should delegate to shared workload image builder")

    duplicated_functions = (
        "build_and_push()",
        "catalog_build_context()",
        "catalog_dockerfile_path()",
        "catalog_prepare_build_args()",
        "catalog_build_and_push()",
    )
    for script in (*scripts[1:], *variant_wrappers):
        relative_path = script.relative_to(repo_root).as_posix()
        content = script.read_text(encoding="utf-8")
        for function_name in duplicated_functions:
            if function_name in content:
                violations.append(f"{relative_path} should not duplicate {function_name}")

    return tuple(violations)


def image_catalog_context_adapter_contract_violations(repo_root: Path) -> tuple[str, ...]:
    context_lib_path = repo_root / "kubernetes" / "workflow" / "image-catalog-context-lib.sh"
    image_build_lib_path = repo_root / "kubernetes" / "workflow" / "image-build-lib.sh"
    platform_builder_path = repo_root / "kubernetes" / "kind" / "scripts" / "build-local-platform-images.sh"
    violations: list[str] = []

    for path in (context_lib_path, image_build_lib_path, platform_builder_path):
        if not path.exists():
            violations.append(f"{path.relative_to(repo_root).as_posix()} missing")
    if violations:
        return tuple(violations)

    context_lib = context_lib_path.read_text(encoding="utf-8")
    image_build_lib = image_build_lib_path.read_text(encoding="utf-8")
    platform_builder = platform_builder_path.read_text(encoding="utf-8")

    required_context_fragments = (
        "image_catalog_prepare_build_context_adapter()",
        "image_catalog_prepare_backstage_build_context()",
        "copy_backstage_app_catalog()",
        "generated-backstage",
        "apps/apim-simulator/catalog-info.yaml",
    )
    for fragment in required_context_fragments:
        if fragment not in context_lib:
            violations.append(f"image-catalog-context-lib missing {fragment}")

    duplicated_fragments = (
        "copy_backstage_app_catalog()",
        "copy_backstage_apim_simulator_catalog()",
        'cp -R "${REPO_ROOT}/apps/backstage/."',
        'copy_backstage_app_catalog "${context_dir}" "subnetcalc"',
    )
    for fragment in duplicated_fragments:
        if fragment in platform_builder:
            violations.append(f"platform image builder should not duplicate {fragment}")

    if "kubernetes/workflow/image-catalog-context-lib.sh" not in platform_builder:
        violations.append("platform image builder should source image-catalog-context-lib.sh")
    if "image_catalog_prepare_build_context_adapter" not in image_build_lib:
        violations.append("image-build-lib should call image_catalog_prepare_build_context_adapter")

    return tuple(violations)


def local_platform_image_build_spec_contract_violations(repo_root: Path) -> tuple[str, ...]:
    catalog_path = repo_root / "kubernetes" / "workflow" / "image-catalog.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    build_script = (
        repo_root / "kubernetes" / "kind" / "scripts" / "build-local-platform-images.sh"
    ).read_text(encoding="utf-8")
    image_build_lib = (
        repo_root / "kubernetes" / "workflow" / "image-build-lib.sh"
    ).read_text(encoding="utf-8")
    images = {
        image["id"]: image
        for category in ("platform_images", "workload_images")
        for image in catalog[category]
    }
    violations: list[str] = []

    expected_builds = {
        "idp-core": {
            "context": ".",
            "dockerfile": "apps/idp-core/app/Dockerfile",
            "tag": "default",
            "prebuild": "make -C apps/idp-core/app build-linux",
        },
        "platform-mcp": {
            "context": "apps/platform-mcp/app",
            "dockerfile": "Dockerfile",
            "tag": "default",
            "prebuild": "make -C apps/platform-mcp/app build-linux",
        },
        "chatgpt-sim": {
            "context": "apps/chatgpt-sim/app",
            "dockerfile": "Dockerfile",
            "tag": "default",
            "prebuild": "make -C apps/chatgpt-sim/app build-linux",
        },
        "backstage": {
            "context": "generated-backstage",
            "dockerfile": "Dockerfile",
            "tag": "default",
        },
        "keycloak": {
            "context": "apps/keycloak",
            "dockerfile": "Dockerfile",
            "tag": "default",
        },
        "langfuse-demos": {
            "context": "apps/langfuse-demos/app",
            "dockerfile": "Dockerfile",
            "tag": "default",
            "prebuild": "make -C apps/langfuse-demos/app build-linux",
        },
    }

    for image_id, expected_build in expected_builds.items():
        image = images.get(image_id)
        if image is None:
            violations.append(f"image catalog missing {image_id}")
            continue
        actual_build = image.get("build")
        if actual_build != expected_build:
            violations.append(f"{image_id} catalog build spec drifted: {actual_build!r}")

    required_script_fragments = (
        (build_script, "image_build_catalog_build_and_push", "build script should use catalog build adapter"),
        (image_build_lib, "image_catalog_build_field", "image build lib should read catalog build fields"),
        (image_build_lib, "image_catalog_default_tag", "image build lib should own default tags"),
    )
    for content, fragment, message in required_script_fragments:
        if fragment not in content:
            violations.append(message)

    forbidden_build_script_fragments = (
        '"${REPO_ROOT}/apps/idp-core/app/Dockerfile"',
        '"${REPO_ROOT}/apps/platform-mcp/Dockerfile"',
        '"${REPO_ROOT}/apps/keycloak/Dockerfile"',
    )
    for fragment in forbidden_build_script_fragments:
        if fragment in build_script:
            violations.append(f"build script should not hard-code {fragment}")

    required_app_sources = {
        "langfuse-demos": (
            "apps/langfuse-demos/app/internal",
            "apps/langfuse-demos/app/internal/app/web",
        ),
        "chatgpt-sim": (
            "apps/chatgpt-sim/app/internal",
            "apps/chatgpt-sim/app/internal/app/web",
        ),
    }
    for image_id, expected_sources in required_app_sources.items():
        image = images.get(image_id)
        if image is None:
            continue
        sources = set(image.get("fingerprint_sources", []))
        for source in expected_sources:
            if source not in sources:
                violations.append(f"{image_id} fingerprint missing {source}")
    violations.extend(
        _missing_shared_fingerprint_sources_by_image(
            repo_root,
            images,
            ("chatgpt-sim", "idp-core", "langfuse-demos", "platform-mcp"),
        )
    )

    return tuple(violations)


def local_workload_image_build_spec_contract_violations(repo_root: Path) -> tuple[str, ...]:
    catalog_path = repo_root / "kubernetes" / "workflow" / "image-catalog.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    workloads = {image["id"]: image for image in catalog["workload_images"]}
    image_build_lib = (
        repo_root / "kubernetes" / "workflow" / "image-build-lib.sh"
    ).read_text(encoding="utf-8")
    violations: list[str] = []

    expected_builds = {
        "sentiment-api": {
            "context": "apps/sentiment/app",
            "dockerfile": "Dockerfile",
            "tag": "default",
            "prebuild": "make -C apps/sentiment/app build-linux",
        },
        "sentiment-auth-ui": {
            "context": "apps/sentiment/app",
            "dockerfile": "Dockerfile",
            "tag": "default",
            "prebuild": "make -C apps/sentiment/app build-linux",
        },
        "subnetcalc-api": {
            "context": "apps/subnetcalc/app",
            "dockerfile": "Dockerfile",
            "tag": "default",
            "prebuild": "make -C apps/subnetcalc/app build-linux",
        },
        "subnetcalc-apim-simulator": {
            "context": "apps/apim-simulator",
            "dockerfile": "app/Dockerfile",
            "tag": "default",
            "prebuild": "make -C apps/apim-simulator/app build-linux",
        },
        "subnetcalc-frontend": {
            "context": "apps/subnetcalc/app",
            "dockerfile": "Dockerfile",
            "tag": "default",
            "prebuild": "make -C apps/subnetcalc/app build-linux",
        },
    }

    for image_id, expected_build in expected_builds.items():
        image = workloads.get(image_id)
        if image is None:
            violations.append(f"image catalog missing {image_id}")
            continue
        actual_build = image.get("build")
        if actual_build != expected_build:
            violations.append(f"{image_id} catalog build spec drifted: {actual_build!r}")

    script_paths = (
        repo_root / "kubernetes" / "kind" / "scripts" / "build-local-workload-images.sh",
        repo_root / "kubernetes" / "scripts" / "build-local-workload-images.sh",
    )
    variant_wrapper_paths = (
        repo_root / "kubernetes" / "lima" / "scripts" / "build-local-workload-images.sh",
        repo_root / "kubernetes" / "slicer" / "scripts" / "build-local-workload-images.sh",
    )
    hard_coded_paths = (
        "apps/sentiment/app/Dockerfile",
        "apps/apim-simulator/app/Dockerfile",
    )

    for script in script_paths:
        content = script.read_text(encoding="utf-8")
        relative_path = script.relative_to(repo_root).as_posix()
        if "image_build_catalog_build_loop workload workload" not in content:
            violations.append(f"{relative_path} should use the workload catalog build loop")
        if "kubernetes/workflow/image-build-lib.sh" not in content:
            violations.append(f"{relative_path} should source image-build-lib.sh")
        for hard_coded_path in hard_coded_paths:
            if hard_coded_path in content:
                violations.append(f"{relative_path} should not hard-code {hard_coded_path}")

    for script in variant_wrapper_paths:
        content = script.read_text(encoding="utf-8")
        relative_path = script.relative_to(repo_root).as_posix()
        if "kubernetes/scripts/build-local-workload-images.sh" not in content:
            violations.append(f"{relative_path} should delegate to the shared workload build script")
        for hard_coded_path in hard_coded_paths:
            if hard_coded_path in content:
                violations.append(f"{relative_path} should not hard-code {hard_coded_path}")

    for fragment in (
        "image_catalog_build_specs",
        "image_catalog_build_arg_specs",
        "image_catalog_default_tag",
        "image_build_catalog_build_and_push",
        "image_build_run_prebuild",
    ):
        if fragment not in image_build_lib:
            violations.append(f"image-build-lib.sh missing {fragment}")

    loop_body = image_build_lib[image_build_lib.index("image_build_catalog_build_loop()"):]
    if '"${TAG:-latest}"' in loop_body:
        violations.append("image_build_catalog_build_loop should use catalog default tags")

    violations.extend(
        _missing_shared_fingerprint_sources_by_image(
            repo_root,
            workloads,
            tuple(sorted(expected_builds)),
        )
    )

    return tuple(violations)


def _tmpfs_missing_entries(service: dict[str, Any], required_entries: list[str]) -> list[str]:
    tmpfs_entries = service.get("tmpfs", [])
    return [entry for entry in required_entries if entry not in tmpfs_entries]


def _compose_service_hardening_violations(
    relative_path: str,
    service_name: str,
    service: dict[str, Any],
    expected: dict[str, Any],
) -> tuple[str, ...]:
    violations: list[str] = []
    for key in ("user", "read_only", "cap_drop", "security_opt"):
        if key in expected and service.get(key) != expected[key]:
            violations.append(f"{relative_path}:{service_name} {key} should be {expected[key]}, got {service.get(key)}")

    for missing in _tmpfs_missing_entries(service, expected.get("tmpfs", [])):
        violations.append(f"{relative_path}:{service_name} missing tmpfs {missing}")

    if "build_args" in expected:
        build = service.get("build", {})
        if build.get("args") != expected["build_args"]:
            violations.append(
                f"{relative_path}:{service_name} build args should be {expected['build_args']}, got {build.get('args')}"
            )

    return tuple(violations)


def _nginx_tmpfs_entries() -> list[str]:
    return [
        "/tmp:rw,noexec,nosuid,nodev,uid=65532,gid=65532,mode=1777",
        "/var/cache/nginx:rw,noexec,nosuid,nodev,uid=65532,gid=65532",
        "/var/run/nginx:rw,noexec,nosuid,nodev,uid=65532,gid=65532",
    ]


def _go_app_compose_hardening_expectation() -> dict[str, Any]:
    return {
        "read_only": True,
        "cap_drop": ["ALL"],
        "security_opt": ["no-new-privileges:true"],
        "tmpfs": ["/tmp:rw,noexec,nosuid,nodev,mode=1777"],
    }


def _explicit_compose_hardening_expectations() -> dict[str, dict[str, dict[str, Any]]]:
    go_app = _go_app_compose_hardening_expectation()
    nginx = {
        "user": "65532:65532",
        "read_only": True,
        "cap_drop": ["ALL"],
        "security_opt": ["no-new-privileges:true"],
        "tmpfs": _nginx_tmpfs_entries(),
    }
    return {
        "docker/compose/compose.yml": {
            "edge": nginx,
            "subnetcalc-api-dev": go_app,
            "subnetcalc-api-uat": go_app,
            "subnetcalc-frontend-dev": go_app,
            "subnetcalc-frontend-uat": go_app,
            "subnetcalc-router-dev": nginx,
            "subnetcalc-router-uat": nginx,
        },
    }


def compose_hardening_contract_violations(repo_root: Path) -> tuple[str, ...]:
    violations: list[str] = []
    go_app_expectation = _go_app_compose_hardening_expectation()

    for compose_path, service_name, service, _dockerfile in iter_go_app_compose_services(repo_root):
        relative_path = compose_path.relative_to(repo_root).as_posix()
        violations.extend(
            _compose_service_hardening_violations(relative_path, service_name, service, go_app_expectation)
        )

    for relative_path, services in _explicit_compose_hardening_expectations().items():
        compose = load_yaml(repo_root / relative_path)
        for service_name, expected in services.items():
            service = compose["services"][service_name]
            violations.extend(_compose_service_hardening_violations(relative_path, service_name, service, expected))

    return tuple(violations)


def compose_hardening_validated_services(repo_root: Path) -> tuple[str, ...]:
    services: list[str] = []
    services.extend(
        f"{compose_path.relative_to(repo_root).as_posix()}:{service_name}"
        for compose_path, service_name, _service, _dockerfile in iter_go_app_compose_services(repo_root)
    )
    for relative_path, expected_services in _explicit_compose_hardening_expectations().items():
        services.extend(f"{relative_path}:{service_name}" for service_name in expected_services)
    return tuple(services)


def additional_subnetcalc_compose_hardening_expectations() -> dict[str, dict[str, list[str]]]:
    app_tmpfs = ["/tmp:rw,noexec,nosuid,nodev,mode=1777"]
    return {
        "apps/subnetcalc/compose.yml": {
            "subnetcalc-backend": app_tmpfs,
            "subnetcalc-frontend": app_tmpfs,
        },
        "docker/compose/compose.yml": {
            "apim-simulator": app_tmpfs,
            "subnetcalc-api-dev": app_tmpfs,
            "subnetcalc-api-uat": app_tmpfs,
            "subnetcalc-frontend-dev": app_tmpfs,
            "subnetcalc-frontend-uat": app_tmpfs,
        },
    }


def additional_subnetcalc_compose_hardening_validated_services() -> tuple[str, ...]:
    return tuple(
        f"{relative_path}:{service_name}"
        for relative_path, services in additional_subnetcalc_compose_hardening_expectations().items()
        for service_name in services
    )


def additional_subnetcalc_compose_hardening_contract_violations(repo_root: Path) -> tuple[str, ...]:
    violations: list[str] = []

    for relative_path, services in additional_subnetcalc_compose_hardening_expectations().items():
        compose = load_yaml(repo_root / relative_path)
        for service_name, required_tmpfs in services.items():
            service = compose["services"][service_name]
            expected = {
                "read_only": True,
                "cap_drop": ["ALL"],
                "security_opt": ["no-new-privileges:true"],
                "tmpfs": required_tmpfs,
            }
            violations.extend(_compose_service_hardening_violations(relative_path, service_name, service, expected))

    return tuple(violations)


def docker_build_audit_tooling_contract_violations(repo_root: Path) -> tuple[str, ...]:
    script = repo_root / "scripts" / "audit-docker-builds.sh"
    if not script.exists():
        return ("scripts/audit-docker-builds.sh missing",)

    content = script.read_text(encoding="utf-8")
    required_fragments = (
        "--progress=plain",
        "docker history",
        "docker image inspect",
        "warning",
        "apps/subnetcalc/app/Dockerfile",
        "apim-simulator/app/Dockerfile",
    )
    return tuple(
        f"scripts/audit-docker-builds.sh missing {fragment}"
        for fragment in required_fragments
        if fragment not in content
    )


def grafana_plugin_archive_mirroring_contract_violations(repo_root: Path) -> tuple[str, ...]:
    dockerfile_path = repo_root / "kubernetes" / "kind" / "images" / "grafana-victorialogs" / "Dockerfile"
    build_script_path = repo_root / "kubernetes" / "kind" / "scripts" / "build-local-platform-images.sh"
    image_catalog_path = repo_root / "kubernetes" / "workflow" / "image-catalog.json"
    variables_path = repo_root / "terraform" / "kubernetes" / "variables.tf"
    violations: list[str] = []

    for path in (dockerfile_path, build_script_path, image_catalog_path, variables_path):
        if not path.exists():
            violations.append(f"{path.relative_to(repo_root).as_posix()} missing")
    if violations:
        return tuple(violations)

    dockerfile = dockerfile_path.read_text(encoding="utf-8")
    build_script = build_script_path.read_text(encoding="utf-8")
    image_catalog = image_catalog_path.read_text(encoding="utf-8")
    variables_tf = variables_path.read_text(encoding="utf-8")

    required_fragments = {
        "terraform/kubernetes/variables.tf": (
            "grafana_victoria_logs_plugin_version",
            "grafana_victoria_logs_plugin_sha256",
        ),
        "kubernetes/kind/images/grafana-victorialogs/Dockerfile": (
            "busybox unzip",
            "COPY ",
            "victorialogs.zip",
        ),
        "kubernetes/workflow/image-catalog.json": (
            '"terraform_version_variable": "grafana_victoria_logs_plugin_version"',
            '"terraform_sha256_variable": "grafana_victoria_logs_plugin_sha256"',
        ),
        "kubernetes/kind/scripts/build-local-platform-images.sh": (
            'tf_default_from_variables "${VICTORIA_LOGS_PLUGIN_VERSION_VAR}"',
            'tf_default_from_variables "${VICTORIA_LOGS_PLUGIN_SHA256_VAR}"',
            "shasum -a 256",
        ),
    }
    contents = {
        "terraform/kubernetes/variables.tf": variables_tf,
        "kubernetes/kind/images/grafana-victorialogs/Dockerfile": dockerfile,
        "kubernetes/workflow/image-catalog.json": image_catalog,
        "kubernetes/kind/scripts/build-local-platform-images.sh": build_script,
    }

    for relative_path, fragments in required_fragments.items():
        content = contents[relative_path]
        for fragment in fragments:
            if fragment not in content:
                violations.append(f"{relative_path} missing {fragment}")

    for forbidden in ("curl -fsSL", "apk add"):
        if forbidden in dockerfile:
            violations.append(f"kubernetes/kind/images/grafana-victorialogs/Dockerfile should not use {forbidden}")

    return tuple(violations)


def go_compose_healthcheck_contract_violations(repo_root: Path) -> tuple[str, ...]:
    violations: list[str] = []

    for compose_path, service_name, service, _dockerfile in iter_go_app_compose_services(repo_root):
        relative_path = compose_path.relative_to(repo_root).as_posix()
        service_id = f"{relative_path}:{service_name}"
        healthcheck = service.get("healthcheck", {}).get("test")
        if not isinstance(healthcheck, list):
            violations.append(f"{service_id} healthcheck test should be a Compose exec-form list")
            continue
        if not healthcheck:
            violations.append(f"{service_id} healthcheck test should not be empty")
            continue
        if healthcheck[0] != "CMD":
            violations.append(f"{service_id} healthcheck should use CMD, got {healthcheck[0]}")
        if healthcheck[-1] != "healthcheck":
            violations.append(f"{service_id} healthcheck should call the app healthcheck command, got {healthcheck}")
        if "/bin/sh" in healthcheck or "CMD-SHELL" in healthcheck:
            violations.append(f"{service_id} healthcheck should not require a shell, got {healthcheck}")

    return tuple(violations)


def go_compose_healthcheck_validated_services(repo_root: Path) -> tuple[str, ...]:
    return tuple(
        f"{compose_path.relative_to(repo_root).as_posix()}:{service_name}"
        for compose_path, service_name, _service, _dockerfile in iter_go_app_compose_services(repo_root)
    )


def _oauth2_proxy_skip_auth_regex(oauth2_proxy: dict[str, Any]) -> str | None:
    command = oauth2_proxy.get("command")
    if not isinstance(command, list):
        return None

    return next(
        (item for item in command if isinstance(item, str) and item.startswith("--skip-auth-regex=")),
        None,
    )


def browser_sso_static_allowlist_contract_violations(repo_root: Path) -> tuple[str, ...]:
    violations: list[str] = []

    for compose_path, web_dir, oauth2_proxy in iter_browser_sso_compose_services(repo_root):
        app_name = compose_path.parent.name
        service_id = f"{compose_path.relative_to(repo_root).as_posix()}:oauth2-proxy"
        skip_auth = _oauth2_proxy_skip_auth_regex(oauth2_proxy)
        if skip_auth is None:
            violations.append(f"{service_id} missing --skip-auth-regex command")
            continue

        if "app-shell\\.css" not in skip_auth:
            violations.append(f"{app_name} SSO allowlist should include shared app-shell.css")
        if "styles\\.css" in skip_auth:
            violations.append(f"{app_name} SSO allowlist should not reference retired styles.css")

        for asset_name in ("style.css", "favicon.svg", "favicon.ico"):
            if not (web_dir / asset_name).exists():
                continue

            escaped = asset_name.replace(".", "\\.")
            if escaped not in skip_auth:
                violations.append(f"{app_name} SSO allowlist should include {asset_name}")

    return tuple(violations)


def browser_sso_static_allowlist_validated_apps(repo_root: Path) -> tuple[str, ...]:
    return tuple(
        compose_path.parent.name
        for compose_path, _web_dir, _oauth2_proxy in iter_browser_sso_compose_services(repo_root)
    )


def _dockerfile_runtime_user(dockerfile: Path) -> str | None:
    user_lines = [
        line.strip()
        for line in dockerfile.read_text(encoding="utf-8").splitlines()
        if line.strip().startswith("USER ")
    ]
    if not user_lines:
        return None

    return user_lines[-1].split(None, 1)[1]


def dockerfile_runtime_user_contract_violations(
    repo_root: Path,
    *,
    expected_user: str = "65532:65532",
) -> tuple[str, ...]:
    violations: list[str] = []

    for dockerfile in iter_go_app_dockerfiles(repo_root):
        relative_path = dockerfile.relative_to(repo_root).as_posix()
        actual_user = _dockerfile_runtime_user(dockerfile)
        if actual_user is None:
            violations.append(f"{relative_path} missing runtime USER")
        elif actual_user != expected_user:
            violations.append(f"{relative_path} runtime USER should be {expected_user}, got {actual_user}")

    return tuple(violations)


def go_app_dockerfile_runtime_contract_violations(repo_root: Path) -> tuple[str, ...]:
    copy_lines = {
        "apim-simulator": "COPY --chown=65532:65532 app/.run/apim-simulator /apim-simulator",
        "chatgpt-sim": "COPY --chown=65532:65532 .run/chatgpt-sim /chatgpt-sim",
        "idp-core": "COPY --chown=65532:65532 apps/idp-core/app/.run/idp-core /usr/local/bin/idp-core",
        "langfuse-demos": "COPY --chown=65532:65532 .run/langfuse-demos /langfuse-demos",
        "platform-mcp": "COPY --chown=65532:65532 .run/platform-mcp /platform-mcp",
        "sentiment": "COPY --chown=65532:65532 .run/sentiment /sentiment",
        "subnetcalc": "COPY --chown=65532:65532 .run/subnetcalc /subnetcalc",
    }
    entrypoints = {
        "idp-core": 'ENTRYPOINT ["/usr/local/bin/idp-core"]',
    }
    forbidden_fragments = (
        "--mount=type=cache",
        "node_modules",
        "python",
        "pip",
        "npm",
        "yarn",
        "pnpm",
        "bun",
        "uv",
    )
    violations: list[str] = []

    for dockerfile in iter_go_app_dockerfiles(repo_root):
        app_name = dockerfile.parent.parent.name
        relative_path = dockerfile.relative_to(repo_root).as_posix()
        content = dockerfile.read_text(encoding="utf-8")
        lower_content = content.lower()

        if not content.startswith("FROM dhi.io/static:"):
            violations.append(f"{relative_path} should use the DHI static runtime base")

        expected_copy = copy_lines.get(app_name)
        if expected_copy is None:
            violations.append(f"{app_name} missing Dockerfile runtime copy contract")
        elif expected_copy not in content:
            violations.append(f"{relative_path} should copy runtime binary with {expected_copy}")

        expected_entrypoint = entrypoints.get(app_name, f'ENTRYPOINT ["/{app_name}"]')
        if expected_entrypoint not in content:
            violations.append(f"{relative_path} should use {expected_entrypoint}")

        if not re.search(r"(^|[ \t])HOME=/tmp([ \t]|$|\\)", content, flags=re.MULTILINE):
            violations.append(f"{relative_path} should set HOME=/tmp for the non-root runtime user")

        for forbidden in forbidden_fragments:
            if forbidden in lower_content:
                violations.append(f"{relative_path} should not contain {forbidden}")

    violations.extend(dockerfile_runtime_user_contract_violations(repo_root))

    apim_dockerfile = repo_root / "apps" / "apim-simulator" / "app" / "Dockerfile"
    if apim_dockerfile.exists() and "COPY examples /app/examples" not in apim_dockerfile.read_text(encoding="utf-8"):
        violations.append("apps/apim-simulator/app/Dockerfile should copy APIM examples")

    return tuple(violations)


def dockerfile_runtime_user_validated_files(repo_root: Path) -> tuple[str, ...]:
    return tuple(
        dockerfile.relative_to(repo_root).as_posix()
        for dockerfile in iter_go_app_dockerfiles(repo_root)
    )


def _compose_environment_map(service: dict[str, Any]) -> dict[str, str]:
    environment = service.get("environment", {})
    if isinstance(environment, dict):
        return {str(key): str(value) for key, value in environment.items()}
    if isinstance(environment, list):
        result: dict[str, str] = {}
        for item in environment:
            if not isinstance(item, str) or "=" not in item:
                continue
            key, value = item.split("=", 1)
            result[key] = value
        return result

    return {}


def sentiment_compose_diagnostics_contract_violations(repo_root: Path) -> tuple[str, ...]:
    compose = load_yaml(repo_root / "apps" / "sentiment" / "compose.yml")
    frontend = compose["services"]["sentiment-auth-frontend"]
    env = _compose_environment_map(frontend)
    violations: list[str] = []

    expected_values = {
        "RUNTIME_ROLE": "frontend",
        "BACKEND_URL": "${SENTIMENT_FRONTEND_BACKEND_URL:-http://sentiment-api:8080}",
        "API_BASE_PATH": "/api/v1",
        "SHOW_NETWORK_PATH": "${SENTIMENT_SHOW_NETWORK_PATH:-true}",
    }
    for key, expected in expected_values.items():
        actual = env.get(key)
        if actual != expected:
            violations.append(f"sentiment-auth-frontend {key} should be {expected}, got {actual}")

    try:
        network_hops = json.loads(env.get("NETWORK_HOPS", "[]"))
    except json.JSONDecodeError as error:
        violations.append(f"sentiment-auth-frontend NETWORK_HOPS should be JSON: {error}")
    else:
        labels = [hop.get("label") for hop in network_hops if isinstance(hop, dict)]
        expected_labels = ["Browser", "Sentiment edge", "Sentiment frontend", "Sentiment API"]
        if labels != expected_labels:
            violations.append(f"sentiment-auth-frontend NETWORK_HOPS labels should be {expected_labels}, got {labels}")

    return tuple(violations)


def subnetcalc_compose_topology_contract_violations(repo_root: Path) -> tuple[str, ...]:
    compose = load_yaml(repo_root / "apps" / "subnetcalc" / "compose.yml")
    services = compose["services"]
    violations: list[str] = []

    default_services = {
        name
        for name, service in services.items()
        if "profiles" not in service
    }
    expected_default_services = {"subnetcalc-backend", "subnetcalc-frontend"}
    if default_services != expected_default_services:
        violations.append(f"subnetcalc default services should be {expected_default_services}, got {default_services}")

    sso_services = {
        name
        for name, service in services.items()
        if service.get("profiles") == ["sso"]
    }
    expected_sso_services = {"keycloak", "edge", "oauth2-proxy"}
    if sso_services != expected_sso_services:
        violations.append(f"subnetcalc SSO services should be {expected_sso_services}, got {sso_services}")

    expected_roles = {
        "subnetcalc-backend": "backend",
        "subnetcalc-frontend": "frontend",
    }
    for service_name, expected_role in expected_roles.items():
        actual_role = _compose_environment_map(services[service_name]).get("RUNTIME_ROLE")
        if actual_role != expected_role:
            violations.append(f"{service_name} RUNTIME_ROLE should be {expected_role}, got {actual_role}")

    oauth2_command = services["oauth2-proxy"].get("command", [])
    if not isinstance(oauth2_command, list):
        violations.append("subnetcalc oauth2-proxy command should be a list")
    else:
        if oauth2_command.count("--cookie-refresh=1h") != 1:
            violations.append("subnetcalc oauth2-proxy should refresh cookies once per hour")
        if "--pass-access-token=true" not in oauth2_command:
            violations.append("subnetcalc oauth2-proxy should pass access tokens to the frontend")

    return tuple(violations)


def subnetcalc_runtime_config_contract_violations(repo_root: Path) -> tuple[str, ...]:
    server_go = (repo_root / "apps" / "subnetcalc" / "app" / "internal" / "app" / "server.go").read_text(
        encoding="utf-8"
    )
    app_js = (repo_root / "apps" / "subnetcalc" / "app" / "internal" / "app" / "web" / "app.js").read_text(
        encoding="utf-8"
    )
    violations: list[str] = []

    for key in ('"authMethod"', '"apiAuthMethod"', '"oidcAuthority"'):
        if key not in server_go:
            violations.append(f"subnetcalc server runtime config missing {key}")
    if "window.SUBNETCALC_RUNTIME_CONFIG" not in server_go:
        violations.append("subnetcalc server should write window.SUBNETCALC_RUNTIME_CONFIG")
    if 'config.apiAuthMethod === "oidc"' not in app_js:
        violations.append("subnetcalc browser app should branch on OIDC API auth method")

    return tuple(violations)


def shared_sign_out_page_contract_violations(repo_root: Path) -> tuple[str, ...]:
    server_go = (repo_root / "apps" / "subnetcalc" / "app" / "internal" / "app" / "server.go").read_text(
        encoding="utf-8"
    )
    appshell_go = (repo_root / "apps" / "shared" / "appshell" / "appshell.go").read_text(encoding="utf-8")
    violations: list[str] = []

    if "appshell.SignedOutPage" not in server_go:
        violations.append("subnetcalc frontend should use appshell.SignedOutPage")
    if 'AppName:     "IPv4 Subnet Calculator"' not in server_go:
        violations.append("subnetcalc frontend should pass its app name to the shared sign-out page")
    for text in ("Signed out", "Sign in now", "/.auth/login/sso"):
        if text not in appshell_go:
            violations.append(f"shared appshell sign-out page missing {text}")

    return tuple(violations)


def _kubernetes_workload_security_expectations() -> dict[str, dict[str, int]]:
    return {
        "sentiment-api": {"runAsUser": 1000, "runAsGroup": 1000, "fsGroup": 1000},
        "sentiment-auth-ui": {"runAsUser": 65532, "runAsGroup": 65532, "fsGroup": 65532},
        "sentiment-router": {"runAsUser": 65532, "runAsGroup": 65532, "fsGroup": 65532},
        "subnetcalc-api": {"runAsUser": 65532, "runAsGroup": 65532, "fsGroup": 65532},
        "subnetcalc-frontend": {"runAsUser": 65532, "runAsGroup": 65532, "fsGroup": 65532},
        "subnetcalc-router": {"runAsUser": 65532, "runAsGroup": 65532, "fsGroup": 65532},
    }


def kubernetes_workload_runtime_user_contract_violations(repo_root: Path) -> tuple[str, ...]:
    docs = [
        doc
        for doc in load_yaml_all(repo_root / "terraform" / "kubernetes" / "apps" / "workloads" / "base" / "all.yaml")
        if doc
    ]
    deployments = {
        doc.get("metadata", {}).get("name"): doc
        for doc in docs
        if doc.get("kind") == "Deployment"
    }
    violations: list[str] = []

    for deployment_name, expected_security in _kubernetes_workload_security_expectations().items():
        deployment = deployments.get(deployment_name)
        if deployment is None:
            violations.append(f"{deployment_name} Deployment missing from workload manifest")
            continue

        pod_security = deployment["spec"]["template"]["spec"].get("securityContext", {})
        for key, expected_value in expected_security.items():
            actual_value = pod_security.get(key)
            if actual_value != expected_value:
                violations.append(f"{deployment_name} {key} should be {expected_value}, got {actual_value}")

    return tuple(violations)


def kubernetes_workload_runtime_user_validated_deployments() -> tuple[str, ...]:
    return tuple(_kubernetes_workload_security_expectations())


@dataclass(frozen=True)
class BrowserRouterExpectation:
    config_map: str
    frontend_upstream: str
    authorization_variable: str
    requires_apim_bypass: bool = False
    requires_health_locations: bool = False


def _browser_router_expectations() -> dict[str, BrowserRouterExpectation]:
    return {
        "subnetcalc": BrowserRouterExpectation(
            config_map="subnetcalc-router-nginx",
            frontend_upstream="http://subnetcalc-frontend:8080;",
            authorization_variable="$apim_auth",
        ),
        "sentiment": BrowserRouterExpectation(
            config_map="sentiment-router-nginx",
            frontend_upstream="http://sentiment-auth-ui:8080;",
            authorization_variable="$api_auth",
            requires_apim_bypass=True,
            requires_health_locations=True,
        ),
    }


def browser_router_auth_api_contract_violations(repo_root: Path) -> tuple[str, ...]:
    docs = [
        doc
        for doc in load_yaml_all(repo_root / "terraform" / "kubernetes" / "apps" / "workloads" / "base" / "all.yaml")
        if doc
    ]
    config_maps = {
        doc.get("metadata", {}).get("name"): doc
        for doc in docs
        if doc.get("kind") == "ConfigMap"
    }
    violations: list[str] = []

    for app_name, expected in _browser_router_expectations().items():
        config = config_maps.get(expected.config_map)
        if config is None:
            violations.append(f"{app_name} router ConfigMap {expected.config_map} missing")
            continue

        nginx_conf = config.get("data", {}).get("default.conf", "")
        required_fragments = [
            "location ^~ /api/",
            "proxy_pass http://subnetcalc-apim-simulator.apim.svc.cluster.local:8000;",
            f"proxy_set_header Authorization {expected.authorization_variable};",
            "location / {",
            "set $auth_email $http_x_auth_request_email;",
            'if ($auth_email = "") { return 302 https://$host/oauth2/start?rd=$uri; }',
            f"proxy_pass {expected.frontend_upstream}",
        ]
        if expected.requires_apim_bypass:
            required_fragments.append("proxy_set_header X-Apim-Bypass-Subscription true;")
        if expected.requires_health_locations:
            required_fragments.extend(("location = /health", "location = /health/ready", "location = /health/live"))

        for fragment in required_fragments:
            if fragment not in nginx_conf:
                violations.append(f"{expected.config_map} missing {fragment}")

    return tuple(violations)


def browser_router_auth_api_validated_apps() -> tuple[str, ...]:
    return tuple(_browser_router_expectations())


def _manifest_docs_by_kind_name(docs: list[dict[str, Any]]) -> dict[tuple[str, str], dict[str, Any]]:
    return {
        (str(doc.get("kind")), str(doc.get("metadata", {}).get("name"))): doc
        for doc in docs
    }


def _deployment_container_env(deployment: dict[str, Any]) -> dict[str, str]:
    containers = deployment["spec"]["template"]["spec"]["containers"]
    return {
        item["name"]: str(item.get("value", ""))
        for item in containers[0].get("env", [])
    }


def sentiment_kubernetes_frontend_apim_contract_violations(repo_root: Path) -> tuple[str, ...]:
    workload_docs = [
        doc
        for doc in load_yaml_all(repo_root / "terraform" / "kubernetes" / "apps" / "workloads" / "base" / "all.yaml")
        if doc
    ]
    workload_by_kind_name = _manifest_docs_by_kind_name(workload_docs)
    violations: list[str] = []

    frontend = workload_by_kind_name.get(("Deployment", "sentiment-auth-ui"))
    if frontend is None:
        violations.append("sentiment-auth-ui Deployment missing")
    else:
        frontend_env = _deployment_container_env(frontend)
        expected_env = {
            "AUTH_METHOD": "gateway",
            "API_AUTH_METHOD": "oidc",
            "API_BASE_PATH": "/api/v1",
            "BACKEND_URL": "http://sentiment-api:8080",
            "SHOW_NETWORK_PATH": "true",
        }
        for key, expected_value in expected_env.items():
            actual_value = frontend_env.get(key)
            if actual_value != expected_value:
                violations.append(f"sentiment-auth-ui {key} should be {expected_value}, got {actual_value}")

        try:
            network_hops = json.loads(frontend_env.get("NETWORK_HOPS", "[]"))
        except json.JSONDecodeError as error:
            violations.append(f"sentiment-auth-ui NETWORK_HOPS should be JSON: {error}")
        else:
            labels = [hop.get("label") for hop in network_hops if isinstance(hop, dict)]
            expected_labels = [
                "Browser",
                "OAuth2 Proxy",
                "Sentiment router",
                "Sentiment frontend",
                "APIM simulator",
                "Sentiment API",
            ]
            if labels != expected_labels:
                violations.append(f"sentiment-auth-ui NETWORK_HOPS labels should be {expected_labels}, got {labels}")

        frontend_container = frontend["spec"]["template"]["spec"]["containers"][0]
        expected_probe_paths = {
            "readinessProbe": "/health/ready",
            "livenessProbe": "/health/live",
        }
        for probe_name, expected_path in expected_probe_paths.items():
            actual_path = frontend_container.get(probe_name, {}).get("httpGet", {}).get("path")
            if actual_path != expected_path:
                violations.append(f"sentiment-auth-ui {probe_name} path should be {expected_path}, got {actual_path}")

    edge_conf = (repo_root / "apps" / "sentiment" / "edge" / "nginx.conf").read_text(encoding="utf-8")
    if 'set $api_upstream "sentiment-auth-frontend:8080";' not in edge_conf:
        violations.append("apps/sentiment/edge/nginx.conf should route API through sentiment-auth-frontend")
    if 'set $api_upstream "sentiment-api:8080";' in edge_conf:
        violations.append("apps/sentiment/edge/nginx.conf should not route API directly to sentiment-api")

    apim_docs = [
        doc
        for doc in load_yaml_all(repo_root / "terraform" / "kubernetes" / "apps" / "apim" / "all.yaml")
        if doc
    ]
    apim_by_kind_name = _manifest_docs_by_kind_name(apim_docs)
    apim_config = apim_by_kind_name.get(("ConfigMap", "subnetcalc-apim-simulator-config"))
    if apim_config is None:
        violations.append("subnetcalc-apim-simulator-config ConfigMap missing")
    else:
        apim_payload = json.loads(apim_config["data"]["config.json"])
        routes = {route["name"]: route for route in apim_payload["routes"]}
        expected_routes = {
            "sentiment-api-dev": "http://sentiment-api.dev.svc.cluster.local:8080",
            "sentiment-api-uat": "http://sentiment-api.uat.svc.cluster.local:8080",
        }
        for route_name, expected_upstream in expected_routes.items():
            actual_upstream = routes.get(route_name, {}).get("upstream_base_url")
            if actual_upstream != expected_upstream:
                violations.append(f"{route_name} upstream should be {expected_upstream}, got {actual_upstream}")
        if "https://sentiment.dev.127.0.0.1.sslip.io" not in apim_payload["allowed_origins"]:
            violations.append("APIM allowed_origins should include sentiment dev origin")
        bypass = {"header": "X-Apim-Bypass-Subscription", "equals": "true"}
        if bypass not in apim_payload["subscription"]["bypass"]:
            violations.append("APIM subscription bypass should allow X-Apim-Bypass-Subscription=true")

    return tuple(violations)


def sentiment_api_kubernetes_runtime_contract_violations(repo_root: Path) -> tuple[str, ...]:
    workload_docs = [
        doc
        for doc in load_yaml_all(repo_root / "terraform" / "kubernetes" / "apps" / "workloads" / "base" / "all.yaml")
        if doc
    ]
    workload_by_kind_name = _manifest_docs_by_kind_name(workload_docs)
    deployment = workload_by_kind_name.get(("Deployment", "sentiment-api"))
    violations: list[str] = []

    if deployment is None:
        return ("sentiment-api Deployment missing",)

    container = deployment["spec"]["template"]["spec"]["containers"][0]
    env = _deployment_container_env(deployment)
    expected_env = {
        "AUTH_METHOD": "oidc",
        "OIDC_AUDIENCE": "apim-simulator",
        "OIDC_JWKS_URI": "http://keycloak.sso.svc.cluster.local:8080/realms/platform/protocol/openid-connect/certs",
    }
    for key, expected_value in expected_env.items():
        actual_value = env.get(key)
        if actual_value != expected_value:
            violations.append(f"sentiment-api {key} should be {expected_value}, got {actual_value}")

    resources = container.get("resources", {})
    expected_resources = {
        ("requests", "memory"): "768Mi",
        ("limits", "memory"): "2048Mi",
        ("limits", "cpu"): "1",
    }
    for (section, key), expected_value in expected_resources.items():
        actual_value = resources.get(section, {}).get(key)
        if actual_value != expected_value:
            violations.append(f"sentiment-api resources.{section}.{key} should be {expected_value}, got {actual_value}")

    expected_probe_paths = {
        "readinessProbe": "/api/v1/health/ready",
        "livenessProbe": "/api/v1/health/live",
    }
    for probe_name, expected_path in expected_probe_paths.items():
        actual_path = container.get(probe_name, {}).get("httpGet", {}).get("path")
        if actual_path != expected_path:
            violations.append(f"sentiment-api {probe_name} path should be {expected_path}, got {actual_path}")

    return tuple(violations)


def chatgpt_sim_compose_llm_langfuse_contract_violations(repo_root: Path) -> tuple[str, ...]:
    compose = load_yaml(repo_root / "apps" / "chatgpt-sim" / "compose.yml")
    services = compose.get("services", {})
    shell = services.get("chatgpt-sim", {})
    llm = services.get("llm", {})
    shell_env = _compose_environment_map(shell)
    llm_env = _compose_environment_map(llm)
    violations: list[str] = []

    expected_shell_env = {
        "LLM_URL": "${CHATGPT_SIM_LLM_URL:-http://llm:8080/v1/chat/completions}",
        "LLM_MODEL": "${CHATGPT_SIM_LLM_MODEL:-${PLATFORM_LLM_MODEL:-go-local-openai-compatible-stub}}",
        "LLM_TIMEOUT_SECONDS": "${CHATGPT_SIM_LLM_TIMEOUT_SECONDS:-1}",
        "LLM_MAX_TOKENS": "${CHATGPT_SIM_LLM_MAX_TOKENS:-32}",
        "LANGFUSE_HOST": "${CHATGPT_SIM_LANGFUSE_HOST:-}",
        "LANGFUSE_PUBLIC_KEY": "${CHATGPT_SIM_LANGFUSE_PUBLIC_KEY:-}",
        "LANGFUSE_SECRET_KEY": "${CHATGPT_SIM_LANGFUSE_SECRET_KEY:-}",
        "LANGFUSE_TIMEOUT_SECONDS": "${CHATGPT_SIM_LANGFUSE_TIMEOUT_SECONDS:-1}",
    }
    for key, expected_value in expected_shell_env.items():
        actual_value = shell_env.get(key)
        if actual_value != expected_value:
            violations.append(f"chatgpt-sim {key} should be {expected_value}, got {actual_value}")

    expected_llm_model = "${PLATFORM_LLM_MODEL:-go-local-openai-compatible-stub}"
    if llm_env.get("LLM_MODEL") != expected_llm_model:
        violations.append(f"chatgpt-sim llm LLM_MODEL should be {expected_llm_model}, got {llm_env.get('LLM_MODEL')}")

    return tuple(violations)


def _gitea_workflow_go_image_expectations() -> dict[str, dict[str, tuple[str, ...]]]:
    return {
        "apps/sentiment/.gitea/workflows/build-images.yaml": {
            "required": (
                '"app/**"',
                "golang:1.26-alpine",
                '-v "${APPS_DIR}/sentiment/app:/src"',
                '-v "${APPS_DIR}/shared:/shared:ro"',
                'docker build --provenance=false -t "${REGISTRY_HOST}/${GITEA_REPO_OWNER}/sentiment-api:${TAG}" "${APPS_DIR}/sentiment/app"',
                'docker tag "${REGISTRY_HOST}/${GITEA_REPO_OWNER}/sentiment-api:${TAG}" "${REGISTRY_HOST}/${GITEA_REPO_OWNER}/sentiment-auth-ui:${TAG}"',
            ),
            "forbidden": (
                '-v "${WORKDIR}/app:/src"',
                'docker build --provenance=false -t "${REGISTRY_HOST}/${GITEA_REPO_OWNER}/sentiment-api:${TAG}" ./app',
                'docker build --provenance=false -t "${REGISTRY_HOST}/${GITEA_REPO_OWNER}/sentiment-api:${TAG}" ./api-sentiment',
                'docker build --provenance=false -t "${REGISTRY_HOST}/${GITEA_REPO_OWNER}/sentiment-auth-ui:${TAG}" ./frontend-react-vite/sentiment-auth-ui',
            ),
        },
        "apps/subnetcalc/.gitea/workflows/build-images.yaml": {
            "required": (
                '"app/**"',
                "golang:1.26-alpine",
                '-v "${APPS_DIR}/subnetcalc/app:/src"',
                '-v "${APPS_DIR}/shared:/shared:ro"',
                'docker build --provenance=false -t "${REGISTRY_HOST}/${GITEA_REPO_OWNER}/subnetcalc-api:${TAG}" "${APPS_DIR}/subnetcalc/app"',
                'docker tag "${REGISTRY_HOST}/${GITEA_REPO_OWNER}/subnetcalc-api:${TAG}" "${REGISTRY_HOST}/${GITEA_REPO_OWNER}/subnetcalc-frontend:${TAG}"',
            ),
            "forbidden": (
                '-v "${WORKDIR}/app:/src"',
                'docker build --provenance=false -t "${REGISTRY_HOST}/${GITEA_REPO_OWNER}/subnetcalc-api:${TAG}" ./app',
                'docker build --provenance=false -t "${REGISTRY_HOST}/${GITEA_REPO_OWNER}/subnetcalc-apim-simulator:${TAG}"',
                'docker build --provenance=false -t "${REGISTRY_HOST}/${GITEA_REPO_OWNER}/subnetcalc-frontend:${TAG}" -f ./frontend-typescript-vite/Dockerfile .',
                'docker build --provenance=false -t "${REGISTRY_HOST}/${GITEA_REPO_OWNER}/subnetcalc-api:${TAG}" ./api-fastapi-container-app',
            ),
        },
    }


def gitea_workflow_go_image_contract_violations(repo_root: Path) -> tuple[str, ...]:
    violations: list[str] = []
    for relative_path, spec in _gitea_workflow_go_image_expectations().items():
        workflow = repo_root / relative_path
        if not workflow.exists():
            violations.append(f"{relative_path} missing")
            continue
        text = workflow.read_text(encoding="utf-8")
        for expected in spec["required"]:
            if expected not in text:
                violations.append(f"{relative_path} missing {expected}")
        for forbidden in spec["forbidden"]:
            if forbidden in text:
                violations.append(f"{relative_path} should not contain {forbidden}")

    return tuple(violations)


def gitea_workflow_go_image_validated_files() -> tuple[str, ...]:
    return tuple(_gitea_workflow_go_image_expectations())


def subnetcalc_runtime_config_response_contract_violations(repo_root: Path) -> tuple[str, ...]:
    server_go = (repo_root / "apps" / "subnetcalc" / "app" / "internal" / "app" / "server.go").read_text(
        encoding="utf-8"
    )
    appshell_go = (repo_root / "apps" / "shared" / "appshell" / "appshell.go").read_text(encoding="utf-8")
    required_fragments = {
        "apps/subnetcalc/app/internal/app/server.go": (
            'mux.HandleFunc("GET /runtime-config.js", server.runtimeConfig)',
            'appshell.WriteScriptConfigForRequest(w, r, "window.SUBNETCALC_RUNTIME_CONFIG", runtimePayload)',
        ),
        "apps/shared/appshell/appshell.go": (
            'w.Header().Set("Content-Type", "application/javascript; charset=utf-8")',
            '_, _ = w.Write([]byte(globalName + " = "))',
        ),
    }
    sources = {
        "apps/subnetcalc/app/internal/app/server.go": server_go,
        "apps/shared/appshell/appshell.go": appshell_go,
    }
    violations: list[str] = []

    for relative_path, fragments in required_fragments.items():
        content = sources[relative_path]
        for fragment in fragments:
            if fragment not in content:
                violations.append(f"{relative_path} missing {fragment}")

    return tuple(violations)


def _oauth2_proxy_token_refresh_names() -> tuple[str, ...]:
    return (
        "oauth2-proxy-sentiment-dev",
        "oauth2-proxy-sentiment-uat",
        "oauth2-proxy-subnetcalc-dev",
        "oauth2-proxy-subnetcalc-uat",
    )


def _oauth2_proxy_token_refresh_args() -> tuple[str, ...]:
    return (
        "--cookie-expire=4h",
        "--cookie-refresh=1h",
        "--skip-auth-regex=^/(signed-out\\.html|style\\.css|app-shell\\.css|favicon\\.svg|favicon\\.ico)$",
        "--pass-access-token=true",
        "--set-xauthrequest=true",
        "--set-authorization-header=true",
    )


def oauth2_proxy_token_refresh_contract_violations(repo_root: Path) -> tuple[str, ...]:
    sso_tf = (repo_root / "terraform" / "kubernetes" / "sso.tf").read_text(encoding="utf-8")
    violations: list[str] = []

    for name in _oauth2_proxy_token_refresh_names():
        marker = f"name: {name}"
        if marker not in sso_tf:
            violations.append(f"{name} missing from terraform/kubernetes/sso.tf")
            continue

        start = sso_tf.index(marker)
        end = sso_tf.index("syncPolicy:", start)
        block = sso_tf[start:end]
        for expected in _oauth2_proxy_token_refresh_args():
            if expected not in block:
                violations.append(f"{name} missing {expected}")

    return tuple(violations)


def oauth2_proxy_token_refresh_validated_names() -> tuple[str, ...]:
    return _oauth2_proxy_token_refresh_names()


def _image_prebuild_direct_scripts() -> tuple[str, ...]:
    return (
        "kubernetes/kind/scripts/build-local-workload-images.sh",
        "kubernetes/scripts/build-local-workload-images.sh",
    )


def _image_prebuild_wrapper_scripts() -> tuple[str, ...]:
    return (
        "kubernetes/lima/scripts/build-local-workload-images.sh",
        "kubernetes/slicer/scripts/build-local-workload-images.sh",
    )


def image_prebuild_hook_contract_violations(repo_root: Path) -> tuple[str, ...]:
    shared = (repo_root / "kubernetes" / "workflow" / "image-build-lib.sh").read_text(encoding="utf-8")
    catalog = (repo_root / "kubernetes" / "workflow" / "image-catalog.json").read_text(encoding="utf-8")
    violations: list[str] = []

    for expected in (
        '"prebuild": "make -C apps/sentiment/app build-linux"',
        '"prebuild": "make -C apps/subnetcalc/app build-linux"',
        '"apps/sentiment/app/go.sum"',
        '"apps/subnetcalc/app/go.sum"',
    ):
        if expected not in catalog:
            violations.append(f"image catalog missing {expected}")

    for expected in (
        "image_build_run_prebuild()",
        'image_build_run_prebuild "${category}" "${image_id}"',
    ):
        if expected not in shared:
            violations.append(f"image-build-lib.sh missing {expected}")

    for relative_path in _image_prebuild_direct_scripts():
        content = (repo_root / relative_path).read_text(encoding="utf-8")
        if "kubernetes/workflow/image-build-lib.sh" not in content:
            violations.append(f"{relative_path} should source image-build-lib.sh")
        if "image_build_catalog_build_loop workload workload" not in content:
            violations.append(f"{relative_path} should call image_build_catalog_build_loop workload workload")

    for relative_path in _image_prebuild_wrapper_scripts():
        content = (repo_root / relative_path).read_text(encoding="utf-8")
        if "kubernetes/scripts/build-local-workload-images.sh" not in content:
            violations.append(f"{relative_path} should delegate to the shared workload image builder")

    return tuple(violations)


def image_prebuild_hook_validated_builders() -> tuple[str, ...]:
    return _image_prebuild_direct_scripts() + _image_prebuild_wrapper_scripts()


def oauth2_proxy_backend_logout_contract_violations(repo_root: Path) -> tuple[str, ...]:
    locals_tf = (repo_root / "terraform" / "kubernetes" / "locals.tf").read_text(encoding="utf-8")
    sso_tf = (repo_root / "terraform" / "kubernetes" / "sso.tf").read_text(encoding="utf-8")
    violations: list[str] = []

    for expected in (
        "oauth2_proxy_backend_logout_url",
        "/protocol/openid-connect/logout?id_token_hint={id_token}",
        "oauth2_proxy_backend_logout_arg",
        "--backend-logout-url=${local.oauth2_proxy_backend_logout_url}",
        "backend_logout_arg = local.oauth2_proxy_backend_logout_arg_map",
    ):
        if expected not in locals_tf:
            violations.append(f"terraform/kubernetes/locals.tf missing {expected}")

    for forbidden in ("sso_oauth2_proxy_post_logout_redirect_uris",):
        if forbidden in locals_tf:
            violations.append(f"terraform/kubernetes/locals.tf should not use {forbidden}")

    for forbidden in ("post.logout.redirect.uris",):
        if forbidden in sso_tf:
            violations.append(f"terraform/kubernetes/sso.tf should not use {forbidden}")

    backend_logout_arg_count = sso_tf.count("${local.oauth2_proxy_backend_logout_arg}")
    if backend_logout_arg_count != 4:
        violations.append(
            f"terraform/kubernetes/sso.tf should render backend logout arg 4 times, got {backend_logout_arg_count}"
        )
    if '${try(each.value.backend_logout_arg, "")}' not in sso_tf:
        violations.append("terraform/kubernetes/sso.tf should tolerate empty backend logout args")

    return tuple(violations)


def load_yaml(path: Path) -> dict[str, Any]:
    import yaml

    return yaml.safe_load(path.read_text(encoding="utf-8"))


def load_yaml_all(path: Path) -> tuple[dict[str, Any] | None, ...]:
    import yaml

    return tuple(yaml.safe_load_all(path.read_text(encoding="utf-8")))


def app_owned_catalog_files(repo_root: Path) -> tuple[Path, ...]:
    return tuple(
        sorted(
            path
            for path in (repo_root / "apps").glob("*/catalog-info.yaml")
            if path.parent.name != "backstage"
        )
    )


def backstage_local_catalog_files(repo_root: Path) -> tuple[Path, ...]:
    return (
        repo_root / "apps" / "backstage" / "catalog" / "entities.yaml",
        repo_root / "apps" / "backstage" / "catalog" / "apps" / "langfuse" / "catalog-info.yaml",
        *app_owned_catalog_files(repo_root),
    )


def backstage_production_catalog_files(repo_root: Path) -> tuple[Path, ...]:
    bundled_app_catalogs = tuple(
        sorted((repo_root / "apps" / "backstage" / "catalog" / "apps").glob("*/catalog-info.yaml"))
    )
    return (
        repo_root / "apps" / "backstage" / "catalog" / "entities.yaml",
        *bundled_app_catalogs,
    )


def backstage_production_catalog_targets(repo_root: Path) -> tuple[str, ...]:
    catalog_root = repo_root / "apps" / "backstage"
    return tuple(
        f"./{catalog_file.relative_to(catalog_root).as_posix()}"
        for catalog_file in backstage_production_catalog_files(repo_root)
    )


def backstage_catalog_documents(catalog_files: tuple[Path, ...]) -> tuple[dict[str, Any], ...]:
    docs: list[dict[str, Any]] = []
    for catalog_file in catalog_files:
        docs.extend(doc for doc in load_yaml_all(catalog_file) if doc)
    return tuple(docs)


def backstage_local_catalog_documents(repo_root: Path) -> tuple[dict[str, Any], ...]:
    return backstage_catalog_documents(backstage_local_catalog_files(repo_root))


def backstage_production_catalog_documents(repo_root: Path) -> tuple[dict[str, Any], ...]:
    return backstage_catalog_documents(backstage_production_catalog_files(repo_root))


def canonical_go_app_catalog_ownership_contract_violations(repo_root: Path) -> tuple[str, ...]:
    owned_catalog_app_names = {catalog.parent.name for catalog in app_owned_catalog_files(repo_root)}
    violations: list[str] = []
    for app_name in canonical_go_app_names():
        if app_name not in owned_catalog_app_names:
            violations.append(f"{app_name} should own apps/{app_name}/catalog-info.yaml")

    return tuple(violations)


def backstage_app_catalog_mirror_contract_violations(repo_root: Path) -> tuple[str, ...]:
    production_config = (repo_root / "apps" / "backstage" / "app-config.production.yaml").read_text(
        encoding="utf-8"
    )
    local_config = (repo_root / "apps" / "backstage" / "app-config.yaml").read_text(encoding="utf-8")
    violations: list[str] = []

    for app_catalog in app_owned_catalog_files(repo_root):
        app_name = app_catalog.parent.name
        bundled_catalog = repo_root / "apps" / "backstage" / "catalog" / "apps" / app_name / "catalog-info.yaml"
        if not bundled_catalog.exists():
            violations.append(f"{app_name} app-owned catalog missing Backstage bundled mirror")
            continue
        if bundled_catalog.read_text(encoding="utf-8") != app_catalog.read_text(encoding="utf-8"):
            violations.append(f"{app_name} Backstage catalog copy drifted from app-owned catalog-info.yaml")

        production_target = f"./catalog/apps/{app_name}/catalog-info.yaml"
        if production_target not in production_config:
            violations.append(f"{app_name} Backstage production catalog should register {production_target}")

        local_target = f"../../../{app_name}/catalog-info.yaml"
        if local_target not in local_config:
            violations.append(f"{app_name} Backstage local catalog should register {local_target}")

    return tuple(violations)


def platform_mcp_langfuse_inventory_contract_violations(repo_root: Path) -> tuple[str, ...]:
    catalog = json.loads((repo_root / "catalog" / "platform-apps.json").read_text(encoding="utf-8"))
    apps = {app["name"]: app for app in catalog.get("applications", [])}
    violations: list[str] = []

    for app_name, expected in platform_mcp_langfuse_inventory_expectations().items():
        app = apps.get(app_name)
        if app is None:
            violations.append(f"platform app catalog missing {app_name}")
            continue

        if app.get("owner") != expected["owner"]:
            violations.append(f"{app_name} owner should be {expected['owner']}")
        if app.get("source", {}).get("path") != expected["source_path"]:
            violations.append(f"{app_name} source.path should be {expected['source_path']}")
        if app.get("deployment", {}).get("applications") != expected["applications"]:
            violations.append(f"{app_name} deployment applications should be {expected['applications']}")
        if app.get("scorecard", {}).get("has_network_policy") is not True:
            violations.append(f"{app_name} should record network policy evidence")

        environments = app.get("environments", [])
        if not any(
            environment.get("name") == expected["environment"]
            and environment.get("namespace") == expected["namespace"]
            and environment.get("route") == expected["route"]
            for environment in environments
        ):
            violations.append(
                f"{app_name} should expose {expected['environment']} in {expected['namespace']} at {expected['route']}"
            )

    return tuple(violations)


def platform_mcp_langfuse_inventory_expectations() -> dict[str, dict[str, Any]]:
    return {
        "platform-mcp": {
            "owner": "platform",
            "source_path": "apps/platform-mcp",
            "applications": ["mcp"],
            "environment": "local",
            "namespace": "mcp",
            "route": "https://mcp.127.0.0.1.sslip.io/mcp",
        },
        "mcp-inspector": {
            "owner": "platform",
            "source_path": "apps/platform-mcp",
            "applications": ["mcp"],
            "environment": "local",
            "namespace": "mcp",
            "route": "https://mcp-console.127.0.0.1.sslip.io",
        },
        "langfuse": {
            "owner": "platform",
            "source_path": "terraform/kubernetes/apps/langfuse",
            "applications": ["langfuse"],
            "environment": "local",
            "namespace": "langfuse",
            "route": "https://langfuse.admin.127.0.0.1.sslip.io",
        },
        "langfuse-trace-chat": {
            "owner": "platform",
            "source_path": "apps/langfuse-demos",
            "applications": ["langfuse-demos"],
            "environment": "dev",
            "namespace": "dev",
            "route": "https://lf-chat.dev.127.0.0.1.sslip.io",
        },
        "langfuse-tool-agent": {
            "owner": "platform",
            "source_path": "apps/langfuse-demos",
            "applications": ["langfuse-demos"],
            "environment": "dev",
            "namespace": "dev",
            "route": "https://lf-agent.dev.127.0.0.1.sslip.io",
        },
        "langfuse-eval-runner": {
            "owner": "platform",
            "source_path": "apps/langfuse-demos",
            "applications": ["langfuse-demos"],
            "environment": "dev",
            "namespace": "dev",
            "route": "https://lf-evals.dev.127.0.0.1.sslip.io",
        },
    }


def application_surface_projection_contract_violations(repo_root: Path) -> tuple[str, ...]:
    catalog = json.loads((repo_root / "catalog" / "platform-apps.json").read_text(encoding="utf-8"))
    surfaces = {
        (app["name"], environment["name"]): {
            "app": app["name"],
            "display_name": app["display_name"],
            "owner": app["owner"],
            "environment": environment["name"],
            "route": environment["route"],
            "rbac_group": environment.get("rbac", {}).get("group"),
        }
        for app in catalog["applications"]
        for environment in app.get("environments", [])
    }
    expected_selectors = {
        "apim-simulator": "app.kubernetes.io/name=subnetcalc-apim-simulator",
        "langfuse": "app.kubernetes.io/name=langfuse",
        "langfuse-trace-chat": "app.kubernetes.io/name=langfuse-trace-chat",
        "langfuse-tool-agent": "app.kubernetes.io/name=langfuse-tool-agent",
        "langfuse-eval-runner": "app.kubernetes.io/name=langfuse-eval-runner",
    }
    docs = backstage_production_catalog_documents(repo_root)
    components = {
        doc["metadata"]["name"]: doc
        for doc in docs
        if doc.get("kind") == "Component"
    }
    launchpad = json.loads(
        (repo_root / "terraform" / "kubernetes" / "config" / "platform-launchpad.apps.json").read_text(
            encoding="utf-8"
        )
    )
    tiles = launchpad["tiles"]
    violations: list[str] = []
    catalog_routes = {
        (surface["app"], surface["environment"], surface["route"])
        for surface in surfaces.values()
    }

    for app, environment in sorted(surfaces):
        surface = surfaces[(app, environment)]
        component = components.get(app)
        if component is None:
            violations.append(f"{app} missing Backstage component")
            continue

        metadata = component.get("metadata", {})
        annotations = metadata.get("annotations", {})
        links = {link["url"]: link for link in metadata.get("links", [])}
        expected_owner = f"group:default/{surface['owner']}"
        expected_selector = expected_selectors.get(app, f"app={app}")

        if metadata.get("title") != surface["display_name"]:
            violations.append(f"{app} Backstage title should match platform app display_name")
        if component.get("spec", {}).get("owner") != expected_owner:
            violations.append(f"{app} Backstage owner should be {expected_owner}")
        if annotations.get("backstage.io/kubernetes-label-selector") != expected_selector:
            violations.append(f"{app} Backstage Kubernetes selector should be {expected_selector}")
        if surface["route"] not in links:
            violations.append(f"{app}/{environment} route missing from Backstage catalog links")

        route_tile = next(
            (
                tile
                for tile in tiles
                if tile.get("service") == app
                and tile.get("environment") == environment
                and tile.get("url") == surface["route"]
            ),
            None,
        )
        if route_tile is None:
            violations.append(f"{app}/{environment} route missing from Launchpad tiles")
            continue
        if route_tile.get("owner") != surface["owner"]:
            violations.append(f"{app}/{environment} Launchpad tile owner should be {surface['owner']}")
        if route_tile.get("rbac_group") != surface["rbac_group"]:
            violations.append(f"{app}/{environment} Launchpad tile rbac_group should be {surface['rbac_group']}")

    for tile in tiles:
        if "service" not in tile or "environment" not in tile:
            continue
        url = tile.get("url", "")
        if "grafana.admin.127.0.0.1.sslip.io/d/" in url:
            continue
        route = (tile["service"], tile["environment"], url)
        if route not in catalog_routes:
            violations.append(
                f"{tile['service']}/{tile['environment']} Launchpad route tile missing from platform app catalog"
            )

    backstage_surface = surfaces.get(("backstage", "local"))
    backstage_observability = next((tile for tile in tiles if tile.get("title") == "Backstage Observability"), None)
    if backstage_surface is None:
        violations.append("backstage/local missing from platform app catalog")
    elif backstage_observability is None:
        violations.append("Backstage Observability tile missing from Launchpad tiles")
    else:
        if backstage_observability.get("service") != backstage_surface["app"]:
            violations.append("Backstage Observability tile service should match backstage/local")
        if backstage_observability.get("owner") != backstage_surface["owner"]:
            violations.append("Backstage Observability tile owner should match backstage/local")
        if backstage_observability.get("environment") != backstage_surface["environment"]:
            violations.append("Backstage Observability tile environment should match backstage/local")
        backstage_links = components.get("backstage", {}).get("metadata", {}).get("links", [])
        if not any(
            link.get("title") == backstage_observability.get("title")
            and link.get("url") == backstage_observability.get("url")
            for link in backstage_links
        ):
            violations.append("Backstage Observability tile missing from Backstage catalog links")

    catalog_metrics = (
        repo_root / "apps" / "backstage" / "packages" / "backend" / "src" / "modules" / "catalogMetrics.ts"
    ).read_text(encoding="utf-8")
    catalog_root = repo_root / "apps" / "backstage"
    for catalog_file in backstage_production_catalog_files(repo_root):
        relative_path = catalog_file.relative_to(catalog_root).as_posix()
        if relative_path not in catalog_metrics:
            violations.append(f"catalog metrics should ingest {relative_path}")
    for fragment in (
        "backstage_catalog_component_locality_total",
        "backstage_catalog_component_links_total",
        "normalizedUrl.includes('/d/')",
    ):
        if fragment not in catalog_metrics:
            violations.append(f"catalog metrics missing {fragment}")

    return tuple(violations)


def ddd_current_service_catalog_surface_contract_violations(repo_root: Path) -> tuple[str, ...]:
    catalog = json.loads((repo_root / "catalog" / "platform-apps.json").read_text(encoding="utf-8"))
    text = (repo_root / "docs" / "ddd" / "ubiquitous-language.md").read_text(encoding="utf-8")
    if "Current app/environment surfaces include" not in text:
        return ("ubiquitous language missing current app/environment surface paragraph",)

    paragraph = text.split("Current app/environment surfaces include", 1)[1].split("\n\n", 1)[0]
    return tuple(
        f"ubiquitous language missing service catalog surface `{app['name']}-{environment['name']}`"
        for app in catalog["applications"]
        for environment in app.get("environments", [])
        if f"`{app['name']}-{environment['name']}`" not in paragraph
    )


def ddd_shared_browser_types_contract_violations(repo_root: Path) -> tuple[str, ...]:
    text = (repo_root / "docs" / "ddd" / "contracts.md").read_text(encoding="utf-8")
    expected = (
        "- **Shared browser types:** the vanilla browser apps keep app-local\n"
        "  `api-types.d.ts` files and import common browser contract types from\n"
        "  `apps/shared/web/api-types.d.ts`. That shared file is a deliberate Shared\n"
        "  Kernel for dependency-free browser apps, not a frontend build package and\n"
        "  not a backend contract generator."
    )
    stale_fragments = (
        "the React and TypeScript-Vite frontends both consume",
        "@subnetcalc/shared-frontend",
    )
    violations: list[str] = []

    if expected not in text:
        violations.append("DDD contracts should describe shared browser types for vanilla browser apps")
    for fragment in stale_fragments:
        if fragment in text:
            violations.append(f"DDD contracts should not reference stale browser type contract {fragment}")

    return tuple(violations)


def docs_app_no_npm_apim_asset_contract_violations(repo_root: Path) -> tuple[str, ...]:
    text = (repo_root / "docs" / "apps-no-npm.md").read_text(encoding="utf-8")
    expected = (
        "`apps/apim-simulator/app/internal/app/web` is now the static operator console:\n"
        "`index.html`, `style.css`, and `app.js` are embedded in the Go runtime."
    )
    stale = (
        "`apps/apim-simulator/app/internal/app/web` is now the static operator console:\n"
        "`index.html`, `styles.css`, and `app.js` are embedded in the Go runtime."
    )
    violations: list[str] = []

    if expected not in text:
        violations.append("docs/apps-no-npm.md should document APIM console style.css")
    if stale in text:
        violations.append("docs/apps-no-npm.md should not document retired APIM console styles.css")

    return tuple(violations)


def kubernetes_app_c4_go_runtime_docs_contract_violations(repo_root: Path) -> tuple[str, ...]:
    paths = (
        repo_root / "terraform" / "kubernetes" / "docs" / "apps-c4.md",
        repo_root / "terraform" / "kubernetes" / "docs" / "diagrams" / "apps-c4" / "02-container-subnetcalc.mmd",
        repo_root / "terraform" / "kubernetes" / "docs" / "diagrams" / "apps-c4" / "03-container-sentiment.mmd",
        repo_root / "terraform" / "kubernetes" / "docs" / "diagrams" / "apps-c4" / "06-dynamic-subnetcalc-api-path.mmd",
        repo_root / "terraform" / "kubernetes" / "docs" / "diagrams" / "apps-c4" / "07-dynamic-subnetcalc-range-source-split.mmd",
        repo_root / "terraform" / "kubernetes" / "docs" / "diagrams" / "apps-c4" / "08-dynamic-sentiment-api-path.mmd",
        repo_root / "terraform" / "kubernetes" / "docs" / "diagrams" / "apps-c4" / "13-journey-sentiment-request.mmd",
    )
    text = "\n".join(path.read_text(encoding="utf-8") for path in paths)
    violations: list[str] = []

    for stale in ("FastAPI", "SST classifier"):
        if stale in text:
            violations.append(f"Kubernetes app C4 docs should not reference legacy {stale}")
    for expected in (
        "in-process Go lexicon classifier",
        'Container(api, "subnetcalc-api", "Go API"',
    ):
        if expected not in text:
            violations.append(f"Kubernetes app C4 docs missing {expected}")

    return tuple(violations)


def external_runtime_image_ref_expectations() -> dict[str, dict[str, int]]:
    return {
        "apps/sentiment/app/Dockerfile": {
            "FROM dhi.io/static:20260413-alpine3.23": 1,
        },
        "apps/backstage/Dockerfile": {
            "FROM dhi.io/node:22-debian13 AS runtime": 1,
        },
        "apps/sentiment/compose.yml": {
            "image: quay.io/keycloak/keycloak:26.6.3": 1,
            "image: quay.io/oauth2-proxy/oauth2-proxy:v7.15.2@sha256:aa0bd8dd5ab0c78e4c91c92755ad573a5f92241f88138b4141b8ec803463b4fd": 1,
        },
        "apps/subnetcalc/app/Dockerfile": {
            "FROM dhi.io/static:20260413-alpine3.23": 1,
        },
        "terraform/kubernetes/apps/gitea-actions-runner/deployment.yaml": {
            "image: docker:29.4.3-cli": 1,
            "image: gitea/act_runner:0.4.1": 2,
            "image: kindest/node:v1.36.1@sha256:3489c7674813ba5d8b1a9977baea8a6e553784dab7b84759d1014dbd78f7ebd5": 1,
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


def external_runtime_image_ref_expectation_count() -> int:
    return sum(len(expectations) for expectations in external_runtime_image_ref_expectations().values())


def external_runtime_image_ref_contract_violations(repo_root: Path) -> tuple[str, ...]:
    violations: list[str] = []

    for relative_path, expectations in external_runtime_image_ref_expectations().items():
        content = (repo_root / relative_path).read_text(encoding="utf-8")
        for needle, expected_count in expectations.items():
            actual_count = content.count(needle)
            if actual_count != expected_count:
                violations.append(
                    f"{relative_path} should contain {needle!r} {expected_count} time(s), got {actual_count}"
                )

    return tuple(violations)


def preload_image_snapshot_files() -> tuple[str, ...]:
    return (
        "kubernetes/kind/preload-images.txt",
        "kubernetes/lima/preload-images.txt",
        "kubernetes/slicer/preload-images.txt",
        "kubernetes/docker-desktop/preload-images.txt",
    )


def preload_image_required_refs() -> tuple[str, ...]:
    return (
        "ghcr.io/nginx/nginx-gateway-fabric:2.5.1",
        "ghcr.io/nginx/nginx-gateway-fabric/nginx:2.5.1",
        "docker:29.4.3-cli",
        "gitea/act_runner:0.4.1",
        "kindest/node:v1.36.1@sha256:3489c7674813ba5d8b1a9977baea8a6e553784dab7b84759d1014dbd78f7ebd5",
        "dhi.io/golang:1.26-alpine3.23-dev",
        "dhi.io/static:20260413-alpine3.23",
        "python:3.12.13-alpine3.23",
        "docker.io/curlimages/curl:8.19.0",
        "curlimages/curl:8.19.0",
    )


def preload_image_retired_refs() -> tuple[str, ...]:
    return (
        "dhi.io/node:22-debian13-dev",
        "golang:1.26.2-alpine3.23",
        "oven/bun:1.3.13",
        "oven/bun:1.3.13-alpine",
        "node:22-alpine",
    )


def preload_image_lock_refs() -> tuple[str, ...]:
    return (
        "ghcr.io/nginx/nginx-gateway-fabric:2.5.1",
        "docker:29.4.3-cli",
        "gitea/act_runner:0.4.1",
        "kindest/node:v1.36.1@sha256:3489c7674813ba5d8b1a9977baea8a6e553784dab7b84759d1014dbd78f7ebd5",
        "python:3.12.13-alpine3.23",
        "docker.io/curlimages/curl:8.19.0",
        "curlimages/curl:8.19.0",
    )


def preload_image_artifact_contract_violations(repo_root: Path) -> tuple[str, ...]:
    violations: list[str] = []

    for relative_path in preload_image_snapshot_files():
        content = (repo_root / relative_path).read_text(encoding="utf-8")
        for image_ref in preload_image_required_refs():
            if image_ref not in content:
                violations.append(f"{relative_path} missing preload image {image_ref}")
        for image_ref in preload_image_retired_refs():
            if image_ref in content:
                violations.append(f"{relative_path} should not include retired preload image {image_ref}")

    lock_file = (repo_root / "terraform" / "kubernetes" / "scripts" / "preload-images.linux-arm64.lock").read_text(
        encoding="utf-8"
    )
    for image_ref in preload_image_lock_refs():
        pattern = re.compile(rf"^{re.escape(image_ref)}\t.+@sha256:[0-9a-f]+$", re.MULTILINE)
        if not pattern.search(lock_file):
            violations.append(f"preload-images.linux-arm64.lock missing digest lock for {image_ref}")
    for image_ref in preload_image_retired_refs():
        if f"{image_ref}\t" in lock_file:
            violations.append(f"preload-images.linux-arm64.lock should not include retired {image_ref}")

    return tuple(violations)


def langfuse_runtime_image_refs() -> tuple[str, ...]:
    return (
        "docker.io/langfuse/langfuse:3",
        "docker.io/langfuse/langfuse-worker:3",
        "docker.io/postgres:17.6-alpine",
        "docker.io/redis:8.2.7-alpine",
        "docker.io/clickhouse/clickhouse-server:25.5.11",
        "cgr.dev/chainguard/minio:latest",
        "cgr.dev/chainguard/busybox:latest",
    )


def langfuse_registry_policy_patterns() -> tuple[str, ...]:
    return (
        '"docker.io/langfuse/*"',
        '"docker.io/postgres:*"',
        '"docker.io/redis:*"',
        '"docker.io/clickhouse/*"',
        '"cgr.dev/*"',
    )


def langfuse_image_artifact_contract_violations(repo_root: Path) -> tuple[str, ...]:
    violations: list[str] = []
    policy = (
        repo_root
        / "terraform"
        / "kubernetes"
        / "cluster-policies"
        / "kyverno"
        / "shared"
        / "restrict-image-registries.yaml"
    ).read_text(encoding="utf-8")

    for required_policy in langfuse_registry_policy_patterns():
        if required_policy not in policy:
            violations.append(f"restrict-image-registries.yaml missing {required_policy}")

    for relative_path in preload_image_snapshot_files():
        lines = (repo_root / relative_path).read_text(encoding="utf-8").splitlines()
        for image_ref in langfuse_runtime_image_refs():
            if image_ref not in lines:
                violations.append(f"{relative_path} missing Langfuse preload image {image_ref}")
        for retired_prefix in ("dhi.io/langfuse:", "dhi.io/postgres:", "dhi.io/redis:"):
            if any(line.startswith(retired_prefix) for line in lines):
                violations.append(f"{relative_path} should not include retired {retired_prefix} image")
        if any("bitnamilegacy" in line for line in lines if "langfuse" in line.lower()):
            violations.append(f"{relative_path} should not include Bitnami legacy Langfuse images")

    docs = load_yaml_all(repo_root / "terraform" / "kubernetes" / "apps" / "langfuse" / "all.yaml")
    redis = next(
        (
            doc
            for doc in docs
            if doc
            and doc.get("kind") == "StatefulSet"
            and doc.get("metadata", {}).get("name") == "langfuse-redis"
        ),
        None,
    )
    if not redis:
        violations.append("terraform/kubernetes/apps/langfuse/all.yaml missing langfuse-redis StatefulSet")
    else:
        redis_pod_spec = redis["spec"]["template"]["spec"]
        redis_container = redis_pod_spec["containers"][0]
        if redis_pod_spec.get("securityContext", {}).get("fsGroup") != 1000:
            violations.append("langfuse-redis pod securityContext should set fsGroup 1000")
        container_security = redis_container.get("securityContext", {})
        if container_security.get("runAsUser") != 999:
            violations.append("langfuse-redis container securityContext should set runAsUser 999")
        if container_security.get("runAsGroup") != 1000:
            violations.append("langfuse-redis container securityContext should set runAsGroup 1000")

    network_policy = next(
        (
            doc
            for doc in docs
            if doc
            and doc.get("kind") == "NetworkPolicy"
            and doc.get("metadata", {}).get("name") == "langfuse-runtime"
        ),
        None,
    )
    if not network_policy:
        violations.append("terraform/kubernetes/apps/langfuse/all.yaml missing langfuse-runtime NetworkPolicy")
        return tuple(violations)

    if network_policy.get("metadata", {}).get("namespace") != "langfuse":
        violations.append("langfuse-runtime NetworkPolicy should live in the langfuse namespace")
    spec = network_policy.get("spec", {})
    if set(spec.get("policyTypes", [])) != {"Ingress", "Egress"}:
        violations.append("langfuse-runtime NetworkPolicy should enforce ingress and egress")

    ingress_ports = {
        str(port["port"])
        for rule in spec.get("ingress", [])
        for port in rule.get("ports", [])
    }
    egress_ports = {
        str(port["port"])
        for rule in spec.get("egress", [])
        for port in rule.get("ports", [])
    }
    for required_port in ("3000", "3030", "5432", "6379", "8123", "9000"):
        if required_port not in ingress_ports:
            violations.append(f"langfuse-runtime NetworkPolicy ingress missing port {required_port}")
        if required_port not in egress_ports:
            violations.append(f"langfuse-runtime NetworkPolicy egress missing port {required_port}")

    dns_rules = [
        rule
        for rule in spec.get("egress", [])
        if any(str(port["port"]) == "53" for port in rule.get("ports", []))
    ]
    dns_peers = [peer for rule in dns_rules for peer in rule.get("to", [])]
    if not any(
        peer.get("namespaceSelector", {}).get("matchLabels", {}).get("kubernetes.io/metadata.name") == "kube-system"
        and peer.get("podSelector", {}).get("matchLabels", {}).get("k8s-app") == "kube-dns"
        for peer in dns_peers
    ):
        violations.append("langfuse-runtime NetworkPolicy should allow egress DNS to kube-dns")

    return tuple(violations)


def subnetcalc_frontend_local_replica_contract_violations(repo_root: Path) -> tuple[str, ...]:
    docs = load_yaml_all(repo_root / "terraform" / "kubernetes" / "apps" / "workloads" / "base" / "all.yaml")
    frontend = next(
        (
            doc
            for doc in docs
            if doc
            and doc.get("kind") == "Deployment"
            and doc.get("metadata", {}).get("name") == "subnetcalc-frontend"
        ),
        None,
    )
    if not frontend:
        return ("terraform/kubernetes/apps/workloads/base/all.yaml missing subnetcalc-frontend Deployment",)

    violations: list[str] = []
    spec = frontend.get("spec", {})
    if spec.get("replicas") != 1:
        violations.append("subnetcalc-frontend should stay single-replica for local laptop clusters")
    pod_spec = spec.get("template", {}).get("spec", {})
    if "topologySpreadConstraints" in pod_spec:
        violations.append("subnetcalc-frontend should not set topologySpreadConstraints in local base manifests")

    return tuple(violations)


def app_compose_files(repo_root: Path) -> list[Path]:
    return sorted((repo_root / "apps").glob("*/compose.yml"))


def iter_go_app_roots(repo_root: Path) -> Iterator[Path]:
    yield from sorted(
        app_root
        for app_root in (repo_root / "apps").iterdir()
        if (app_root / "app" / "go.mod").exists()
    )


def iter_go_app_workflow_roots(repo_root: Path) -> Iterator[Path]:
    yield from (
        app_root
        for app_root in iter_go_app_roots(repo_root)
        if (app_root / ".gitea" / "workflows" / "build-images.yaml").exists()
    )


def iter_go_app_wrapper_roots(repo_root: Path) -> Iterator[Path]:
    yield from (
        app_root
        for app_root in iter_go_app_roots(repo_root)
        if (app_root / "Makefile").exists()
    )


def iter_go_app_dockerfiles(repo_root: Path) -> Iterator[Path]:
    yield from sorted(
        app_root / "app" / "Dockerfile"
        for app_root in iter_go_app_roots(repo_root)
        if (app_root / "app" / "Dockerfile").exists()
    )


def go_app_makefile_build_linux_contract_violations(repo_root: Path) -> tuple[str, ...]:
    violations: list[str] = []

    for app_root in iter_go_app_roots(repo_root):
        makefile = app_root / "app" / "Makefile"
        if not makefile.exists():
            continue
        app_name = app_root.name
        binary_name = "apim-simulator" if app_name == "apim-simulator" else app_name
        content = makefile.read_text(encoding="utf-8")
        if "build-linux:" not in content:
            violations.append(f"{app_name} Makefile missing build-linux target")
            continue
        target_body = content.split("build-linux:", 1)[1].split("\n\n", 1)[0]
        if "CGO_ENABLED=0 GOOS=linux GOARCH=$${GOARCH:-$(" not in target_body:
            violations.append(f"{app_name} build-linux should use the common Linux Go environment prefix")
        expected_output = f"-o .run/{binary_name} ./cmd/{binary_name}"
        if expected_output not in target_body:
            violations.append(f"{app_name} build-linux should write {expected_output}")
        if "$(BINARY)" in target_body:
            violations.append(f"{app_name} build-linux should not hide the runtime binary path behind BINARY")

    return tuple(violations)


def go_app_makefile_workflow_contract_violations(repo_root: Path) -> tuple[str, ...]:
    help_headings = {
        "apim-simulator": "APIM Simulator app:",
        "chatgpt-sim": "ChatGPT Sim app:",
        "idp-core": "IDP Core app:",
        "langfuse-demos": "Langfuse demo apps:",
        "platform-mcp": "Platform MCP app:",
        "sentiment": "Sentiment app:",
        "subnetcalc": "Subnetcalc app:",
    }
    violations: list[str] = []

    for app_root in iter_go_app_roots(repo_root):
        app_name = app_root.name
        makefile = app_root / "app" / "Makefile"
        if not makefile.exists():
            violations.append(f"{app_name} missing app Makefile")
            continue
        content = makefile.read_text(encoding="utf-8")
        relative_path = makefile.relative_to(repo_root)

        for target in ("help", "test", "build", "build-linux", "clean"):
            if not re.search(rf"(^|[ \t]){re.escape(target)}([ \t]|$)", content.splitlines()[0]):
                violations.append(f"{relative_path} .PHONY missing {target}")
            if f"\n{target}:" not in f"\n{content}":
                violations.append(f"{relative_path} missing {target} target")

        build_body = content.split("build:", 1)[1].split("\n\n", 1)[0] if "build:" in content else ""
        if "\n\t@mkdir -p .run" not in f"\n{build_body}":
            violations.append(f"{relative_path} build target should create .run")
        if "go build" not in build_body:
            violations.append(f"{relative_path} build target should run go build")
        for fragment in ("-trimpath", '-ldflags="-s -w"'):
            if fragment not in build_body:
                violations.append(f"{relative_path} build target missing {fragment}")

        expected_heading = help_headings.get(app_name)
        if expected_heading is None:
            violations.append(f"{app_name} missing Makefile help heading contract")
        elif expected_heading not in content:
            violations.append(f"{relative_path} help should include {expected_heading}")
        if "Build the Linux binary used by compose/kind images" not in content:
            violations.append(f"{relative_path} help should describe build-linux")
        for target in ("test", "build", "build-linux", "clean"):
            if f"  {target}" not in content:
                violations.append(f"{relative_path} help should list {target}")

        clean_body = content.split("clean:", 1)[1].split("\n\n", 1)[0] if "clean:" in content else ""
        if "rm -rf .run" not in clean_body:
            violations.append(f"{relative_path} clean target should remove .run")

    return tuple(violations)


def service_dockerfile(compose_path: Path, service: dict[str, Any]) -> Path | None:
    build = service.get("build")
    if not isinstance(build, dict):
        return None

    context = build.get("context", ".")
    dockerfile = build.get("dockerfile", "Dockerfile")
    if not isinstance(context, str) or not isinstance(dockerfile, str):
        return None

    context_path = (compose_path.parent / context).resolve()
    return (context_path / dockerfile).resolve()


def is_go_app_dockerfile(repo_root: Path, dockerfile: Path) -> bool:
    try:
        relative = dockerfile.relative_to(repo_root.resolve())
    except ValueError:
        return False

    return (
        len(relative.parts) >= 4
        and relative.parts[0] == "apps"
        and relative.parts[2] == "app"
        and relative.name == "Dockerfile"
        and (dockerfile.parent / "go.mod").exists()
    )


def iter_go_app_compose_services(repo_root: Path) -> Iterator[tuple[Path, str, dict[str, Any], Path]]:
    for compose_path in app_compose_files(repo_root):
        compose = load_yaml(compose_path)
        for service_name, service in compose.get("services", {}).items():
            dockerfile = service_dockerfile(compose_path, service)
            if dockerfile is None or not is_go_app_dockerfile(repo_root, dockerfile):
                continue

            yield compose_path, service_name, service, dockerfile


def iter_browser_sso_compose_services(repo_root: Path) -> Iterator[tuple[Path, Path, dict[str, Any]]]:
    for compose_path in app_compose_files(repo_root):
        app_root = compose_path.parent
        web_dir = app_root / "app" / "internal" / "app" / "web"
        if not web_dir.exists():
            continue

        compose = load_yaml(compose_path)
        oauth2_proxy = compose.get("services", {}).get("oauth2-proxy")
        if not isinstance(oauth2_proxy, dict):
            continue

        yield compose_path, web_dir, oauth2_proxy
