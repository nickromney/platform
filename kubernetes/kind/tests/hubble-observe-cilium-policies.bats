#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT_UNDER_TEST="${REPO_ROOT}/terraform/kubernetes/scripts/hubble-observe-cilium-policies.sh"
  export TEST_ROOT="${BATS_TEST_TMPDIR}/audit-sandbox"
  export SCRIPT_DIR="${TEST_ROOT}/terraform/kubernetes/scripts"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  export PATH="${TEST_BIN}:${PATH}"
  export KUBECTL_LOG="${BATS_TEST_TMPDIR}/kubectl.log"
  export CAPTURE_LOG="${BATS_TEST_TMPDIR}/capture.log"
  export SUMMARIZE_LOG="${BATS_TEST_TMPDIR}/summarize.log"
  export RENDER_LOG="${BATS_TEST_TMPDIR}/render.log"

  mkdir -p "${SCRIPT_DIR}" "${TEST_BIN}" "${HOME}"
  cp "${SCRIPT_UNDER_TEST}" "${SCRIPT_DIR}/hubble-observe-cilium-policies.sh"
  chmod +x "${SCRIPT_DIR}/hubble-observe-cilium-policies.sh"

  cat > "${TEST_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${KUBECTL_LOG}"

case "$*" in
  *"auth can-i list namespaces")
    printf '%s\n' "yes"
    ;;
  *"auth can-i get ciliumnodes.cilium.io")
    printf '%s\n' "yes"
    ;;
  *"auth can-i get nodes")
    printf '%s\n' "yes"
    ;;
  *"auth can-i get services -n kube-system")
    printf '%s\n' "yes"
    ;;
  *"auth can-i get pods -n kube-system")
    printf '%s\n' "yes"
    ;;
  *"auth can-i create pods/portforward -n kube-system")
    printf '%s\n' "yes"
    ;;
  *"auth can-i get deployments -n "*)
    printf '%s\n' "yes"
    ;;
  *"auth can-i get daemonsets -n "*)
    printf '%s\n' "yes"
    ;;
  *"auth can-i get statefulsets -n "*)
    printf '%s\n' "yes"
    ;;
  *"auth can-i get pods -n "*)
    printf '%s\n' "yes"
    ;;
  *"auth can-i get replicasets -n "*)
    printf '%s\n' "yes"
    ;;
  "get namespaces -o json")
    cat <<'JSON'
{"items":[{"metadata":{"name":"kube-system"}},{"metadata":{"name":"observability"}},{"metadata":{"name":"datadog"}}]}
JSON
    ;;
  "config current-context")
    printf '%s\n' "kind-kind-local"
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
  *"port-forward --address 127.0.0.1 service/hubble-relay :4245")
    printf '%s\n' "Forwarding from 127.0.0.1:49000 -> 4245"
    while true; do
      sleep 1
    done
    ;;
  *"port-forward --address 127.0.0.1 service/hubble-relay "*":4245")
    local_port="${*: -1}"
    local_port="${local_port%%:4245}"
    printf 'Forwarding from 127.0.0.1:%s -> 4245\n' "${local_port}"
    while true; do
      sleep 1
    done
    ;;
  *)
    echo "unexpected kubectl invocation: $*" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "${TEST_BIN}/kubectl"
}

@test "hubble-observe-cilium-policies dry-run discovers namespaces and prints delegated capture commands" {
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

  run "${SCRIPT_DIR}/hubble-observe-cilium-policies.sh" \
    --dry-run \
    --capture-strategy since \
    --iterations 2 \
    --since 1m \
    --namespace observability \
    --exclude-namespace datadog

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"capture observability iteration 1/2: ${SCRIPT_DIR}/hubble-capture-flows.sh --namespace observability --field-mask-profile policy-observe --capture-strategy since --since 1m --verdict FORWARDED --port-forward-port 0"* ]]
  [[ "${output}" == *"capture observability iteration 2/2: ${SCRIPT_DIR}/hubble-capture-flows.sh --namespace observability --field-mask-profile policy-observe --capture-strategy since --since 1m --verdict FORWARDED --port-forward-port 0"* ]]
  [[ "${output}" != *"capture datadog iteration"* ]]

  run cat "${KUBECTL_LOG}"

  [ "${status}" -eq 0 ]
  [[ "${output}" != *"get namespaces -o json"* ]]
  [[ "${output}" == *"get ciliumnodes -o json"* ]]
  [[ "${output}" == *"get nodes -o json"* ]]
}

