#!/usr/bin/env bash
# Prove the multi-team model:
#   - every team's hostname is served through the ONE Gateway proxy;
#   - team-b's attempt to take a.shop.test is refused (HostnameConflict) and
#     team-a keeps serving it;
#   - team-c's namespace is not allowed: its ListenerSet is NotAllowed and
#     c.shop.test is not served;
#   - the Gateway counts the attached ListenerSets.
set -uo pipefail
cd "$(dirname "$0")" || exit 1
source ../lib/common.sh

fail=0
check() { # <label> <expected> <actual>
  if [ "$2" = "$3" ]; then printf '  %-52s %s  PASS\n' "$1" "$3"
  else printf '  %-52s %s  (want %s)  FAIL\n' "$1" "$3" "$2"; fail=1; fi
}

echo "# status"
check "team-a ListenerSet Accepted" True \
  "$(kubectl -n team-a get listenerset team-a -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}')"
check "team-b listener 'steal' Conflicted (reason)" HostnameConflict \
  "$(kubectl -n team-b get listenerset team-b -o jsonpath='{.status.listeners[?(@.name=="steal")].conditions[?(@.type=="Conflicted")].reason}')"
check "team-b listener 'b' Programmed" True \
  "$(kubectl -n team-b get listenerset team-b -o jsonpath='{.status.listeners[?(@.name=="b")].conditions[?(@.type=="Programmed")].status}')"
check "team-c ListenerSet not allowed (reason)" NotAllowed \
  "$(kubectl -n team-c get listenerset team-c -o jsonpath='{.status.conditions[?(@.type=="Accepted")].reason}')"
check "Gateway status.attachedListenerSets" 2 \
  "$(kubectl -n platform get gateway shop -o jsonpath='{.status.attachedListenerSets}')"
check "proxy Services for all teams (one address)" 1 \
  "$(kubectl get svc -A -l gateway.networking.k8s.io/gateway-name -o name | wc -l | tr -d ' ')"

echo "# traffic through the one Gateway proxy"
zi_gateway_forward platform shop 80 || exit 1
get() { curl -s -H "Host: $1" "http://localhost:$ZI_PORT/"; }
code() { curl -s -o /dev/null -w '%{http_code}' -H "Host: $1" "http://localhost:$ZI_PORT/"; }
check "www.shop.test -> platform" "platform: www" "$(get www.shop.test)"
check "a.shop.test   -> team-a (not team-b)" "team-a: shop A" "$(get a.shop.test)"
check "b.shop.test   -> team-b" "team-b: shop B" "$(get b.shop.test)"
check "c.shop.test   -> not served (team-c not allowed)" 404 "$(code c.shop.test)"

echo
[ "$fail" = 0 ] && echo "PASS — teams self-serve hostnames on one shared Gateway, safely." \
  || { echo "FAIL"; exit 1; }
