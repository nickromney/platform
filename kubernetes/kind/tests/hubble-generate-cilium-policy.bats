#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/terraform/kubernetes/scripts/hubble-generate-cilium-policy.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  export PATH="${TEST_BIN}:${PATH}"
  export MODULE_ROOT="${BATS_TEST_TMPDIR}/cilium-module"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export KUBECTL_LOG="${BATS_TEST_TMPDIR}/kubectl.log"

  mkdir -p \
    "${TEST_BIN}" \
    "${MODULE_ROOT}/sources/observability" \
    "${MODULE_ROOT}/categories/observability" \
    "${HOME}/.kube"

  : > "${KUBECTL_LOG}"
  touch "${HOME}/.kube/kind-kind-local.yaml"

  cat > "${TEST_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${KUBECTL_LOG:-}" ]]; then
  printf '%s\n' "$*" >> "${KUBECTL_LOG}"
fi

case "$*" in
  *"auth can-i get deployments -n "*)
    printf '%s\n' "yes"
    ;;
  *"auth can-i get daemonsets -n "*)
    printf '%s\n' "yes"
    ;;
  *"auth can-i get statefulsets -n "*)
    printf '%s\n' "yes"
    ;;
  *"-n observability get deployment otel-collector -o json"*)
    cat <<'JSON'
{"metadata":{"labels":{"app.kubernetes.io/name":"otel-collector"}}}
JSON
    ;;
  *"-n dev get deployment sentiment-api -o json"*)
    cat <<'JSON'
{"metadata":{"labels":{"app.kubernetes.io/name":"sentiment-api"}}}
JSON
    ;;
  *"-n dev get deployment subnetcalc-api -o json"*)
    cat <<'JSON'
{"metadata":{"labels":{"app.kubernetes.io/name":"subnetcalc-api"}}}
JSON
    ;;
  *"-n uat get deployment sentiment-api -o json"*)
    cat <<'JSON'
{"metadata":{"labels":{"app.kubernetes.io/name":"sentiment-api"}}}
JSON
    ;;
  *"-n uat get deployment subnetcalc-api -o json"*)
    cat <<'JSON'
{"metadata":{"labels":{"app.kubernetes.io/name":"subnetcalc-api"}}}
JSON
    ;;
  *)
    exit 1
    ;;
esac
EOF
  chmod +x "${TEST_BIN}/kubectl"
}

@test "hubble-generate-cilium-policy writes source and rendered category files" {
  local input_file
  local source_file
  local rendered_file

  input_file="${BATS_TEST_TMPDIR}/edges.tsv"
  source_file="${MODULE_ROOT}/sources/observability/cnp-observability-otel-collector-allow-tcp-4318-from-observed-workloads.yaml"
  rendered_file="${MODULE_ROOT}/categories/observability/cnp-observability-otel-collector-allow-tcp-4318-from-observed-workloads.yaml"

  cat > "${input_file}" <<'EOF'
count	direction	verdict	protocol	src_ns	src	dst_class	dst_ns	dst	dst_port
20	EGRESS	FORWARDED	tcp	dev	sentiment-api	workload	observability	otel-collector	4318
4	EGRESS	FORWARDED	tcp	dev	subnetcalc-api	workload	observability	otel-collector	4318
21	EGRESS	FORWARDED	tcp	uat	sentiment-api	workload	observability	otel-collector	4318
4	EGRESS	FORWARDED	tcp	uat	subnetcalc-api	workload	observability	otel-collector	4318
EOF

  run "${SCRIPT}" \
    --input "${input_file}" \
    --category observability \
    --module-root "${MODULE_ROOT}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"generated source: ${source_file}"* ]]
  [[ "${output}" == *"rendered category: ${rendered_file}"* ]]
  [ -f "${source_file}" ]
  [ -f "${rendered_file}" ]

  run sed -n '1,220p' "${source_file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'name: cnp-observability-otel-collector-allow-tcp-4318-from-observed-workloads'* ]]
  [[ "${output}" == *'"k8s:app.kubernetes.io/name": "otel-collector"'* ]]
  [[ "${output}" == *'"k8s:io.kubernetes.pod.namespace": "dev"'* ]]
  [[ "${output}" == *'"k8s:app.kubernetes.io/name": "subnetcalc-api"'* ]]
  [[ "${output}" == *'port: "4318"'* ]]
  [[ "${output}" == *'protocol: TCP'* ]]

  run sed -n '1,160p' "${rendered_file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *$'metadata:\n  name: cnp-observability-otel-collector-allow-tcp-4318-from-observed-workloads'* ]]
  [[ "${output}" == *$'specs:\n  - description:'* ]]
}

