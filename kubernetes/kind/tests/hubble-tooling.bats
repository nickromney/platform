#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export CAPTURE_SCRIPT="${REPO_ROOT}/terraform/kubernetes/scripts/hubble-capture-flows.sh"
  export CHECK_SCRIPT="${REPO_ROOT}/terraform/kubernetes/scripts/hubble-check-connection.sh"
  export SUMMARIZE_SCRIPT="${REPO_ROOT}/terraform/kubernetes/scripts/hubble-summarise-flows.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  export HUBBLE_LOG="${BATS_TEST_TMPDIR}/hubble.log"
  export PATH="${TEST_BIN}:${PATH}"

  mkdir -p "${TEST_BIN}" "${HOME}/.kube"

  cat > "${TEST_BIN}/hubble" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${HUBBLE_LOG}"

if [[ "${1:-}" == "observe" ]]; then
  cat
elif [[ "${1:-}" == "status" ]]; then
  echo "Healthcheck (via stub): Ok"
fi
EOF
  chmod +x "${TEST_BIN}/hubble"
}

@test "hubble-capture-flows normalises HTTPS server input to TLS relay flags" {
  run "${CAPTURE_SCRIPT}" \
    --server https://relay.example.com \
    --last 10 \
    --namespace observability \
    </dev/null

  [ "${status}" -eq 0 ]

  run cat "${HUBBLE_LOG}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"observe --output jsonpb --last 10"* ]]
  [[ "${output}" == *"--server tls://relay.example.com:443"* ]]
  [[ "${output}" == *"--tls"* ]]
  [[ "${output}" == *"--tls-server-name relay.example.com"* ]]
  [[ "${output}" == *"--namespace observability"* ]]
  [[ "${output}" != *"--since"* ]]
}

@test "hubble-capture-flows defaults to repo port-forward mode" {
  touch "${HOME}/.kube/kind-kind-local.yaml"

  run "${CAPTURE_SCRIPT}" \
    --last 10 \
    --namespace observability \
    </dev/null

  [ "${status}" -eq 0 ]

  run cat "${HUBBLE_LOG}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"observe --output jsonpb --last 10"* ]]
  [[ "${output}" == *"--port-forward"* ]]
  [[ "${output}" == *"--kubeconfig ${HOME}/.kube/kind-kind-local.yaml"* ]]
  [[ "${output}" == *"--kube-namespace kube-system"* ]]
}

@test "hubble-capture-flows keeps explicit non-443 HTTPS ports and repo default namespaces" {
  run "${CAPTURE_SCRIPT}" \
    --server https://hubble.example.com:4443 \
    --since 15m \
    </dev/null

  [ "${status}" -eq 0 ]

  run cat "${HUBBLE_LOG}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"--server tls://hubble.example.com:4443"* ]]
  [[ "${output}" == *"--tls-server-name hubble.example.com"* ]]
  [[ "${output}" == *"--namespace argocd"* ]]
  [[ "${output}" == *"--namespace dev"* ]]
  [[ "${output}" == *"--namespace kyverno"* ]]
  [[ "${output}" == *"--namespace nginx-gateway"* ]]
  [[ "${output}" == *"--namespace observability"* ]]
}

@test "hubble-capture-flows explains when a UI route is used instead of the relay" {
  cat > "${TEST_BIN}/hubble" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${HUBBLE_LOG}"
echo 'unexpected HTTP status code received from server: 302 (Found); malformed header: missing HTTP content-type' >&2
exit 1
EOF
  chmod +x "${TEST_BIN}/hubble"

  run "${CAPTURE_SCRIPT}" \
    --server https://hubble.admin.127.0.0.1.sslip.io \
    --last 10 \
    --namespace observability \
    </dev/null

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"did not behave like a Hubble Relay gRPC endpoint"* ]]
  [[ "${output}" == *"https://hubble.admin.127.0.0.1.sslip.io is the Hubble UI route"* ]]
}

