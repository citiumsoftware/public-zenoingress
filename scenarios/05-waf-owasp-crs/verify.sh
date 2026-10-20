#!/usr/bin/env bash
# Prove the OWASP CRS works: clean input passes (200); a range of attack classes
# the CRS covers are blocked (403) in the proxy before reaching the app.
set -uo pipefail
cd "$(dirname "$0")" || exit 1
source ../lib/common.sh
zi_gateway_forward waf-crs waf-gateway 80 || exit 1
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

echo "# sending probes through the OWASP CRS"
probe "clean"          200 "hello world"
probe "sql-injection"  403 "' OR 1=1--"
probe "xss"            403 "<script>alert(1)</script>"
probe "lfi"            403 "/etc/passwd"
probe "command-inj"    403 ";cat /etc/passwd"

echo
if [ "$fail" = 0 ]; then
  echo "PASS — clean traffic flows, the CRS blocks the attack classes."
else
  echo "FAIL — check the WAF loaded (proxy at --log-level=debug logs coraza's own"
  echo "       messages under target=wasm_filter). First run also fetches + compiles CRS."
  exit 1
fi
