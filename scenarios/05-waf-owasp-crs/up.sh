#!/usr/bin/env bash
# Stand up the OWASP-CRS WAF scenario in a local kind cluster:
#
#   curl/browser -> ZenoIngress proxy [Coraza + full OWASP CRS] -> Caddy form page
#
# The proxy pulls the Coraza proxy-wasm module via an init container (see
# values-waf.yaml) and a WafPolicy loads the whole CRS. Requires: docker, kind,
# kubectl, helm 3.8+, and internet from the cluster (to fetch the module).
set -euo pipefail
cd "$(dirname "$0")" || exit 1
source ../lib/common.sh
CLUSTER=zeno-waf-crs

echo "==> 1/4 kind cluster '${CLUSTER}'"
zi_cluster "$CLUSTER"
zi_load_images "$CLUSTER" controller proxy

echo "==> 2/4 Gateway API ${GATEWAY_API_VERSION} CRDs"
zi_gateway_api

echo "==> 3/4 install ZenoIngress ${ZENOINGRESS_VERSION} (+ the Coraza module init container)"
zi_install -f values-waf.yaml

echo "==> 4/4 deploy the app, Gateway and routes, then wait"
kubectl apply -f k8s/manifests.yaml
kubectl -n waf-crs rollout status deploy/waf-app --timeout=120s
# The Gateway's proxy fetches the WAF module, then compiles ~900 CRS rules.
zi_wait_gateway waf-crs waf-gateway 420s

echo
echo "Done. Verify with: ./verify.sh"
