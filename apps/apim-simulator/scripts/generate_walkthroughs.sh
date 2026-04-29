#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCS_DIR="$ROOT_DIR/docs"
# shellcheck source=./stack-env.sh
source "$ROOT_DIR/scripts/stack-env.sh"
# shellcheck source=/dev/null
source "$ROOT_DIR/scripts/lib/shell-cli.sh"
stack_env_init

DOC_CORE="$DOCS_DIR/walkthrough-core-stacks.md"
DOC_EXAMPLES="$DOCS_DIR/walkthrough-example-stacks.md"
DOC_TUTORIALS="$DOCS_DIR/walkthrough-apim-get-started.md"
SHOWBOAT_BASH_ENV=""

usage() {
  cat <<EOF
Usage: generate_walkthroughs.sh [--dry-run] [--execute] [core|examples|tutorials|all ...]

Generate captured walkthrough Markdown using showboat, Docker Compose, and the
local APIM tutorial scripts.

$(shell_cli_standard_options)
EOF
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

port_in_use() {
  local port="$1"

  if have_cmd lsof; then
    lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
    return $?
  fi

  if have_cmd ss; then
    ss -H -ltn "sport = :${port}" 2>/dev/null | rg -q .
    return $?
  fi

  echo "Neither lsof nor ss is available; cannot inspect host ports." >&2
  exit 2
}

pick_free_port() {
  local start="$1"
  local end="$2"
  local port

  for port in $(seq "$start" "$end"); do
    if ! port_in_use "$port"; then
      printf '%s\n' "$port"
      return 0
    fi
  done

  echo "No free port found in range ${start}-${end}" >&2
  exit 1
}

configure_walkthrough_ports() {
  local requested_port="${TODO_FRONTEND_PORT:-3000}"

  if port_in_use "$requested_port"; then
    if [[ "$requested_port" == "3000" ]]; then
      TODO_FRONTEND_PORT="$(pick_free_port 3300 3399)"
      TODO_FRONTEND_PORT_REMAPPED=1
    else
      echo "Requested TODO_FRONTEND_PORT $requested_port is already in use" >&2
      exit 1
    fi
  else
    TODO_FRONTEND_PORT="$requested_port"
    TODO_FRONTEND_PORT_REMAPPED=0
  fi

  export TODO_FRONTEND_PORT
  export TODO_FRONTEND_PORT_REMAPPED
  export TODO_APIM_BASE_URL="${TODO_APIM_BASE_URL:-$APIM_LOOPBACK_BASE_URL}"
  export TODO_FRONTEND_BASE_URL="http://127.0.0.1:${TODO_FRONTEND_PORT}"
  export TODO_FRONTEND_BROWSER_URL="http://localhost:${TODO_FRONTEND_PORT}"
  export TODO_FRONTEND_ORIGIN_LOCALHOST="http://localhost:${TODO_FRONTEND_PORT}"
  export TODO_FRONTEND_ORIGIN_LOOPBACK="http://127.0.0.1:${TODO_FRONTEND_PORT}"
}

install_showboat_bash_env() {
  SHOWBOAT_BASH_ENV="$(mktemp)"
  cat >"$SHOWBOAT_BASH_ENV" <<'EOF'
port_in_use() {
  local port="$1"

  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
    return $?
  fi

  if command -v ss >/dev/null 2>&1; then
    ss -H -ltn "sport = :${port}" 2>/dev/null | grep -q .
    return $?
  fi

  return 1
}

wait_for_port_release() {
  local port="$1"
  local attempt
  local max_attempts="${SHOWBOAT_PORT_CLEAR_ATTEMPTS:-120}"
  local retry_after="${SHOWBOAT_PORT_CLEAR_RETRY_AFTER:-30}"
  local retried=0
  [[ -n "$port" ]] || return 0

  for attempt in $(seq 1 "$max_attempts"); do
    if ! port_in_use "$port"; then
      return 0
    fi

    if [[ "$retried" -eq 0 && "$attempt" -eq "$retry_after" ]]; then
      echo "host port $port still busy after ${retry_after}s; retrying make down once" >&2
      command make down >/dev/null 2>&1 || true
      retried=1
    fi

    sleep 1
  done

  echo "host port $port did not clear after docker compose down (${max_attempts}s)" >&2
  if command -v docker >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    docker ps --format json --filter "publish=${port}" | jq -sS . >&2 || true
  fi
  return 1
}

after_down_wait() {
  local ports=(
    "${APIM_GATEWAY_PORT:-8000}"
    "${GRAFANA_PORT:-8443}"
    "${OTEL_GRPC_PORT:-4317}"
    "${OTEL_HTTP_PORT:-4318}"
    "${OPERATOR_CONSOLE_PORT:-3007}"
    "${EDGE_HTTP_PORT:-8088}"
    "${EDGE_TLS_HTTP_PORT:-8080}"
    "${EDGE_TLS_PORT:-9443}"
    "${KEYCLOAK_PORT:-8180}"
  )
  local port

  if [[ -n "${TODO_FRONTEND_PORT:-}" ]]; then
    ports+=("${TODO_FRONTEND_PORT}")
  fi

  for port in "${ports[@]}"; do
    wait_for_port_release "$port"
  done
}

make() {
  command make "$@"
  local status=$?

  if [[ $status -eq 0 && "${1:-}" == "down" ]]; then
    after_down_wait
  fi

  return $status
}

tutorial_cleanup_and_wait() {
  ./docs/tutorials/apim-get-started/tutorial-cleanup.sh --execute >/dev/null 2>&1 || true
  after_down_wait
}
EOF
  export BASH_ENV="$SHOWBOAT_BASH_ENV"
}

cleanup_doc() {
  local doc="$1"
  local asset
  if [[ ! -f "$doc" ]]; then
    return
  fi

  while IFS= read -r asset; do
    [[ -n "$asset" ]] || continue
    rm -f "$(dirname "$doc")/$asset"
  done < <(sed -n 's/^!\[[^]]*\](\(.*\))$/\1/p' "$doc")

  rm -f "$doc"
}

sanitize_walkthrough_doc() {
  local doc="$1"
  [[ -f "$doc" ]] || return

  perl -0pi -e "s|\Q$ROOT_DIR\E|.|g" "$doc"
}

cleanup_stacks() {
  (cd "$ROOT_DIR" && make down-all >/dev/null 2>&1) || true
  (cd "$ROOT_DIR" && make down >/dev/null 2>&1) || true
}

cleanup_stage_images() {
  rm -f \
    "$ROOT_DIR/walkthrough-core-grafana.png" \
    "$ROOT_DIR/walkthrough-core-operator-console.png" \
    "$ROOT_DIR/walkthrough-example-todo.png"
}

ensure_rodney() {
  if ! rodney status >/dev/null 2>&1; then
    rodney start >/dev/null
  fi
}

sb_note() {
  local doc="$1"
  showboat note "$doc"
}

sb_exec() {
  local doc="$1"
  showboat exec --workdir "$ROOT_DIR" "$doc" bash
}

sb_image() {
  local doc="$1"
  showboat image --workdir "$ROOT_DIR" "$doc"
}

split_doc_by_h2() {
  local source="$1"
  shift

  uv run --project "$ROOT_DIR" python - "$source" "$DOCS_DIR" "$@" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1])
