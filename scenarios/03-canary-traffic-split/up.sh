#!/usr/bin/env bash
# Stand up the canary scenario in a local kind cluster:
#
#   curl -> ZenoIngress proxy -> HTTPRoute (weighted 90/10) -> welcome-v1 / welcome-v2
#
# Standard ingress mode; the only "canary" bit is the weighted backendRefs in
# k8s/manifests.yaml. Requires: docker, kind, kubectl, helm 3.8+.
set -euo pipefail
cd "$(dirname "$0")"
CLUSTER=zeno-canary
CHART="oci://ghcr.io/citiumsoftware/zenoingress-chart"
CHART_VERSION="${ZENOINGRESS_CHART_VERSION:-0.1.4}"

echo "==> 1/4 kind cluster '${CLUSTER}'"
kind get clusters 2>/dev/null | grep -qx "$CLUSTER" || kind create cluster --name "$CLUSTER" --wait 60s

echo "==> 2/4 Gateway API v1.2.0 CRDs"
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml

echo "==> 3/4 install ZenoIngress from the public chart (standard mode; ClusterIP, 1 replica each)"
helm upgrade --install zenoingress "$CHART" --version "$CHART_VERSION" \
  -n zenoingress-system --create-namespace \
  --set proxy.service.type=ClusterIP \
  --set proxy.replicaCount=1 \
  --set controller.replicaCount=1

echo "==> 4/4 deploy both versions + the weighted Gateway/HTTPRoute, then wait"
kubectl apply -f k8s/manifests.yaml
kubectl -n zenoingress-system wait --for=condition=Available deploy --all --timeout=180s
kubectl -n canary rollout status deploy/welcome-v1 --timeout=120s
kubectl -n canary rollout status deploy/welcome-v2 --timeout=120s
kubectl wait --for=condition=Programmed gateway/canary-gateway -n canary --timeout=120s || true

echo
echo "Done. Verify with: ./verify.sh"
