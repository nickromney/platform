#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export SCRIPT="${REPO_ROOT}/scripts/validate-cilium-policies.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN}"
}

@test "subnetcalc Cilium policy sends router API traffic through APIM" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
docs = [
    doc
    for doc in yaml.safe_load_all(
        (repo_root / "terraform/kubernetes/cluster-policies/cilium/projects/subnetcalc/subnetcalc-http-routes.yaml").read_text(encoding="utf-8")
    )
    if doc
]
shared_docs = [
    doc
    for doc in yaml.safe_load_all((repo_root / "terraform/kubernetes/cluster-policies/cilium/shared/apim-baseline.yaml").read_text(encoding="utf-8"))
    if doc
]

router_policy = next(doc for doc in docs if doc["metadata"]["name"] == "subnetcalc-router-http-routes")
api_policy = next(doc for doc in docs if doc["metadata"]["name"] == "subnetcalc-api-http-routes")
apim_policy = next(doc for doc in shared_docs if doc["metadata"]["name"] == "apim-baseline")

router_egress = router_policy["spec"]["egress"]
router_apim_rule = next(
    rule
    for rule in router_egress
    if any(
        endpoint.get("matchLabels", {}).get("k8s:app.kubernetes.io/name") == "subnetcalc-apim-simulator"
        for endpoint in rule.get("toEndpoints", [])
    )
)
assert any(
    endpoint.get("matchLabels", {}).get("k8s:app.kubernetes.io/name") == "subnetcalc-apim-simulator"
    for rule in router_egress
    for endpoint in rule.get("toEndpoints", [])
)
assert not any(
    endpoint.get("matchLabels", {}).get("k8s:app.kubernetes.io/name") == "subnetcalc-api"
    for rule in router_egress
    for endpoint in rule.get("toEndpoints", [])
)
assert any(
    port.get("port") == "8000"
    for to_ports in router_apim_rule.get("toPorts", [])
    for port in to_ports.get("ports", [])
)

api_ingress = api_policy["spec"]["ingress"]
api_apim_rule = next(
    rule
    for rule in api_ingress
    if any(
        endpoint.get("matchLabels", {}).get("k8s:app.kubernetes.io/name") == "subnetcalc-apim-simulator"
        for endpoint in rule.get("fromEndpoints", [])
    )
)
assert any(
    endpoint.get("matchLabels", {}).get("k8s:app.kubernetes.io/name") == "subnetcalc-apim-simulator"
    for rule in api_ingress
    for endpoint in rule.get("fromEndpoints", [])
)
assert any(
    port.get("port") == "8080"
    for to_ports in api_apim_rule.get("toPorts", [])
    for port in to_ports.get("ports", [])
)
api_keycloak_rule = next(
    rule
    for rule in api_policy["spec"]["egress"]
    if any(
        endpoint.get("matchLabels", {}).get("k8s:app.kubernetes.io/name") == "keycloak"
        for endpoint in rule.get("toEndpoints", [])
    )
)
assert any(
    port.get("port") == "8080"
    for to_ports in api_keycloak_rule.get("toPorts", [])
    for port in to_ports.get("ports", [])
)

apim_api_rule = next(
    rule
    for rule in apim_policy["spec"]["egress"]
    if any(
        endpoint.get("matchLabels", {}).get(
            "k8s:io.cilium.k8s.namespace.labels.platform.publiccloudexperiments.net/namespace-role"
        ) == "application"
        and endpoint.get("matchLabels", {}).get("k8s:team") == "dolphin"
        and endpoint.get("matchLabels", {}).get("k8s:tier") == "backend"
        for endpoint in rule.get("toEndpoints", [])
    )
)
assert any(
    port.get("port") == "8080"
    for to_ports in apim_api_rule.get("toPorts", [])
    for port in to_ports.get("ports", [])
)

print("validated subnetcalc router-to-apim-to-backend policy")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated subnetcalc router-to-apim-to-backend policy"* ]]
}

@test "sentiment Cilium policy sends router API traffic through APIM" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
docs = [
    doc
    for doc in yaml.safe_load_all(
        (repo_root / "terraform/kubernetes/cluster-policies/cilium/projects/sentiment/sentiment-http-routes.yaml").read_text(encoding="utf-8")
    )
    if doc
]
runtime_docs = [
    doc
    for doc in yaml.safe_load_all(
        (repo_root / "terraform/kubernetes/cluster-policies/cilium/projects/sentiment/sentiment-runtime.yaml").read_text(encoding="utf-8")
    )
    if doc
]
shared_docs = [
    doc
    for doc in yaml.safe_load_all((repo_root / "terraform/kubernetes/cluster-policies/cilium/shared/apim-baseline.yaml").read_text(encoding="utf-8"))
    if doc
]

