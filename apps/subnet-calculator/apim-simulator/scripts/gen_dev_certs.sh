#!/usr/bin/env sh
set -eu

DEFAULT_ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
ROOT_DIR="${APIM_SIMULATOR_ROOT_DIR:-$DEFAULT_ROOT_DIR}"
PLATFORM_ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/../../../.." && pwd)
CERT_DIR="$ROOT_DIR/examples/edge/certs"
CERT_PATH="$CERT_DIR/apim.localtest.me.crt"
KEY_PATH="$CERT_DIR/apim.localtest.me.key"
CA_CERT_PATH="$CERT_DIR/dev-root-ca.crt"
CA_KEY_PATH="$CERT_DIR/dev-root-ca.key"
CA_SERIAL_PATH="$CERT_DIR/dev-root-ca.srl"
CSR_PATH="$CERT_DIR/apim.localtest.me.csr"

# shellcheck source=/dev/null
. "$PLATFORM_ROOT_DIR/scripts/lib/shell-cli-posix.sh"

usage() {
  cat <<EOF
Usage: gen_dev_certs.sh [--dry-run] [--execute]

Generate the self-signed local edge TLS development certificates.
$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage \
  "would generate local edge TLS development certificates under $CERT_DIR" \
  "$@"

mkdir -p "$CERT_DIR"

TMP_CONFIG=$(mktemp)
trap 'rm -f "$TMP_CONFIG"' EXIT

cat >"$TMP_CONFIG" <<'EOF'
[req]
distinguished_name = req_distinguished_name
prompt = no
x509_extensions = v3_ca

[req_distinguished_name]
CN = apim.localtest.me

[v3_ca]
basicConstraints = critical,CA:TRUE
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer

[v3_req]
basicConstraints = critical,CA:FALSE
subjectAltName = @alt_names
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth

[alt_names]
DNS.1 = apim.localtest.me
DNS.2 = localhost
IP.1 = 127.0.0.1
EOF

has_valid_ca() {
  [ -f "$CA_CERT_PATH" ] && [ -f "$CA_KEY_PATH" ] || return 1
  openssl x509 -in "$CA_CERT_PATH" -noout -text 2>/dev/null \
    | grep -q "CA:TRUE" \
    || return 1
  openssl x509 -in "$CA_CERT_PATH" -noout -text 2>/dev/null \
    | grep -q "Certificate Sign" \
    || return 1
}

if ! has_valid_ca; then
  rm -f "$CA_CERT_PATH" "$CA_KEY_PATH" "$CA_SERIAL_PATH"
  openssl req \
    -x509 \
    -nodes \
    -newkey rsa:2048 \
    -sha256 \
    -days 3650 \
    -config "$TMP_CONFIG" \
    -extensions v3_ca \
    -subj "/CN=APIM Simulator Local Dev CA" \
    -keyout "$CA_KEY_PATH" \
    -out "$CA_CERT_PATH" >/dev/null 2>&1
fi

chmod 600 "$CA_KEY_PATH"
chmod 644 "$CA_CERT_PATH"

openssl req \
  -nodes \
  -newkey rsa:2048 \
  -sha256 \
  -config "$TMP_CONFIG" \
  -keyout "$KEY_PATH" \
  -out "$CSR_PATH" >/dev/null 2>&1

openssl x509 \
  -req \
  -sha256 \
  -days 825 \
  -in "$CSR_PATH" \
  -CA "$CA_CERT_PATH" \
  -CAkey "$CA_KEY_PATH" \
  -CAcreateserial \
  -CAserial "$CA_SERIAL_PATH" \
  -extfile "$TMP_CONFIG" \
  -extensions v3_req \
  -out "$CERT_PATH" >/dev/null 2>&1

rm -f "$CSR_PATH"

# The edge proxy runs as a non-root numeric UID. On Linux bind mounts, a 0600
# key owned by the host user is unreadable inside the container, so keep the
# generated dev server cert and key world-readable. These files are ignored and
# used only for the local self-signed edge stack, not as production secrets.
chmod 644 "$CERT_PATH" "$KEY_PATH"

printf 'Generated %s and %s\n' "$CERT_PATH" "$KEY_PATH"
printf 'Local CA available at %s\n' "$CA_CERT_PATH"
