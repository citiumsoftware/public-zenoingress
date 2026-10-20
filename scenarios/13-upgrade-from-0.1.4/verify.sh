#!/usr/bin/env bash
# Works before and after ./upgrade.sh: the app is served, through the shared
# proxy Service in zenoingress-system. After the upgrade it also checks that the
# release stayed in shared mode and kept its proxy Service (same address).
set -uo pipefail
cd "$(dirname "$0")" || exit 1
source ../lib/common.sh
HOST=welcome.zenoingress.test
STATE="$(dirname "$0")/.proxy-ip"

fail=0
check() { # <label> <expected> <actual>
  if [ "$2" = "$3" ]; then printf '  %-48s %s  PASS\n' "$1" "$3"
  else printf '  %-48s %s  (want %s)  FAIL\n' "$1" "$3" "$2"; fail=1; fi
}

SVC="$(kubectl -n zenoingress-system get svc -l app.kubernetes.io/component=proxy -o name | head -1)"
[ -n "$SVC" ] || { echo "FAIL — no shared proxy Service in zenoingress-system"; exit 1; }
ip="$(kubectl -n zenoingress-system get "$SVC" -o jsonpath='{.spec.clusterIP}')"
controller="$(kubectl -n zenoingress-system get deploy -l app.kubernetes.io/component=controller \
  -o jsonpath='{.items[0].spec.template.spec.containers[0].image}')"
echo "# controller image: $controller"
echo "# shared proxy: $SVC ($ip)"

if [ -f "$STATE" ]; then
  check "shared proxy kept its address" "$(cat "$STATE")" "$ip"
  check "provisioning mode stayed" shared "$(kubectl -n zenoingress-system get deploy \
    -l app.kubernetes.io/component=controller \
    -o jsonpath='{.items[0].metadata.annotations.zenoingress\.io/provisioning}')"
  check "no per-Gateway proxy was created" "" \
    "$(kubectl -n simple-ingress get svc -l gateway.networking.k8s.io/gateway-name -o name)"
  check "Gateway still Programmed" True \
    "$(kubectl -n simple-ingress get gateway simple-gateway -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}')"
else
  echo "$ip" > "$STATE"
fi

zi_port_forward zenoingress-system "$SVC" 80 || exit 1
body="$(curl -s -H "Host: $HOST" "http://localhost:$ZI_PORT/")"
printf '%s' "$body" | grep -q "Welcome To ZenoIngress" \
  && check "welcome page through the shared proxy" served served \
  || check "welcome page through the shared proxy" served "not served"

echo
[ "$fail" = 0 ] && echo "PASS" || { echo "FAIL"; exit 1; }