@test "hubble-capture-flows explains when localhost 4245 has no port-forward behind it" {
  cat > "${TEST_BIN}/hubble" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${HUBBLE_LOG}"
echo 'rpc error: code = Unavailable desc = connection error: desc = "transport: Error while dialing: dial tcp 127.0.0.1:4245: connect: connection refused"' >&2
exit 1
EOF
  chmod +x "${TEST_BIN}/hubble"

  run "${CAPTURE_SCRIPT}" \
    --server localhost:4245 \
    --last 10 \
    --namespace observability \
    </dev/null

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"localhost:4245 refused the connection"* ]]
  [[ "${output}" == *"no local port-forward is running yet"* ]]
  [[ "${output}" == *"kubectl -n kube-system port-forward service/hubble-relay 4245:4245"* ]]
}

@test "hubble-capture-flows help prefers port-forward mode for this cluster" {
  run "${CAPTURE_SCRIPT}" --help

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"works without a pre-existing localhost port-forward"* ]]
  [[ "${output}" == *"./hubble-capture-flows.sh -P --kubeconfig ~/.kube/kind-kind-local.yaml"* ]]
  [[ "${output}" == *"kubectl -n kube-system port-forward service/hubble-relay 4245:4245"* ]]
}

@test "hubble-check-connection.sh normalises HTTPS server input to TLS relay flags" {
  run "${CHECK_SCRIPT}" --server https://relay.example.com

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Healthcheck (via stub): Ok"* ]]

  run cat "${HUBBLE_LOG}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"status --server tls://relay.example.com:443"* ]]
  [[ "${output}" == *"--tls"* ]]
  [[ "${output}" == *"--tls-server-name relay.example.com"* ]]
}

@test "hubble-check-connection.sh defaults to repo port-forward mode" {
  touch "${HOME}/.kube/kind-kind-local.yaml"

  run "${CHECK_SCRIPT}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Healthcheck (via stub): Ok"* ]]

  run cat "${HUBBLE_LOG}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"status --port-forward"* ]]
  [[ "${output}" == *"--kubeconfig ${HOME}/.kube/kind-kind-local.yaml"* ]]
  [[ "${output}" == *"--kube-namespace kube-system"* ]]
}

@test "hubble-check-connection.sh explains when localhost 4245 is not listening" {
  cat > "${TEST_BIN}/nc" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "${TEST_BIN}/nc"

  run "${CHECK_SCRIPT}" --server localhost:4245

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"localhost:4245 is not listening on this machine"* ]]
  [[ "${output}" == *"kubectl -n kube-system port-forward service/hubble-relay 4245:4245"* ]]
}

@test "hubble-check-connection.sh explains when a UI route is used instead of the relay" {
  cat > "${TEST_BIN}/hubble" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${HUBBLE_LOG}"
echo 'unexpected HTTP status code received from server: 302 (Found); malformed header: missing HTTP content-type' >&2
exit 1
EOF
  chmod +x "${TEST_BIN}/hubble"

  run "${CHECK_SCRIPT}" --server https://hubble.admin.127.0.0.1.sslip.io

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"did not behave like a Hubble Relay gRPC endpoint"* ]]
  [[ "${output}" == *"https://hubble.admin.127.0.0.1.sslip.io is the Hubble UI route"* ]]
}

