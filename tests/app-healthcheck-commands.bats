#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  HEALTH_PIDS=()
}

teardown() {
  local pid
  for pid in "${HEALTH_PIDS[@]:-}"; do
    kill "${pid}" >/dev/null 2>&1 || true
    wait "${pid}" >/dev/null 2>&1 || true
  done
}

start_health_server() {
  local port="$1"
  shift
  local ready_file="${BATS_TEST_TMPDIR}/health-${port}.ready"
  local error_file="${BATS_TEST_TMPDIR}/health-${port}.error"

  python3 - "${port}" "${ready_file}" "${error_file}" "$@" <<'PY' &
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

port = int(sys.argv[1])
ready_file = Path(sys.argv[2])
error_file = Path(sys.argv[3])
paths = set(sys.argv[4:])

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def do_GET(self):
        if self.path not in paths:
            self.send_response(404)
            self.end_headers()
            return
        body = json.dumps({"status": "ok"}).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

try:
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
except OSError as exc:
    error_file.write_text(str(exc), encoding="utf-8")
    raise SystemExit(1)

ready_file.write_text("ready", encoding="utf-8")
server.serve_forever()
PY
  local pid=$!
  HEALTH_PIDS+=("${pid}")

  for _ in {1..50}; do
    if [ -f "${ready_file}" ]; then
      return 0
    fi
    if [ -f "${error_file}" ]; then
      skip "port ${port} is not available for command-level healthcheck test: $(cat "${error_file}")"
    fi
    sleep 0.1
  done

  skip "healthcheck stub server on port ${port} did not become ready"
}

run_go_healthcheck() {
  local app_dir="$1"
  local command="$2"

  run bash -lc "cd '${REPO_ROOT}/${app_dir}' && go run ./cmd/${command} healthcheck"
  [ "${status}" -eq 0 ]
}

@test "Go app healthcheck subcommands use service-specific health endpoints" {
  command -v python3 >/dev/null 2>&1 || skip "python3 is required for local healthcheck stub"

  start_health_server 8000 "/apim/health"
  start_health_server 8080 "/health" "/api/v1/health"

  run_go_healthcheck "apps/apim-simulator/app" "apim-simulator"
  run_go_healthcheck "apps/chatgpt-sim/app" "chatgpt-sim"
  run_go_healthcheck "apps/idp-core/app" "idp-core"
  run_go_healthcheck "apps/langfuse-demos/app" "langfuse-demos"
  run_go_healthcheck "apps/platform-mcp/app" "platform-mcp"
  run_go_healthcheck "apps/sentiment/app" "sentiment"
  run_go_healthcheck "apps/subnetcalc/app" "subnetcalc"
}
