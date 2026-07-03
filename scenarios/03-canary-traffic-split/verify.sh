#!/usr/bin/env bash
# Prove the split: fire N requests at one hostname and count how many landed on
# stable (v1) vs canary (v2). With weights 90/10 you should see roughly 9:1.
set -uo pipefail
cd "$(dirname "$0")"
HOST=canary.zenoingress.test
NS=zenoingress-system
N="${1:-40}"

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
