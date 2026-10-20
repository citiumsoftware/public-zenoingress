#!/usr/bin/env bash
# Throwaway demo PKI for the backend-TLS scenario: a CA, and a server
# certificate for the backend (SAN DNS:backend.secure.test plus a SPIFFE URI).
# EC P-256. Do not use for anything real.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p certs && cd certs
openssl ecparam -genkey -name prime256v1 -out ca.key
openssl req -x509 -new -key ca.key -sha256 -days 365 -subj "/CN=backend-demo-ca" -out ca.crt
openssl ecparam -genkey -name prime256v1 -out backend.key
openssl req -new -key backend.key -subj "/CN=backend.secure.test" -out backend.csr
openssl x509 -req -in backend.csr -CA ca.crt -CAkey ca.key -CAcreateserial -sha256 -days 365 \
  -out backend.crt -extfile <(printf 'subjectAltName=DNS:backend.secure.test,URI:spiffe://secure.test/backend\nextendedKeyUsage=serverAuth\n')
rm -f backend.csr
chmod 0644 ./*
echo "wrote $(pwd)/{ca,backend}.{crt,key}"
