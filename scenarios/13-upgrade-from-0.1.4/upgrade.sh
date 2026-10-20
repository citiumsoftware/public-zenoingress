#!/usr/bin/env bash
# Upgrade the 0.1.4 install from ./up.sh to the current release, the way an
# existing user should:
#
#   1. Gateway API CRDs v1.2.0 -> v1.6.1 (server-side apply)
#   2. ZenoIngress's own CRDs (Helm installs crds/ only on first install and
#      never upgrades them)
#   3. helm upgrade
#
# The release keeps its shared proxy (an upgrade never changes the provisioning
# model, so the address stays the same).
set -euo pipefail
cd "$(dirname "$0")" || exit 1
source ../lib/common.sh
CLUSTER=zeno-upgrade
zi_load_images "$CLUSTER" controller proxy

echo "==> 1/3 Gateway API ${GATEWAY_API_VERSION} CRDs"
zi_gateway_api

echo "==> 2/3 ZenoIngress ${ZENOINGRESS_VERSION} CRDs"
case "$ZENOINGRESS_CHART" in
  oci://*) helm show crds "$ZENOINGRESS_CHART" --version "$ZENOINGRESS_VERSION" ;;
  *) helm show crds "$ZENOINGRESS_CHART" ;;
esac | kubectl apply --server-side --force-conflicts -f -

echo "==> 3/3 helm upgrade to ${ZENOINGRESS_VERSION}"
# --reset-then-reuse-values (Helm 3.14+): the new chart's defaults, plus the
# values you set before. Plain --reuse-values lacks settings added since.
zi_install --reset-then-reuse-values
kubectl -n zenoingress-system rollout status deploy --timeout=180s

echo
echo "Done. Verify with: ./verify.sh"
