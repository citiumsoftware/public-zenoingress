#!/usr/bin/env bash
# Play the browser: send the CORS preflight and the actual request from an
# allowed origin, a wildcard-matched origin and a foreign origin.
set -uo pipefail
cd "$(dirname "$0")"
source ../lib/common.sh

zi_gateway_forward cors gw 80 || exit 1
URL="http://localhost:$ZI_PORT/orders"
H="Host: api.example.test"
fail=0
check() { # <label> <expected> <actual>
  if [ "$2" = "$3" ]; then printf '  %-56s %s  PASS\n' "$1" "${3:-<absent>}"
  else printf '  %-56s %s  (want %s)  FAIL\n' "$1" "${3:-<absent>}" "${2:-<absent>}"; fail=1; fi
}
# header <name> <curl args...>: one response header's value (empty if absent).
header() {
  local name="$1"; shift
  curl -s -D - -o /dev/null "$@" | tr -d '\r' | awk -v IGNORECASE=1 -F': ' -v h="$name" 'tolower($1)==tolower(h){print $2}'
}
preflight() { # <origin> <method>
  curl -s -o /dev/null -w '%{http_code}' -X OPTIONS -H "$H" -H "Origin: $1" \
    -H "Access-Control-Request-Method: $2" "$URL"
}

echo "# preflight (answered by the proxy, not the API)"
check "preflight from https://app.example.test" 204 "$(preflight https://app.example.test DELETE)"
check "  allow-origin echoes the origin" https://app.example.test \
  "$(header access-control-allow-origin -X OPTIONS -H "$H" -H 'Origin: https://app.example.test' -H 'Access-Control-Request-Method: DELETE' "$URL")"
check "  allow-methods" "GET, POST, DELETE" \
  "$(header access-control-allow-methods -X OPTIONS -H "$H" -H 'Origin: https://app.example.test' -H 'Access-Control-Request-Method: DELETE' "$URL")"
check "  max-age" 600 \
  "$(header access-control-max-age -X OPTIONS -H "$H" -H 'Origin: https://app.example.test' -H 'Access-Control-Request-Method: DELETE' "$URL")"
check "preflight from https://pr-42.preview.example.test" https://pr-42.preview.example.test \
  "$(header access-control-allow-origin -X OPTIONS -H "$H" -H 'Origin: https://pr-42.preview.example.test' -H 'Access-Control-Request-Method: GET' "$URL")"
check "preflight from https://evil.test: no allow-origin" "" \
  "$(header access-control-allow-origin -X OPTIONS -H "$H" -H 'Origin: https://evil.test' -H 'Access-Control-Request-Method: GET' "$URL")"

echo "# actual requests (forwarded to the API, CORS headers added)"
check "GET from app origin: body from the API" '{"orders": 3}' \
  "$(curl -s -H "$H" -H 'Origin: https://app.example.test' "$URL")"
check "  allow-origin" https://app.example.test \
  "$(header access-control-allow-origin -H "$H" -H 'Origin: https://app.example.test' "$URL")"
check "  allow-credentials" true \
  "$(header access-control-allow-credentials -H "$H" -H 'Origin: https://app.example.test' "$URL")"
check "  expose-headers" x-request-id \
  "$(header access-control-expose-headers -H "$H" -H 'Origin: https://app.example.test' "$URL")"
check "GET from https://evil.test: no allow-origin" "" \
  "$(header access-control-allow-origin -H "$H" -H 'Origin: https://evil.test' "$URL")"

echo
[ "$fail" = 0 ] && echo "PASS — only the allowed origins get CORS access." || { echo "FAIL"; exit 1; }