router_policy = next(doc for doc in docs if doc["metadata"]["name"] == "sentiment-router-http-routes")
api_policy = next(doc for doc in runtime_docs if doc["metadata"]["name"] == "sentiment-backend-ingress")
apim_policy = next(doc for doc in shared_docs if doc["metadata"]["name"] == "apim-baseline")

router_egress = router_policy["spec"]["egress"]
router_apim_rule = next(
    rule
    for rule in router_egress
    if any(
        endpoint.get("matchLabels", {}).get("k8s:app.kubernetes.io/name") == "subnetcalc-apim-simulator"
        for endpoint in rule.get("toEndpoints", [])
    )
)
assert any(
    endpoint.get("matchLabels", {}).get("k8s:app.kubernetes.io/name") == "subnetcalc-apim-simulator"
    for rule in router_egress
    for endpoint in rule.get("toEndpoints", [])
)
assert not any(
    endpoint.get("matchLabels", {}).get("k8s:app.kubernetes.io/name") == "sentiment-api"
    for rule in router_egress
    for endpoint in rule.get("toEndpoints", [])
)
assert any(
    port.get("port") == "8000"
    for to_ports in router_apim_rule.get("toPorts", [])
    for port in to_ports.get("ports", [])
)

api_ingress = api_policy["spec"]["ingress"]
assert any(
    endpoint.get("matchLabels", {}).get("k8s:app.kubernetes.io/name") == "subnetcalc-apim-simulator"
    for rule in api_ingress
    for endpoint in rule.get("fromEndpoints", [])
)
assert not any(
    endpoint.get("matchLabels", {}).get("k8s:app.kubernetes.io/name") == "sentiment-router"
    for rule in api_ingress
    for endpoint in rule.get("fromEndpoints", [])
)

apim_egress = apim_policy["spec"]["egress"]
backend_rule = next(
    rule
    for rule in apim_egress
    if any(
        endpoint.get("matchLabels", {}).get("k8s:tier") == "backend"
        for endpoint in rule.get("toEndpoints", [])
    )
)
backend_labels = backend_rule["toEndpoints"][0]["matchLabels"]
assert backend_labels["k8s:io.cilium.k8s.namespace.labels.platform.publiccloudexperiments.net/namespace-role"] == "application"
assert backend_labels["k8s:team"] == "dolphin"
assert backend_labels["k8s:tier"] == "backend"
assert "k8s:app" not in backend_labels
assert any(
    port.get("port") == "8080"
    for to_ports in backend_rule.get("toPorts", [])
    for port in to_ports.get("ports", [])
)

print("validated sentiment router-to-apim-to-backend policy")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated sentiment router-to-apim-to-backend policy"* ]]
}

@test "platform gateway Cilium policy allows Langfuse native OIDC discovery through the gateway" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
docs = [
    doc
    for doc in yaml.safe_load_all(
        (repo_root / "terraform/kubernetes/cluster-policies/cilium/shared/platform-gateway-hardened.yaml").read_text(encoding="utf-8")
    )
    if doc
]

policy = next(doc for doc in docs if doc["metadata"]["name"] == "platform-gateway-hardened")
ingress = policy["spec"]["ingress"]

langfuse_gateway_rule = next(
    rule
    for rule in ingress
    if any(
        endpoint.get("matchLabels", {}).get("k8s:io.kubernetes.pod.namespace") == "langfuse"
        for endpoint in rule.get("fromEndpoints", [])
    )
)
assert any(
    port.get("port") == "443"
    for to_ports in langfuse_gateway_rule.get("toPorts", [])
    for port in to_ports.get("ports", [])
)

print("validated Langfuse native OIDC ingress to platform gateway")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated Langfuse native OIDC ingress to platform gateway"* ]]
}

@test "static validation renders policy manifests and kustomize overlays" {
  policy_root="${BATS_TEST_TMPDIR}/cilium"
  render_stub="${BATS_TEST_TMPDIR}/render.sh"
  log_file="${BATS_TEST_TMPDIR}/static.log"

  mkdir -p "${policy_root}/shared"
  cat >"${policy_root}/kustomization.yaml" <<'EOF'
resources:
  - shared
EOF
  cat >"${policy_root}/shared/kustomization.yaml" <<'EOF'
resources:
  - policy.yaml
  - cidr.yaml
EOF
  cat >"${policy_root}/shared/policy.yaml" <<'EOF'
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: allow-demo
spec:
  endpointSelector: {}
EOF
  cat >"${policy_root}/shared/cidr.yaml" <<'EOF'
apiVersion: cilium.io/v2
kind: CiliumCIDRGroup
metadata:
  name: approved-egress
spec:
  externalCIDRs:
    - 10.0.0.0/24
EOF

cat >"${render_stub}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'render %s\n' "\${@: -1}" >>"${log_file}"
EOF
  chmod +x "${render_stub}"

  cat >"${TEST_BIN}/kubectl" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "kustomize" ]]; then
  printf 'kustomize %s\n' "\$2" >>"${log_file}"
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/kubectl"

  cat >"${TEST_BIN}/yq" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
