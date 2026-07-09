#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

teardown() {
  rm -rf "${REPO_ROOT}/apps/zz-test-dockerfile-runtime"
  rm -rf "${REPO_ROOT}/apps/zz-test-compose-healthcheck"
  rm -rf "${REPO_ROOT}/apps/zz-test-compose-hardening"
  rm -rf "${REPO_ROOT}/apps/zz-test-sso-allowlist"
}

@test "app runtime tests share compose service discovery helpers" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import iter_browser_sso_compose_services, iter_go_app_dockerfiles

repo_root = Path(os.environ["REPO_ROOT"])
test_file = repo_root / "tests" / "validate-app-runtime-surfaces.bats"
helper = repo_root / "tests" / "app_contracts.py"
content = test_file.read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content.splitlines()
    if "Go app Dockerfile discovery should move" not in line
]

assert helper.exists(), "tests/app_contracts.py should own reusable app contract helpers"
assert content.count("\ndef service_dockerfile") == 0, "inline service_dockerfile helpers should move to tests/app_contracts.py"
assert content.count("\ndef is_go_app_dockerfile") == 0, "inline Go Dockerfile predicates should move to tests/app_contracts.py"
assert not any('repo_root / "apps").glob("*/app/Dockerfile")' in line for line in contract_lines), "Go app Dockerfile discovery should move to tests/app_contracts.py"
assert "iter_go_app_compose_services" in content, "runtime contracts should call the shared compose service iterator"
assert "iter_browser_sso_compose_services" in content, "browser SSO contracts should call the shared compose service iterator"
assert "iter_go_app_dockerfiles" in content, "Dockerfile contracts should call the shared Go app Dockerfile iterator"
assert callable(iter_browser_sso_compose_services)
assert callable(iter_go_app_dockerfiles)

print("validated shared app contract helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared app contract helper usage"* ]]
}

@test "lightweight app source trees avoid literal unknown tokens" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import lightweight_app_source_unknown_token_contract_violations

violations = lightweight_app_source_unknown_token_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated lightweight app source unknown-token contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated lightweight app source unknown-token contract"* ]]
}

@test "app discovery metadata avoids literal unknown placeholders" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import app_discovery_metadata_unknown_token_contract_violations

violations = app_discovery_metadata_unknown_token_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated app discovery metadata unknown-token contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated app discovery metadata unknown-token contract"* ]]
}

@test "browser Go apps share static asset serving helpers" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import browser_app_static_asset_go_contract_violations

violations = browser_app_static_asset_go_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated browser Go static asset helper contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated browser Go static asset helper contract"* ]]
}

@test "browser Go app health payloads expose canonical dependency footprints" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import browser_app_health_dependency_footprint_contract_violations

violations = browser_app_health_dependency_footprint_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated browser Go app health dependency footprint contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated browser Go app health dependency footprint contract"* ]]
}

@test "app runtime tests share compose hardening helpers" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import compose_hardening_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
test_file = repo_root / "tests" / "validate-app-runtime-surfaces.bats"
content = test_file.read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content.splitlines()
    if "compose hardening policy should move" not in line
]

assert callable(compose_hardening_contract_violations)
assert "compose_hardening_contract_violations" in content, "compose hardening contracts should call tests/app_contracts.py"
assert not any("go_service_expectation =" in line for line in contract_lines), "compose hardening policy should move to tests/app_contracts.py"
assert not any("explicit_expectations =" in line for line in contract_lines), "compose hardening policy should move to tests/app_contracts.py"

print("validated shared compose hardening helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared compose hardening helper usage"* ]]
}

@test "app runtime tests share Go compose healthcheck helpers" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import go_compose_healthcheck_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
test_file = repo_root / "tests" / "validate-app-runtime-surfaces.bats"
content = test_file.read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content.splitlines()
    if "Go compose healthcheck policy should move" not in line
]

assert callable(go_compose_healthcheck_contract_violations)
assert "go_compose_healthcheck_contract_violations" in content, "Go compose healthcheck contracts should call tests/app_contracts.py"
assert not any('healthcheck = service.get("healthcheck"' in line for line in contract_lines), "Go compose healthcheck policy should move to tests/app_contracts.py"
assert not any('healthcheck[0] == "CMD"' in line for line in contract_lines), "Go compose healthcheck policy should move to tests/app_contracts.py"
assert not any('healthcheck[-1] == "healthcheck"' in line for line in contract_lines), "Go compose healthcheck policy should move to tests/app_contracts.py"

print("validated shared Go compose healthcheck helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared Go compose healthcheck helper usage"* ]]
}

@test "app runtime tests share browser SSO static allowlist helpers" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import browser_sso_static_allowlist_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
test_file = repo_root / "tests" / "validate-app-runtime-surfaces.bats"
content = test_file.read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content.splitlines()
    if "browser SSO static allowlist policy should move" not in line
]

