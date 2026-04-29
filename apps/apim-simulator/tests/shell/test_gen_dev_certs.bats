#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/scripts/gen_dev_certs.sh"
  export APIM_ROOT="$BATS_TEST_TMPDIR/apim-root"
  export CERT_DIR="$APIM_ROOT/examples/edge/certs"
}

@test "gen_dev_certs.sh writes the certificate bundle under an override root" {
  run env APIM_SIMULATOR_ROOT_DIR="$APIM_ROOT" "$SCRIPT" --execute

  [ "$status" -eq 0 ]
  [[ "$output" == *"Generated $CERT_DIR/edge.apim.127.0.0.1.sslip.io.crt and $CERT_DIR/edge.apim.127.0.0.1.sslip.io.key"* ]]
  [[ "$output" == *"Local CA available at $CERT_DIR/dev-root-ca.crt"* ]]
  [ -f "$CERT_DIR/edge.apim.127.0.0.1.sslip.io.crt" ]
  [ -f "$CERT_DIR/edge.apim.127.0.0.1.sslip.io.key" ]
  [ -f "$CERT_DIR/dev-root-ca.crt" ]
  [ ! -f "$CERT_DIR/dev-root-ca.key" ]

  run openssl x509 -in "$CERT_DIR/dev-root-ca.crt" -noout -text
  [ "$status" -eq 0 ]
  [[ "$output" == *"CA:TRUE"* ]]

  run openssl x509 -in "$CERT_DIR/edge.apim.127.0.0.1.sslip.io.crt" -noout -text
  [ "$status" -eq 0 ]
  [[ "$output" == *"DNS:edge.apim.127.0.0.1.sslip.io"* ]]
  [[ "$output" == *"DNS:*.apim.127.0.0.1.sslip.io"* ]]
  [[ "$output" == *"DNS:localhost"* ]]
  [[ "$output" == *"IP Address:127.0.0.1"* ]]

  run openssl verify -CAfile "$CERT_DIR/dev-root-ca.crt" "$CERT_DIR/edge.apim.127.0.0.1.sslip.io.crt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$CERT_DIR/edge.apim.127.0.0.1.sslip.io.crt: OK"* ]]
}

@test "gen_dev_certs.sh keeps an existing valid CA on rerun" {
  run env APIM_SIMULATOR_ROOT_DIR="$APIM_ROOT" "$SCRIPT" --execute
  [ "$status" -eq 0 ]

  before_ca_fingerprint="$(openssl x509 -in "$CERT_DIR/dev-root-ca.crt" -noout -fingerprint -sha256)"

  run env APIM_SIMULATOR_ROOT_DIR="$APIM_ROOT" "$SCRIPT" --execute
  [ "$status" -eq 0 ]

  after_ca_fingerprint="$(openssl x509 -in "$CERT_DIR/dev-root-ca.crt" -noout -fingerprint -sha256)"

  [ "$before_ca_fingerprint" = "$after_ca_fingerprint" ]
}
