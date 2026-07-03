#!/usr/bin/env bash
# Prove HA: the app is reachable via BOTH edges, and stopping one edge leaves the
# other still serving (a single front-door failure does not take the app down).
set -uo pipefail
cd "$(dirname "$0")"
APP=app.demo.zenoingress.test

hit() { curl -sk --resolve "$APP:$1:127.0.0.1" -o /dev/null -w '%{http_code}' "https://$APP:$1/" 2>/dev/null; }
wait_ok() { for _ in $(seq 1 15); do [ "$(hit "$1")" = "200" ] && return 0; sleep 2; done; return 1; }

echo "# both edges front the same app"
wait_ok 8443 && echo "  edge-a (:8443)  ->  200  OK" || { echo "  FAIL: edge-a never served"; exit 1; }
wait_ok 9443 && echo "  edge-b (:9443)  ->  200  OK" || { echo "  FAIL: edge-b never served"; exit 1; }

echo
echo "# HA: stop edge-a; edge-b must keep serving"
docker stop edge-a >/dev/null 2>&1
sleep 3
a="$(hit 8443)"; b="$(hit 9443)"
echo "  edge-a (:8443, stopped) -> ${a:-000}    edge-b (:9443) -> ${b}"
docker start edge-a >/dev/null 2>&1   # restore the second front door

echo
if [ "$b" = "200" ] && [ "$a" != "200" ]; then
  echo "PASS — one hostname, two edges. A single edge failure does not take the app down."
  echo "       (edge-a restarted; give it a few seconds to re-establish its tunnel.)"
else
  echo "FAIL — expected edge-b to keep serving (200) while edge-a was down."
  exit 1
fi
