#!/usr/bin/env bash
# Stand up the Gateway-per-team scenario in a local kind cluster:
#
#   team-red  Gateway -> its own proxy + Service -> red app
#   team-blue Gateway -> its own proxy + Service -> blue app   (same hostname)
#
# Requires: docker, kind, kubectl, helm 3.8+. See ../lib/common.sh.
set -euo pipefail
cd "$(dirname "$0")" || exit 1
source ../lib/common.sh
CLUSTER=zeno-per-team

echo "==> 1/4 kind cluster '${CLUSTER}'"
zi_cluster "$CLUSTER"
zi_load_images "$CLUSTER" controller proxy

echo "==> 2/4 Gateway API ${GATEWAY_API_VERSION} CRDs"
zi_gateway_api

echo "==> 3/4 install ZenoIngress ${ZENOINGRESS_VERSION} (new installs give each Gateway its own proxy)"
zi_install --set proxy.service.type=ClusterIP --set proxy.replicaCount=1

echo "==> 4/4 two teams, two Gateways, the same hostname"
kubectl apply -f k8s/manifests.yaml
for ns in team-red team-blue; do
  kubectl -n "$ns" rollout status deploy/app --timeout=120s
  zi_wait_gateway "$ns" web
done

echo
echo "Done. Verify with: ./verify.sh"