@test "hubble-generate-cilium-policy refuses to overwrite an existing source manifest without force" {
  local input_file
  local source_file

  input_file="${BATS_TEST_TMPDIR}/edges.tsv"
  source_file="${MODULE_ROOT}/sources/observability/cnp-observability-otel-collector-allow-tcp-4318-from-observed-workloads.yaml"

  cat > "${input_file}" <<'EOF'
count	direction	verdict	protocol	src_ns	src	dst_class	dst_ns	dst	dst_port
20	EGRESS	FORWARDED	tcp	dev	sentiment-api	workload	observability	otel-collector	4318
EOF

  cat > "${source_file}" <<'EOF'
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: cnp-observability-otel-collector-allow-tcp-4318-from-observed-workloads
EOF

  run "${SCRIPT}" \
    --input "${input_file}" \
    --category observability \
    --module-root "${MODULE_ROOT}"

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"source manifest already exists"* ]]
}

@test "hubble-generate-cilium-policy defaults to the repo kind kubeconfig when none is set" {
  local input_file

  input_file="${BATS_TEST_TMPDIR}/edges.tsv"

  cat > "${input_file}" <<'EOF'
count	direction	verdict	protocol	src_ns	src	dst_class	dst_ns	dst	dst_port
20	EGRESS	FORWARDED	tcp	dev	sentiment-api	workload	observability	otel-collector	4318
EOF

  run "${SCRIPT}" \
    --input "${input_file}" \
    --category observability \
    --module-root "${MODULE_ROOT}" \
    --force

  [ "${status}" -eq 0 ]

  run rg --fixed-strings -- "${HOME}/.kube/kind-kind-local.yaml" "${KUBECTL_LOG}"

  [ "${status}" -eq 0 ]
}

@test "hubble-generate-cilium-policy accepts output-root as an alias for module-root" {
  local input_file
  local source_file

  input_file="${BATS_TEST_TMPDIR}/edges.tsv"
  source_file="${MODULE_ROOT}/sources/observability/cnp-observability-otel-collector-allow-tcp-4318-from-observed-workloads.yaml"

  cat > "${input_file}" <<'EOF'
count	direction	verdict	protocol	src_ns	src	dst_class	dst_ns	dst	dst_port
20	EGRESS	FORWARDED	tcp	dev	sentiment-api	workload	observability	otel-collector	4318
EOF

  run "${SCRIPT}" \
    --input "${input_file}" \
    --category observability \
    --output-root "${MODULE_ROOT}"

  [ "${status}" -eq 0 ]
  [ -f "${source_file}" ]
}

@test "hubble-generate-cilium-policy explains multi-group input when policy-name is forced" {
  local input_file

  input_file="${BATS_TEST_TMPDIR}/edges.tsv"

  cat > "${input_file}" <<'EOF'
count	direction	verdict	protocol	src_ns	src	dst_class	dst_ns	dst	dst_port
20	EGRESS	FORWARDED	tcp	dev	sentiment-api	workload	observability	otel-collector	4318
7	EGRESS	FORWARDED	tcp	dev	sentiment-api	workload	observability	otel-collector	8888
EOF

  run "${SCRIPT}" \
    --input "${input_file}" \
    --category observability \
    --module-root "${MODULE_ROOT}" \
    --policy-name cnp-observability-custom

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"--policy-name only supports a single generated policy; this input expands to 2 groups"* ]]
  [[ "${output}" == *"observability/otel-collector TCP/4318"* ]]
  [[ "${output}" == *"observability/otel-collector TCP/8888"* ]]
}