assert callable(browser_sso_static_allowlist_contract_violations)
assert "browser_sso_static_allowlist_contract_violations" in content, "browser SSO static allowlist contracts should call tests/app_contracts.py"
assert not any("skip_auth = next" in line for line in contract_lines), "browser SSO static allowlist policy should move to tests/app_contracts.py"
assert not any('"app-shell\\\\.css" in skip_auth' in line for line in contract_lines), "browser SSO static allowlist policy should move to tests/app_contracts.py"
assert not any('"styles\\\\.css" not in skip_auth' in line for line in contract_lines), "browser SSO static allowlist policy should move to tests/app_contracts.py"

print("validated shared browser SSO static allowlist helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared browser SSO static allowlist helper usage"* ]]
}

@test "app runtime tests share Dockerfile runtime user helpers" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import dockerfile_runtime_user_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
test_file = repo_root / "tests" / "validate-app-runtime-surfaces.bats"
content = test_file.read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content.splitlines()
    if "Dockerfile runtime user policy should move" not in line
]

assert callable(dockerfile_runtime_user_contract_violations)
assert "dockerfile_runtime_user_contract_violations" in content, "Dockerfile runtime user contracts should call tests/app_contracts.py"
assert not any("user_lines =" in line for line in contract_lines), "Dockerfile runtime user policy should move to tests/app_contracts.py"
assert not any('actual_user == "65532:65532"' in line for line in contract_lines), "Dockerfile runtime user policy should move to tests/app_contracts.py"

print("validated shared Dockerfile runtime user helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared Dockerfile runtime user helper usage"* ]]
}

@test "app runtime tests share sentiment compose diagnostics helpers" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import sentiment_compose_diagnostics_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
test_file = repo_root / "tests" / "validate-app-runtime-surfaces.bats"
content = test_file.read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content.splitlines()
    if "sentiment compose diagnostics policy should move" not in line
]

assert callable(sentiment_compose_diagnostics_contract_violations)
assert "sentiment_compose_diagnostics_contract_violations" in content, "sentiment compose diagnostics contracts should call tests/app_contracts.py"
assert not any('frontend = compose["services"]["sentiment-auth-frontend"]' in line for line in contract_lines), "sentiment compose diagnostics policy should move to tests/app_contracts.py"
assert not any('assert env["SHOW_NETWORK_PATH"]' in line for line in contract_lines), "sentiment compose diagnostics policy should move to tests/app_contracts.py"
assert not any('json.loads(env["NETWORK_HOPS"])' in line for line in contract_lines), "sentiment compose diagnostics policy should move to tests/app_contracts.py"

print("validated shared sentiment compose diagnostics helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared sentiment compose diagnostics helper usage"* ]]
}

@test "app runtime tests share subnetcalc compose topology helpers" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import subnetcalc_compose_topology_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
test_file = repo_root / "tests" / "validate-app-runtime-surfaces.bats"
content = test_file.read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content.splitlines()
    if "subnetcalc compose topology policy should move" not in line
]

assert callable(subnetcalc_compose_topology_contract_violations)
assert "subnetcalc_compose_topology_contract_violations" in content, "subnetcalc compose topology contracts should call tests/app_contracts.py"
assert not any("default_services =" in line for line in contract_lines), "subnetcalc compose topology policy should move to tests/app_contracts.py"
assert not any("sso_services =" in line for line in contract_lines), "subnetcalc compose topology policy should move to tests/app_contracts.py"
assert not any('services["oauth2-proxy"]["command"].count("--cookie-refresh=1h")' in line for line in contract_lines), "subnetcalc compose topology policy should move to tests/app_contracts.py"

print("validated shared subnetcalc compose topology helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared subnetcalc compose topology helper usage"* ]]
}

@test "app runtime tests share subnetcalc runtime config helpers" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import subnetcalc_runtime_config_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
test_file = repo_root / "tests" / "validate-app-runtime-surfaces.bats"
content = test_file.read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content.splitlines()
    if "subnetcalc runtime config policy should move" not in line
]

assert callable(subnetcalc_runtime_config_contract_violations)
assert "subnetcalc_runtime_config_contract_violations" in content, "subnetcalc runtime config contracts should call tests/app_contracts.py"
assert not any('app_js = (repo_root / "apps/subnetcalc/app/internal/app/web/app.js")' in line for line in contract_lines), "subnetcalc runtime config policy should move to tests/app_contracts.py"
assert not any('assert \'"authMethod"\' in server_go' in line for line in contract_lines), "subnetcalc runtime config policy should move to tests/app_contracts.py"
assert not any('"window.SUBNETCALC_RUNTIME_CONFIG" in server_go' in line for line in contract_lines), "subnetcalc runtime config policy should move to tests/app_contracts.py"

print("validated shared subnetcalc runtime config helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared subnetcalc runtime config helper usage"* ]]
}

@test "app runtime tests share sign-out landing page helpers" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import shared_sign_out_page_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
test_file = repo_root / "tests" / "validate-app-runtime-surfaces.bats"
content = test_file.read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content.splitlines()
    if "sign-out landing page policy should move" not in line
]

