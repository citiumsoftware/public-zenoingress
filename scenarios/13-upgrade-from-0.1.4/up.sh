#!/usr/bin/env bash
# Install the PREVIOUS release (0.1.4, on Gateway API v1.2.0) with the
# basic-ingress app, as an existing user would have it. ./upgrade.sh then
# upgrades it to the current release.
#
# Requires: docker, kind, kubectl, helm 3.8+. See ../lib/common.sh.
set -euo pipefail
cd "$(dirname "$0")"
source ../lib/common.sh
CLUSTER=zeno-upgrade
FROM_VERSION="${FROM_VERSION:-0.1.4}"

echo "==> 1/4 kind cluster '${CLUSTER}'"
zi_cluster "$CLUSTER"

echo "==> 2/4 Gateway API v1.2.0 CRDs (what 0.1.4 was installed with)"
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml >/dev/null

echo "==> 3/4 install ZenoIngress ${FROM_VERSION} from the public chart"
helm upgrade --install zenoingress oci://ghcr.io/citiumsoftware/zenoingress-chart --version "$FROM_VERSION" \
  -n zenoingress-system --create-namespace \
  --set proxy.service.type=ClusterIP --set proxy.replicaCount=1 --set controller.replicaCount=1

echo "==> 4/4 the basic-ingress app"
kubectl apply -f k8s/manifests.yaml
kubectl -n simple-ingress rollout status deploy/welcome --timeout=120s
kubectl -n simple-ingress wait --for=condition=Programmed gateway/simple-gateway --timeout=120s
# 0.1.4's proxy turns ready once its config (a ConfigMap, delivered by the
# kubelet within about a minute) has routes.
kubectl -n zenoingress-system wait --for=condition=Available deploy --all --timeout=300s

echo
echo "Done. ${FROM_VERSION} is running. Check it with ./verify.sh, then run ./upgrade.sh"
