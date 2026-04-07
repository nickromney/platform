#!/usr/bin/env bats

SCRIPT="/Users/nickromney/Developer/personal/apim-simulator/scripts/gen_dev_certs.sh"

setup() {
  export APIM_ROOT="$BATS_TEST_TMPDIR/apim-root"
  export CERT_DIR="$APIM_ROOT/examples/edge/certs"
}

@test "gen_dev_certs.sh writes the certificate bundle under an override root" {
  run env APIM_SIMULATOR_ROOT_DIR="$APIM_ROOT" "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Generated $CERT_DIR/apim.localtest.me.crt and $CERT_DIR/apim.localtest.me.key"* ]]
  [[ "$output" == *"Local CA available at $CERT_DIR/dev-root-ca.crt"* ]]
  [ -f "$CERT_DIR/apim.localtest.me.crt" ]
  [ -f "$CERT_DIR/apim.localtest.me.key" ]
  [ -f "$CERT_DIR/dev-root-ca.crt" ]
  [ -f "$CERT_DIR/dev-root-ca.key" ]

  run openssl x509 -in "$CERT_DIR/dev-root-ca.crt" -noout -text
  [ "$status" -eq 0 ]
  [[ "$output" == *"CA:TRUE"* ]]

  run openssl x509 -in "$CERT_DIR/apim.localtest.me.crt" -noout -text
  [ "$status" -eq 0 ]
  [[ "$output" == *"DNS:apim.localtest.me"* ]]
  [[ "$output" == *"DNS:localhost"* ]]
  [[ "$output" == *"IP Address:127.0.0.1"* ]]
}

@test "gen_dev_certs.sh keeps an existing valid CA on rerun" {
  run env APIM_SIMULATOR_ROOT_DIR="$APIM_ROOT" "$SCRIPT"
  [ "$status" -eq 0 ]

  before_ca_fingerprint="$(openssl x509 -in "$CERT_DIR/dev-root-ca.crt" -noout -fingerprint -sha256)"
  before_key_checksum="$(shasum -a 256 "$CERT_DIR/dev-root-ca.key" | awk '{print $1}')"

  run env APIM_SIMULATOR_ROOT_DIR="$APIM_ROOT" "$SCRIPT"
  [ "$status" -eq 0 ]

  after_ca_fingerprint="$(openssl x509 -in "$CERT_DIR/dev-root-ca.crt" -noout -fingerprint -sha256)"
  after_key_checksum="$(shasum -a 256 "$CERT_DIR/dev-root-ca.key" | awk '{print $1}')"

  [ "$before_ca_fingerprint" = "$after_ca_fingerprint" ]
  [ "$before_key_checksum" = "$after_key_checksum" ]
}