docs_dir = Path(sys.argv[2])
mappings = [arg.split("::", 1) for arg in sys.argv[3:]]

lines = source.read_text(encoding="utf-8").splitlines()
sections: dict[str, str] = {}
current_heading: str | None = None
buffer: list[str] = []

for line in lines:
    if line.startswith("## "):
        if current_heading is not None:
            sections[current_heading] = "\n".join(buffer).strip() + "\n"
        current_heading = line[3:].strip()
        buffer = []
        continue
    if current_heading is not None:
        buffer.append(line)

if current_heading is not None:
    sections[current_heading] = "\n".join(buffer).strip() + "\n"

for slug, heading in mappings:
    body = sections.get(heading)
    if body is None:
        raise SystemExit(f"missing heading {heading!r} in {source}")
    target = docs_dir / f"walkthrough-{slug}.md"
    target.write_text(
        f"# APIM Simulator Walkthrough: {heading}\n\n"
        "Generated from a live run against the local repository.\n\n"
        f"{body}",
        encoding="utf-8",
    )
PY
}

init_doc() {
  local doc="$1"
  local title="$2"
  cleanup_doc "$doc"
  showboat init "$doc" "$title"
}

generate_core_doc() {
  init_doc "$DOC_CORE" "APIM Simulator Walkthrough: Core Compose Stacks"

  sb_note "$DOC_CORE" <<'EOF'
This document was generated from a live run against the local repository. Each section starts the stack, waits for it to become ready, and captures a concise JSON summary plus screenshots where the stack has a browser surface.
EOF

  sb_note "$DOC_CORE" <<'EOF'
## Direct Public Gateway
`make up` is the smallest APIM-shaped path: gateway, mock backend, and the management surface on `localhost:8000`.
EOF

  sb_exec "$DOC_CORE" <<'EOF'
set -euo pipefail
make down >/dev/null 2>&1 || true
log="$(mktemp)"
make up >"$log" 2>&1 || { cat "$log"; exit 1; }
for _ in $(seq 1 60); do
  curl -fsS http://localhost:8000/apim/health >/dev/null 2>&1 && break
  sleep 1
done
docker compose -f compose.yml -f compose.public.yml ps --format json | jq -sS .
rm -f "$log"
EOF

  sb_exec "$DOC_CORE" <<'EOF'
set -euo pipefail
health="$(curl -fsS http://localhost:8000/apim/health)"
startup="$(curl -fsS http://localhost:8000/apim/startup)"
status="$(curl -fsS -H 'X-Apim-Tenant-Key: local-dev-tenant-key' http://localhost:8000/apim/management/status)"
echo_payload="$(curl -fsS http://localhost:8000/api/echo)"
jq -n \
  --argjson health "$health" \
  --argjson startup "$startup" \
  --argjson status "$status" \
  --argjson echo_payload "$echo_payload" \
  '{
    health: $health,
    startup: $startup,
    management: {
      service: $status.service,
      counts: $status.counts
    },
    echo: {
      path: $echo_payload.path,
      auth_method: $echo_payload.headers["x-apim-auth-method"],
      user_email: $echo_payload.headers["x-apim-user-email"]
    }
  }'
EOF

  sb_note "$DOC_CORE" <<EOF
## Direct Public Gateway With OTEL
`make up-otel` adds the LGTM stack on [$GRAFANA_BASE_URL]($GRAFANA_BASE_URL) so APIM traffic is visible in Grafana, Loki, Tempo, and Prometheus.
EOF

  sb_exec "$DOC_CORE" <<'EOF'
set -euo pipefail
make down >/dev/null 2>&1 || true
log="$(mktemp)"
make up-otel >"$log" 2>&1 || { cat "$log"; exit 1; }
for _ in $(seq 1 90); do
  curl -fsS http://localhost:8000/apim/health >/dev/null 2>&1 && curl -fsS "$GRAFANA_BASE_URL/api/health" >/dev/null 2>&1 && break
  sleep 1