@test "hubble-observe-cilium-policies fails early when namespace discovery needs list namespaces permission" {
  cat > "${TEST_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${KUBECTL_LOG}"

case "$*" in
  *"auth can-i list namespaces")
    printf '%s\n' "no"
    ;;
  "config current-context")
    printf '%s\n' "kind-kind-local"
    ;;
  *)
    echo "unexpected kubectl invocation: $*" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "${TEST_BIN}/kubectl"

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

  run "${SCRIPT_DIR}/hubble-observe-cilium-policies.sh" --dry-run

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"missing required Kubernetes permission to discover namespaces when --namespace is not provided"* ]]
  [[ "${output}" == *"kubectl auth can-i list namespaces"* ]]
}

@test "hubble-observe-cilium-policies reports raw and policy-usable rows separately" {
  local output_dir

  output_dir="${BATS_TEST_TMPDIR}/usable-row-run"

  cat > "${SCRIPT_DIR}/hubble-capture-flows.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cat <<'JSON'
{"flow":{"verdict":"FORWARDED"}}
JSON
EOF
  chmod +x "${SCRIPT_DIR}/hubble-capture-flows.sh"

  cat > "${SCRIPT_DIR}/hubble-summarise-flows.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

report=""
direction=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --report)
      report="${2:-}"
      shift 2
      ;;
    --direction)
      direction="${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

if [[ "${report}" == "edges" ]]; then
  cat <<'TSV'
count	direction	verdict	protocol	src_ns	src	dst_class	dst_ns	dst	dst_port
5	EGRESS	FORWARDED	tcp		10.244.1.252	workload	observability	prometheus-server	9090
TSV
  exit 0
fi

cat <<'TSV'
count	direction	verdict	protocol	world_side	peer_ns	peer	world_names	world_ip	port
TSV
EOF
  chmod +x "${SCRIPT_DIR}/hubble-summarise-flows.sh"

  run "${SCRIPT_DIR}/hubble-observe-cilium-policies.sh" \
    --namespace observability \
    --capture-strategy since \
    --iterations 1 \
    --output-dir "${output_dir}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"observability: ingress raw=0 usable=0 candidate=omitted, egress raw=1 usable=0 candidate=omitted"* ]]

  run sed -n '1,120p' "${output_dir}/run-report.md"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'- Raw summary rows: `1`'* ]]
  [[ "${output}" == *'- Policy-usable rows: `0`'* ]]
}

@test "hubble-observe-cilium-policies defaults output dir under the kube context" {
  cat > "${SCRIPT_DIR}/hubble-capture-flows.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cat <<'JSON'
{"flow":{"verdict":"FORWARDED"}}
JSON
EOF
  chmod +x "${SCRIPT_DIR}/hubble-capture-flows.sh"

  cat > "${SCRIPT_DIR}/hubble-summarise-flows.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

report=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --report)
      report="${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

if [[ "${report}" == "edges" ]]; then
  cat <<'TSV'
count	direction	verdict	protocol	src_ns	src	dst_class	dst_ns	dst	dst_port
TSV
else
  cat <<'TSV'
count	direction	verdict	protocol	world_side	peer_ns	peer	world_names	world_ip	port
TSV
fi
EOF
  chmod +x "${SCRIPT_DIR}/hubble-summarise-flows.sh"

  run "${SCRIPT_DIR}/hubble-observe-cilium-policies.sh" \
    --namespace observability \
    --capture-strategy since \
    --iterations 1

  [ "${status}" -eq 0 ]
  [[ "${output}" =~ output\ dir:\ ${TEST_ROOT}/\.run/hubble-observe-kind-kind-local/[0-9]{8}-[0-9]{6} ]]
}