assert callable(shared_sign_out_page_contract_violations)
assert "shared_sign_out_page_contract_violations" in content, "sign-out landing page contracts should call tests/app_contracts.py"
assert not any("appshell.SignedOutPage" in line and "assert" in line for line in contract_lines), "sign-out landing page policy should move to tests/app_contracts.py"
assert not any('AppName:     "IPv4 Subnet Calculator"' in line and "assert" in line for line in contract_lines), "sign-out landing page policy should move to tests/app_contracts.py"
assert not any('for text in ("Signed out", "Sign in now", "/.auth/login/sso")' in line for line in contract_lines), "sign-out landing page policy should move to tests/app_contracts.py"

print("validated shared sign-out landing page helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared sign-out landing page helper usage"* ]]
}

@test "app runtime tests share Kubernetes workload runtime user helpers" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import kubernetes_workload_runtime_user_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
test_file = repo_root / "tests" / "validate-app-runtime-surfaces.bats"
content = test_file.read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content.splitlines()
    if "Kubernetes workload runtime user policy should move" not in line
]

assert callable(kubernetes_workload_runtime_user_contract_violations)
assert "kubernetes_workload_runtime_user_contract_violations" in content, "Kubernetes workload runtime user contracts should call tests/app_contracts.py"
assert not any('"sentiment-api": {"runAsUser": 1000' in line for line in contract_lines), "Kubernetes workload runtime user policy should move to tests/app_contracts.py"
assert not any('pod_security = deployment["spec"]["template"]["spec"].get("securityContext", {})' in line for line in contract_lines), "Kubernetes workload runtime user policy should move to tests/app_contracts.py"
assert not any('for deployment_name, expected_security in expected.items()' in line for line in contract_lines), "Kubernetes workload runtime user policy should move to tests/app_contracts.py"

print("validated shared Kubernetes workload runtime user helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared Kubernetes workload runtime user helper usage"* ]]
}

@test "app runtime tests share browser router auth and API routing helpers" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import browser_router_auth_api_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
test_file = repo_root / "tests" / "validate-app-runtime-surfaces.bats"
content = test_file.read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content.splitlines()
    if "browser router auth/API policy should move" not in line
]

assert callable(browser_router_auth_api_contract_violations)
assert "browser_router_auth_api_contract_violations" in content, "browser router auth/API contracts should call tests/app_contracts.py"
assert not any('"subnetcalc-router-nginx"' in line for line in contract_lines), "browser router auth/API policy should move to tests/app_contracts.py"
assert not any('"sentiment-router-nginx"' in line for line in contract_lines), "browser router auth/API policy should move to tests/app_contracts.py"
assert not any('"proxy_pass http://subnetcalc-apim-simulator.apim.svc.cluster.local:8000;"' in line for line in contract_lines), "browser router auth/API policy should move to tests/app_contracts.py"
assert not any('"proxy_set_header Authorization' in line for line in contract_lines), "browser router auth/API policy should move to tests/app_contracts.py"

print("validated shared browser router auth/API helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared browser router auth/API helper usage"* ]]
}

@test "app runtime tests share sentiment Kubernetes frontend and APIM helpers" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import sentiment_kubernetes_frontend_apim_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
test_file = repo_root / "tests" / "validate-app-runtime-surfaces.bats"
content = test_file.read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content[
        content.index('@test "sentiment router protects the frontend and sends API calls through APIM"'):
    ].splitlines()
    if "sentiment Kubernetes frontend/APIM policy should move" not in line
]

assert callable(sentiment_kubernetes_frontend_apim_contract_violations)
assert "sentiment_kubernetes_frontend_apim_contract_violations" in content, "sentiment Kubernetes frontend/APIM contracts should call tests/app_contracts.py"
assert not any('"NETWORK_HOPS"' in line for line in contract_lines), "sentiment Kubernetes frontend/APIM policy should move to tests/app_contracts.py"
assert not any('"sentiment-api-dev"' in line for line in contract_lines), "sentiment Kubernetes frontend/APIM policy should move to tests/app_contracts.py"
assert not any('"subnetcalc-apim-simulator-config"' in line for line in contract_lines), "sentiment Kubernetes frontend/APIM policy should move to tests/app_contracts.py"
assert not any('"X-Apim-Bypass-Subscription"' in line for line in contract_lines), "sentiment Kubernetes frontend/APIM policy should move to tests/app_contracts.py"

print("validated shared sentiment Kubernetes frontend/APIM helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared sentiment Kubernetes frontend/APIM helper usage"* ]]
}

@test "app runtime tests share sentiment API Kubernetes runtime helpers" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import sentiment_api_kubernetes_runtime_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
test_file = repo_root / "tests" / "validate-app-runtime-surfaces.bats"
content = test_file.read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content[
        content.index('@test "Go sentiment workload has a bounded laptop runtime profile and health probes"'):
    ].splitlines()
    if "sentiment API Kubernetes runtime policy should move" not in line
]