done
docker compose -f compose.yml -f compose.public.yml -f compose.otel.yml ps --format json | jq -sS .
rm -f "$log"
EOF

  sb_exec "$DOC_CORE" <<'EOF'
set -euo pipefail
verify_log="$(mktemp)"
make verify-otel >"$verify_log" 2>&1 || { cat "$verify_log"; exit 1; }
apim_health="$(curl -fsS http://localhost:8000/apim/health)"
grafana_health="$(curl -fsS "$GRAFANA_BASE_URL/api/health")"
jq -n \
  --argjson apim_health "$apim_health" \
  --argjson grafana_health "$grafana_health" \
  --arg verify_log "$(cat "$verify_log")" \
  '{
    apim_health: $apim_health,
    grafana_health: $grafana_health,
    verify_otel: "passed",
    verify_output: ($verify_log | split("\n") | map(select(length > 0)))
  }'
rm -f "$verify_log"
EOF

  sb_image "$DOC_CORE" <<'EOF'
set -euo pipefail
rodney stop >/dev/null 2>&1 || true
rm -f "$HOME/.rodney/chrome-data/SingletonLock"
rodney start >/tmp/rodney-start.log 2>&1 || true
sleep 2
rodney open "$GRAFANA_BASE_URL/d/apim-simulator-overview/apim-simulator-overview" >/dev/null
rodney waitload >/dev/null
rodney waitstable >/dev/null
rodney sleep 2 >/dev/null
rodney screenshot walkthrough-core-grafana.png
EOF

  sb_note "$DOC_CORE" <<'EOF'
## OIDC Gateway
`make up-oidc` adds Keycloak and the OIDC-protected routes used by the simulator’s JWT and role-based auth examples.
EOF

  sb_exec "$DOC_CORE" <<'EOF'
set -euo pipefail
make down >/dev/null 2>&1 || true
log="$(mktemp)"
make up-oidc >"$log" 2>&1 || { cat "$log"; exit 1; }
for _ in $(seq 1 90); do
  curl -fsS http://localhost:8000/apim/health >/dev/null 2>&1 && curl -fsS http://localhost:8180/realms/subnet-calculator/.well-known/openid-configuration >/dev/null 2>&1 && break
  sleep 1
done
docker compose -f compose.yml -f compose.public.yml -f compose.oidc.yml ps --format json | jq -sS .
rm -f "$log"
EOF

  sb_exec "$DOC_CORE" <<'EOF'
set -euo pipefail
smoke_log="$(mktemp)"
make smoke-oidc >"$smoke_log" 2>&1 || { cat "$smoke_log"; exit 1; }
well_known="$(curl -fsS http://localhost:8180/realms/subnet-calculator/.well-known/openid-configuration)"
jq -n \
  --argjson well_known "$well_known" \
  --arg smoke_log "$(cat "$smoke_log")" \
  '{
    oidc: {
      issuer: $well_known.issuer,
      authorization_endpoint: $well_known.authorization_endpoint,
      token_endpoint: $well_known.token_endpoint
    },
    smoke_oidc: "passed",
    smoke_output: ($smoke_log | split("\n") | map(select(length > 0)))
  }'
rm -f "$smoke_log"
EOF

  sb_note "$DOC_CORE" <<'EOF'
## MCP Gateway
`make up-mcp` fronts the example MCP server through APIM and keeps the simulator’s management surface available on the same gateway.
EOF

  sb_exec "$DOC_CORE" <<'EOF'
set -euo pipefail
make down >/dev/null 2>&1 || true
log="$(mktemp)"
make up-mcp >"$log" 2>&1 || { cat "$log"; exit 1; }
for _ in $(seq 1 90); do
  curl -fsS http://localhost:8000/apim/health >/dev/null 2>&1 && break
  sleep 1
done
docker compose -f compose.yml -f compose.public.yml -f compose.mcp.yml ps --format json | jq -sS .
rm -f "$log"
EOF

  sb_exec "$DOC_CORE" <<'EOF'
set -euo pipefail
smoke_log="$(mktemp)"
make smoke-mcp >"$smoke_log" 2>&1 || { cat "$smoke_log"; exit 1; }
status="$(curl -fsS -H 'X-Apim-Tenant-Key: local-dev-tenant-key' http://localhost:8000/apim/management/status)"
jq -n \
  --argjson status "$status" \
  --arg smoke_log "$(cat "$smoke_log")" \
  '{
    management: {
      service: $status.service,
      counts: $status.counts
    },
    smoke_mcp: "passed",
    smoke_output: ($smoke_log | split("\n") | map(select(length > 0)))
  }'
rm -f "$smoke_log"
EOF

  sb_note "$DOC_CORE" <<'EOF'
## Edge HTTP
`make up-edge` terminates through the nginx edge proxy on `edge.apim.127.0.0.1.sslip.io:8088` and verifies forwarded-host behavior before the request reaches APIM and the MCP backend.
EOF

  sb_exec "$DOC_CORE" <<'EOF'
set -euo pipefail
make down >/dev/null 2>&1 || true
log="$(mktemp)"
make up-edge >"$log" 2>&1 || { cat "$log"; exit 1; }
for _ in $(seq 1 90); do
  curl -fsS http://edge.apim.127.0.0.1.sslip.io:8088/apim/health >/dev/null 2>&1 && break
  sleep 1
done
docker compose -f compose.yml -f compose.edge.yml -f compose.mcp.yml ps --format json | jq -sS .
rm -f "$log"
EOF

  sb_exec "$DOC_CORE" <<'EOF'
