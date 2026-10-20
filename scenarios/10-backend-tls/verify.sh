#!/usr/bin/env bash
# Prove backend TLS works, and fails closed:
#   backend.secure.test : TLS to the backend, certificate verified -> 200
#   wrong-name          : certificate does not match the policy's hostname -> 5xx
#   no-ca               : the policy's CA does not exist -> 5xx, policy not accepted
#   spiffe              : SAN check against a SPIFFE URI instead of the name -> 200
set -uo pipefail
cd "$(dirname "$0")" || exit 1
source ../lib/common.sh
NS=backend-tls

fail=0
check() { # <label> <expected (regex)> <actual>
  if printf '%s' "$3" | grep -qE "^($2)\$"; then printf '  %-50s %s  PASS\n' "$1" "$3"
  else printf '  %-50s %s  (want %s)  FAIL\n' "$1" "$3" "$2"; fail=1; fi
}
cond() { # <policy> <type> -> status/reason of our ancestor entry
  kubectl -n "$NS" get backendtlspolicy "$1" \
    -o jsonpath="{.status.ancestors[0].conditions[?(@.type==\"$2\")].status}/{.status.ancestors[0].conditions[?(@.type==\"$2\")].reason}"
}

echo "# policy status (per Gateway that uses the Service)"
check "backend   Accepted" "True/Accepted" "$(cond backend Accepted)"
check "backend   ResolvedRefs" "True/ResolvedRefs" "$(cond backend ResolvedRefs)"
check "no-ca     Accepted" "False/NoValidCACertificate" "$(cond no-ca Accepted)"
check "no-ca     ResolvedRefs" "False/InvalidCACertificateRef" "$(cond no-ca ResolvedRefs)"

echo "# traffic"
zi_gateway_forward "$NS" gw 80 || exit 1
code() { curl -s -o /dev/null -w '%{http_code}' -H "Host: $1" "http://localhost:$ZI_PORT/"; }
body="$(curl -s -H "Host: secure.test" "http://localhost:$ZI_PORT/")"
check "secure.test            -> verified TLS backend" "secure backend: TLS verified" "$body"
check "wrong-name.secure.test -> refused (name mismatch)" "50[0-4]" "$(code wrong-name.secure.test)"
check "no-ca.secure.test      -> refused (no trust anchor)" "50[0-4]" "$(code no-ca.secure.test)"
check "spiffe.secure.test     -> verified by SPIFFE URI SAN" 200 "$(code spiffe.secure.test)"

echo
[ "$fail" = 0 ] && echo "PASS — the proxy re-encrypts to the backend and never skips verification." \
  || { echo "FAIL"; exit 1; }
