#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT_UNDER_TEST="${REPO_ROOT}/terraform/kubernetes/scripts/hubble-audit-cilium-policies.sh"
  export TEST_ROOT="${BATS_TEST_TMPDIR}/audit-sandbox"
  export SCRIPT_DIR="${TEST_ROOT}/terraform/kubernetes/scripts"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  export PATH="${TEST_BIN}:${PATH}"
  export KUBECTL_LOG="${BATS_TEST_TMPDIR}/kubectl.log"
  export CAPTURE_LOG="${BATS_TEST_TMPDIR}/capture.log"
  export SUMMARIZE_LOG="${BATS_TEST_TMPDIR}/summarize.log"

  mkdir -p "${SCRIPT_DIR}" "${TEST_BIN}" "${HOME}"
  cp "${SCRIPT_UNDER_TEST}" "${SCRIPT_DIR}/hubble-audit-cilium-policies.sh"
  chmod +x "${SCRIPT_DIR}/hubble-audit-cilium-policies.sh"

  cat > "${TEST_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${KUBECTL_LOG}"

case "$*" in
  "get namespaces -o json")
    cat <<'JSON'
{"items":[{"metadata":{"name":"kube-system"}},{"metadata":{"name":"observability"}},{"metadata":{"name":"datadog"}}]}
JSON
    ;;
  "get ciliumnodes -o json")
    cat <<'JSON'
{"items":[]}
JSON
    ;;
  "get nodes -o json")
    cat <<'JSON'
{"items":[]}
JSON
    ;;
  *)
    echo "unexpected kubectl invocation: $*" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "${TEST_BIN}/kubectl"
}

@test "hubble-audit-cilium-policies dry-run discovers namespaces and prints delegated capture commands" {
  cat > "${SCRIPT_DIR}/hubble-capture-flows.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${SCRIPT_DIR}/hubble-capture-flows.sh"

  cat > "${SCRIPT_DIR}/hubble-summarise-flows.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${SCRIPT_DIR}/hubble-summarise-flows.sh"

  run "${SCRIPT_DIR}/hubble-audit-cilium-policies.sh" \
    --dry-run \
    --iterations 2 \
    --since 1m \
    --namespace observability \
    --exclude-namespace datadog

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"capture observability iteration 1: ${SCRIPT_DIR}/hubble-capture-flows.sh --since 1m --namespace observability --port-forward-port 0"* ]]
  [[ "${output}" == *"capture observability iteration 2: ${SCRIPT_DIR}/hubble-capture-flows.sh --since 1m --namespace observability --port-forward-port 0"* ]]
  [[ "${output}" != *"capture datadog iteration"* ]]

  run cat "${KUBECTL_LOG}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"get namespaces -o json"* ]]
  [[ "${output}" == *"get ciliumnodes -o json"* ]]
  [[ "${output}" == *"get nodes -o json"* ]]
}

@test "hubble-audit-cilium-policies chains capture and summarise helpers and falls back to namespace mode" {
  local output_dir
  local ingress_policy
  local egress_policy
  local report_file

  output_dir="${BATS_TEST_TMPDIR}/run"
  ingress_policy="${output_dir}/policies/observability/cnp-observability-observed-ingress-candidate.yaml"
  egress_policy="${output_dir}/policies/observability/cnp-observability-observed-egress-candidate.yaml"
  report_file="${output_dir}/run-report.md"

  cat > "${SCRIPT_DIR}/hubble-capture-flows.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${CAPTURE_LOG}"
cat <<'JSON'
{"flow":{"verdict":"FORWARDED"}}
JSON
EOF
  chmod +x "${SCRIPT_DIR}/hubble-capture-flows.sh"

  cat > "${SCRIPT_DIR}/hubble-summarise-flows.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${SUMMARIZE_LOG}"

direction=""
report=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --direction)
      direction="${2:-}"
      shift 2
      ;;
    --report)
      report="${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

if [[ "${report}" == "edges" && "${direction}" == "ingress" ]]; then
  cat <<'TSV'
count	direction	verdict	protocol	src_ns	src	dst_class	dst_ns	dst	dst_port
7	INGRESS	FORWARDED	tcp	dev	sentiment-api	workload	observability	otel-collector	4318
3	INGRESS	FORWARDED	tcp	uat	subnetcalc-api	workload	observability	victoria-logs-single	9428
TSV
  exit 0
fi

if [[ "${report}" == "edges" && "${direction}" == "egress" ]]; then
  cat <<'TSV'
count	direction	verdict	protocol	src_ns	src	dst_class	dst_ns	dst	dst_port
9	EGRESS	FORWARDED	tcp	observability	otel-collector	workload	dev	sentiment-api	8080
4	EGRESS	FORWARDED	tcp	observability	victoria-logs-single	workload	argocd	argocd-server	443
TSV
  exit 0
fi

if [[ "${report}" == "world" ]]; then
  cat <<'TSV'
count	direction	verdict	protocol	world_side	peer_ns	peer	world_names	world_ip	port
TSV
  exit 0
fi

echo "unexpected summarize invocation: report=${report} direction=${direction}" >&2
exit 1
EOF
  chmod +x "${SCRIPT_DIR}/hubble-summarise-flows.sh"

  run "${SCRIPT_DIR}/hubble-audit-cilium-policies.sh" \
    --namespace observability \
    --iterations 1 \
    --row-threshold 1 \
    --output-dir "${output_dir}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"output dir: ${output_dir}"* ]]
  [[ "${output}" == *"report: ${report_file}"* ]]
  [ -f "${ingress_policy}" ]
  [ -f "${egress_policy}" ]
  [ -f "${output_dir}/namespaces/observability/ingress.aggregate-namespace.tsv" ]
  [ -f "${output_dir}/namespaces/observability/egress.aggregate-namespace.tsv" ]

  run cat "${CAPTURE_LOG}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"--since 1m --namespace observability --port-forward-port 0"* ]]

  run cat "${SUMMARIZE_LOG}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"--report edges --aggregate-by workload --direction ingress --format tsv --top 0 --verdict FORWARDED"* ]]
  [[ "${output}" == *"--report edges --aggregate-by workload --direction egress --format tsv --top 0 --verdict FORWARDED"* ]]
  [[ "${output}" == *"--report world --aggregate-by workload --direction ingress --format tsv --top 0 --verdict FORWARDED"* ]]
  [[ "${output}" == *"--report world --aggregate-by workload --direction egress --format tsv --top 0 --verdict FORWARDED"* ]]

  run sed -n '1,220p' "${ingress_policy}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'"platform.publiccloudexperiments.net/hubble-policy-mode": "namespace"'* ]]
  [[ "${output}" == *'"k8s:io.kubernetes.pod.namespace": "dev"'* ]]
  [[ "${output}" == *'"k8s:io.kubernetes.pod.namespace": "uat"'* ]]

  run sed -n '1,220p' "${egress_policy}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'"platform.publiccloudexperiments.net/hubble-policy-mode": "namespace"'* ]]
  [[ "${output}" == *'"k8s:io.kubernetes.pod.namespace": "argocd"'* ]]
  [[ "${output}" == *'"k8s:io.kubernetes.pod.namespace": "dev"'* ]]

  run sed -n '1,220p' "${report_file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'## observability ingress'* ]]
  [[ "${output}" == *'- Generation mode: `namespace`'* ]]
}
