#!/usr/bin/env bash
set -euo pipefail

: "${RUN_DIR:?RUN_DIR is required}"
: "${SLICER_SOCKET:?SLICER_SOCKET is required}"
: "${SLICER_DOCKER_CONFIG_DIR:=$RUN_DIR/docker-config}"

mkdir -p "$RUN_DIR"
mkdir -p "$SLICER_DOCKER_CONFIG_DIR"
if [ ! -f "$SLICER_DOCKER_CONFIG_DIR/config.json" ]; then
  # Use a neutral Docker config so slicer-mac does not block on desktop
  # credential helpers while pulling the OCI base image.
  printf '{}\n' > "$SLICER_DOCKER_CONFIG_DIR/config.json"
fi

active_file="$RUN_DIR/slicer.sock.active"
system_socket="${SLICER_SYSTEM_SOCKET:-${HOME}/slicer-mac/slicer.sock}"
ignore_system_socket="${IGNORE_SYSTEM_SOCKET:-0}"
system_wait_seconds="${SLICER_SYSTEM_SOCKET_WAIT_SECONDS:-90}"

socket_ready() {
  local socket="$1"
  local output=""
  output="$(SLICER_URL="$socket" slicer vm list 2>&1)" && return 0
  if printf '%s' "$output" | grep -Eiq 'service not ready|503 Service Unavailable|preparing VM artifacts|launching guest'; then
    return 2
  fi
  return 1
}

# 1. System tray socket (highest priority - don't stomp on running instance)
if [ "$ignore_system_socket" != "1" ]; then
  # If a launchd/system daemon is starting up, wait for it before falling back
  # to a project-managed daemon.
  for _ in $(seq 1 "$system_wait_seconds"); do
    if [ -S "$system_socket" ]; then
      if socket_ready "$system_socket"; then
        echo "Using existing slicer-mac at ${system_socket}"
        echo "$system_socket" > "$active_file"
        exit 0
      fi
      rc=$?
      if [ "$rc" = "2" ]; then
        sleep 1
        continue
      fi
    fi
    sleep 1
  done
  if [ -S "$system_socket" ]; then
    echo "System socket present but not ready after ${system_wait_seconds}s; refusing to start a competing project daemon." >&2
    exit 1
  fi
fi

# 2. Project socket already responding
if [ -S "$SLICER_SOCKET" ] && SLICER_URL="$SLICER_SOCKET" slicer vm list >/dev/null 2>&1; then
  echo "slicer-mac already running at ${SLICER_SOCKET}"
  echo "$SLICER_SOCKET" > "$active_file"
  exit 0
fi

# 3. Start a project-managed daemon
: "${CONFIG_FILE:?CONFIG_FILE is required (needed to start project daemon)}"
: "${SLICER_RUNTIME_DIR:?SLICER_RUNTIME_DIR is required (needed to start project daemon)}"

mkdir -p "$SLICER_RUNTIME_DIR"
pid_file="$RUN_DIR/slicer-mac.pid"
log_file="$RUN_DIR/slicer-mac.log"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Missing config: $CONFIG_FILE (run: make render-config)"
  exit 1
fi

if [ -f "$pid_file" ]; then
  pid="$(cat "$pid_file")"
  if [ -n "$pid" ] && ps -p "$pid" >/dev/null 2>&1; then
    echo "Stopping stale project slicer-mac (pid=$pid)..."
    kill "$pid" >/dev/null 2>&1 || true
    for _ in $(seq 1 20); do
      ps -p "$pid" >/dev/null 2>&1 || break
      sleep 1
    done
    ps -p "$pid" >/dev/null 2>&1 && kill -9 "$pid" >/dev/null 2>&1 || true
  fi
  rm -f "$pid_file"
fi

(
  cd "$SLICER_RUNTIME_DIR"
  DOCKER_CONFIG="$SLICER_DOCKER_CONFIG_DIR" \
    nohup slicer-mac up --config "$CONFIG_FILE" --api-socket "$SLICER_SOCKET" >"$log_file" 2>&1 &
  echo $! > "$pid_file"
)
pid="$(cat "$pid_file")"
echo "Started project slicer-mac (pid=$pid, log=$log_file)"

for _ in $(seq 1 45); do
  if SLICER_URL="$SLICER_SOCKET" slicer vm list >/dev/null 2>&1; then
    echo "slicer-mac ready at ${SLICER_SOCKET}"
    echo "$SLICER_SOCKET" > "$active_file"
    exit 0
  fi
  sleep 2
done

echo "Timed out waiting for slicer-mac. Check $log_file"
kill "$pid" >/dev/null 2>&1 || true
rm -f "$pid_file"
exit 1