@test "hubble-generate-cilium-policy skips unresolved sources and still generates supported groups" {
  local input_file
  local source_file

  input_file="${BATS_TEST_TMPDIR}/edges.tsv"
  source_file="${MODULE_ROOT}/sources/observability/cnp-observability-otel-collector-allow-tcp-4318-from-observed-workloads.yaml"

  cat > "${input_file}" <<'EOF'
count	direction	verdict	protocol	src_ns	src	dst_class	dst_ns	dst	dst_port
20	EGRESS	FORWARDED	tcp	dev	sentiment-api	workload	observability	otel-collector	4318
1	EGRESS	FORWARDED	tcp	kube-system	coredns-7d764666f9-vdll5	workload	observability	otel-collector	4318
1	EGRESS	FORWARDED	tcp	kube-system	coredns-7d764666f9-vdll5	workload	observability	otel-collector	9150
EOF

  run "${SCRIPT}" \
    --input "${input_file}" \
    --category observability \
    --module-root "${MODULE_ROOT}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"skipping source kube-system/coredns-7d764666f9-vdll5 for observability/otel-collector TCP/4318"* ]]
  [[ "${output}" == *"skipping observability/otel-collector TCP/9150: no resolvable source workloads remained after filtering"* ]]
  [[ "${output}" == *"generated 1 policies; skipped 1 groups and 2 source entries"* ]]
  [ -f "${source_file}" ]

  run sed -n '1,220p' "${source_file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'"k8s:io.kubernetes.pod.namespace": "dev"'* ]]
  [[ "${output}" != *'coredns-7d764666f9-vdll5'* ]]
}

@test "hubble-generate-cilium-policy caches repeated selector resolutions" {
  local input_file

  input_file="${BATS_TEST_TMPDIR}/edges.tsv"

  cat > "${input_file}" <<'EOF'
count	direction	verdict	protocol	src_ns	src	dst_class	dst_ns	dst	dst_port
20	EGRESS	FORWARDED	tcp	dev	sentiment-api	workload	observability	otel-collector	4318
7	EGRESS	FORWARDED	tcp	dev	sentiment-api	workload	observability	otel-collector	4319
EOF

  run "${SCRIPT}" \
    --input "${input_file}" \
    --category observability \
    --module-root "${MODULE_ROOT}"

  [ "${status}" -eq 0 ]

  run grep -c -- "-n observability get deployment otel-collector -o json" "${KUBECTL_LOG}"

  [ "${status}" -eq 0 ]
  [ "${output}" = "1" ]

  run grep -c -- "-n dev get deployment sentiment-api -o json" "${KUBECTL_LOG}"

  [ "${status}" -eq 0 ]
  [ "${output}" = "1" ]
}

@test "hubble-generate-cilium-policy ignores unsupported summary protocols" {
  local input_file
  local source_file

  input_file="${BATS_TEST_TMPDIR}/edges.tsv"
  source_file="${MODULE_ROOT}/sources/observability/cnp-observability-otel-collector-allow-tcp-4318-from-observed-workloads.yaml"

  cat > "${input_file}" <<'EOF'
count	direction	verdict	protocol	src_ns	src	dst_class	dst_ns	dst	dst_port
20	EGRESS	FORWARDED	tcp	dev	sentiment-api	workload	observability	otel-collector	4318
3	EGRESS	FORWARDED	dns	kube-system	coredns	workload	observability	otel-collector	37306
EOF

  run "${SCRIPT}" \
    --input "${input_file}" \
    --category observability \
    --module-root "${MODULE_ROOT}"

  [ "${status}" -eq 0 ]
  [ -f "${source_file}" ]
  [[ "${output}" != *"37306"* ]]
  [[ "${output}" != *"protocol: DNS"* ]]
}

@test "hubble-generate-cilium-policy fails early when selector-resolution RBAC is missing" {
  local input_file

  input_file="${BATS_TEST_TMPDIR}/edges.tsv"

  cat > "${input_file}" <<'EOF'
count	direction	verdict	protocol	src_ns	src	dst_class	dst_ns	dst	dst_port
20	EGRESS	FORWARDED	tcp	dev	sentiment-api	workload	observability	otel-collector	4318
EOF

  cat > "${TEST_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${KUBECTL_LOG:-}" ]]; then
  printf '%s\n' "$*" >> "${KUBECTL_LOG}"
fi

case "$*" in
  *"auth can-i get deployments -n observability")
    printf '%s\n' "no"
    ;;
  *)
    echo "unexpected kubectl invocation: $*" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "${TEST_BIN}/kubectl"

  run "${SCRIPT}" \
    --input "${input_file}" \
    --category observability \
    --module-root "${MODULE_ROOT}"

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"missing required Kubernetes permission to resolve stable workload selectors"* ]]
  [[ "${output}" == *"kubectl auth can-i get deployments -n "* ]]
}
