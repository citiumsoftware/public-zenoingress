#!/usr/bin/env bash
# Prove traffic flows: client -> ZenoIngress proxy -> Caddy static page.
# Port-forwards the proxy Service and curls it with the demo Host header.
set -uo pipefail
cd "$(dirname "$0")"
HOST=welcome.zenoingress.test
NS=zenoingress-system

SVC="$(kubectl -n "$NS" get svc -o name | grep -m1 proxy)"
[ -n "$SVC" ] || { echo "proxy service not found in $NS — is ZenoIngress installed? run ./up.sh"; exit 1; }

# Forward to a random free local port (":80" lets kubectl pick one) so we never
# clash with something already on :8080.
PF_LOG="$(mktemp)"
kubectl -n "$NS" port-forward "$SVC" :80 >"$PF_LOG" 2>&1 &
trap 'kill %1 2>/dev/null; rm -f "$PF_LOG"' EXIT
sleep 3
PORT="$(sed -nE 's|.*127\.0\.0\.1:([0-9]+).*|\1|p' "$PF_LOG" | head -1)"
[ -n "$PORT" ] || { echo "port-forward failed:"; cat "$PF_LOG"; exit 1; }
echo "# port-forward $SVC  (localhost:$PORT -> proxy :80)"

echo "# GET http://$HOST/  (routed by ZenoIngress)"
code="$(curl -s -o /dev/null -w '%{http_code}' -H "Host: $HOST" "http://localhost:$PORT/")"
body="$(curl -s -H "Host: $HOST" "http://localhost:$PORT/")"

if printf '%s' "$body" | grep -q "Welcome To ZenoIngress"; then
  echo "PASS [$code] — served the welcome page through ZenoIngress"
else
  echo "FAIL [$code] — unexpected response:"
  printf '%s\n' "$body" | head
  exit 1
fi
