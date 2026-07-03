#!/usr/bin/env bash
# Prove the OWASP CRS works: clean input passes (200); a range of attack classes
# the CRS covers are blocked (403) in the proxy before reaching the app.
set -uo pipefail
cd "$(dirname "$0")"
NS=zenoingress-system

SVC="$(kubectl -n "$NS" get svc -o name | grep -m1 proxy)"
[ -n "$SVC" ] || { echo "proxy service not found in $NS — run ./up.sh first"; exit 1; }

# Random free local port (avoids clashing with anything on :8080).
PF_LOG="$(mktemp)"
kubectl -n "$NS" port-forward "$SVC" :80 >"$PF_LOG" 2>&1 &
trap 'kill %1 2>/dev/null; rm -f "$PF_LOG"' EXIT
sleep 3
PORT="$(sed -nE 's|.*127\.0\.0\.1:([0-9]+).*|\1|p' "$PF_LOG" | head -1)"
[ -n "$PORT" ] || { echo "port-forward failed:"; cat "$PF_LOG"; exit 1; }
echo "# port-forward $SVC  (localhost:$PORT -> proxy :80)"

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
