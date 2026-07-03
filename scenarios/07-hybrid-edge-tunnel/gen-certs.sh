#!/usr/bin/env bash
# Self-signed TLS cert for the edge (data + control plane). Demo only, throwaway.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p certs
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout certs/edge.key -out certs/edge.crt \
  -subj "/CN=demo.zenoingress.test" \
  -addext "subjectAltName=DNS:app.demo.zenoingress.test,DNS:localhost,IP:127.0.0.1"
# World-readable so the edge container's non-root uid can read the mounted key.
chmod 0644 certs/edge.key certs/edge.crt
echo "wrote $(pwd)/certs/edge.{crt,key}"
