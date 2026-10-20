#!/usr/bin/env bash
# Prove the WAF works: clean input passes (200), attack payloads are blocked
# in the proxy (403) before they reach the app. The route has no hostname, so
# we just curl localhost through the port-forward.
set -uo pipefail
cd "$(dirname "$0")" || exit 1
source ../lib/common.sh
zi_gateway_forward waf-app waf-gateway 80 || exit 1
PORT="$ZI_PORT"

fail=0
probe() { # <label> <expected-code> <query>
  local label="$1" want="$2" q="$3" got
  got="$(curl -s -o /dev/null -w '%{http_code}' --get --data-urlencode "q=$q" "http://localhost:$PORT/")"
  if [ "$got" = "$want" ]; then
    printf '  %-16s -> %s  (want %s)  PASS\n' "$label" "$got" "$want"
  else
    printf '  %-16s -> %s  (want %s)  FAIL\n' "$label" "$got" "$want"; fail=1
  fi
}

echo "# sending probes through the WAF"
probe "clean"          200 "hello world"
probe "sql-injection"  403 "' OR 1=1--"
probe "xss"            403 "<script>alert(1)</script>"
probe "path-traversal" 403 "/../../etc/passwd"

echo
if [ "$fail" = 0 ]; then
  echo "PASS — clean traffic flows, attacks bounce off."
else
  echo "FAIL — check the proxy WAF is loaded (kubectl -n waf-app logs deploy/waf-gateway-zenoingress | grep -i waf)."
  echo "       First run also needs the init container to have fetched the module."
  exit 1
fi
