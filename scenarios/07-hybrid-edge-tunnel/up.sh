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
cd "$(dirname "$0")"
CLUSTER=zeno-tunnel
EDGE=zeno-edge
NET=kind
EDGE_IMAGE="ghcr.io/citiumsoftware/zenoingress-edge:${ZENOINGRESS_VERSION:-0.1.4}"
CHART="oci://ghcr.io/citiumsoftware/zenoingress-chart"
CHART_VERSION="${ZENOINGRESS_CHART_VERSION:-0.1.4}"

echo "==> 1/7 sovereign kind cluster '${CLUSTER}' (also creates the '${NET}' docker network)"
kind get clusters 2>/dev/null | grep -qx "$CLUSTER" || kind create cluster --name "$CLUSTER" --wait 60s

echo "==> 2/7 Gateway API v1.2.0 CRDs"
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml

echo "==> 3/7 mint a self-signed edge TLS cert"
./gen-certs.sh

echo "==> 4/7 deploy the edge (public zenoingress-edge image) as a container on '${NET}'"
docker rm -f "$EDGE" 2>/dev/null || true
docker run -d --name "$EDGE" --network "$NET" --restart unless-stopped \
  -p 8443:8443 -v "$(pwd)/certs:/certs:ro" \
  "$EDGE_IMAGE" \
  --data-addr=0.0.0.0:8443 --control-addr=0.0.0.0:7844 \
  --cert=/certs/edge.crt --key=/certs/edge.key --auth-mode=none --json-logs >/dev/null
EDGE_IP="$(docker inspect -f "{{(index .NetworkSettings.Networks \"$NET\").IPAddress}}" "$EDGE")"
echo "    edge control plane: ${EDGE_IP}:7844   data plane: https://localhost:8443"

echo "==> 5/7 install ZenoIngress in TUNNEL mode (the proxy dials OUT to the edge)"
helm upgrade --install zenoingress "$CHART" --version "$CHART_VERSION" \
  -n zenoingress-system --create-namespace -f values-tunnel.yaml \
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
