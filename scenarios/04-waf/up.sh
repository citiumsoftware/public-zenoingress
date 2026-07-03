#!/usr/bin/env bash
# Stand up the WAF scenario in a local kind cluster:
#
#   curl/browser -> ZenoIngress proxy [Coraza WAF] -> Caddy form page
#
# The proxy pulls the Coraza proxy-wasm module via an init container (see
# values-waf.yaml) and a WafPolicy attaches it to the route. Requires: docker,
# kind, kubectl, helm 3.8+, and internet from the cluster (to fetch the module).
set -euo pipefail
cd "$(dirname "$0")"
CLUSTER=zeno-waf
CHART="oci://ghcr.io/citiumsoftware/zenoingress-chart"
CHART_VERSION="${ZENOINGRESS_CHART_VERSION:-0.1.4}"

echo "==> 1/4 kind cluster '${CLUSTER}'"
kind get clusters 2>/dev/null | grep -qx "$CLUSTER" || kind create cluster --name "$CLUSTER" --wait 60s

echo "==> 2/4 Gateway API v1.2.0 CRDs"
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml

echo "==> 3/4 install ZenoIngress from the public chart (+ Coraza module init container)"
helm upgrade --install zenoingress "$CHART" --version "$CHART_VERSION" \
  -n zenoingress-system --create-namespace -f values-waf.yaml

echo "==> 4/4 deploy the app + Gateway + HTTPRoute + WafPolicy, then wait"
kubectl apply -f k8s/manifests.yaml
# The proxy init container downloads the WAF module first, so give it room.
kubectl -n zenoingress-system wait --for=condition=Available deploy --all --timeout=300s
kubectl -n waf-app rollout status deploy/waf-app --timeout=120s
kubectl wait --for=condition=Programmed gateway/waf-gateway -n waf-app --timeout=120s || true

echo
echo "Done. Verify with: ./verify.sh"
echo "Or browse it:  kubectl -n zenoingress-system port-forward svc/\$(kubectl -n zenoingress-system get svc -o name | grep -m1 proxy | cut -d/ -f2) 18080:80  then open http://localhost:18080  (any free local port works)"
