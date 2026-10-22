#!/usr/bin/env bash
# HA / multi-edge: TWO public edges (two "regions") in front of ONE sovereign
# cluster. The proxy dials out to both; either edge serves the app, and a single
# edge failure does not take the app down.
#
#   client ─▶ edge-a (:8443) ─┐
#             edge-b (:9443) ─┴─ reverse tunnels ─▶ proxy (tunnel mode) ─▶ app
#   sovereign kind cluster · NO inbound ports
#
# The edges run the public zenoingress-edge image as containers on the kind
# docker network (standing in for public VMs / container-platform nodes). The
# only zeno dependency is zenoingress itself; the backend is a stock Caddy image.
#
# Requires: docker, kind, kubectl, helm 3.8+, openssl.
set -euo pipefail
cd "$(dirname "$0")" || exit 1
source ../lib/common.sh
CLUSTER=zeno-ha
NET=kind
EDGE_IMAGE="$(zi_image edge)"

echo "==> 1/7 sovereign kind cluster '${CLUSTER}' (also creates the '${NET}' docker network)"
zi_cluster "$CLUSTER"
zi_load_images "$CLUSTER" controller proxy

echo "==> 2/7 Gateway API ${GATEWAY_API_VERSION} CRDs"
zi_gateway_api

echo "==> 3/7 mint a self-signed edge TLS cert"
./gen-certs.sh

echo "==> 4/7 deploy TWO edges (edge-a → localhost:8443, edge-b → localhost:9443) on '${NET}'"
for spec in "edge-a 8443" "edge-b 9443"; do
  set -- $spec
  docker rm -f "$1" 2>/dev/null || true
  docker run -d --name "$1" --network "$NET" --restart unless-stopped \
    -p "$2:8443" -v "$(pwd)/certs:/certs:ro" \
    "$EDGE_IMAGE" \
    --data-addr=0.0.0.0:8443 --control-addr=0.0.0.0:7844 \
    --config=/certs/edge-auth.yaml \
    --cert=/certs/edge.crt --key=/certs/edge.key --auth-mode=token --json-logs >/dev/null
done
EA="$(docker inspect -f "{{(index .NetworkSettings.Networks \"$NET\").IPAddress}}" edge-a)"
EB="$(docker inspect -f "{{(index .NetworkSettings.Networks \"$NET\").IPAddress}}" edge-b)"
echo "    edge-a=${EA}:7844 (localhost:8443)   edge-b=${EB}:7844 (localhost:9443)"

echo "==> 5/7 install ZenoIngress in TUNNEL mode with BOTH edges (one proxy Deployment per edge)"
zi_install -f values-tunnel.yaml \
  --set "proxy.tunnel.auth.token=$(cat certs/tunnel-token)" \
  --set "proxy.tunnel.edges[0].address=${EA}:7844" \
  --set "proxy.tunnel.edges[1].address=${EB}:7844"

echo "==> 6/7 deploy the demo app + Gateway + HTTPRoute"
kubectl apply -f k8s/manifests.yaml

echo "==> 7/7 wait for BOTH tunnel proxies to become Ready"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=proxy \
  -n zenoingress-system --timeout=180s || true

echo
echo "Done. Verify with: ./verify.sh"
