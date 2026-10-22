# Scenario 13 — Upgrade from 0.1.5

Upgrade an existing 0.1.5 install, the way a running cluster should be
upgraded, and prove nothing moved.

## Run

```bash
./up.sh        # kind + Gateway API v1.2.0 + ZenoIngress 0.1.5 + the basic-ingress app
./verify.sh    # the app is served by 0.1.5's shared proxy (remembers its address)
./upgrade.sh   # the three upgrade steps below
./verify.sh    # same address, still shared, still served
./down.sh      # delete the kind cluster
```

## The upgrade steps

```bash
# 1. Gateway API CRDs v1.6.1 (needs Kubernetes 1.31+; server-side apply, the
#    CRDs are too large for client-side apply)
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.1/standard-install.yaml

# 2. ZenoIngress's own CRDs: Helm installs crds/ on the first install only
helm show crds oci://ghcr.io/citiumsoftware/zenoingress-chart --version 0.2.0 \
  | kubectl apply --server-side --force-conflicts -f -

# 3. The release. --reset-then-reuse-values (Helm 3.14+) keeps the values you
#    set and gives new settings their defaults; plain --reuse-values would not.
helm upgrade zenoingress oci://ghcr.io/citiumsoftware/zenoingress-chart --version 0.2.0 \
  -n zenoingress-system --reset-then-reuse-values
```

## What it checks

- The proxy Service in `zenoingress-system` keeps its address.
- The release stays in **shared** mode: an upgrade never switches to a proxy
  per Gateway, because that would give every Gateway a new address. The chart
  records the mode on the controller Deployment
  (`zenoingress.io/provisioning`). To move to per-Gateway proxies later, set
  `provisioning: per-gateway` deliberately and update DNS to the new addresses.
- The Gateway stays `Programmed` and the app is served.

## Things to know when upgrading

- **GitOps / `helm template`:** without cluster access the chart cannot read the
  previous mode, so set `provisioning: shared` explicitly for an existing
  install (a new install defaults to `per-gateway`).
- **mTLS:** the experimental per-listener `tls.frontendValidation` is not kept
  by the v1.5+ CRDs. Move client-certificate validation to the Gateway's
  `spec.tls.frontend` (see [scenario 06](../06-zero-trust-mtls/)) **before**
  upgrading the CRDs, or listeners that required client certificates will
  stop requiring them.
- **BodyTransformPolicy** changed its short name from `btp` to `btfp` (it
  collided with BackendTLSPolicy); step 2 updates it.
- **Tunnel edges** (scenarios 07/08) now refuse `--auth-mode none` unless
  started with `--insecure-allow-no-auth`; configure token or mTLS auth first.
- **For about 30 seconds after the upgrade** the old 0.1.5 controller is still
  terminating (its leader election flag has no effect, and it waits out its
  grace period) while the new one runs. Both write Gateway and GatewayClass
  status, so the new controller's log shows a burst of reconciles. It stops
  when the old pod exits; traffic is not affected. Upgrades from 0.2.0 on hand
  over through leader election.
