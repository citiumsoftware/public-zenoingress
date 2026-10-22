#!/usr/bin/env bash
# Prove the two gates:
#   1. mTLS — no client cert → the TLS handshake is refused.
#   2. Cedar — only the payments SVID doing POST /api/payments is permitted;
#      a different SVID or a different method is denied (403).
set -uo pipefail
cd "$(dirname "$0")" || exit 1
HOST=zt.demo.zeno
source ../lib/common.sh

[ -f certs/ca.crt ] || { echo "no certs/ — run ./up.sh (or ./gen-certs.sh) first"; exit 1; }
zi_gateway_forward zero-trust zt-gateway 443 || exit 1
PORT="$ZI_PORT"

BASE="--resolve $HOST:$PORT:127.0.0.1 --cacert certs/ca.crt"
url="https://$HOST:$PORT/api/payments"
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
