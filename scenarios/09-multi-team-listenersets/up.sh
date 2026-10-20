#!/usr/bin/env bash
# Stand up the multi-team scenario in a local kind cluster:
#
#   one Gateway (platform team) + ListenerSets (application teams) -> one proxy,
#   one address, each team on its own hostname, in its own namespace.
#
# Requires: docker, kind, kubectl, helm 3.8+. See ../lib/common.sh for overrides.
set -euo pipefail
cd "$(dirname "$0")"
source ../lib/common.sh
CLUSTER=zeno-teams

echo "==> 1/5 kind cluster '${CLUSTER}'"
zi_cluster "$CLUSTER"
zi_load_images "$CLUSTER" controller proxy

echo "==> 2/5 Gateway API ${GATEWAY_API_VERSION} CRDs (ListenerSet is Standard since v1.5)"
zi_gateway_api

echo "==> 3/5 install ZenoIngress ${ZENOINGRESS_VERSION} (ClusterIP proxies: kind has no load balancer)"
zi_install --set proxy.service.type=ClusterIP --set proxy.replicaCount=1

echo "==> 4/5 platform Gateway + team-a"
kubectl apply -f k8s/platform-and-team-a.yaml
zi_wait_gateway platform shop
kubectl -n team-a wait --for=condition=Accepted listenerset/team-a --timeout=120s

echo "==> 5/5 team-b (one listener collides with team-a) and team-c (not allowed)"
kubectl apply -f k8s/team-b-and-team-c.yaml
for ns in platform team-a team-b team-c; do
  kubectl -n "$ns" rollout status deploy/app --timeout=120s
done
kubectl -n team-b wait --for=condition=Accepted listenerset/team-b --timeout=120s

echo
echo "Done. Verify with: ./verify.sh"
