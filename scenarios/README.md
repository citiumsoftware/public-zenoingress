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
| 09 | [Many teams, one Gateway](./09-multi-team-listenersets/) | Teams add their own hostnames with **ListenerSets**; conflicts and namespace policy enforced. |
| 10 | [TLS to the backend](./10-backend-tls/) | **BackendTLSPolicy**: re-encrypt and verify the backend; fails closed. |
| 11 | [CORS](./11-cors/) | The HTTPRoute **CORS** filter for a browser-facing API. |
| 12 | [A Gateway per team](./12-gateway-per-team/) | Each Gateway its own proxy and address; the same hostname, isolated. |
| 13 | [Upgrade from 0.1.5](./13-upgrade-from-0.1.5/) | The upgrade path, proving the address and the mode survive. |
| 14 | [Resilience](./14-resilience/) | Traffic keeps flowing while proxies and controllers are replaced (no failed requests). |

<!-- Add new scenarios as numbered directories and list them here. -->

## Prerequisites for the runnable scenarios (02+)

- `docker`, [`kind`](https://kind.sigs.k8s.io/) (0.24+, Kubernetes 1.31+ nodes), `kubectl`,
  [`helm`](https://helm.sh/) 3.8+ (OCI support; 3.14+ for scenario 13), `curl`
- `openssl` for scenarios 06, 07, 08 and 10 (08 also uses host ports 8443/9443, 07 port 8443)
- Internet access from the cluster (public images, Gateway API CRDs, and — for the WAF
  scenarios — the Coraza module)
- About 4 GB of free memory per running scenario. Each scenario has its own kind cluster; run
  `./down.sh` before the next one.

Each `verify.sh` prints PASS or FAIL per check and exits non-zero on any failure, so the
scenarios double as a test suite: `./run-all.sh` runs 02-14 one after another (about 30
minutes) and writes a summary to `results/`.

## Versions and overrides

All scripts share [`lib/common.sh`](./lib/common.sh). Defaults install the published release;
environment variables change that:

| Variable | Default | Meaning |
|---|---|---|
| `ZENOINGRESS_VERSION` | `0.2.0` | chart and image version |
| `ZENOINGRESS_CHART` | `oci://ghcr.io/citiumsoftware/zenoingress-chart` | the chart: the OCI chart, or a chart directory |
| `ZENOINGRESS_REGISTRY` | `ghcr.io/citiumsoftware` | where the images come from (used for the edge container and `kind load`) |
| `ZENOINGRESS_LOAD_IMAGES` | unset | `1`: copy the images from your local docker daemon into kind instead of pulling them |
| `GATEWAY_API_VERSION` | `v1.6.1` | Gateway API CRD release |

### Running against a local build

With images built or mirrored locally (tagged `<registry>/zenoingress-{controller,proxy,edge}:<version>`)
and the chart on disk:

```bash
export ZENOINGRESS_CHART=/path/to/zenoingress/chart
export ZENOINGRESS_LOAD_IMAGES=1
cd 02-basic-ingress && ./up.sh && ./verify.sh
```

> The runnable scenarios install from `oci://ghcr.io/citiumsoftware/zenoingress-chart`
> and pull the `ghcr.io/citiumsoftware/*` images; those packages must be public
> for the pulls to succeed.
