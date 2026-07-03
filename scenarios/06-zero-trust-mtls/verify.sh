#!/usr/bin/env bash
# Prove the two gates:
#   1. mTLS — no client cert → the TLS handshake is refused.
#   2. Cedar — only the payments SVID doing POST /api/payments is permitted;
#      a different SVID or a different method is denied (403).
set -uo pipefail
cd "$(dirname "$0")"
NS=zenoingress-system
HOST=zt.demo.zeno

[ -f certs/ca.crt ] || { echo "no certs/ — run ./up.sh (or ./gen-certs.sh) first"; exit 1; }
SVC="$(kubectl -n "$NS" get svc -o name | grep -m1 proxy)"
[ -n "$SVC" ] || { echo "proxy service not found in $NS — run ./up.sh first"; exit 1; }

echo "# port-forward $SVC  (localhost:8443 -> proxy :443)"
kubectl -n "$NS" port-forward "$SVC" 8443:443 >/dev/null 2>&1 &
trap 'kill %1 2>/dev/null' EXIT
sleep 2

BASE="--resolve $HOST:8443:127.0.0.1 --cacert certs/ca.crt"
url="https://$HOST:8443/api/payments"
code() { curl -s -o /dev/null -w '%{http_code}' $BASE "$@" 2>/dev/null; }
check() { # <label> <expected> <actual>
  if [ "$2" = "$3" ]; then printf '  %-42s %s  (want %s)  PASS\n' "$1" "$3" "$2"
  else printf '  %-42s %s  (want %s)  FAIL\n' "$1" "$3" "$2"; fail=1; fi
}
fail=0
PC="--cert certs/payments.crt  --key certs/payments.key"
AC="--cert certs/analytics.crt --key certs/analytics.key"

check "payments SVID  POST /api/payments" 200 "$(code $PC -X POST "$url")"
check "analytics SVID POST /api/payments" 403 "$(code $AC -X POST "$url")"
check "payments SVID  GET  /api/payments" 403 "$(code $PC "$url")"

echo -n "  no client cert (handshake must fail)       "
if curl -s -o /dev/null $BASE -X POST "$url" 2>/dev/null; then
  echo "CONNECTED  FAIL"; fail=1
else
  echo "refused  PASS"
fi

echo
[ "$fail" = 0 ] && echo "PASS — identity is the perimeter." || { echo "FAIL — see notes in README.md"; exit 1; }
