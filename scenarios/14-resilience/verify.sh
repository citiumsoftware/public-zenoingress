#!/usr/bin/env bash
# Keep requests flowing through the Gateway (from inside the cluster, through
# the proxy Service, as real clients would) while things break:
#   1. one of the two proxy pods is deleted;
#   2. the controller is restarted (rolling);
#   3. the leading controller is deleted, and the other must take over.
# Then count the requests that did not get a 200.
set -uo pipefail
cd "$(dirname "$0")" || exit 1
source ../lib/common.sh
NS=resilience
DURATION="${DURATION:-120}"
fail=0
check() { # <label> <expected> <actual>
  if [ "$2" = "$3" ]; then printf '  %-50s %s  PASS\n' "$1" "$3"
  else printf '  %-50s %s  (want %s)  FAIL\n' "$1" "$3" "$2"; fail=1; fi
}
holder() { kubectl -n zenoingress-system get lease zenoingress-controller-leader -o jsonpath='{.spec.holderIdentity}'; }

echo "# ${DURATION}s of traffic: http://web-zenoingress.$NS.svc/ (Host: app.resilience.test), every 50 ms"
kubectl -n "$NS" delete pod load --ignore-not-found >/dev/null
kubectl -n "$NS" run load --image=curlimages/curl:8.10.1 --restart=Never --command -- sh -c "
  end=\$(( \$(date +%s) + $DURATION ))
  while [ \$(date +%s) -lt \$end ]; do
    curl -s -o /dev/null -m 2 -w '%{http_code}\n' -H 'Host: app.resilience.test' http://web-zenoingress.$NS.svc/
    sleep 0.05
  done" >/dev/null
kubectl -n "$NS" wait --for=condition=Ready pod/load --timeout=120s >/dev/null
sleep 10

echo "# 1. delete one proxy pod"
pod="$(kubectl -n "$NS" get pods -l zenoingress.io/gateway-proxy=web-zenoingress -o name | head -1)"
kubectl -n "$NS" delete "$pod" --wait=false >/dev/null
kubectl -n "$NS" rollout status deploy/web-zenoingress --timeout=120s >/dev/null
sleep 10

echo "# 2. restart the controller"
kubectl -n zenoingress-system rollout restart deploy -l app.kubernetes.io/component=controller >/dev/null
kubectl -n zenoingress-system rollout status deploy -l app.kubernetes.io/component=controller --timeout=180s >/dev/null
sleep 5

echo "# 3. delete the leading controller"
before="$(holder)"
leader_pod="${before%-*}"            # identity = <pod name>-<random suffix>
kubectl -n zenoingress-system delete pod "$leader_pod" --wait=false >/dev/null
after="$before"
for _ in $(seq 1 30); do
  after="$(holder)"
  [ -n "$after" ] && [ "$after" != "$before" ] && break
  sleep 1
done
[ -n "$after" ] && [ "$after" != "$before" ] \
  && check "another controller took the lease" yes yes \
  || check "another controller took the lease" yes "no ($after)"

echo "# waiting for the traffic to finish"
kubectl -n "$NS" wait --for=jsonpath='{.status.phase}'=Succeeded pod/load --timeout="$((DURATION + 60))s" >/dev/null
codes="$(kubectl -n "$NS" logs load | sort | uniq -c | sort -rn)"
echo "$codes" | sed 's/^/    /'
total="$(kubectl -n "$NS" logs load | wc -l | tr -d ' ')"
bad="$(kubectl -n "$NS" logs load | grep -vc '^200$')"
echo "  requests: $total"
check "requests without a 200" 0 "$bad"

echo
[ "$fail" = 0 ] && echo "PASS — no request failed while proxies and controllers were replaced." || { echo "FAIL"; exit 1; }
