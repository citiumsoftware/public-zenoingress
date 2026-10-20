#!/usr/bin/env bash
# Stand up the CORS scenario in a local kind cluster:
#
#   browser (another origin) -> ZenoIngress proxy [CORS filter] -> JSON API
#
# Requires: docker, kind, kubectl, helm 3.8+. See ../lib/common.sh.
set -euo pipefail
cd "$(dirname "$0")"
source ../lib/common.sh
CLUSTER=zeno-cors

echo "==> 1/4 kind cluster '${CLUSTER}'"
zi_cluster "$CLUSTER"
zi_load_images "$CLUSTER" controller proxy

echo "==> 2/4 Gateway API ${GATEWAY_API_VERSION} CRDs (the CORS filter is Standard since v1.5)"
zi_gateway_api

echo "==> 3/4 install ZenoIngress ${ZENOINGRESS_VERSION} (ClusterIP proxies: kind has no load balancer)"
zi_install --set proxy.service.type=ClusterIP --set proxy.replicaCount=1

echo "==> 4/4 the API, Gateway and HTTPRoute with a CORS filter, then wait"
kubectl apply -f k8s/manifests.yaml
kubectl -n cors rollout status deploy/api --timeout=120s
zi_wait_gateway cors gw

echo
echo "Done. Verify with: ./verify.sh"
