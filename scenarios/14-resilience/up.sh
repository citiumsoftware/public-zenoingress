#!/usr/bin/env bash
# Stand up the resilience scenario: two controller replicas (leader election)
# and a Gateway whose proxy runs two replicas, in front of a two-replica app.
#
# Requires: docker, kind, kubectl, helm 3.8+. See ../lib/common.sh.
set -euo pipefail
cd "$(dirname "$0")" || exit 1
source ../lib/common.sh
CLUSTER=zeno-resilience

echo "==> 1/4 kind cluster '${CLUSTER}'"
zi_cluster "$CLUSTER"
zi_load_images "$CLUSTER" controller proxy

echo "==> 2/4 Gateway API ${GATEWAY_API_VERSION} CRDs"
zi_gateway_api

echo "==> 3/4 install ZenoIngress ${ZENOINGRESS_VERSION}: 2 controllers, 2 proxy replicas per Gateway"
zi_install --set proxy.service.type=ClusterIP --set proxy.replicaCount=2 --set controller.replicaCount=2

echo "==> 4/4 the app and its Gateway"
kubectl apply -f k8s/manifests.yaml
kubectl -n resilience rollout status deploy/welcome --timeout=120s
zi_wait_gateway resilience web
kubectl -n resilience rollout status deploy/web-zenoingress --timeout=120s

echo
echo "Done. Verify with: ./verify.sh"
