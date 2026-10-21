# zenoingress

> A sovereign, memory-safe Kubernetes Gateway API ingress controller, written in Rust.

[![License](https://img.shields.io/badge/license-Proprietary-red.svg)](./LICENSE)
[![Gateway API](https://img.shields.io/badge/Gateway%20API-v1.6.1-green.svg)](https://gateway-api.sigs.k8s.io/)
[![Conformance](https://img.shields.io/badge/GATEWAY--HTTP-90%2F90-green.svg)](#gateway-api-conformance)
[![Container images](https://img.shields.io/badge/ghcr.io-citiumsoftware-1f6feb.svg)](https://github.com/orgs/citiumsoftware/packages?repo_name=public-zenoingress)

zenoingress is a modern ingress controller that implements the
[Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/). Built in Rust for performance and
safety, it routes HTTP, gRPC, TLS, TCP and UDP traffic to your Kubernetes services with security
built in — no sidecars.

> [!NOTE]
> This repository is **documentation only** — getting-started guides, license, example
> scenarios and the [pilot playbook](./PILOT.md). The zenoingress source is maintained
> separately; here you'll find everything you need to *run* the published container images and
> Helm chart.

## Why zenoingress

- **Memory-safe by construction** — 100% safe Rust (`#![forbid(unsafe_code)]`); the memory-corruption
  bug class behind critical CVEs in C/C++ proxies simply cannot occur.
- **Post-quantum TLS** — TLS 1.3 defaults to the hybrid X25519MLKEM768 (ML-KEM-768, NIST FIPS 203)
  key exchange via rustls + aws-lc-rs. No OpenSSL.
- **Integrated security, no sidecars** — built-in WAF (Coraza / OWASP CRS), in-process Cedar
  authorization, external OAuth2/OIDC auth, client-certificate (mTLS) validation and verified TLS
  to backends, all in one binary.
- **A data plane per Gateway** — each Gateway gets its own proxy and address in its own namespace,
  so teams are isolated by default; teams can still share one Gateway with ListenerSets.
- **Sovereign & restricted environments** — a hybrid tunnel + edge mode exposes private or
  air-gapped clusters with no inbound access (EU data-sovereignty, FedRAMP-style data planes).
- **Gateway API native** — Gateway API v1.6: Gateway, HTTPRoute, GRPCRoute, ListenerSet,
  BackendTLSPolicy, the CORS filter, TLS/TCP/UDP routes and ReferenceGrant.
- **Observable & production-ready** — Prometheus metrics, structured logging, OpenTelemetry tracing,
  health checks, circuit breaking, graceful shutdown, leader election and hot-reload configuration.

## Components

zenoingress is distributed as container images under the org's public GitHub Container Registry:

| Component  | Image                                            | Role |
|------------|--------------------------------------------------|------|
| Controller | `ghcr.io/citiumsoftware/zenoingress-controller`  | Control plane — watches Gateway API resources and starts and programs the data plane. |
| Proxy      | `ghcr.io/citiumsoftware/zenoingress-proxy`       | Data plane — terminates TLS and routes client traffic to backend services. One per Gateway (or one shared). |
| Edge       | `ghcr.io/citiumsoftware/zenoingress-edge`        | Optional edge server for hybrid/tunnel mode — runs on public infrastructure so the in-cluster proxy can expose a private or air-gapped cluster with no inbound access. |
| Helm chart | `oci://ghcr.io/citiumsoftware/zenoingress-chart` | Installs the controller, the GatewayClass and the CRDs. |

## Quick start

> [!TIP]
> The currently published versions are free to run in **one production Kubernetes cluster** plus
> **unlimited development and test clusters** — see [License](#license). No sign-up needed.

### Prerequisites

- A Kubernetes cluster, **v1.31+** (the Gateway API v1.6 CRDs need it)
- [Helm](https://helm.sh/) **3.8+** (OCI registry support; 3.14+ for upgrades) and `kubectl`
- A load balancer for `LoadBalancer` Services (any cloud; MetalLB or similar on bare metal) — or
  install with `--set proxy.service.type=ClusterIP` (or `NodePort`)

### 1. Install the Gateway API CRDs

```bash
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.1/standard-install.yaml
```

`--server-side` is required: the v1.5+ CRDs are too large for client-side apply.

### 2. Install zenoingress

The chart is an OCI artifact — no `helm repo add` needed:

```bash
helm install zenoingress \
  oci://ghcr.io/citiumsoftware/zenoingress-chart \
  --version 0.1.5 \
  --namespace zenoingress-system \
  --create-namespace
```
<!-- TODO(maintainer): requires the 0.1.5 chart and images pushed to ghcr before these docs go public. -->

### 3. Verify

```bash
kubectl get pods -n zenoingress-system          # the controller
kubectl get gatewayclass zenoingress             # ACCEPTED = True
```

Then create a Gateway and a route — see [scenario 01](./scenarios/01-basic-http-routing/) — and
wait for it:

```bash
kubectl wait --for=condition=Programmed gateway/web --timeout=180s
kubectl get gateway web                          # ADDRESS = where to send traffic
```

## How Gateways get their proxy

For each Gateway, zenoingress starts a **proxy of its own**, in the Gateway's namespace: a
Deployment and a Service named `<gateway>-<gatewayclass>` (e.g. `web-zenoingress`), owned by the
Gateway and removed with it. The Service's address is the Gateway's address
(`status.addresses`), and `Programmed=True` means that proxy runs and has an address. Each proxy
receives only its own Gateway's configuration.

- **Size the proxies** with the chart's `proxy` values (`replicaCount`, `resources`,
  `service.type`, `service.annotations`, `nodeSelector`, ...). `spec.infrastructure.labels` and
  `annotations` on a Gateway are copied onto its proxy objects.
- **One address for many teams:** let teams add their hostnames to a shared Gateway with
  ListenerSets ([scenario 09](./scenarios/09-multi-team-listenersets/)).
- **Shared mode:** `--set provisioning=shared` (or the GatewayClass annotation
  `zenoingress.io/provisioning: shared`) serves all Gateways of a class from one proxy on one
  address, as releases before 0.1.5 did. Tunnel mode always uses it.
- **Conflicts:** two listeners that claim the same hostname on the same proxy and port, or use
  different protocols on it, can't both be served. The Gateway's own listeners and older ones win;
  the other reports `Conflicted=True` (`HostnameConflict` / `ProtocolConflict`) and serves nothing.

## Upgrading

From 0.1.4 (full walkthrough: [scenario 13](./scenarios/13-upgrade-from-0.1.4/)):

```bash
# 1. Gateway API CRDs
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.1/standard-install.yaml
# 2. zenoingress CRDs (Helm installs crds/ on the first install only)
helm show crds oci://ghcr.io/citiumsoftware/zenoingress-chart --version 0.1.5 \
  | kubectl apply --server-side --force-conflicts -f -
# 3. the release
helm upgrade zenoingress oci://ghcr.io/citiumsoftware/zenoingress-chart --version 0.1.5 \
  -n zenoingress-system --reset-then-reuse-values
```

- An upgrade **keeps the shared proxy and its address**; it never switches to a proxy per Gateway on
  its own. With GitOps or `helm template` (no cluster access), set `provisioning: shared`
  explicitly.
- Client-certificate validation moved from the experimental per-listener
  `tls.frontendValidation` to the Gateway's `spec.tls.frontend` (Standard since Gateway API v1.5).
  Move it **before** upgrading the CRDs ([scenario 06](./scenarios/06-zero-trust-mtls/)).
- Tunnel edges refuse `--auth-mode none` unless started with `--insecure-allow-no-auth`; use token
  or mTLS auth ([scenario 07](./scenarios/07-hybrid-edge-tunnel/)).

## Container images

All images live under the `citiumsoftware` org and are public — anyone can pull them without
authentication. Pulling an image does **not** grant a license to use zenoingress; see
[License](#license).

| Image                                            | Current tag |
|--------------------------------------------------|-------------|
| `ghcr.io/citiumsoftware/zenoingress-controller`  | `0.1.5`     |
| `ghcr.io/citiumsoftware/zenoingress-proxy`       | `0.1.5`     |
| `ghcr.io/citiumsoftware/zenoingress-edge`        | `0.1.5`     |
| `oci://ghcr.io/citiumsoftware/zenoingress-chart` | `0.1.5`     |

```bash
docker pull ghcr.io/citiumsoftware/zenoingress-controller:0.1.5
```

## Scenarios

Worked examples live in [`scenarios/`](./scenarios/). Scenario 01 is a manual walkthrough (it
assumes zenoingress is already installed via the [Quick start](#quick-start)); scenarios 02+ are
one-command demos — each `./up.sh` spins up a local `kind` cluster and installs from the public
chart, `./verify.sh` proves it with PASS/FAIL checks, and `./down.sh` cleans up.

| #  | Scenario | What it shows |
|----|----------|---------------|
| 01 | [Basic HTTP routing](./scenarios/01-basic-http-routing/) | Expose a service with a Gateway + HTTPRoute (manual walkthrough). |
| 02 | [Basic ingress](./scenarios/02-basic-ingress/) | The same, in one command: kind + chart + a Caddy app. |
| 03 | [Canary traffic splitting](./scenarios/03-canary-traffic-split/) | Weighted `HTTPRoute` — shift traffic 90/10 → 0/100. |
| 04 | [WAF](./scenarios/04-waf/) | In-proxy Coraza WAF: block SQLi/XSS/traversal on a route. |
| 05 | [WAF with OWASP CRS](./scenarios/05-waf-owasp-crs/) | The full OWASP Core Rule Set, in-proxy. |
| 06 | [Zero-trust (mTLS + Cedar)](./scenarios/06-zero-trust-mtls/) | Client-SVID mTLS + Cedar authz, deny-by-default. |
| 07 | [Hybrid edge (reverse tunnel)](./scenarios/07-hybrid-edge-tunnel/) | Expose a cluster with no inbound ports via the edge + reverse tunnel. |
| 08 | [HA / multi-edge](./scenarios/08-ha-multi-edge/) | Two edges front one sovereign cluster — a single edge failure doesn't take the app down. |
| 09 | [Many teams, one Gateway](./scenarios/09-multi-team-listenersets/) | Teams add their own hostnames with ListenerSets; conflicts and namespace policy enforced. |
| 10 | [TLS to the backend](./scenarios/10-backend-tls/) | BackendTLSPolicy: re-encrypt and verify the backend; fails closed. |
| 11 | [CORS](./scenarios/11-cors/) | The HTTPRoute CORS filter for a browser-facing API. |
| 12 | [A Gateway per team](./scenarios/12-gateway-per-team/) | Each Gateway its own proxy and address; same hostname, isolated. |
| 13 | [Upgrade from 0.1.4](./scenarios/13-upgrade-from-0.1.4/) | The upgrade path, proving the address and mode survive. |
| 14 | [Resilience](./scenarios/14-resilience/) | Traffic keeps flowing while proxies and controllers are replaced (no failed requests). |

To run the scenarios against a build you have locally (images in your docker daemon, chart on
disk), see [`scenarios/README.md`](./scenarios/README.md#running-against-a-local-build).

## Pilot testing

Testing zenoingress with us? The [pilot playbook](./PILOT.md) lists what to try, how to check it
and what we'd like to hear back.

## Gateway API conformance

zenoingress 0.1.5 passes the Gateway API **v1.6.1** conformance suite, profile **GATEWAY-HTTP**:
**Core 37/37, Extended 53/53**. Supported features (the GatewayClass also reports them in
`status.supportedFeatures`): Gateway, HTTPRoute, ReferenceGrant, GatewayPort8080,
GatewayAddressEmpty, GatewayHTTPListenerIsolation, GatewayHTTPSListenerDetectMisdirectedRequests,
GatewayInfrastructurePropagation, GatewayFrontendClientCertificateValidation (+InsecureFallback),
ListenerSet, BackendTLSPolicy (+SANValidation), HTTPRouteCORS, and the HTTPRoute features for
host/path rewrites, redirects (ports, schemes, 303/307/308), header modifiers (request, response,
backend), mirrors (multiple, percentage), query/method/destination-port matching, named rules,
parentRef ports, request/backend timeouts, WebSocket and h2c backends.

## Documentation

Full documentation will be published separately. For now, start with the
[Quick start](#quick-start) and the [scenarios](./scenarios/).
<!-- TODO: link the documentation site once it's live. -->

## Support

Questions, licensing, and commercial support: **support@citiumsoftware.com**.
For security reports, follow [SECURITY.md](./SECURITY.md).

## License

zenoingress is **proprietary software** — © 2026 Citium Software. All rights reserved.
It is **not** open source or source-available. The public container images are provided for
distribution only; pulling an image does not by itself grant a license to use the software.

**Free-use allowance (current versions):** you may run the currently published versions free of
charge in **one (1) production Kubernetes cluster** plus **unlimited development and test clusters**.
Anything beyond that requires a commercial license.

See [LICENSE](./LICENSE) for the authoritative terms, and contact
**support@citiumsoftware.com** for commercial licensing.
