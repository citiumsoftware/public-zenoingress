#!/usr/bin/env bash
# Mint a throwaway demo PKI for the zero-trust showcase:
#   - a CA
#   - a server cert for the gateway listener            (SAN: DNS zt.demo.zeno)
#   - two client SPIFFE SVIDs                            (URI SAN spiffe://demo.zeno/<name>)
# These are demo certs (EC P-256). Do not use them for anything real.
set -euo pipefail
cd "$(dirname "$0")"
D=certs
mkdir -p "$D"; cd "$D"

HOST=zt.demo.zeno
TRUST=demo.zeno

# --- CA ---
openssl ecparam -genkey -name prime256v1 -out ca.key
openssl req -x509 -new -key ca.key -sha256 -days 3650 -subj "/CN=zeno-demo-ca" -out ca.crt

# gen_leaf <name> <extfile-contents>
gen_leaf() {
  local name="$1" ext="$2"
  openssl ecparam -genkey -name prime256v1 -out "$name.key"
  openssl req -new -key "$name.key" -subj "/CN=$name" -out "$name.csr"
  openssl x509 -req -in "$name.csr" -CA ca.crt -CAkey ca.key -CAcreateserial \
    -sha256 -days 825 -out "$name.crt" -extfile <(printf '%s\n' "$ext")
  rm -f "$name.csr"
}

# server cert: TLS server auth + hostnames the client connects to
gen_leaf server "subjectAltName=DNS:$HOST,DNS:localhost,IP:127.0.0.1
extendedKeyUsage=serverAuth"

# client SVIDs: TLS client auth + a single SPIFFE URI SAN (the identity)
gen_leaf payments  "subjectAltName=URI:spiffe://$TRUST/payments
extendedKeyUsage=clientAuth"
gen_leaf analytics "subjectAltName=URI:spiffe://$TRUST/analytics
extendedKeyUsage=clientAuth"

echo "PKI written to $(pwd)"
