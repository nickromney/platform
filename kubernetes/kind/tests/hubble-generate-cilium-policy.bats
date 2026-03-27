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
