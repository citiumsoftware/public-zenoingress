#!/usr/bin/env bash
# Prove it end-to-end: client -> edge (public container) -> reverse tunnel ->
# proxy (sovereign cluster, no inbound) -> demo app.
set -uo pipefail
APP=app.demo.zenoingress.test
URL="https://$APP:8443/"
RES="--resolve $APP:8443:127.0.0.1"

echo "# client -> edge (localhost:8443) -> tunnel -> in-cluster proxy -> demo app"
code=000; body=""
for i in $(seq 1 10); do
  code="$(curl -sk $RES -o /dev/null -w '%{http_code}' "$URL" 2>/dev/null)"
  body="$(curl -sk $RES "$URL" 2>/dev/null)"
  printf '%s' "$body" | grep -q "ZenoIngress edge" && break
  echo "  ...waiting for the tunnel to carry traffic (try $i, last HTTP $code)"
  sleep 2
done

echo
if printf '%s' "$body" | grep -q "ZenoIngress edge"; then
  echo "PASS [$code] — reached the in-cluster app through the edge tunnel."
  echo "             the sovereign cluster's proxy Service is ClusterIP — it has NO inbound ports,"
  echo "             yet the app is reachable from outside via the edge the proxy dialed out to."
else
  echo "FAIL [$code] — traffic did not reach the app. Check:"
  echo "  docker logs zeno-edge"
  echo "  kubectl -n zenoingress-system logs -l app.kubernetes.io/component=proxy --tail=50"
  exit 1
fi
