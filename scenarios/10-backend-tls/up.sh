#!/usr/bin/env bash
# Stand up the backend-TLS scenario in a local kind cluster:
#
#   curl -> ZenoIngress proxy -> TLS, verified by BackendTLSPolicy -> Caddy :8443
#
# Requires: docker, kind, kubectl, helm 3.8+, openssl. See ../lib/common.sh.
set -euo pipefail
cd "$(dirname "$0")" || exit 1
source ../lib/common.sh
CLUSTER=zeno-backend-tls
NS=backend-tls

echo "==> 1/5 kind cluster '${CLUSTER}'"
zi_cluster "$CLUSTER"
zi_load_images "$CLUSTER" controller proxy

echo "==> 2/5 Gateway API ${GATEWAY_API_VERSION} CRDs (BackendTLSPolicy is Standard since v1.4)"
zi_gateway_api

echo "==> 3/5 demo PKI: the backend's certificate Secret and the CA ConfigMap"
./gen-certs.sh
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NS" create secret tls backend-cert \
  --cert=certs/backend.crt --key=certs/backend.key --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NS" create configmap backend-ca \
  --from-file=ca.crt=certs/ca.crt --dry-run=client -o yaml | kubectl apply -f -

echo "==> 4/5 install ZenoIngress ${ZENOINGRESS_VERSION} (ClusterIP proxies: kind has no load balancer)"
zi_install --set proxy.service.type=ClusterIP --set proxy.replicaCount=1

echo "==> 5/5 backend, Gateway, routes and BackendTLSPolicies, then wait"
kubectl apply -f k8s/manifests.yaml
kubectl -n "$NS" rollout status deploy/backend --timeout=120s
zi_wait_gateway "$NS" gw

echo
echo "Done. Verify with: ./verify.sh"