set -euo pipefail
smoke_log="$(mktemp)"
make smoke-edge >"$smoke_log" 2>&1 || { cat "$smoke_log"; exit 1; }
edge_echo="$(curl -fsS -H 'Ocp-Apim-Subscription-Key: mcp-demo-key' -H 'x-apim-trace: true' http://edge.apim.127.0.0.1.sslip.io:8088/__edge/echo)"
jq -n \
  --argjson edge_echo "$edge_echo" \
  --arg smoke_log "$(cat "$smoke_log")" \
  '{
    edge_echo: {
      path: $edge_echo.path,
      host: $edge_echo.headers.host,
      forwarded_host: $edge_echo.headers["x-forwarded-host"],
      forwarded_proto: $edge_echo.headers["x-forwarded-proto"]
    },
    smoke_edge: "passed",
    smoke_output: ($smoke_log | split("\n") | map(select(length > 0)))
  }'
rm -f "$smoke_log"
EOF

  sb_note "$DOC_CORE" <<'EOF'
## Edge TLS
`make up-tls` uses the generated development certificate and the same forwarded-header path, but on `https://edge.apim.127.0.0.1.sslip.io:9443`.
EOF

  sb_exec "$DOC_CORE" <<'EOF'
set -euo pipefail
make down >/dev/null 2>&1 || true
log="$(mktemp)"
make up-tls >"$log" 2>&1 || { cat "$log"; exit 1; }
for _ in $(seq 1 90); do
  curl --cacert examples/edge/certs/dev-root-ca.crt -fsS https://edge.apim.127.0.0.1.sslip.io:9443/apim/health >/dev/null 2>&1 && break
  sleep 1
done
docker compose -f compose.yml -f compose.edge.yml -f compose.tls.yml -f compose.mcp.yml ps --format json | jq -sS .
rm -f "$log"
EOF

  sb_exec "$DOC_CORE" <<'EOF'
set -euo pipefail
smoke_log="$(mktemp)"
make smoke-tls >"$smoke_log" 2>&1 || { cat "$smoke_log"; exit 1; }
edge_echo="$(curl --cacert examples/edge/certs/dev-root-ca.crt -fsS -H 'Ocp-Apim-Subscription-Key: mcp-demo-key' -H 'x-apim-trace: true' https://edge.apim.127.0.0.1.sslip.io:9443/__edge/echo)"
jq -n \
  --argjson edge_echo "$edge_echo" \
  --arg smoke_log "$(cat "$smoke_log")" \
  '{
    edge_echo: {
      path: $edge_echo.path,
      host: $edge_echo.headers.host,
      forwarded_host: $edge_echo.headers["x-forwarded-host"],
      forwarded_proto: $edge_echo.headers["x-forwarded-proto"]
    },
    smoke_tls: "passed",
    smoke_output: ($smoke_log | split("\n") | map(select(length > 0)))
  }'
rm -f "$smoke_log"
EOF

  sb_note "$DOC_CORE" <<'EOF'
## Private Internal Stack
The private shape intentionally does not publish `localhost:8000`. Validation happens through the internal smoke runner container instead.
EOF

  sb_exec "$DOC_CORE" <<'EOF'
set -euo pipefail
make down >/dev/null 2>&1 || true
log="$(mktemp)"
docker compose -f compose.yml -f compose.private.yml -f compose.mcp.yml up --build -d >"$log" 2>&1 || { cat "$log"; exit 1; }
docker compose -f compose.yml -f compose.private.yml -f compose.mcp.yml ps --format json | jq -sS .
rm -f "$log"
EOF

  sb_exec "$DOC_CORE" <<'EOF'
set -euo pipefail
smoke_log="$(mktemp)"
make smoke-private >"$smoke_log" 2>&1 || { cat "$smoke_log"; exit 1; }
jq -n \
  --arg smoke_log "$(cat "$smoke_log")" \
  '{
    localhost_8000_reachable: false,
    smoke_private: "passed",
    smoke_output: ($smoke_log | split("\n") | map(select(length > 0)))
  }'
rm -f "$smoke_log"
EOF

  sb_note "$DOC_CORE" <<'EOF'
## Operator Console
`make up-ui` adds the local operator console on `localhost:3007` against a management-enabled APIM stack.
EOF

  sb_exec "$DOC_CORE" <<'EOF'
set -euo pipefail
make down >/dev/null 2>&1 || true
log="$(mktemp)"
make up-ui >"$log" 2>&1 || { cat "$log"; exit 1; }
ready=false
for _ in $(seq 1 120); do
  if curl -fsS http://localhost:8000/apim/health >/dev/null 2>&1 && curl -fsS http://localhost:3007 >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 1
done
if [[ "$ready" != true ]]; then
  echo "operator console did not become ready on http://localhost:3007 within 120 seconds" >&2
  docker compose -f compose.yml -f compose.public.yml -f compose.ui.yml ps -a --format json | jq -sS .
  docker compose -f compose.yml -f compose.public.yml -f compose.ui.yml logs --tail 200 ui || true
  exit 1
fi
docker compose -f compose.yml -f compose.public.yml -f compose.ui.yml ps -a --format json | jq -sS .
rm -f "$log"
EOF

  sb_exec "$DOC_CORE" <<'EOF'
set -euo pipefail
status="$(curl -fsS -H 'X-Apim-Tenant-Key: local-dev-tenant-key' http://localhost:8000/apim/management/status)"
jq -n \
  --argjson status "$status" \
  '{
    operator_console: {
      url: "http://localhost:3007",
      gateway_target: "http://localhost:8000"
    },
    management: {
      service: $status.service,
      counts: $status.counts
    }
  }'
EOF

  sb_image "$DOC_CORE" <<'EOF'