@test "hubble-observe-cilium-policies deduplicates workload specs that resolve to the same selector" {
  local output_dir
  local ingress_policy
  local egress_policy

  output_dir="${BATS_TEST_TMPDIR}/dedupe-run"
  ingress_policy="${output_dir}/policies/sso/cnp-sso-observed-ingress-candidate.yaml"
  egress_policy="${output_dir}/policies/sso/cnp-sso-observed-egress-candidate.yaml"

  cat > "${TEST_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${KUBECTL_LOG}"

case "$*" in
  *"auth can-i get services -n kube-system")
    printf '%s\n' "yes"
    ;;
  *"auth can-i get pods -n kube-system")
    printf '%s\n' "yes"
    ;;
  *"auth can-i create pods/portforward -n kube-system")
    printf '%s\n' "yes"
    ;;
  *"auth can-i get ciliumnodes.cilium.io")
    printf '%s\n' "yes"
    ;;
  *"auth can-i get nodes")
    printf '%s\n' "yes"
    ;;
  *"auth can-i get deployments -n "*)
    printf '%s\n' "yes"
    ;;
  *"auth can-i get daemonsets -n "*)
    printf '%s\n' "yes"
    ;;
  *"auth can-i get statefulsets -n "*)
    printf '%s\n' "yes"
    ;;
  *"auth can-i get pods -n "*)
    printf '%s\n' "yes"
    ;;
  *"auth can-i get replicasets -n "*)
    printf '%s\n' "yes"
    ;;
  "get namespaces -o json")
    cat <<'JSON'
{"items":[{"metadata":{"name":"sso"}}]}
JSON
    ;;
  "get ciliumnodes -o json")
    cat <<'JSON'
{"items":[{"spec":{"addresses":[{"type":"InternalIP","ip":"10.244.1.252"}]}}]}
JSON
    ;;
  "get nodes -o json")
    cat <<'JSON'
{"items":[]}
JSON
    ;;
  *"port-forward --address 127.0.0.1 service/hubble-relay :4245")
    printf '%s\n' "Forwarding from 127.0.0.1:49000 -> 4245"
    while true; do
      sleep 1
    done
    ;;
  *"port-forward --address 127.0.0.1 service/hubble-relay "*":4245")
    local_port="${*: -1}"
    local_port="${local_port%%:4245}"
    printf 'Forwarding from 127.0.0.1:%s -> 4245\n' "${local_port}"
    while true; do
      sleep 1
    done
    ;;
  "-n sso get deployment oauth2-proxy-argocd -o json"|"-n sso get deployment oauth2-proxy-gitea -o json")
    cat <<'JSON'
{"metadata":{"labels":{"app.kubernetes.io/name":"oauth2-proxy"}}}
JSON
    ;;
  "-n argocd get deployment argocd-server -o json")
    cat <<'JSON'
{"metadata":{"labels":{"app.kubernetes.io/name":"argocd-server"}}}
JSON
    ;;
  *)
    echo "unexpected kubectl invocation: $*" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "${TEST_BIN}/kubectl"

  cat > "${SCRIPT_DIR}/hubble-capture-flows.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cat <<'JSON'
{"flow":{"verdict":"FORWARDED"}}
JSON
EOF
  chmod +x "${SCRIPT_DIR}/hubble-capture-flows.sh"

  cat > "${SCRIPT_DIR}/hubble-summarise-flows.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

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

if [[ "${report}" == "edges" ]]; then
  cat <<'TSV'
count	direction	verdict	protocol	src_ns	src	dst_class	dst_ns	dst	dst_port
30	INGRESS	FORWARDED	tcp		10.244.1.252	workload	sso	oauth2-proxy-argocd	4180
24	INGRESS	FORWARDED	tcp		10.244.1.252	workload	sso	oauth2-proxy-gitea	4180
12	EGRESS	FORWARDED	tcp	sso	oauth2-proxy-argocd	workload	argocd	argocd-server	443
8	EGRESS	FORWARDED	tcp	sso	oauth2-proxy-gitea	workload	argocd	argocd-server	443
TSV
  exit 0
fi

