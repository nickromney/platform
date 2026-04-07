#!/usr/bin/env bats

SCRIPT="/Users/nickromney/Developer/personal/apim-simulator/examples/todo-app/frontend-astro/scripts/render-runtime-config.sh"

setup() {
  export TEMPLATE_PATH="$BATS_TEST_TMPDIR/runtime-config.template.js"
  export OUTPUT_PATH="$BATS_TEST_TMPDIR/html/runtime-config.js"

  cat >"$TEMPLATE_PATH" <<'EOF'
window.__APIM__ = {
  apiBaseUrl: "${API_BASE_URL}",
  subscriptionKey: "${APIM_SUBSCRIPTION_KEY}",
  grafanaBaseUrl: "${GRAFANA_BASE_URL}",
  dashboardUrl: "${OBSERVABILITY_DASHBOARD_URL}"
};
EOF
}

@test "render-runtime-config.sh writes a rendered config to an override path" {
  run env \
    RUNTIME_CONFIG_TEMPLATE_PATH="$TEMPLATE_PATH" \
    RUNTIME_CONFIG_OUTPUT_PATH="$OUTPUT_PATH" \
    API_BASE_URL="https://gateway.example.test" \
    APIM_SUBSCRIPTION_KEY="todo-shell-test-key" \
    GRAFANA_BASE_URL="https://grafana.example.test" \
    OBSERVABILITY_DASHBOARD_URL="https://grafana.example.test/d/custom" \
    sh "$SCRIPT"

  [ "$status" -eq 0 ]
  [ -f "$OUTPUT_PATH" ]

  run cat "$OUTPUT_PATH"
  [ "$status" -eq 0 ]
  [[ "$output" == *'https://gateway.example.test'* ]]
  [[ "$output" == *'todo-shell-test-key'* ]]
  [[ "$output" == *'https://grafana.example.test'* ]]
  [[ "$output" == *'https://grafana.example.test/d/custom'* ]]
}

@test "render-runtime-config.sh applies the documented defaults when env is unset" {
  run env \
    RUNTIME_CONFIG_TEMPLATE_PATH="$TEMPLATE_PATH" \
    RUNTIME_CONFIG_OUTPUT_PATH="$OUTPUT_PATH" \
    sh "$SCRIPT"

  [ "$status" -eq 0 ]

  run cat "$OUTPUT_PATH"
  [ "$status" -eq 0 ]
  [[ "$output" == *'http://localhost:8000'* ]]
  [[ "$output" == *'todo-demo-key'* ]]
  [[ "$output" == *'http://localhost:3001'* ]]
  [[ "$output" == *'http://localhost:3001/d/apim-simulator-overview/apim-simulator-overview'* ]]
}