set -euo pipefail
rodney stop >/dev/null 2>&1 || true
rm -f "$HOME/.rodney/chrome-data/SingletonLock"
rodney start >/tmp/rodney-start.log 2>&1 || true
sleep 2
rodney open http://localhost:3007 >/dev/null
rodney waitload >/dev/null
rodney waitstable >/dev/null
rodney sleep 2 >/dev/null
rodney screenshot walkthrough-core-operator-console.png
EOF

  sanitize_walkthrough_doc "$DOC_CORE"

  split_doc_by_h2 "$DOC_CORE" \
    'direct-public-gateway::Direct Public Gateway' \
    'direct-public-gateway-otel::Direct Public Gateway With OTEL' \
    'oidc-gateway::OIDC Gateway' \
    'mcp-gateway::MCP Gateway' \
    'edge-http::Edge HTTP' \
    'edge-tls::Edge TLS' \
    'private-internal-stack::Private Internal Stack' \
    'operator-console::Operator Console'

}

generate_example_doc() {
  init_doc "$DOC_EXAMPLES" "APIM Simulator Walkthrough: Example Stacks"

  sb_note "$DOC_EXAMPLES" <<'EOF'
This document covers the higher-level examples shipped with the repo: the hello starter variants, the browser-backed todo demo, and the Bruno collection used to exercise the todo API through APIM.
EOF

  if [[ "$TODO_FRONTEND_PORT_REMAPPED" == "1" ]]; then
    sb_note "$DOC_EXAMPLES" <<'EOF'
Port `3000` was already occupied during generation, so the todo sections in this captured run use an alternate frontend binding. The stack behavior is the same; only the host-facing Astro port changed.
EOF
  fi

  sb_note "$DOC_EXAMPLES" <<'EOF'
## Hello Starter
`make up-hello` puts the smallest checked-in backend behind APIM with anonymous access.
EOF

  sb_exec "$DOC_EXAMPLES" <<'EOF'
set -euo pipefail
make down >/dev/null 2>&1 || true
log="$(mktemp)"
make up-hello >"$log" 2>&1 || { cat "$log"; exit 1; }
for _ in $(seq 1 90); do
  curl -fsS http://localhost:8000/api/health >/dev/null 2>&1 && break
  sleep 1
done
docker compose -f compose.yml -f compose.public.yml -f compose.hello.yml ps --format json | jq -sS .
rm -f "$log"
EOF

  sb_exec "$DOC_EXAMPLES" <<'EOF'
set -euo pipefail
health="$(curl -fsS http://localhost:8000/api/health)"
hello="$(curl -fsS 'http://localhost:8000/api/hello?name=team')"
jq -n \
  --argjson health "$health" \
  --argjson hello "$hello" \
  '{health: $health, hello: $hello}'
EOF

  sb_note "$DOC_EXAMPLES" <<'EOF'
## Hello Starter With Subscription
`make up-hello-subscription` adds APIM product protection and the demo subscription key checks.
EOF

  sb_exec "$DOC_EXAMPLES" <<'EOF'
set -euo pipefail
make down >/dev/null 2>&1 || true
log="$(mktemp)"
make up-hello-subscription >"$log" 2>&1 || { cat "$log"; exit 1; }
for _ in $(seq 1 90); do
  curl -fsS http://localhost:8000/apim/health >/dev/null 2>&1 && break
  sleep 1
done
docker compose -f compose.yml -f compose.public.yml -f compose.hello.yml ps --format json | jq -sS .
rm -f "$log"
EOF

  sb_exec "$DOC_EXAMPLES" <<'EOF'
set -euo pipefail
uv run --project . python - <<'PY'
import json
import httpx

client = httpx.Client(timeout=10.0)
missing = client.get("http://localhost:8000/api/health")
invalid = client.get(
    "http://localhost:8000/api/health",
    headers={"Ocp-Apim-Subscription-Key": "hello-demo-key-invalid"},
)
valid = client.get(
    "http://localhost:8000/api/hello?name=subscription",
    headers={"Ocp-Apim-Subscription-Key": "hello-demo-key"},
)
valid.raise_for_status()
summary = {
    "missing_subscription": {"status": missing.status_code, "body": missing.json()},
    "invalid_subscription": {"status": invalid.status_code, "body": invalid.json()},
    "valid_subscription": {
        "status": valid.status_code,
        "policy_header": valid.headers.get("x-hello-policy"),
        "body": valid.json(),
    },
}
print(json.dumps(summary, indent=2, sort_keys=True))
PY
EOF

  sb_note "$DOC_EXAMPLES" <<'EOF'
## Hello Starter With OIDC
`make up-hello-oidc` keeps the hello backend but fronts it with Keycloak-backed bearer token validation.
EOF

  sb_exec "$DOC_EXAMPLES" <<'EOF'
set -euo pipefail
make down >/dev/null 2>&1 || true
log="$(mktemp)"
make up-hello-oidc >"$log" 2>&1 || { cat "$log"; exit 1; }
for _ in $(seq 1 90); do
  curl -fsS http://localhost:8000/apim/health >/dev/null 2>&1 && curl -fsS http://localhost:8180/realms/subnet-calculator/.well-known/openid-configuration >/dev/null 2>&1 && break
  sleep 1
done
docker compose -f compose.yml -f compose.public.yml -f compose.oidc.yml -f compose.hello.yml ps --format json | jq -sS .
rm -f "$log"
EOF

  sb_exec "$DOC_EXAMPLES" <<'EOF'
set -euo pipefail
smoke_log="$(mktemp)"
SMOKE_HELLO_MODE=oidc-jwt make smoke-hello >"$smoke_log" 2>&1 || { cat "$smoke_log"; exit 1; }
well_known="$(curl -fsS http://localhost:8180/realms/subnet-calculator/.well-known/openid-configuration)"
jq -n \
  --argjson well_known "$well_known" \
  --arg smoke_log "$(cat "$smoke_log")" \
  '{
    oidc: {
      issuer: $well_known.issuer,
      token_endpoint: $well_known.token_endpoint
    },
    smoke_hello: "passed",
    smoke_output: ($smoke_log | split("\n") | map(select(length > 0)))
  }'
