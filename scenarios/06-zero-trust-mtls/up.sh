#!/usr/bin/env bash
# Stand up the zero-trust scenario in a local kind cluster:
#
#   mTLS client SVID -> ZenoIngress proxy -> Cedar AuthzPolicy -> api
#
# Every request must present a valid client SPIFFE certificate, and a Cedar
# policy authorizes on that identity (deny-by-default). Requires: docker, kind,
# kubectl, helm 3.8+, openssl.
set -euo pipefail
cd "$(dirname "$0")"
CLUSTER=zeno-zt
NS=zero-trust
CHART="oci://ghcr.io/citiumsoftware/zenoingress-chart"
CHART_VERSION="${ZENOINGRESS_CHART_VERSION:-0.1.4}"

echo "==> 1/5 kind cluster '${CLUSTER}'"
kind get clusters 2>/dev/null | grep -qx "$CLUSTER" || kind create cluster --name "$CLUSTER" --wait 60s

echo "==> 2/5 Gateway API CRDs (EXPERIMENTAL channel — GEP-91 frontendValidation)"
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/experimental-install.yaml

echo "==> 3/5 mint demo PKI + create the server-cert / client-CA secrets"
./gen-certs.sh
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NS" create secret tls zt-server-cert \
  --cert=certs/server.crt --key=certs/server.key --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NS" create secret generic zt-client-ca \
  --from-file=ca.crt=certs/ca.crt --dry-run=client -o yaml | kubectl apply -f -

echo "==> 4/5 install ZenoIngress from the public chart (standard mode; ClusterIP, 1 replica each)"
helm upgrade --install zenoingress "$CHART" --version "$CHART_VERSION" \
  -n zenoingress-system --create-namespace \
  --set proxy.service.type=ClusterIP --set proxy.replicaCount=1 --set controller.replicaCount=1

echo "==> 5/5 apply backend + mTLS Gateway + Cedar AuthzPolicy, then wait"
kubectl apply -f k8s/manifests.yaml
kubectl -n zenoingress-system wait --for=condition=Available deploy --all --timeout=240s
kubectl -n "$NS" rollout status deploy/api --timeout=120s
kubectl wait --for=condition=Programmed gateway/zt-gateway -n "$NS" --timeout=120s || true

echo
echo "Done. Verify with: ./verify.sh"