assert callable(sentiment_api_kubernetes_runtime_contract_violations)
assert "sentiment_api_kubernetes_runtime_contract_violations" in content, "sentiment API Kubernetes runtime contracts should call tests/app_contracts.py"
assert not any('"OIDC_JWKS_URI"' in line for line in contract_lines), "sentiment API Kubernetes runtime policy should move to tests/app_contracts.py"
assert not any('"768Mi"' in line for line in contract_lines), "sentiment API Kubernetes runtime policy should move to tests/app_contracts.py"
assert not any('"/api/v1/health/ready"' in line for line in contract_lines), "sentiment API Kubernetes runtime policy should move to tests/app_contracts.py"

print("validated shared sentiment API Kubernetes runtime helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared sentiment API Kubernetes runtime helper usage"* ]]
}

@test "app runtime tests share ChatGPT Sim compose LLM and Langfuse helpers" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import chatgpt_sim_compose_llm_langfuse_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
test_file = repo_root / "tests" / "validate-app-runtime-surfaces.bats"
content = test_file.read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content[
        content.index('@test "chatgpt-sim compose can target external OpenAI-compatible LLMs and Langfuse"'):
    ].splitlines()
    if "ChatGPT Sim compose LLM/Langfuse policy should move" not in line
]

assert callable(chatgpt_sim_compose_llm_langfuse_contract_violations)
assert "chatgpt_sim_compose_llm_langfuse_contract_violations" in content, "ChatGPT Sim compose LLM/Langfuse contracts should call tests/app_contracts.py"
assert not any('"LLM_URL"' in line for line in contract_lines), "ChatGPT Sim compose LLM/Langfuse policy should move to tests/app_contracts.py"
assert not any('"LANGFUSE_TIMEOUT_SECONDS"' in line for line in contract_lines), "ChatGPT Sim compose LLM/Langfuse policy should move to tests/app_contracts.py"
assert not any('"${PLATFORM_LLM_MODEL:-go-local-openai-compatible-stub}"' in line for line in contract_lines), "ChatGPT Sim compose LLM/Langfuse policy should move to tests/app_contracts.py"

print("validated shared ChatGPT Sim compose LLM/Langfuse helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared ChatGPT Sim compose LLM/Langfuse helper usage"* ]]
}

@test "app runtime tests share Gitea workflow Go image build helpers" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import gitea_workflow_go_image_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
test_file = repo_root / "tests" / "validate-app-runtime-surfaces.bats"
content = test_file.read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content[
        content.index('@test "app Gitea workflows build the default Go runtime images"'):
    ].splitlines()
    if "Gitea workflow Go image policy should move" not in line
]

assert callable(gitea_workflow_go_image_contract_violations)
assert "gitea_workflow_go_image_contract_violations" in content, "Gitea workflow Go image contracts should call tests/app_contracts.py"
assert not any('"apps/sentiment/.gitea/workflows/build-images.yaml"' in line for line in contract_lines), "Gitea workflow Go image policy should move to tests/app_contracts.py"
assert not any('"docker build --provenance=false -t' in line for line in contract_lines), "Gitea workflow Go image policy should move to tests/app_contracts.py"
assert not any('"frontend-typescript-vite/Dockerfile"' in line for line in contract_lines), "Gitea workflow Go image policy should move to tests/app_contracts.py"

print("validated shared Gitea workflow Go image helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared Gitea workflow Go image helper usage"* ]]
}

@test "app runtime tests share subnetcalc runtime-config response helpers" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import subnetcalc_runtime_config_response_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
test_file = repo_root / "tests" / "validate-app-runtime-surfaces.bats"
content = test_file.read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content[
        content.index('@test "subnetcalc Go frontend serves runtime config directly from the binary"'):
    ].splitlines()
    if "subnetcalc runtime-config response policy should move" not in line
]

assert callable(subnetcalc_runtime_config_response_contract_violations)
assert "subnetcalc_runtime_config_response_contract_violations" in content, "subnetcalc runtime-config response contracts should call tests/app_contracts.py"
assert not any('"/runtime-config.js"' in line for line in contract_lines), "subnetcalc runtime-config response policy should move to tests/app_contracts.py"
assert not any('"window.SUBNETCALC_RUNTIME_CONFIG"' in line for line in contract_lines), "subnetcalc runtime-config response policy should move to tests/app_contracts.py"
assert not any('"application/javascript; charset=utf-8"' in line for line in contract_lines), "subnetcalc runtime-config response policy should move to tests/app_contracts.py"

print("validated shared subnetcalc runtime-config response helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared subnetcalc runtime-config response helper usage"* ]]
}

@test "app runtime tests share oauth2-proxy token refresh helpers" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import oauth2_proxy_token_refresh_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
test_file = repo_root / "tests" / "validate-app-runtime-surfaces.bats"
content = test_file.read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content.splitlines()
    if "oauth2-proxy token refresh policy should move" not in line
]

assert callable(oauth2_proxy_token_refresh_contract_violations)
assert "oauth2_proxy_token_refresh_contract_violations" in content, "oauth2-proxy token refresh contracts should call tests/app_contracts.py"
assert not any('start = sso_tf.index(f"name: {name}")' in line for line in contract_lines), "oauth2-proxy token refresh policy should move to tests/app_contracts.py"
assert not any('"oauth2-proxy-sentiment-dev"' in line for line in contract_lines), "oauth2-proxy token refresh policy should move to tests/app_contracts.py"
assert not any('"--pass-access-token=true"' in line and "assert" in line for line in contract_lines), "oauth2-proxy token refresh policy should move to tests/app_contracts.py"

