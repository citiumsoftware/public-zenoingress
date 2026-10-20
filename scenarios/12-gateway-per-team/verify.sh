#!/usr/bin/env bash
# Prove per-Gateway data planes:
#   - each Gateway has its own proxy Service and address;
#   - the same hostname reaches each team's own app through its own Gateway;
#   - spec.infrastructure labels are on the generated objects;
#   - deleting a Gateway removes its proxy, and the other team is unaffected.
set -uo pipefail
cd "$(dirname "$0")"
source ../lib/common.sh

fail=0
check() { # <label> <expected> <actual>
  if [ "$2" = "$3" ]; then printf '  %-52s %s  PASS\n' "$1" "$3"
  else printf '  %-52s %s  (want %s)  FAIL\n' "$1" "$3" "$2"; fail=1; fi
}
addr() { kubectl -n "$1" get gateway web -o jsonpath='{.status.addresses[0].value}'; }
via() { # <namespace>: the body for shop.example.test through that team's Gateway
  local svc pf port log
  svc="$(zi_gateway_service "$1" web)"
  log="$(mktemp)"
  kubectl -n "$1" port-forward "$svc" :80 >"$log" 2>&1 & pf=$!
  for _ in $(seq 1 20); do
    port="$(sed -nE 's|.*127\.0\.0\.1:([0-9]+).*|\1|p' "$log" | head -1)"
    [ -n "$port" ] && break; sleep 0.5
  done
  curl -s -H "Host: shop.example.test" "http://localhost:$port/"
  kill "$pf" 2>/dev/null; rm -f "$log"
}

echo "# one data plane per Gateway"
red="$(addr team-red)"; blue="$(addr team-blue)"
printf '  team-red address %s, team-blue address %s\n' "$red" "$blue"
[ -n "$red" ] && [ "$red" != "$blue" ] && check "two different addresses" yes yes || check "two different addresses" yes no
check "team-red proxy Service" "service/web-zenoingress" "$(zi_gateway_service team-red web)"
check "infrastructure label on team-red's Service" team-red \
  "$(kubectl -n team-red get svc web-zenoingress -o jsonpath='{.metadata.labels.cost-center}')"
check "Service owned by the Gateway" Gateway \
  "$(kubectl -n team-red get svc web-zenoingress -o jsonpath='{.metadata.ownerReferences[0].kind}')"

echo "# the same hostname, isolated"
check "shop.example.test via team-red's Gateway" "red shop" "$(via team-red)"
check "shop.example.test via team-blue's Gateway" "blue shop" "$(via team-blue)"

echo "# delete team-blue's Gateway: its proxy goes, team-red keeps serving"
kubectl -n team-blue delete gateway web --wait=true >/dev/null
for _ in $(seq 1 30); do
  [ -z "$(kubectl -n team-blue get deploy,svc -l gateway.networking.k8s.io/gateway-name=web -o name)" ] && break
  sleep 2
done
check "team-blue proxy objects removed" "" \
  "$(kubectl -n team-blue get deploy,svc -l gateway.networking.k8s.io/gateway-name=web -o name)"
check "shop.example.test via team-red's Gateway" "red shop" "$(via team-red)"
kubectl apply -f k8s/manifests.yaml >/dev/null   # restore, so verify can run again

echo
[ "$fail" = 0 ] && echo "PASS — each Gateway is its own data plane." || { echo "FAIL"; exit 1; }