@test "hubble-summarise-flows aggregates workload edges" {
  input_file="${BATS_TEST_TMPDIR}/flows.jsonl"

  cat > "${input_file}" <<'EOF'
{"flow":{"verdict":"FORWARDED","traffic_direction":"EGRESS","source":{"namespace":"dev","pod_name":"sentiment-api-abc","workloads":[{"name":"sentiment-api","kind":"Deployment"}]},"destination":{"namespace":"observability","pod_name":"otel-collector-xyz","workloads":[{"name":"otel-collector","kind":"Deployment"}]},"l4":{"TCP":{"destination_port":4318}}}}
{"flow":{"verdict":"FORWARDED","traffic_direction":"EGRESS","source":{"namespace":"dev","pod_name":"sentiment-api-def","workloads":[{"name":"sentiment-api","kind":"Deployment"}]},"destination":{"namespace":"observability","pod_name":"otel-collector-xyz","workloads":[{"name":"otel-collector","kind":"Deployment"}]},"l4":{"TCP":{"destination_port":4318}}}}
{"flow":{"verdict":"FORWARDED","traffic_direction":"EGRESS","source":{"namespace":"dev","pod_name":"subnetcalc-api-aaa","workloads":[{"name":"subnetcalc-api","kind":"Deployment"}]},"destination":{"namespace":"observability","pod_name":"otel-collector-xyz","workloads":[{"name":"otel-collector","kind":"Deployment"}]},"l4":{"TCP":{"destination_port":4318}}}}
EOF

  run "${SUMMARIZE_SCRIPT}" --input "${input_file}" --report edges --aggregate-by workload --direction egress --top 10 --format tsv

  [ "${status}" -eq 0 ]
  [[ "${output}" == *$'count\tdirection\tverdict\tprotocol\tsrc_ns\tsrc\tdst_class\tdst_ns\tdst\tdst_port'* ]]
  [[ "${output}" == *$'\n2\tEGRESS\tFORWARDED\ttcp\tdev\tsentiment-api\tworkload\tobservability\totel-collector\t4318'* ]]
  [[ "${output}" == *$'\n1\tEGRESS\tFORWARDED\ttcp\tdev\tsubnetcalc-api\tworkload\tobservability\totel-collector\t4318'* ]]
}

@test "hubble-summarise-flows reports world destinations and DNS queries" {
  world_file="${BATS_TEST_TMPDIR}/world.jsonl"
  dns_file="${BATS_TEST_TMPDIR}/dns.jsonl"

  cat > "${world_file}" <<'EOF'
{"flow":{"verdict":"FORWARDED","traffic_direction":"EGRESS","source":{"namespace":"sandbox","pod_name":"datadog-agent-123","workloads":[{"name":"datadog-agent","kind":"DaemonSet"}]},"destination":{"labels":["reserved:world"]},"destination_names":["api.datadoghq.com"],"IP":{"destination":"104.16.0.1"},"l4":{"TCP":{"destination_port":443}}}}
EOF

  run "${SUMMARIZE_SCRIPT}" --input "${world_file}" --report world --aggregate-by workload --direction egress --format tsv

  [ "${status}" -eq 0 ]
  [[ "${output}" == *$'count\tdirection\tverdict\tprotocol\tworld_side\tpeer_ns\tpeer\tworld_names\tworld_ip\tport'* ]]
  [[ "${output}" == *$'\n1\tEGRESS\tFORWARDED\ttcp\tdestination\tsandbox\tdatadog-agent\tapi.datadoghq.com\t104.16.0.1\t443'* ]]

  cat > "${dns_file}" <<'EOF'
{"flow":{"verdict":"FORWARDED","traffic_direction":"EGRESS","source":{"namespace":"sandbox","pod_name":"datadog-agent-123","workloads":[{"name":"datadog-agent","kind":"DaemonSet"}]},"destination":{"namespace":"kube-system","pod_name":"coredns-123","workloads":[{"name":"coredns","kind":"Deployment"}]},"l7":{"dns":{"query":"api.datadoghq.com.","qtypes":["A"],"rcode":"NOERROR"}}}}
EOF

  run "${SUMMARIZE_SCRIPT}" --input "${dns_file}" --report dns --aggregate-by workload --direction egress --format tsv

  [ "${status}" -eq 0 ]
  [[ "${output}" == *$'count\tdirection\tverdict\tsrc_ns\tsrc\tdns_server\tquery\tqtypes\trcode'* ]]
  [[ "${output}" == *$'\n1\tEGRESS\tFORWARDED\tsandbox\tdatadog-agent\tkube-system/coredns\tapi.datadoghq.com.\tA\tNOERROR'* ]]
}