rm -f "$smoke_log"
EOF

  sb_note "$DOC_EXAMPLES" <<'EOF'
## Hello Starter With OIDC And Subscription
`make up-hello-oidc-subscription` combines bearer token checks with the APIM product subscription gate.
EOF

  sb_exec "$DOC_EXAMPLES" <<'EOF'
set -euo pipefail
make down >/dev/null 2>&1 || true
log="$(mktemp)"
make up-hello-oidc-subscription >"$log" 2>&1 || { cat "$log"; exit 1; }
for _ in $(seq 1 90); do
  curl -fsS http://localhost:8000/apim/health >/dev/null 2>&1 && curl -fsS http://localhost:8180/realms/subnet-calculator/.well-known/openid-configuration >/dev/null 2>&1 && break
  sleep 1
done
docker compose -f compose.yml -f compose.public.yml -f compose.oidc.yml -f compose.hello.yml ps --format json | jq -sS .
rm -f "$log"
EOF

  sb_exec "$DOC_EXAMPLES" <<'EOF'
set -euo pipefail
smoke_log="$(mktemp)"
SMOKE_HELLO_MODE=oidc-subscription make smoke-hello >"$smoke_log" 2>&1 || { cat "$smoke_log"; exit 1; }
well_known="$(curl -fsS http://localhost:8180/realms/subnet-calculator/.well-known/openid-configuration)"
jq -n \
  --argjson well_known "$well_known" \
  --arg smoke_log "$(cat "$smoke_log")" \
  '{
    oidc: {
      issuer: $well_known.issuer,
      token_endpoint: $well_known.token_endpoint
    },
    smoke_hello: "passed",
    smoke_output: ($smoke_log | split("\n") | map(select(length > 0)))
  }'
rm -f "$smoke_log"
EOF

  sb_note "$DOC_EXAMPLES" <<'EOF'
## Hello Starter With OTEL
`make up-hello-otel` adds the same LGTM stack used by the core OTEL walkthrough, but this time the hello backend emits its own logs, metrics, and traces too.
EOF

  sb_exec "$DOC_EXAMPLES" <<'EOF'
set -euo pipefail
make down >/dev/null 2>&1 || true
log="$(mktemp)"
make up-hello-otel >"$log" 2>&1 || { cat "$log"; exit 1; }
for _ in $(seq 1 90); do
  curl -fsS http://localhost:8000/api/health >/dev/null 2>&1 && curl -fsS "$GRAFANA_BASE_URL/api/health" >/dev/null 2>&1 && break
  sleep 1
done
docker compose -f compose.yml -f compose.public.yml -f compose.hello.yml -f compose.otel.yml -f compose.hello.otel.yml ps --format json | jq -sS .
rm -f "$log"
EOF

  sb_exec "$DOC_EXAMPLES" <<'EOF'
set -euo pipefail
verify_log="$(mktemp)"
make verify-hello-otel >"$verify_log" 2>&1 || { cat "$verify_log"; exit 1; }
grafana_health="$(curl -fsS "$GRAFANA_BASE_URL/api/health")"
jq -n \
  --argjson grafana_health "$grafana_health" \
  --arg verify_log "$(cat "$verify_log")" \
  '{
    grafana_health: $grafana_health,
    verify_hello_otel: "passed",
    verify_output: ($verify_log | split("\n") | map(select(length > 0)))
  }'
rm -f "$verify_log"
EOF

  sb_note "$DOC_EXAMPLES" <<EOF