print("validated shared oauth2-proxy token refresh helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared oauth2-proxy token refresh helper usage"* ]]
}

@test "app runtime tests share image prebuild hook helpers" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import image_prebuild_hook_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
test_file = repo_root / "tests" / "validate-app-runtime-surfaces.bats"
content = test_file.read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content.splitlines()
    if "image prebuild hook policy should move" not in line
]

assert callable(image_prebuild_hook_contract_violations)
assert "image_prebuild_hook_contract_violations" in content, "image prebuild hook contracts should call tests/app_contracts.py"
assert not any('"prebuild": "make -C apps/sentiment/app build-linux"' in line for line in contract_lines), "image prebuild hook policy should move to tests/app_contracts.py"
assert not any('"apps/subnetcalc/app/go.sum"' in line for line in contract_lines), "image prebuild hook policy should move to tests/app_contracts.py"
assert not any('"image_build_run_prebuild()"' in line for line in contract_lines), "image prebuild hook policy should move to tests/app_contracts.py"

print("validated shared image prebuild hook helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared image prebuild hook helper usage"* ]]
}

@test "app runtime tests share oauth2-proxy backend logout helpers" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import oauth2_proxy_backend_logout_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
test_file = repo_root / "tests" / "validate-app-runtime-surfaces.bats"
content = test_file.read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content.splitlines()
    if "oauth2-proxy backend logout policy should move" not in line
]

assert callable(oauth2_proxy_backend_logout_contract_violations)
assert "oauth2_proxy_backend_logout_contract_violations" in content, "oauth2-proxy backend logout contracts should call tests/app_contracts.py"
assert not any('"oauth2_proxy_backend_logout_url" in locals_tf' in line for line in contract_lines), "oauth2-proxy backend logout policy should move to tests/app_contracts.py"
assert not any('"post.logout.redirect.uris" not in sso_tf' in line for line in contract_lines), "oauth2-proxy backend logout policy should move to tests/app_contracts.py"
assert not any('sso_tf.count("${local.oauth2_proxy_backend_logout_arg}")' in line for line in contract_lines), "oauth2-proxy backend logout policy should move to tests/app_contracts.py"

print("validated shared oauth2-proxy backend logout helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared oauth2-proxy backend logout helper usage"* ]]
}

@test "repo-owned app Dockerfiles pin numeric runtime users" {
  temp_app="${REPO_ROOT}/apps/zz-test-dockerfile-runtime"
  rm -rf "${temp_app}"
  mkdir -p "${temp_app}/app"
  cat >"${temp_app}/app/go.mod" <<'EOF'
module platform.local/zz-test-dockerfile-runtime

go 1.26
EOF
  cat >"${temp_app}/app/Dockerfile" <<'EOF'
FROM dhi.io/static:20260413-alpine3.23
COPY --chown=65532:65532 .run/zz-test /zz-test
USER 65532:65532
ENTRYPOINT ["/zz-test"]
EOF

  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import dockerfile_runtime_user_contract_violations, dockerfile_runtime_user_validated_files

repo_root = Path(os.environ["REPO_ROOT"])

violations = dockerfile_runtime_user_contract_violations(repo_root)
assert not violations, violations
validated = dockerfile_runtime_user_validated_files(repo_root)

print(f"validated {len(validated)} Dockerfile(s): {', '.join(validated)}")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"zz-test-dockerfile-runtime"* ]]
}

@test "compose app services use hardened runtime settings" {
  temp_app="${REPO_ROOT}/apps/zz-test-compose-hardening"
  rm -rf "${temp_app}"
  mkdir -p "${temp_app}/app"
  cat >"${temp_app}/app/go.mod" <<'EOF'
module platform.local/zz-test-compose-hardening

go 1.26
EOF
  cat >"${temp_app}/app/Dockerfile" <<'EOF'
FROM dhi.io/static:20260413-alpine3.23
COPY --chown=65532:65532 .run/zz-test /zz-test
USER 65532:65532
ENTRYPOINT ["/zz-test"]
EOF
  cat >"${temp_app}/compose.yml" <<'EOF'
services:
  zz-test:
    build:
      context: ./app
      dockerfile: Dockerfile
    read_only: true
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    tmpfs:
      - /tmp:rw,noexec,nosuid,nodev,mode=1777
EOF

  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import compose_hardening_contract_violations, compose_hardening_validated_services

repo_root = Path(os.environ["REPO_ROOT"])

violations = compose_hardening_contract_violations(repo_root)
assert not violations, violations
validated_services = compose_hardening_validated_services(repo_root)
print(f"validated {len(validated_services)} compose service(s): {', '.join(validated_services)}")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"zz-test-compose-hardening/compose.yml:zz-test"* ]]
}