cat <<'TSV'
count	direction	verdict	protocol	world_side	peer_ns	peer	world_names	world_ip	port
TSV
EOF
  chmod +x "${SCRIPT_DIR}/hubble-summarise-flows.sh"

  run "${SCRIPT_DIR}/hubble-observe-cilium-policies.sh" \
    --namespace sso \
    --capture-strategy since \
    --iterations 1 \
    --output-dir "${output_dir}"

  [ "${status}" -eq 0 ]
  [ -f "${ingress_policy}" ]
  [ -f "${egress_policy}" ]

  run grep -c 'description:' "${ingress_policy}"

  [ "${status}" -eq 0 ]
  [ "${output}" = "1" ]

  run sed -n '1,120p' "${ingress_policy}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'Observed ingress traffic from sso/oauth2-proxy'* ]]
  [[ "${output}" == *'"platform.publiccloudexperiments.net/hubble-policy-since": "5m"'* ]]
  [[ "${output}" == *'"platform.publiccloudexperiments.net/hubble-policy-iterations": "1"'* ]]
  [[ "${output}" != *'oauth2-proxy-argocd'* ]]
  [[ "${output}" != *'oauth2-proxy-gitea'* ]]

  run grep -c 'description:' "${egress_policy}"

  [ "${status}" -eq 0 ]
  [ "${output}" = "1" ]

  run sed -n '1,140p' "${egress_policy}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'Observed egress traffic from sso/oauth2-proxy'* ]]
  [[ "${output}" == *'"k8s:app.kubernetes.io/name": "argocd-server"'* ]]

  run grep -c -- "-n argocd get deployment argocd-server -o json" "${KUBECTL_LOG}"

  [ "${status}" -eq 0 ]
  [ "${output}" = "1" ]
}

@test "hubble-observe-cilium-policies can promote generated candidates into cilium-module sources and categories" {
  local output_dir
  local module_root
  local source_file
  local category_file
  local report_file

  output_dir="${BATS_TEST_TMPDIR}/promote-run"
  module_root="${BATS_TEST_TMPDIR}/cilium-module"
  source_file="${module_root}/sources/observability/cnp-observability-observed-ingress-candidate.yaml"
  category_file="${module_root}/categories/observability/cnp-observability-observed-ingress-candidate.yaml"
  report_file="${output_dir}/run-report.md"

  cat > "${SCRIPT_DIR}/hubble-capture-flows.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cat <<'JSON'
{"flow":{"verdict":"FORWARDED"}}
JSON
EOF
  chmod +x "${SCRIPT_DIR}/hubble-capture-flows.sh"

  cat > "${SCRIPT_DIR}/hubble-summarise-flows.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

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

if [[ "${report}" == "edges" ]]; then
  cat <<'TSV'
count	direction	verdict	protocol	src_ns	src	dst_class	dst_ns	dst	dst_port
4	INGRESS	FORWARDED	tcp	dev	sentiment-api	workload	observability	otel-collector	4318
TSV
  exit 0
fi

cat <<'TSV'
count	direction	verdict	protocol	src_ns	src	dst_class	dst_ns	dst	dst_port
TSV
EOF
  chmod +x "${SCRIPT_DIR}/hubble-summarise-flows.sh"

  cat > "${SCRIPT_DIR}/render-cilium-policy-values.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${RENDER_LOG}"

output=""
input=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      output="${2:-}"
      shift 2
      ;;
    *)
      input="$1"
      shift
      ;;
  esac
done

cat > "${output}" <<YAML
metadata:
  promoted-from: "${input}"