file="${@: -1}"
sed -n 's/^kind:[[:space:]]*//p' "${file}" | head -n 1
EOF
  chmod +x "${TEST_BIN}/yq"

  cat >"${TEST_BIN}/jq" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/jq"

  run env \
    PATH="${TEST_BIN}:/usr/bin:/bin" \
    CILIUM_POLICY_ROOT="${policy_root}" \
    RENDER_CILIUM_POLICY_VALUES_SCRIPT="${render_stub}" \
    KUBECTL_BIN=kubectl \
    /bin/bash "${SCRIPT}" --execute static

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated 1 Cilium policy manifest file(s)"* ]]
  [[ "${output}" == *"rendered 2 Cilium kustomize overlay(s)"* ]]

  run cat "${log_file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"render ${policy_root}/shared/policy.yaml"* ]]
  [[ "${output}" == *"kustomize ${policy_root}"* ]]
  [[ "${output}" == *"kustomize ${policy_root}/shared"* ]]
}

@test "live validation falls back to a containerized cilium-dbg runner" {
  variables_file="${BATS_TEST_TMPDIR}/variables.tf"
  log_file="${BATS_TEST_TMPDIR}/live.log"

  cat >"${variables_file}" <<'EOF'
variable "cilium_version" {
  default = "1.19.4"
}
EOF

  cat >"${TEST_BIN}/kubectl" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$1" == "config" && "\$2" == "view" && "\$3" == "--raw" ]]; then
  cat <<'KUBECONFIG'
apiVersion: v1
clusters:
- cluster:
    server: https://example.invalid
  name: demo
contexts:
- context:
    cluster: demo
    user: demo
  name: demo
current-context: demo
kind: Config
users:
- name: demo
  user:
    token: fake
KUBECONFIG
  exit 0
fi
if [[ "\$1" == "--kubeconfig" ]]; then
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/kubectl"

  cat >"${TEST_BIN}/docker" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$1" == "info" ]]; then
  exit 0
fi
printf '%s\n' "\$*" >>"${log_file}"
EOF
  chmod +x "${TEST_BIN}/docker"

  run env \
    PATH="${TEST_BIN}:/usr/bin:/bin" \
    KUBECTL_BIN=kubectl \
    CILIUM_IMAGE_VERSION_FILE="${variables_file}" \
    KUBECONFIG="${BATS_TEST_TMPDIR}/config" \
    /bin/bash "${SCRIPT}" --execute live

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"quay.io/cilium/cilium:v1.19.4"* ]]
  [[ "${output}" == *"OK   cilium live policy validation"* ]]

  run cat "${log_file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"run --rm"* ]]
  [[ "${output}" == *"cilium-dbg preflight validate-cnp"* ]]
}

@test "live validation prefers an in-cluster cilium-dbg runner before docker" {
  log_file="${BATS_TEST_TMPDIR}/live-in-cluster.log"

  cat >"${TEST_BIN}/kubectl" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$1" == "config" && "\$2" == "view" && "\$3" == "--raw" ]]; then
  cat <<'KUBECONFIG'
apiVersion: v1
clusters:
- cluster:
    server: https://127.0.0.1:6443
  name: demo
contexts:
- context:
    cluster: demo
    user: demo
  name: demo
current-context: demo
kind: Config
users:
- name: demo
  user:
    token: fake
KUBECONFIG
  exit 0
fi
if [[ "\$1" == "--kubeconfig" && "\$3" == "cluster-info" ]]; then
  exit 0
fi
if [[ "\$1" == "--kubeconfig" && "\$5" == "get" && "\$6" == "pods" ]]; then
  printf '%s\n' cilium-abc123
  exit 0
fi
if [[ "\$1" == "--kubeconfig" && "\$5" == "exec" ]]; then
  printf '%s\n' "\$*" >>"${log_file}"
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/kubectl"

  cat >"${TEST_BIN}/docker" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >>"${log_file}"
exit 0
EOF
  chmod +x "${TEST_BIN}/docker"

  run env \
    PATH="${TEST_BIN}:/usr/bin:/bin" \
    KUBECTL_BIN=kubectl \
    KUBECONFIG="${BATS_TEST_TMPDIR}/config" \
    /bin/bash "${SCRIPT}" --execute live

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"INFO using in-cluster cilium-abc123"* ]]
  [[ "${output}" == *"OK   cilium live policy validation"* ]]

  run cat "${log_file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"exec cilium-abc123 -- cilium-dbg preflight validate-cnp"* ]]
  [[ "${output}" != *"run --rm"* ]]
}
