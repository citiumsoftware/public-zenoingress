#!/usr/bin/env bash
# Prove the split: fire N requests at one hostname and count how many landed on
# stable (v1) vs canary (v2). With weights 90/10 you should see roughly 9:1.
set -uo pipefail
cd "$(dirname "$0")" || exit 1
HOST=canary.zenoingress.test
N="${1:-40}"
source ../lib/common.sh
zi_gateway_forward canary canary-gateway 80 || exit 1
PORT="$ZI_PORT"

echo "# firing $N requests at http://$HOST/ ..."
v1=0; v2=0; other=0
for _ in $(seq "$N"); do
  tok="$(curl -s -H "Host: $HOST" "http://localhost:$PORT/" | grep -oE 'ZI_VERSION=v[12]' | head -1)"
  case "$tok" in
    *v1) v1=$((v1+1)) ;;
    *v2) v2=$((v2+1)) ;;
    *)   other=$((other+1)) ;;
  esac
done

echo
echo "  stable  v1 : $v1 / $N"
echo "  canary  v2 : $v2 / $N"
[ "$other" -eq 0 ] || echo "  unrouted   : $other / $N  (proxy not ready?)"
echo
echo "(weights are 90/10 in k8s/manifests.yaml; small N will vary. Raise N: ./verify.sh 200)"

# Both versions must take traffic, nothing may be unrouted, and the canary must
# stay the minority (90/10 leaves plenty of slack even at N=40).
if [ "$other" -eq 0 ] && [ "$v1" -gt 0 ] && [ "$v2" -gt 0 ] && [ "$v2" -lt "$v1" ]; then
  echo "PASS — traffic is split between stable and canary."
else
  echo "FAIL — expected both versions to answer, mostly v1, none unrouted."; exit 1
fi