specs: []
YAML
EOF
  chmod +x "${SCRIPT_DIR}/render-cilium-policy-values.sh"

  run "${SCRIPT_DIR}/hubble-observe-cilium-policies.sh" \
    --namespace observability \
    --capture-strategy since \
    --iterations 1 \
    --row-threshold 0 \
    --output-dir "${output_dir}" \
    --promote-to-module \
    --module-root "${module_root}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"promoted 1 candidate policies into ${module_root}"* ]]
  [ -f "${source_file}" ]
  [ -f "${category_file}" ]

  run sed -n '1,160p' "${source_file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'kind: CiliumNetworkPolicy'* ]]
  [[ "${output}" == *'Observed namespace-aggregate ingress traffic for observability'* ]]

  run sed -n '1,80p' "${category_file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'metadata:'* ]]
  [[ "${output}" == *"promoted-from: \"${source_file}\""* ]]

  run cat "${RENDER_LOG}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"--output ${category_file} ${source_file}"* ]]

  run sed -n '1,120p' "${report_file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"- Module promotion: enabled -> \`${module_root}\`"* ]]
}

@test "hubble-observe-cilium-policies supports batched namespace capture workers with deterministic report order" {
  local output_dir
  local report_file

  output_dir="${BATS_TEST_TMPDIR}/workers-run"
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

report=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --report)
      report="${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

if [[ "${report}" == "edges" ]]; then
  cat <<'TSV'
count	direction	verdict	protocol	src_ns	src	dst_class	dst_ns	dst	dst_port
TSV
else
  cat <<'TSV'
count	direction	verdict	protocol	world_side	peer_ns	peer	world_names	world_ip	port
TSV
fi
EOF
  chmod +x "${SCRIPT_DIR}/hubble-summarise-flows.sh"

  run "${SCRIPT_DIR}/hubble-observe-cilium-policies.sh" \
    --namespace observability \
    --namespace datadog \
    --capture-strategy since \
    --iterations 1 \
    --namespace-workers 2 \
    --output-dir "${output_dir}"

  [ "${status}" -eq 0 ]
  [ -f "${report_file}" ]

  run awk '/^## / { print $2, $3 }' "${report_file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == $'observability ingress\nobservability egress\ndatadog ingress\ndatadog egress' ]]
}

@test "hubble-observe-cilium-policies chains capture and summarise helpers and falls back to namespace mode" {
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

if [[ "${report}" == "edges" ]]; then
  cat <<'TSV'
count	direction	verdict	protocol	src_ns	src	dst_class	dst_ns	dst	dst_port
7	INGRESS	FORWARDED	tcp	dev	sentiment-api	workload	observability	otel-collector	4318
3	INGRESS	FORWARDED	tcp	uat	subnetcalc-api	workload	observability	victoria-logs-single	9428
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

  run "${SCRIPT_DIR}/hubble-observe-cilium-policies.sh" \
    --namespace observability \
    --capture-strategy since \
    --iterations 1 \
    --since 1m \
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
  [[ "${output}" == *"--capture-strategy since --since 1m"* ]]
  [[ "${output}" == *"--verdict FORWARDED"* ]]
  [[ "${output}" == *"--server 127.0.0.1:49000"* ]]

  run cat "${SUMMARIZE_LOG}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"--report edges --aggregate-by workload --direction all --format tsv --top 0 --verdict FORWARDED"* ]]
  [[ "${output}" == *"--report world --aggregate-by workload --direction all --format tsv --top 0 --verdict FORWARDED"* ]]

  run grep -c -- "port-forward --address 127.0.0.1 service/hubble-relay :4245" "${KUBECTL_LOG}"

  [ "${status}" -eq 0 ]
  [ "${output}" = "1" ]

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
  [[ "${output}" == *'- Raw summary rows: `2`'* ]]
  [[ "${output}" == *'- Policy-usable rows: `2`'* ]]
  [[ "${output}" == *'- Generation mode: `namespace`'* ]]
}

@test "hubble-observe-cilium-policies emits host and world entity rules in namespace fallback mode" {
  local output_dir
  local ingress_policy
  local egress_policy

  output_dir="${BATS_TEST_TMPDIR}/host-world-run"
  ingress_policy="${output_dir}/policies/observability/cnp-observability-observed-ingress-candidate.yaml"
  egress_policy="${output_dir}/policies/observability/cnp-observability-observed-egress-candidate.yaml"

  cat > "${TEST_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${KUBECTL_LOG}"

case "$*" in
  *"auth can-i get services -n kube-system")
    printf '%s\n' "yes"
    ;;
  *"auth can-i get pods -n kube-system")
    printf '%s\n' "yes"
    ;;
  *"auth can-i create pods/portforward -n kube-system")
    printf '%s\n' "yes"
    ;;
  *"auth can-i get ciliumnodes.cilium.io")
    printf '%s\n' "yes"
    ;;
  *"auth can-i get nodes")
    printf '%s\n' "yes"
    ;;
  "get namespaces -o json")
    cat <<'JSON'
{"items":[{"metadata":{"name":"observability"}}]}
JSON
    ;;
  "get ciliumnodes -o json")
    cat <<'JSON'
{"items":[{"spec":{"addresses":[{"type":"InternalIP","ip":"10.0.0.10"}]}}]}
JSON
    ;;
  "get nodes -o json")
    cat <<'JSON'
{"items":[]}
JSON
    ;;
  *"port-forward --address 127.0.0.1 service/hubble-relay :4245")
    printf '%s\n' "Forwarding from 127.0.0.1:49000 -> 4245"
    while true; do
      sleep 1
    done
    ;;
  *"port-forward --address 127.0.0.1 service/hubble-relay "*":4245")
    local_port="${*: -1}"
    local_port="${local_port%%:4245}"
    printf 'Forwarding from 127.0.0.1:%s -> 4245\n' "${local_port}"
    while true; do
      sleep 1
    done
    ;;
  *)
    echo "unexpected kubectl invocation: $*" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "${TEST_BIN}/kubectl"

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

if [[ "${report}" == "edges" ]]; then
  cat <<'TSV'
count	direction	verdict	protocol	src_ns	src	dst_class	dst_ns	dst	dst_port
5	INGRESS	FORWARDED	tcp		10.0.0.10	workload	observability	otel-collector	4244
4	EGRESS	FORWARDED	tcp	observability	otel-collector	workload	argocd	argocd-server	443
TSV
  exit 0
fi

if [[ "${report}" == "world" ]]; then
  cat <<'TSV'
count	direction	verdict	protocol	world_side	peer_ns	peer	world_names	world_ip	port
2	INGRESS	FORWARDED	tcp	source	observability	otel-collector	external.example.com	203.0.113.10	4244
3	EGRESS	FORWARDED	tcp	destination	observability	otel-collector	api.example.com	104.16.0.1	443
TSV
  exit 0
fi

echo "unexpected summarize invocation: report=${report} direction=${direction}" >&2
exit 1
EOF
  chmod +x "${SCRIPT_DIR}/hubble-summarise-flows.sh"

  run "${SCRIPT_DIR}/hubble-observe-cilium-policies.sh" \
    --namespace observability \
    --capture-strategy since \
    --iterations 1 \
    --row-threshold 0 \
    --output-dir "${output_dir}"

  [ "${status}" -eq 0 ]
  [ -f "${ingress_policy}" ]
  [ -f "${egress_policy}" ]

  run sed -n '1,220p' "${ingress_policy}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'"platform.publiccloudexperiments.net/hubble-policy-mode": "namespace"'* ]]
  [[ "${output}" == *'fromEntities:'* ]]
  [[ "${output}" == *'          - host'* ]]
  [[ "${output}" == *'          - world'* ]]

  run sed -n '1,220p' "${egress_policy}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'"platform.publiccloudexperiments.net/hubble-policy-mode": "namespace"'* ]]
  [[ "${output}" == *'toEntities:'* ]]
  [[ "${output}" == *'          - world'* ]]
  [[ "${output}" == *'"k8s:io.kubernetes.pod.namespace": "argocd"'* ]]
}

@test "hubble-observe-cilium-policies forwards policy-verdict capture mode to the capture helper" {
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

  run "${SCRIPT_DIR}/hubble-observe-cilium-policies.sh" \
    --dry-run \
    --namespace observability \
    --capture-strategy since \
    --capture-mode policy-verdict \
    --print-command

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"--type policy-verdict"* ]]
  [[ "${output}" == *"--print-command"* ]]
}

@test "hubble-observe-cilium-policies emits progress heartbeats for long-running helpers" {
  local output_dir

  output_dir="${BATS_TEST_TMPDIR}/progress-run"

  cat > "${SCRIPT_DIR}/hubble-capture-flows.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

sleep 2
cat <<'JSON'
{"flow":{"verdict":"FORWARDED"}}
JSON
EOF
  chmod +x "${SCRIPT_DIR}/hubble-capture-flows.sh"

  cat > "${SCRIPT_DIR}/hubble-summarise-flows.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

report=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --report)
      report="${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

if [[ "${report}" == "edges" ]]; then
  cat <<'TSV'
count	direction	verdict	protocol	src_ns	src	dst_class	dst_ns	dst	dst_port
TSV
else
  cat <<'TSV'
count	direction	verdict	protocol	world_side	peer_ns	peer	world_names	world_ip	port
TSV
fi
EOF
  chmod +x "${SCRIPT_DIR}/hubble-summarise-flows.sh"

  run "${SCRIPT_DIR}/hubble-observe-cilium-policies.sh" \
    --namespace observability \
    --capture-strategy since \
    --iterations 1 \
    --progress-every 1 \
    --output-dir "${output_dir}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"observing namespace observability (1/1)"* ]]
  [[ "${output}" =~ capture\ observability\ iteration\ 1/1:\ still\ running\ after\ [12]s ]]
}

@test "hubble-observe-cilium-policies quiets empty summaries and reports zero-candidate runs clearly" {
  local output_dir
  local report_file
  local ingress_policy
  local egress_policy
  local warning_count

  output_dir="${BATS_TEST_TMPDIR}/empty-run"
  report_file="${output_dir}/run-report.md"
  ingress_policy="${output_dir}/policies/observability/cnp-observability-observed-ingress-candidate.yaml"
  egress_policy="${output_dir}/policies/observability/cnp-observability-observed-egress-candidate.yaml"

  cat > "${SCRIPT_DIR}/hubble-capture-flows.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${CAPTURE_LOG}"
echo 'time=2026-03-28T08:36:32.008Z level=WARN msg="Hubble CLI version is lower than Hubble Relay, API compatibility is not guaranteed, updating to a matching or higher version is recommended" hubble-cli-version=1.18.6 hubble-relay-version=1.19.2+g3977f6a1' >&2
cat <<'JSON'
{"flow":{"verdict":"FORWARDED"}}
JSON
EOF
  chmod +x "${SCRIPT_DIR}/hubble-capture-flows.sh"

  cat > "${SCRIPT_DIR}/hubble-summarise-flows.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${SUMMARIZE_LOG}"

report=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --report)
      report="${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

if [[ "${report}" == "edges" ]]; then
  cat <<'TSV'
count	direction	verdict	protocol	src_ns	src	dst_class	dst_ns	dst	dst_port
TSV
else
  cat <<'TSV'
count	direction	verdict	protocol	world_side	peer_ns	peer	world_names	world_ip	port
TSV
fi

echo "hubble-summarise-flows.sh: no matching flows" >&2
EOF
  chmod +x "${SCRIPT_DIR}/hubble-summarise-flows.sh"

  run "${SCRIPT_DIR}/hubble-observe-cilium-policies.sh" \
    --namespace observability \
    --capture-strategy since \
    --iterations 2 \
    --output-dir "${output_dir}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"observing namespace observability"* ]]
  [[ "${output}" == *"observability: ingress raw=0 usable=0 candidate=omitted, egress raw=0 usable=0 candidate=omitted"* ]]
  [[ "${output}" == *"no candidate policies generated across 1 namespace(s); widen --since, increase --iterations, or narrow --namespace"* ]]
  [[ "${output}" != *"hubble-summarise-flows.sh: no matching flows"* ]]
  [[ "${output}" != *"Hubble CLI version is lower than Hubble Relay"* ]]

  [ -f "${report_file}" ]
  [ ! -f "${ingress_policy}" ]
  [ ! -f "${egress_policy}" ]
  [ ! -d "${output_dir}/policies/observability" ]
  [ ! -d "${output_dir}/policies" ]

  run sed -n '1,120p' "${report_file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'## observability ingress'* ]]
  [[ "${output}" == *'- Raw summary rows: `0`'* ]]
  [[ "${output}" == *'- Policy-usable rows: `0`'* ]]
  [[ "${output}" == *'- Candidate policy: omitted'* ]]
}
