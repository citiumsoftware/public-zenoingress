#!/usr/bin/env bash
# Stand up the basic-ingress scenario in a local kind cluster:
#
#   curl -> ZenoIngress proxy (Gateway API, standard mode) -> Caddy static page
#
# Self-contained: creates a kind cluster and installs ZenoIngress from the public
# OCI chart. Requires: docker, kind, kubectl, helm 3.8+ (OCI support).
set -euo pipefail
cd "$(dirname "$0")"
CLUSTER=zeno-simple
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

echo "==> 4/4 deploy the Caddy app + Gateway + HTTPRoute, then wait for readiness"
kubectl apply -f k8s/manifests.yaml
kubectl -n zenoingress-system wait --for=condition=Available deploy --all --timeout=180s
kubectl -n simple-ingress rollout status deploy/welcome --timeout=120s
kubectl wait --for=condition=Programmed gateway/simple-gateway -n simple-ingress --timeout=120s || true

echo
echo "Done. Verify with: ./verify.sh"
