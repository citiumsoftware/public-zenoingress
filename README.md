# zenoingress

> A sovereign, memory-safe Kubernetes Gateway API ingress controller, written in Rust.

[![License](https://img.shields.io/badge/license-Proprietary-red.svg)](./LICENSE)
[![Gateway API](https://img.shields.io/badge/Gateway%20API-v1.2.0-green.svg)](https://gateway-api.sigs.k8s.io/)
[![Container images](https://img.shields.io/badge/ghcr.io-citiumsoftware-1f6feb.svg)](https://github.com/orgs/citiumsoftware/packages?repo_name=public-zenoingress)

zenoingress is a modern ingress controller that implements the
[Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/). Built in Rust for performance and
safety, it routes HTTP traffic to your Kubernetes services with security built in — no sidecars.

> [!NOTE]
> This repository is **documentation only** — getting-started guides, license, and example
> scenarios. The zenoingress source is maintained separately; here you'll find everything you need
> to *run* the published container images and Helm chart.

## Why zenoingress

- **Memory-safe by construction** — 100% safe Rust (`#![forbid(unsafe_code)]`); the memory-corruption
  bug class behind critical CVEs in C/C++ proxies simply cannot occur.
- **Post-quantum TLS** — TLS 1.3 defaults to the hybrid X25519MLKEM768 (ML-KEM-768, NIST FIPS 203)
  key exchange via rustls + aws-lc-rs. No OpenSSL.
- **Integrated security, no sidecars** — built-in WAF (Coraza / OWASP CRS), in-process Cedar
  authorization, and external OAuth2/OIDC auth, all in one binary.
- **Sovereign & restricted environments** — a hybrid tunnel + edge mode exposes private or
  air-gapped clusters with no inbound access (EU data-sovereignty, FedRAMP-style data planes).
- **Gateway API native** — GatewayClass, Gateway, and HTTPRoute, with TLS termination and
  certificate management.
- **Observable & production-ready** — Prometheus metrics, structured logging, OpenTelemetry tracing,
  health checks, circuit breaking, graceful shutdown, and hot-reload configuration.

## Components

zenoingress is distributed as container images under the org's public GitHub Container Registry:

| Component  | Image                                            | Role |
|------------|--------------------------------------------------|------|
| Controller | `ghcr.io/citiumsoftware/zenoingress-controller`  | Control plane — watches Gateway API resources (GatewayClass, Gateway, HTTPRoute) and programs the data plane. |
| Proxy      | `ghcr.io/citiumsoftware/zenoingress-proxy`       | Data plane — terminates TLS and routes client traffic to backend services. |
| Edge       | `ghcr.io/citiumsoftware/zenoingress-edge`        | Optional edge server for hybrid/tunnel mode — runs on public infrastructure so the in-cluster proxy can expose a private or air-gapped cluster with no inbound access. |
| Helm chart | `oci://ghcr.io/citiumsoftware/zenoingress-chart` | Installs the controller, proxy, and GatewayClass on Kubernetes. |

## Quick start

> [!TIP]
> The currently published versions are free to run in **one production Kubernetes cluster** plus
> **unlimited development and test clusters** — see [License](#license). No sign-up needed.

### Prerequisites

- A Kubernetes cluster (**v1.25+**)
- [Gateway API](https://gateway-api.sigs.k8s.io/) **v1.2.0** CRDs installed (step 1 below)
- [Helm](https://helm.sh/) 3.8+ (for OCI registry support) and `kubectl`

### 1. Install the Gateway API CRDs

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml
```

### 2. Install zenoingress

The chart is an OCI artifact — no `helm repo add` needed:

```bash
helm install zenoingress \
  oci://ghcr.io/citiumsoftware/zenoingress-chart \
  --version 0.1.4 \
  --namespace zenoingress-system \
  --create-namespace
```
<!-- TODO(maintainer): requires the 0.1.4 chart (ghcr image defaults) pushed to ghcr before docs go public. -->

### 3. Verify

```bash
kubectl get pods -n zenoingress-system
kubectl get gatewayclass zenoingress
```

Then route some traffic — see [Scenarios](#scenarios).

## Container images

All images live under the `citiumsoftware` org and are public — anyone can pull them without
authentication. Pulling an image does **not** grant a license to use zenoingress; see
[License](#license).

| Image                                            | Current tag |
|--------------------------------------------------|-------------|
| `ghcr.io/citiumsoftware/zenoingress-controller`  | `0.1.4`     |
| `ghcr.io/citiumsoftware/zenoingress-proxy`       | `0.1.4`     |
| `ghcr.io/citiumsoftware/zenoingress-edge`        | `0.1.4`     |
| `oci://ghcr.io/citiumsoftware/zenoingress-chart` | `0.1.4`     |

```bash
docker pull ghcr.io/citiumsoftware/zenoingress-controller:0.1.4
```

## Scenarios

Worked examples live in [`scenarios/`](./scenarios/). Scenario 01 is a manual walkthrough (it
assumes zenoingress is already installed via the [Quick start](#quick-start)); scenarios 02+ are
one-command demos — each `./up.sh` spins up a local `kind` cluster and installs from the public
chart, `./verify.sh` proves it, and `./down.sh` cleans up.

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
