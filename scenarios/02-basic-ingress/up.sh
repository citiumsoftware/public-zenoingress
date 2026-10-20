#!/usr/bin/env bash
# Stand up the basic-ingress scenario in a local kind cluster:
#
#   curl -> the Gateway's own ZenoIngress proxy -> Caddy static page
#
# Self-contained: creates a kind cluster and installs ZenoIngress from the
# public OCI chart. Requires: docker, kind, kubectl, helm 3.8+ (OCI support).
# See ../lib/common.sh for the version and local-image overrides.
set -euo pipefail
cd "$(dirname "$0")"
source ../lib/common.sh
CLUSTER=zeno-simple

echo "==> 1/4 kind cluster '${CLUSTER}'"
zi_cluster "$CLUSTER"
zi_load_images "$CLUSTER" controller proxy

echo "==> 2/4 Gateway API ${GATEWAY_API_VERSION} CRDs"
zi_gateway_api

echo "==> 3/4 install ZenoIngress ${ZENOINGRESS_VERSION} (ClusterIP proxies: kind has no load balancer)"
zi_install --set proxy.service.type=ClusterIP --set proxy.replicaCount=1

echo "==> 4/4 deploy the Caddy app + Gateway + HTTPRoute, then wait"
kubectl apply -f k8s/manifests.yaml
kubectl -n simple-ingress rollout status deploy/welcome --timeout=120s
# Programmed = the controller started this Gateway's own proxy and it is up.
zi_wait_gateway simple-ingress simple-gateway

echo
echo "Done. Verify with: ./verify.sh"
