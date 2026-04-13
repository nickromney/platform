#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "sentiment-api image serves local-only sentiment inference" {
  image_tag="platform-test/sentiment-api:bats"
  data_dir="$(mktemp -d)"
  port="$(python3 - <<'PY'
import socket

sock = socket.socket()
sock.bind(("127.0.0.1", 0))
print(sock.getsockname()[1])
sock.close()
PY
)"

  cleanup() {
    if [ -n "${container_id:-}" ]; then
      docker rm -f "${container_id}" >/dev/null 2>&1 || true
    fi
    rm -rf "${data_dir}"
  }
  trap cleanup EXIT

  run docker build -t "${image_tag}" "${REPO_ROOT}/apps/sentiment/api-sentiment"
  [ "${status}" -eq 0 ]

  container_id="$(
    docker run -d \
      -p "127.0.0.1:${port}:8080" \
      --read-only \
      --tmpfs /tmp:rw,noexec,nosuid,nodev,mode=1777 \
      -v "${data_dir}:/data" \
      "${image_tag}"
  )"

  for _ in $(seq 1 60); do
    if curl -fsS "http://127.0.0.1:${port}/api/v1/health" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  run curl -fsS \
    -H 'content-type: application/json' \
    -d '{"text":"I love how fast this is."}' \
    "http://127.0.0.1:${port}/api/v1/comments"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'"label"'* ]]
}
