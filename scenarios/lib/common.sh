# shellcheck shell=bash
# Shared helpers for the runnable scenarios (02+). Sourced by each up.sh /
# verify.sh; not meant to be run directly.
#
# Defaults install the published release. Overrides (all optional):
#
#   ZENOINGRESS_VERSION        chart + image version          (default below)
#   ZENOINGRESS_CHART          chart reference: the OCI chart (default) or a
#                              local chart directory
#   ZENOINGRESS_LOAD_IMAGES=1  `kind load` the images from the local docker
#                              daemon instead of pulling them (for images you
#                              built or mirrored yourself)
#   GATEWAY_API_VERSION        Gateway API CRD release        (default v1.6.1)

ZENOINGRESS_VERSION="${ZENOINGRESS_VERSION:-0.2.0}"
ZENOINGRESS_CHART="${ZENOINGRESS_CHART:-oci://ghcr.io/citiumsoftware/zenoingress-chart}"
ZENOINGRESS_REGISTRY="${ZENOINGRESS_REGISTRY:-ghcr.io/citiumsoftware}"
GATEWAY_API_VERSION="${GATEWAY_API_VERSION:-v1.6.1}"

# zi_cluster <name>: create the kind cluster unless it exists.
zi_cluster() {
  kind get clusters 2>/dev/null | grep -qx "$1" || kind create cluster --name "$1" --wait 60s
}

# zi_gateway_api [standard|experimental]: install the Gateway API CRDs.
# Server-side apply: the v1.5+ CRDs are too large for client-side apply.
zi_gateway_api() {
  local channel="${1:-standard}"
  kubectl apply --server-side -f \
    "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/${channel}-install.yaml" \
    >/dev/null
  kubectl wait --for=condition=Established crd --all --timeout=60s >/dev/null
}

# zi_image <component>: the image reference for controller, proxy or edge.
zi_image() {
  echo "${ZENOINGRESS_REGISTRY}/zenoingress-$1:${ZENOINGRESS_VERSION}"
}

# zi_load_images <cluster> <component>...: with ZENOINGRESS_LOAD_IMAGES=1,
# copy the images from the local docker daemon into the kind cluster.
zi_load_images() {
  [ "${ZENOINGRESS_LOAD_IMAGES:-0}" = 1 ] || return 0
  local cluster="$1"; shift
  local c
  for c in "$@"; do
    kind load docker-image "$(zi_image "$c")" --name "$cluster" >/dev/null
  done
}

# zi_install [helm args...]: install or upgrade ZenoIngress in
# zenoingress-system.
zi_install() {
  local version=()
  case "$ZENOINGRESS_CHART" in
    oci://*) version=(--version "$ZENOINGRESS_VERSION") ;;
  esac
  helm upgrade --install zenoingress "$ZENOINGRESS_CHART" "${version[@]}" \
    -n zenoingress-system --create-namespace \
    --set controller.image.tag="$ZENOINGRESS_VERSION" \
    --set proxy.image.tag="$ZENOINGRESS_VERSION" \
    "$@"
  kubectl -n zenoingress-system rollout status deploy -l app.kubernetes.io/component=controller --timeout=180s
}

# zi_wait_gateway <namespace> <gateway> [timeout]: wait until the Gateway is
# programmed: accepted, and its proxy is running with an address.
zi_wait_gateway() {
  kubectl -n "$1" wait --for=condition=Programmed "gateway/$2" --timeout="${3:-240s}"
}

# zi_gateway_service <namespace> <gateway>: the Service of the Gateway's own
# proxy (one per Gateway, in the Gateway's namespace).
zi_gateway_service() {
  kubectl -n "$1" get svc -l "gateway.networking.k8s.io/gateway-name=$2" -o name | head -1
}

# zi_port_forward <namespace> <service> <port>: port-forward to a random free
# local port, exported as ZI_PORT; stopped when the script exits.
zi_port_forward() {
  local log
  log="$(mktemp)"
  kubectl -n "$1" port-forward "$2" ":$3" >"$log" 2>&1 &
  ZI_PF_PID=$!
  trap 'kill "$ZI_PF_PID" 2>/dev/null; rm -f "'"$log"'"' EXIT

  for _ in $(seq 1 20); do
    ZI_PORT="$(sed -nE 's|.*127\.0\.0\.1:([0-9]+).*|\1|p' "$log" | head -1)"
    [ -n "$ZI_PORT" ] && break
    sleep 0.5
  done
  if [ -z "${ZI_PORT:-}" ]; then
    echo "port-forward to $1/$2 failed:"; cat "$log"; return 1
  fi
  export ZI_PORT
  echo "# port-forward $1/$2  (localhost:$ZI_PORT -> :$3)"
}

# zi_gateway_forward <namespace> <gateway> <port>: port-forward to the
# Gateway's proxy Service.
zi_gateway_forward() {
  local svc
  svc="$(zi_gateway_service "$1" "$2")"
  if [ -z "$svc" ]; then
    echo "no proxy Service for Gateway $1/$2 — run ./up.sh, then check:"
    echo "  kubectl -n $1 get gateway $2 -o yaml"
    return 1
  fi
  zi_port_forward "$1" "$svc" "$3"
}