## Todo Demo
\`make up-todo\` is the most user-facing stack in the repo: Astro frontend on \`$TODO_FRONTEND_BROWSER_URL\`, APIM on \`localhost:8000\`, and the FastAPI todo backend behind it.
EOF

  sb_exec "$DOC_EXAMPLES" <<'EOF'
set -euo pipefail
make down >/dev/null 2>&1 || true
log="$(mktemp)"
make up-todo >"$log" 2>&1 || { cat "$log"; exit 1; }
ready=false
for _ in $(seq 1 120); do
  if curl -fsS "$TODO_FRONTEND_BASE_URL" 2>/dev/null | rg -q 'Gateway-Proof Todo' \
    && curl -fsS http://localhost:8000/apim/health >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 1
done
if [[ "$ready" != true ]]; then
  echo "todo demo did not become ready within 120 seconds" >&2
  docker compose -f compose.todo.yml ps -a --format json | jq -sS .
  docker compose -f compose.todo.yml logs --tail 200 todo-frontend apim-simulator todo-api || true
  exit 1
fi
docker compose -f compose.todo.yml ps --format json | jq -sS .
rm -f "$log"
EOF

  sb_exec "$DOC_EXAMPLES" <<'EOF'
set -euo pipefail
uv run --project . python - <<'PY'
import json
import os
import time
import uuid
import httpx

title = f"walkthrough-{uuid.uuid4().hex[:8]}"
client = httpx.Client(timeout=10.0)
apim_base_url = os.environ["TODO_APIM_BASE_URL"]
frontend_base_url = os.environ["TODO_FRONTEND_BASE_URL"]
subscription_key = os.environ.get("TODO_SUBSCRIPTION_KEY", "todo-demo-key")
invalid_subscription_key = os.environ.get("TODO_INVALID_SUBSCRIPTION_KEY", "todo-demo-key-invalid")

def wait_for(url: str, label: str, timeout_seconds: float = 60.0) -> None:
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        try:
            response = client.get(url)
            if response.is_success:
                return
        except httpx.HTTPError:
            pass
        time.sleep(1)
    raise RuntimeError(f"timed out waiting for {label}: {url}")

wait_for(f"{apim_base_url}/apim/health", "gateway health")
deadline = time.time() + 120.0
frontend = None
while time.time() < deadline:
    try:
        candidate = client.get(frontend_base_url)
        if candidate.is_success and "Gateway-Proof Todo" in candidate.text:
            frontend = candidate
            break
    except httpx.HTTPError:
        pass
    time.sleep(1)
if frontend is None:
    raise RuntimeError(f"timed out waiting for todo frontend: {frontend_base_url}")
health = client.get(
    f"{apim_base_url}/api/health",
    headers={"Ocp-Apim-Subscription-Key": subscription_key},
)
health.raise_for_status()
missing = client.get(f"{apim_base_url}/api/todos")
invalid = client.get(
    f"{apim_base_url}/api/todos",
    headers={"Ocp-Apim-Subscription-Key": invalid_subscription_key},
)
created = client.post(
    f"{apim_base_url}/api/todos",
    headers={"Ocp-Apim-Subscription-Key": subscription_key},
    json={"title": title},
)
created.raise_for_status()
created_payload = created.json()
updated = client.patch(
    f"{apim_base_url}/api/todos/{created_payload['id']}",
    headers={"Ocp-Apim-Subscription-Key": subscription_key},
    json={"completed": True},
)
updated.raise_for_status()
listed = client.get(
    f"{apim_base_url}/api/todos",
    headers={"Ocp-Apim-Subscription-Key": subscription_key},
)
listed.raise_for_status()
listed_payload = listed.json()
summary = {
    "frontend_base_url": frontend_base_url,
    "frontend_title_present": "Gateway-Proof Todo" in frontend.text,
    "health": {
        "status": health.status_code,
        "policy_header": health.headers.get("x-todo-demo-policy"),
        "body": health.json(),
    },
    "missing_subscription": {"status": missing.status_code, "body": missing.json()},
    "invalid_subscription": {"status": invalid.status_code, "body": invalid.json()},
    "created_todo": created_payload,
    "updated_todo": updated.json(),
    "list_count": len(listed_payload["items"]),
}
print(json.dumps(summary, indent=2, sort_keys=True))
PY
EOF

  sb_image "$DOC_EXAMPLES" <<'EOF'
set -euo pipefail
rodney stop >/dev/null 2>&1 || true
rm -f "$HOME/.rodney/chrome-data/SingletonLock"
rodney start >/tmp/rodney-start.log 2>&1 || true
sleep 2
rodney open "$TODO_FRONTEND_BASE_URL" >/dev/null
rodney waitload >/dev/null
rodney waitstable >/dev/null
rodney sleep 2 >/dev/null
rodney screenshot walkthrough-example-todo.png
EOF

  sb_note "$DOC_EXAMPLES" <<'EOF'
## Bruno Collection Against The Todo Demo
The Bruno collection under `examples/todo-app/api-clients/bruno/` exercises the todo API through APIM in the same order documented in `docs/API-CLIENT-GUIDE.md`.
EOF

  sb_exec "$DOC_EXAMPLES" <<'EOF'
set -euo pipefail
report="$(mktemp)"
log="$(mktemp)"
env_file="$(mktemp)"
cat >"$env_file" <<BRUNO_ENV
vars {
  apimBaseUrl: $TODO_APIM_BASE_URL
  frontendOrigin: $TODO_FRONTEND_BASE_URL
  subscriptionKey: todo-demo-key
  invalidSubscriptionKey: todo-demo-key-invalid
}
BRUNO_ENV
(cd examples/todo-app/api-clients/bruno && npm exec --yes --package=@usebruno/cli -- bru run --env-file "$env_file" --reporter-json "$report" . >"$log" 2>&1) || { cat "$log"; rm -f "$env_file"; exit 1; }
jq -S '
  def report:
    if type == "array" then .[0] else . end;

  report as $report
  | {
      collection: ($report.collection.name // "todo-demo-bruno"),
      passed_requests: ($report.summary.passedRequests // $report.stats.passed),
      failed_requests: ($report.summary.failedRequests // $report.stats.failed),
      passed_tests: ($report.summary.passedTests // null),
      failed_tests: ($report.summary.failedTests // null),
      requests: [
        $report.results[] | {
          name,
          status,
          tests: (
            (.testResults // .tests // [])
            | map({
                name: (.description // .name // "unnamed"),
                status
              })
          )
        }
      ]
    }
' "$report"
rm -f "$env_file" "$report" "$log"
EOF

  sb_note "$DOC_EXAMPLES" <<'EOF'
## Todo Demo With OTEL
`make up-todo-otel` combines the browser-backed todo flow with the LGTM stack so the APIM route tags and todo backend telemetry are both visible.
EOF

  sb_exec "$DOC_EXAMPLES" <<'EOF'
set -euo pipefail
make down >/dev/null 2>&1 || true
log="$(mktemp)"
make up-todo-otel >"$log" 2>&1 || { cat "$log"; exit 1; }
ready=false
for _ in $(seq 1 120); do
  if curl -fsS "$TODO_FRONTEND_BASE_URL" 2>/dev/null | rg -q 'Gateway-Proof Todo' \
    && curl -fsS "$GRAFANA_BASE_URL/api/health" >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 1
done
if [[ "$ready" != true ]]; then
  echo "todo OTEL demo did not become ready within 120 seconds" >&2
  docker compose -f compose.todo.yml -f compose.todo.otel.yml ps -a --format json | jq -sS .
  docker compose -f compose.todo.yml -f compose.todo.otel.yml logs --tail 200 todo-frontend apim-simulator todo-api lgtm || true
  exit 1
fi
docker compose -f compose.todo.yml -f compose.todo.otel.yml ps --format json | jq -sS .
rm -f "$log"
EOF

  sb_exec "$DOC_EXAMPLES" <<'EOF'
set -euo pipefail
verify_log="$(mktemp)"
make verify-todo-otel >"$verify_log" 2>&1 || { cat "$verify_log"; exit 1; }
grafana_health="$(curl -fsS "$GRAFANA_BASE_URL/api/health")"
jq -n \
  --argjson grafana_health "$grafana_health" \
  --arg verify_log "$(cat "$verify_log")" \
  '{
    grafana_health: $grafana_health,
    verify_todo_otel: "passed",
    verify_output: ($verify_log | split("\n") | map(select(length > 0)))
  }'
rm -f "$verify_log"
EOF

  sanitize_walkthrough_doc "$DOC_EXAMPLES"

  split_doc_by_h2 "$DOC_EXAMPLES" \
    'hello-starter::Hello Starter' \
    'hello-starter-subscription::Hello Starter With Subscription' \
    'hello-starter-oidc::Hello Starter With OIDC' \
    'hello-starter-oidc-subscription::Hello Starter With OIDC And Subscription' \
    'hello-starter-otel::Hello Starter With OTEL' \
    'todo-demo::Todo Demo' \
    'todo-demo-bruno::Bruno Collection Against The Todo Demo' \
    'todo-demo-otel::Todo Demo With OTEL'
}

generate_tutorial_doc() {
  init_doc "$DOC_TUTORIALS" "APIM Simulator Walkthrough: APIM Get-Started Tutorial Mirror"

  sb_note "$DOC_TUTORIALS" <<'EOF'
This walkthrough runs every mirrored tutorial script under `docs/tutorials/apim-get-started/` with both `--setup` and `--verify`. The scripts already emit the closest local equivalent to each Microsoft Learn step, so the captured outputs here are the most direct proof that the tutorial mirror still behaves as documented.
EOF

  local tutorial
  for tutorial in $(seq -w 1 11); do
    sb_note "$DOC_TUTORIALS" <<EOF
## Tutorial ${tutorial}
Companion script: [tutorial${tutorial}.sh](tutorials/apim-get-started/tutorial${tutorial}.sh)
EOF

    sb_exec "$DOC_TUTORIALS" <<EOF
set -euo pipefail
tutorial_cleanup_and_wait
./docs/tutorials/apim-get-started/tutorial${tutorial}.sh --setup
./docs/tutorials/apim-get-started/tutorial${tutorial}.sh --verify
EOF

  done

  sanitize_walkthrough_doc "$DOC_TUTORIALS"

  split_doc_by_h2 "$DOC_TUTORIALS" \
    'apim-get-started-tutorial01::Tutorial 01' \
    'apim-get-started-tutorial02::Tutorial 02' \
    'apim-get-started-tutorial03::Tutorial 03' \
    'apim-get-started-tutorial04::Tutorial 04' \
    'apim-get-started-tutorial05::Tutorial 05' \
    'apim-get-started-tutorial06::Tutorial 06' \
    'apim-get-started-tutorial07::Tutorial 07' \
    'apim-get-started-tutorial08::Tutorial 08' \
    'apim-get-started-tutorial09::Tutorial 09' \
    'apim-get-started-tutorial10::Tutorial 10' \
    'apim-get-started-tutorial11::Tutorial 11'
}

main() {
  local section
  local -a sections

  shell_cli_init_standard_flags
  sections=()
  while [[ $# -gt 0 ]]; do
    if shell_cli_handle_standard_flag usage "$1"; then
      shift
      continue
    fi

    case "$1" in
      --)
        shift
        sections+=("$@")
        break
        ;;
      -*)
        shell_cli_unknown_flag "$(shell_cli_script_name)" "$1"
        usage >&2
        exit 1
        ;;
      *)
        sections+=("$1")
        shift
        ;;
    esac
  done

  if [[ "${#sections[@]}" -eq 0 ]]; then
    sections=(core examples tutorials)
  fi

  if [[ "${SHELL_CLI_DRY_RUN}" -eq 1 || "${SHELL_CLI_EXECUTE}" -ne 1 ]]; then
    usage
    echo "INFO dry-run: would generate walkthrough docs for sections: ${sections[*]}"
    exit 0
  fi

  trap 'cleanup_stacks; cleanup_stage_images; rodney stop >/dev/null 2>&1 || true; [[ -n "$SHOWBOAT_BASH_ENV" ]] && rm -f "$SHOWBOAT_BASH_ENV"' EXIT
  cleanup_stacks
  configure_walkthrough_ports
  install_showboat_bash_env
  ensure_rodney
  cleanup_stage_images

  for section in "${sections[@]}"; do
    case "$section" in
      core)
        generate_core_doc
        ;;
      examples)
        generate_example_doc
        ;;
      tutorials)
        generate_tutorial_doc
        ;;
      all)
        generate_core_doc
        generate_example_doc
        generate_tutorial_doc
        ;;
      *)
        echo "unknown walkthrough section: $section" >&2
        exit 2
        ;;
    esac
  done

  cleanup_stacks
}

main "$@"
