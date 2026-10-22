#!/usr/bin/env bash
# Demonstrate the HYBRID EDGE / reverse-tunnel deploy — fully self-contained.
#
#   client ─▶ zenoingress-edge (public front door: a container) ─▶ reverse tunnel
#                                                                      │
#   sovereign kind cluster:  proxy ── dials OUT to the edge :7844 ─────┘
#     controller + proxy (tunnel mode) + demo app   ── NO inbound ports on the cluster ──
#
# The edge runs the public zenoingress-edge image as a container on the kind
# docker network — standing in for a public VM / container-platform node, which
# is how it's really deployed. The only zeno dependency is zenoingress itself;
# the backend is a stock Caddy image.
#
# Requires: docker, kind, kubectl, helm 3.8+, openssl.
set -euo pipefail
cd "$(dirname "$0")" || exit 1
source ../lib/common.sh
CLUSTER=zeno-tunnel
EDGE=zeno-edge
NET=kind
EDGE_IMAGE="$(zi_image edge)"

echo "==> 1/7 sovereign kind cluster '${CLUSTER}' (also creates the '${NET}' docker network)"
zi_cluster "$CLUSTER"
zi_load_images "$CLUSTER" controller proxy

echo "==> 2/7 Gateway API ${GATEWAY_API_VERSION} CRDs"
zi_gateway_api

echo "==> 3/7 mint a self-signed edge TLS cert"
./gen-certs.sh

echo "==> 4/7 deploy the edge (public zenoingress-edge image) as a container on '${NET}'"
docker rm -f "$EDGE" 2>/dev/null || true
docker run -d --name "$EDGE" --network "$NET" --restart unless-stopped \
  -p 8443:8443 -v "$(pwd)/certs:/certs:ro" \
  "$EDGE_IMAGE" \
  --data-addr=0.0.0.0:8443 --control-addr=0.0.0.0:7844 \
  --config=/certs/edge-auth.yaml \
  --cert=/certs/edge.crt --key=/certs/edge.key --auth-mode=token --json-logs >/dev/null
sleep 2
EDGE_IP="$(docker inspect -f "{{(index .NetworkSettings.Networks \"$NET\").IPAddress}}" "$EDGE")"
if [ -z "$EDGE_IP" ] || [ "$(docker inspect -f '{{.State.Running}}' "$EDGE")" != true ]; then
  echo "the edge container did not start:"; docker logs "$EDGE" 2>&1 | tail -5; exit 1
fi
echo "    edge control plane: ${EDGE_IP}:7844   data plane: https://localhost:8443"

echo "==> 5/7 install ZenoIngress in TUNNEL mode (the proxy dials OUT to the edge)"
zi_install -f values-tunnel.yaml \
  --set "proxy.tunnel.auth.token=$(cat certs/tunnel-token)" \
  --set "proxy.tunnel.edges[0].address=${EDGE_IP}:7844"

echo "==> 6/7 deploy the demo app + Gateway + HTTPRoute (the controller then publishes routes)"
# Apply AFTER install: the tunnel proxy only goes Ready once the controller has
# routes to publish.
kubectl apply -f k8s/manifests.yaml

echo "==> 7/7 wait for the tunnel proxy to pick up routes + become Ready"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=proxy \
  -n zenoingress-system --timeout=180s || true

echo
echo "Done. Verify with: ./verify.sh"