@test "Go sentiment workload has a bounded laptop runtime profile and health probes" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import sentiment_api_kubernetes_runtime_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
violations = sentiment_api_kubernetes_runtime_contract_violations(repo_root)
assert not violations, violations

print("validated Go sentiment runtime profile")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated Go sentiment runtime profile"* ]]
}

@test "chatgpt-sim compose can target external OpenAI-compatible LLMs and Langfuse" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import chatgpt_sim_compose_llm_langfuse_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
violations = chatgpt_sim_compose_llm_langfuse_contract_violations(repo_root)
assert not violations, violations

print("validated chatgpt-sim compose external LLM and Langfuse knobs")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated chatgpt-sim compose external LLM and Langfuse knobs"* ]]
}

@test "browser app compose SSO static allowlists match embedded asset names" {
  temp_app="${REPO_ROOT}/apps/zz-test-sso-allowlist"
  rm -rf "${temp_app}"
  mkdir -p "${temp_app}/app/internal/app/web"
  cat >"${temp_app}/app/go.mod" <<'EOF'
module platform.local/zz-test-sso-allowlist

go 1.26
EOF
  touch "${temp_app}/app/internal/app/web/index.html"
  touch "${temp_app}/app/internal/app/web/style.css"
  cat >"${temp_app}/compose.yml" <<'EOF'
services:
  oauth2-proxy:
    image: quay.io/oauth2-proxy/oauth2-proxy:v7.15.2
    command:
      - --skip-auth-regex=^/(style\.css|app-shell\.css|favicon\.svg|favicon\.ico)$
EOF

  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import browser_sso_static_allowlist_contract_violations, browser_sso_static_allowlist_validated_apps

repo_root = Path(os.environ["REPO_ROOT"])

violations = browser_sso_static_allowlist_contract_violations(repo_root)
assert not violations, violations
validated = browser_sso_static_allowlist_validated_apps(repo_root)

print(f"validated {len(validated)} browser app compose SSO static allowlist(s): {', '.join(validated)}")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"zz-test-sso-allowlist"* ]]
}

@test "Go app compose healthchecks do not require /bin/sh" {
  temp_app="${REPO_ROOT}/apps/zz-test-compose-healthcheck"
  rm -rf "${temp_app}"
  mkdir -p "${temp_app}/app"
  cat >"${temp_app}/app/go.mod" <<'EOF'
module platform.local/zz-test-compose-healthcheck

go 1.26
EOF
  cat >"${temp_app}/app/Dockerfile" <<'EOF'
FROM dhi.io/static:20260413-alpine3.23
COPY --chown=65532:65532 .run/zz-test /zz-test
USER 65532:65532
ENTRYPOINT ["/zz-test"]
EOF
  cat >"${temp_app}/compose.yml" <<'EOF'
services:
  zz-test:
    build:
      context: ./app
      dockerfile: Dockerfile
    healthcheck:
      test: ["CMD", "/zz-test", "healthcheck"]
EOF

  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import go_compose_healthcheck_contract_violations, go_compose_healthcheck_validated_services

repo_root = Path(os.environ["REPO_ROOT"])

violations = go_compose_healthcheck_contract_violations(repo_root)
assert not violations, violations
validated_services = go_compose_healthcheck_validated_services(repo_root)

print(f"validated {len(validated_services)} shell-free Go healthchecks: {', '.join(validated_services)}")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"zz-test-compose-healthcheck/compose.yml:zz-test"* ]]
}

@test "sentiment compose frontend exposes API proxy diagnostics" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import sentiment_compose_diagnostics_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
violations = sentiment_compose_diagnostics_contract_violations(repo_root)
assert not violations, violations

print("validated sentiment compose API proxy diagnostics")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated sentiment compose API proxy diagnostics"* ]]
}

@test "subnetcalc compose keeps default runtime Go-only and SSO profile services toggleable" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import subnetcalc_compose_topology_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
violations = subnetcalc_compose_topology_contract_violations(repo_root)
assert not violations, violations

print("validated toggleable subnetcalc compose services")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated toggleable subnetcalc compose services"* ]]
}

@test "subnetcalc Go frontend exposes OIDC runtime config without generated files" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import subnetcalc_runtime_config_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
violations = subnetcalc_runtime_config_contract_violations(repo_root)
assert not violations, violations

print("validated Go runtime config contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated Go runtime config contract"* ]]
}

@test "subnetcalc Go frontend uses shared sign-out landing page" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import shared_sign_out_page_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
violations = shared_sign_out_page_contract_violations(repo_root)
assert not violations, violations

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

from tests.app_contracts import (
    kubernetes_workload_runtime_user_contract_violations,
    kubernetes_workload_runtime_user_validated_deployments,
)

repo_root = Path(os.environ["REPO_ROOT"])
violations = kubernetes_workload_runtime_user_contract_violations(repo_root)
assert not violations, violations
validated = kubernetes_workload_runtime_user_validated_deployments()

print(f"validated {len(validated)} workload deployment(s)")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated 6 workload deployment(s)"* ]]
}

@test "subnetcalc router protects the frontend and sends API calls through APIM" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import browser_router_auth_api_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
violations = browser_router_auth_api_contract_violations(repo_root)
assert not violations, violations

