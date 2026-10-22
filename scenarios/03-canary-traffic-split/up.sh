#!/usr/bin/env bash
# Stand up the canary scenario in a local kind cluster:
#
#   curl -> ZenoIngress proxy -> HTTPRoute (weighted 90/10) -> welcome-v1 / welcome-v2
#
# Standard ingress mode; the only "canary" bit is the weighted backendRefs in
# k8s/manifests.yaml. Requires: docker, kind, kubectl, helm 3.8+.
set -euo pipefail
cd "$(dirname "$0")" || exit 1
source ../lib/common.sh
CLUSTER=zeno-canary

echo "==> 1/4 kind cluster '${CLUSTER}'"
zi_cluster "$CLUSTER"
zi_load_images "$CLUSTER" controller proxy

echo "==> 2/4 Gateway API ${GATEWAY_API_VERSION} CRDs"
zi_gateway_api

echo "==> 3/4 install ZenoIngress ${ZENOINGRESS_VERSION} (ClusterIP proxies: kind has no load balancer)"
zi_install --set proxy.service.type=ClusterIP --set proxy.replicaCount=1

echo "==> 4/4 deploy the app, Gateway and routes, then wait"
kubectl apply -f k8s/manifests.yaml
kubectl -n canary rollout status deploy/welcome-v1 --timeout=120s
kubectl -n canary rollout status deploy/welcome-v2 --timeout=120s
zi_wait_gateway canary canary-gateway 240s

echo
echo "Done. Verify with: ./verify.sh"
