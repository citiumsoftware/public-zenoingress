#!/usr/bin/env bash
# Prove traffic flows: client -> the Gateway's proxy -> Caddy static page.
# Port-forwards the Gateway's proxy Service and curls it with the demo Host.
set -uo pipefail
cd "$(dirname "$0")"
source ../lib/common.sh
HOST=welcome.zenoingress.test

zi_gateway_forward simple-ingress simple-gateway 80 || exit 1

echo "# GET http://$HOST/  (routed by ZenoIngress)"
code="$(curl -s -o /dev/null -w '%{http_code}' -H "Host: $HOST" "http://localhost:$ZI_PORT/")"
body="$(curl -s -H "Host: $HOST" "http://localhost:$ZI_PORT/")"

if printf '%s' "$body" | grep -q "Welcome To ZenoIngress"; then
  echo "PASS [$code] — served the welcome page through ZenoIngress"
else
  echo "FAIL [$code] — unexpected response:"
  printf '%s\n' "$body" | head
  exit 1
fi

echo "# GET http://unknown.zenoingress.test/  (no route: must be 404)"
code="$(curl -s -o /dev/null -w '%{http_code}' -H "Host: unknown.zenoingress.test" "http://localhost:$ZI_PORT/")"
if [ "$code" = 404 ]; then
  echo "PASS [404] — hosts without a route are not served"
else
  echo "FAIL [$code] — expected 404 for an unrouted host"; exit 1
fi