print("validated subnetcalc frontend auth gate and API routing")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated subnetcalc frontend auth gate and API routing"* ]]
}

@test "sentiment router protects the frontend and sends API calls through APIM" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import (
    browser_router_auth_api_contract_violations,
    sentiment_kubernetes_frontend_apim_contract_violations,
)

repo_root = Path(os.environ["REPO_ROOT"])
violations = (
    browser_router_auth_api_contract_violations(repo_root)
    + sentiment_kubernetes_frontend_apim_contract_violations(repo_root)
)
assert not violations, violations

print("validated sentiment frontend auth gate, health, and APIM API routing")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated sentiment frontend auth gate, health, and APIM API routing"* ]]
}

@test "app oauth2 proxies refresh forwarded access tokens before API use" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import oauth2_proxy_token_refresh_contract_violations, oauth2_proxy_token_refresh_validated_names

repo_root = Path(os.environ["REPO_ROOT"])
violations = oauth2_proxy_token_refresh_contract_violations(repo_root)
assert not violations, violations
validated = oauth2_proxy_token_refresh_validated_names()

print(f"validated {len(validated)} app oauth2-proxy access-token refresh setting(s)")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated 4 app oauth2-proxy access-token refresh setting(s)"* ]]
}

@test "local workload image builders run app prebuild hooks" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import image_prebuild_hook_contract_violations, image_prebuild_hook_validated_builders

repo_root = Path(os.environ["REPO_ROOT"])
violations = image_prebuild_hook_contract_violations(repo_root)
assert not violations, violations
validated = image_prebuild_hook_validated_builders()

print(f"validated {len(validated)} local workload builder(s)")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated 4 local workload builder(s)"* ]]
}

@test "app oauth2 proxies call Keycloak backend logout with the session ID token" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import oauth2_proxy_backend_logout_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
violations = oauth2_proxy_backend_logout_contract_violations(repo_root)
assert not violations, violations

print("validated Keycloak backend logout for app oauth2 proxies")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated Keycloak backend logout for app oauth2 proxies"* ]]
}

@test "app Gitea workflows build the default Go runtime images" {
  run uv run --isolated python - <<'PY'
from pathlib import Path
import os

from tests.app_contracts import gitea_workflow_go_image_contract_violations, gitea_workflow_go_image_validated_files

repo_root = Path(os.environ["REPO_ROOT"])
violations = gitea_workflow_go_image_contract_violations(repo_root)
assert not violations, violations
validated = gitea_workflow_go_image_validated_files()

print(f"validated {len(validated)} Gitea workflow(s)")
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

from tests.app_contracts import subnetcalc_runtime_config_response_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
violations = subnetcalc_runtime_config_response_contract_violations(repo_root)
assert not violations, violations

print("validated shared Go runtime-config response")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared Go runtime-config response"* ]]
}

@test "external runtime image refs stay aligned across dockerfiles, compose, and kubernetes manifests" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import (
    external_runtime_image_ref_contract_violations,
    external_runtime_image_ref_expectation_count,
)

repo_root = Path(os.environ["REPO_ROOT"])
violations = external_runtime_image_ref_contract_violations(repo_root)
assert not violations, violations

print(f"validated {external_runtime_image_ref_expectation_count()} external image expectation(s)")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated 12 external image expectation(s)"* ]]
}

@test "app runtime tests share external image ref helpers" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import external_runtime_image_ref_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
test_file = repo_root / "tests" / "validate-app-runtime-surfaces.bats"
content = test_file.read_text(encoding="utf-8")
test_body = content[
    content.index('\n@test "external runtime image refs stay aligned across dockerfiles, compose, and kubernetes manifests"'):
    content.index('\n@test "subnetcalc frontend stays single-replica for local laptop clusters"')
]
contract_lines = [
    line
    for line in test_body.splitlines()
    if "external runtime image ref policy should move" not in line
]

assert callable(external_runtime_image_ref_contract_violations)
assert "external_runtime_image_ref_contract_violations" in content
assert not any("expected_counts =" in line for line in contract_lines), "external runtime image ref policy should move to tests/app_contracts.py"
assert not any("dhi.io/static:20260413-alpine3.23" in line for line in contract_lines), "external runtime image ref policy should move to tests/app_contracts.py"
assert not any("gitea/act_runner:0.4.1" in line for line in contract_lines), "external runtime image ref policy should move to tests/app_contracts.py"
assert not any("POLICY_PROBE_IMAGE" in line for line in contract_lines), "external runtime image ref policy should move to tests/app_contracts.py"

print("validated shared external runtime image ref helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared external runtime image ref helper usage"* ]]
}

@test "subnetcalc frontend stays single-replica for local laptop clusters" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import subnetcalc_frontend_local_replica_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
violations = subnetcalc_frontend_local_replica_contract_violations(repo_root)
assert not violations, violations

print("validated single-replica subnetcalc frontend")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated single-replica subnetcalc frontend"* ]]
}

