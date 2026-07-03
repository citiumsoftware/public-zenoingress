# Scenarios

Task-focused walkthroughs for running zenoingress.

- **Scenario 01** is a manual, copy-paste walkthrough — it assumes zenoingress is
  already installed (see the [root README quick-start](../README.md#quick-start)).
- **Scenarios 02+** are one-command runnable demos — each `./up.sh` spins up a
  local `kind` cluster and installs zenoingress from the public chart, so they
  need nothing pre-installed. `./verify.sh` proves it; `./down.sh` cleans up.

| #  | Scenario | What it shows |
|----|----------|---------------|
| 01 | [Basic HTTP routing](./01-basic-http-routing/) | Expose a service with a Gateway + HTTPRoute (manual walkthrough). |
| 02 | [Basic ingress](./02-basic-ingress/) | The same, in one command: kind + chart + a Caddy app. |
| 03 | [Canary traffic splitting](./03-canary-traffic-split/) | Weighted `HTTPRoute` — shift traffic 90/10 → 0/100. |
| 04 | [WAF](./04-waf/) | In-proxy Coraza WAF: block SQLi/XSS/traversal on a route. |
| 05 | [WAF with OWASP CRS](./05-waf-owasp-crs/) | The full OWASP Core Rule Set, in-proxy. |
| 06 | [Zero-trust (mTLS + Cedar)](./06-zero-trust-mtls/) | Client-SVID mTLS + Cedar authz, deny-by-default. |
| 07 | [Hybrid edge (reverse tunnel)](./07-hybrid-edge-tunnel/) | Expose a cluster with **no inbound ports** via the edge + reverse tunnel. |
| 08 | [HA / multi-edge](./08-ha-multi-edge/) | Two edges front one sovereign cluster — a single edge failure doesn't take the app down. |

<!-- Add new scenarios as numbered directories and list them here. -->

## Prerequisites for the runnable scenarios (02+)

- `docker`, [`kind`](https://kind.sigs.k8s.io/), `kubectl`, [`helm`](https://helm.sh/) 3.8+ (OCI support) — scenarios 06, 07 and 08 also need `openssl` (08 also uses host ports 8443/9443)
- Internet access from the cluster (public images, Gateway API CRDs, and — for the WAF scenarios — the Coraza module)

> The runnable scenarios install from `oci://ghcr.io/citiumsoftware/zenoingress-chart`
> and pull the `ghcr.io/citiumsoftware/*` images; those packages must be public
> for the pulls to succeed.
