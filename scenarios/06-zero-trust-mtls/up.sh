#!/usr/bin/env bash
# Stand up the zero-trust scenario in a local kind cluster:
#
#   mTLS client SVID -> ZenoIngress proxy -> Cedar AuthzPolicy -> api
#
# Every request must present a valid client SPIFFE certificate, and a Cedar
# policy authorizes on that identity (deny-by-default). Requires: docker, kind,
# kubectl, helm 3.8+, openssl. See ../lib/common.sh for overrides.
set -euo pipefail
cd "$(dirname "$0")" || exit 1
source ../lib/common.sh
CLUSTER=zeno-zt
NS=zero-trust

echo "==> 1/5 kind cluster '${CLUSTER}'"
zi_cluster "$CLUSTER"
zi_load_images "$CLUSTER" controller proxy

echo "==> 2/5 Gateway API ${GATEWAY_API_VERSION} CRDs (client-certificate validation is Standard)"
zi_gateway_api

echo "==> 3/5 mint demo PKI + create the server-cert Secret and client-CA ConfigMap"
./gen-certs.sh
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NS" create secret tls zt-server-cert \
  --cert=certs/server.crt --key=certs/server.key --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NS" create configmap zt-client-ca \
  --from-file=ca.crt=certs/ca.crt --dry-run=client -o yaml | kubectl apply -f -

echo "==> 4/5 install ZenoIngress ${ZENOINGRESS_VERSION} (ClusterIP proxies: kind has no load balancer)"
zi_install --set proxy.service.type=ClusterIP --set proxy.replicaCount=1

echo "==> 5/5 apply backend + mTLS Gateway + Cedar AuthzPolicy, then wait"
kubectl apply -f k8s/manifests.yaml
kubectl -n "$NS" rollout status deploy/api --timeout=120s
zi_wait_gateway "$NS" zt-gateway

echo
echo "Done. Verify with: ./verify.sh"