@test "app runtime tests share subnetcalc frontend replica helpers" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import subnetcalc_frontend_local_replica_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
test_file = repo_root / "tests" / "validate-app-runtime-surfaces.bats"
content = test_file.read_text(encoding="utf-8")
test_body = content[
    content.index('\n@test "subnetcalc frontend stays single-replica for local laptop clusters"'):
    content.index('\n@test "preload image artifacts track the current external runtime bump set"')
]
contract_lines = [
    line
    for line in test_body.splitlines()
    if "subnetcalc frontend replica policy should move" not in line
]

assert callable(subnetcalc_frontend_local_replica_contract_violations)
assert "subnetcalc_frontend_local_replica_contract_violations" in content
assert not any("yaml.safe_load_all" in line for line in contract_lines), "subnetcalc frontend replica policy should move to tests/app_contracts.py"
assert not any("subnetcalc-frontend" in line for line in contract_lines), "subnetcalc frontend replica policy should move to tests/app_contracts.py"
assert not any("topologySpreadConstraints" in line for line in contract_lines), "subnetcalc frontend replica policy should move to tests/app_contracts.py"

print("validated shared subnetcalc frontend replica helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared subnetcalc frontend replica helper usage"* ]]
}

@test "preload image artifacts track the current external runtime bump set" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import (
    preload_image_artifact_contract_violations,
    preload_image_lock_refs,
    preload_image_snapshot_files,
)

repo_root = Path(os.environ["REPO_ROOT"])
violations = preload_image_artifact_contract_violations(repo_root)
assert not violations, violations

print(f"validated {len(preload_image_snapshot_files())} preload image snapshot(s) and {len(preload_image_lock_refs())} lock entry(ies)")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated 4 preload image snapshot(s) and 8 lock entry(ies)"* ]]
}

@test "app runtime tests share preload image artifact helpers" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import preload_image_artifact_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
test_file = repo_root / "tests" / "validate-app-runtime-surfaces.bats"
content = test_file.read_text(encoding="utf-8")
test_body = content[
    content.index('\n@test "preload image artifacts track the current external runtime bump set"'):
    content.index('\n@test "Langfuse image artifacts use approved non-Bitnami runtime sources"')
]
contract_lines = [
    line
    for line in test_body.splitlines()
    if "preload image artifact policy should move" not in line
]

assert callable(preload_image_artifact_contract_violations)
assert "preload_image_artifact_contract_violations" in content
assert not any("required_lines =" in line for line in contract_lines), "preload image artifact policy should move to tests/app_contracts.py"
assert not any("retired_lines =" in line for line in contract_lines), "preload image artifact policy should move to tests/app_contracts.py"
assert not any("lock_expectations =" in line for line in contract_lines), "preload image artifact policy should move to tests/app_contracts.py"
assert not any("dhi.io/static:20260413-alpine3.23" in line for line in contract_lines), "preload image artifact policy should move to tests/app_contracts.py"
assert not any("oven/bun:1.3.13" in line for line in contract_lines), "preload image artifact policy should move to tests/app_contracts.py"

print("validated shared preload image artifact helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared preload image artifact helper usage"* ]]
}

@test "Langfuse image artifacts use approved non-Bitnami runtime sources" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import langfuse_image_artifact_contract_violations, langfuse_runtime_image_refs

repo_root = Path(os.environ["REPO_ROOT"])
violations = langfuse_image_artifact_contract_violations(repo_root)
assert not violations, violations

print(f"validated {len(langfuse_runtime_image_refs())} Langfuse preload and registry policy source(s)")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated 7 Langfuse preload and registry policy source(s)"* ]]
}

@test "app runtime tests share Langfuse image artifact helpers" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import langfuse_image_artifact_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
test_file = repo_root / "tests" / "validate-app-runtime-surfaces.bats"
content = test_file.read_text(encoding="utf-8")
test_body = content[
    content.index('\n@test "Langfuse image artifacts use approved non-Bitnami runtime sources"'):
]
contract_lines = [
    line
    for line in test_body.splitlines()
    if "Langfuse image artifact policy should move" not in line
]

assert callable(langfuse_image_artifact_contract_violations)
assert "langfuse_image_artifact_contract_violations" in content
assert not any("required_images =" in line for line in contract_lines), "Langfuse image artifact policy should move to tests/app_contracts.py"
assert not any("docker.io/langfuse/langfuse:3" in line for line in contract_lines), "Langfuse image artifact policy should move to tests/app_contracts.py"
assert not any('"docker.io/langfuse/*"' in line for line in contract_lines), "Langfuse image artifact policy should move to tests/app_contracts.py"
assert not any("dhi.io/langfuse:" in line for line in contract_lines), "Langfuse image artifact policy should move to tests/app_contracts.py"
assert not any("langfuse-redis" in line for line in contract_lines), "Langfuse image artifact policy should move to tests/app_contracts.py"
assert not any("kube-dns" in line for line in contract_lines), "Langfuse image artifact policy should move to tests/app_contracts.py"

print("validated shared Langfuse image artifact helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared Langfuse image artifact helper usage"* ]]
}
