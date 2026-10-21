# zenoingress pilot playbook

Thank you for testing zenoingress with us. This playbook is a menu: pick the
parts that matter to you, run them, and tell us what happened, especially what
surprised you or got in your way.

> **Status (21 October 2026):** written for zenoingress **0.2.0** on Gateway API
> **v1.6.1**. Every script in Track A was run end to end on kind against the
> 0.2.0 build and passes. Tracks B and C are checklists for your own clusters;
> their commands were checked against the same build.

## Contents

- [What you need](#what-you-need)
- [Track A — the scenarios on your laptop (about an hour)](#track-a--the-scenarios-on-your-laptop)
- [Track B — your own cluster (half a day)](#track-b--your-own-cluster)
- [Track C — a cluster with no inbound access (optional)](#track-c--a-cluster-with-no-inbound-access-optional)
- [Known limitations](#known-limitations)
- [What to send us](#what-to-send-us)

## What you need

| | Track A (laptop) | Track B (your cluster) |
|---|---|---|
| Kubernetes | created for you with `kind` (0.24+) | **1.31+** (the Gateway API v1.6 CRDs need it), a test or staging cluster |
| Tools | `docker`, `kind`, `kubectl`, `helm` 3.14+, `curl`, `openssl` | `kubectl`, `helm` 3.14+, `curl`, `openssl` (3.5+ to see post-quantum TLS) |
| Access | internet (images, CRDs) | cluster-admin (CRDs, a ClusterRole), a load balancer or NodePort access |
| Your time | about an hour, mostly waiting | half a day |

Nothing reports back to us automatically. You decide what to send.

## Track A — the scenarios on your laptop

Each scenario creates its own kind cluster, installs zenoingress from the
public chart, deploys an app, checks the result (PASS/FAIL per check) and
deletes the cluster again.

```bash
cd scenarios
./run-all.sh            # 02-14, about 30 minutes; or e.g. ./run-all.sh 09 10 12
```

`run-all.sh` writes `scenarios/results/<time>/summary.txt` and a log per
scenario (plus cluster state for any that failed). Please send us the
`results/` folder.

What each scenario proves:

| # | Scenario | What you should see |
|---|---|---|
| 02 | [Basic ingress](./scenarios/02-basic-ingress/) | The Gateway gets its own proxy; a routed host answers, an unrouted one gets 404. |
| 03 | [Canary](./scenarios/03-canary-traffic-split/) | About 90/10 between two versions of an app. |
| 04 | [WAF](./scenarios/04-waf/) | SQL injection, XSS and path traversal blocked with 403; clean traffic passes. |
| 05 | [WAF with OWASP CRS](./scenarios/05-waf-owasp-crs/) | The full Core Rule Set blocks five attack classes. |
| 06 | [Zero trust](./scenarios/06-zero-trust-mtls/) | No client certificate: handshake refused. Wrong identity or method: 403. |
| 07 | [Hybrid edge](./scenarios/07-hybrid-edge-tunnel/) | An app in a cluster with no inbound ports, reached through an edge. |
| 08 | [Two edges](./scenarios/08-ha-multi-edge/) | One edge stopped, the other keeps serving. |
| 09 | [Many teams, one Gateway](./scenarios/09-multi-team-listenersets/) | Teams add hostnames themselves; a stolen hostname is refused; a team without permission is not attached. |
| 10 | [TLS to the backend](./scenarios/10-backend-tls/) | Verified TLS to an HTTPS backend; a wrong name or a missing CA fails closed. |
| 11 | [CORS](./scenarios/11-cors/) | Only allowed origins get CORS access; preflights answered by the gateway. |
| 12 | [A Gateway per team](./scenarios/12-gateway-per-team/) | Two Gateways, two addresses, the same hostname, isolated. |
| 13 | [Upgrade from 0.1.5](./scenarios/13-upgrade-from-0.1.5/) | The address and the shared mode survive the upgrade. |
| 14 | [Resilience](./scenarios/14-resilience/) | No failed request while a proxy pod, the controller and the leader are replaced. |

**Questions for Track A**

1. Did every scenario pass? If not, which, and what did the log say?
2. Which scenario was closest to how you would use zenoingress? What was missing from it?
3. Was anything in the scenario READMEs unclear or wrong?

## Track B — your own cluster

Use a test or staging cluster. Each step says what to run, what you should
see, and what to tell us.

### B1. Install

```bash
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.1/standard-install.yaml
helm install zenoingress oci://ghcr.io/citiumsoftware/zenoingress-chart --version 0.2.0 \
  -n zenoingress-system --create-namespace
kubectl get gatewayclass zenoingress
kubectl get gatewayclass zenoingress -o jsonpath='{.status.supportedFeatures[*].name}'
```

**Expect:** the controller pod `Running`, the GatewayClass `ACCEPTED True`,
and the list of supported features.

- No load balancer? Add `--set proxy.service.type=NodePort` (or `ClusterIP`
  and port-forward).
- Already have Gateway API CRDs from another controller? Tell us which
  version; zenoingress needs v1.6.1 (v1.4+ works without ListenerSet and
  BackendTLSPolicy).
- Already running 0.1.5? Upgrade instead (B10).

### B2. Your first Gateway

Deploy one of your own services (or `kubectl create deployment hello
--image=nginxdemos/hello --port=80 && kubectl expose deployment hello
--port=80`) and follow [scenario 01](./scenarios/01-basic-http-routing/).

```bash
kubectl wait --for=condition=Programmed gateway/web --timeout=180s
kubectl get gateway web                         # ADDRESS
kubectl get deploy,svc -l gateway.networking.k8s.io/gateway-name=web
curl -H "Host: hello.example.com" "http://<ADDRESS>/"
```

**Expect:** a Deployment and a Service `web-zenoingress` next to the Gateway,
the Service's address on the Gateway, and your app answering. Time from
`kubectl apply` to the first successful request: tell us.

### B3. HTTPS with your certificate

Create a `kubernetes.io/tls` Secret (your own certificate, or from
cert-manager) and add an HTTPS listener:

```yaml
    - name: https
      port: 443
      protocol: HTTPS
      hostname: hello.example.com
      tls:
        certificateRefs:
          - name: hello-tls
```

```bash
curl -v --resolve hello.example.com:443:<ADDRESS> https://hello.example.com/
# Post-quantum key exchange (OpenSSL 3.5+):
echo | openssl s_client -connect <ADDRESS>:443 -servername hello.example.com -groups X25519MLKEM768 2>&1 | grep -iE "negotiated|group|Protocol"
```

**Expect:** TLS 1.3 with `X25519MLKEM768` as the negotiated group. A missing or
invalid certificate shows on the listener status (`ResolvedRefs=False`,
`InvalidCertificateRef`), not as a silent failure:
`kubectl get gateway web -o yaml`.

### B4. Choose your tenancy model

zenoingress gives each Gateway its own proxy and address by default. Try the
model you would use:

- **A Gateway per team** ([scenario 12](./scenarios/12-gateway-per-team/)):
  isolated data planes, one load balancer each.
- **One Gateway, many teams** ([scenario 09](./scenarios/09-multi-team-listenersets/)):
  the platform team owns the Gateway and allows ListenerSets from selected
  namespaces; teams add hostnames and certificates themselves, on one
  address.
- **Shared proxy for a whole class** (`helm upgrade ... --set provisioning=shared`
  for new installs, or the GatewayClass annotation
  `zenoingress.io/provisioning: shared`): all Gateways on one proxy and
  address.

**Tell us:** which model fits your organisation, how many Gateways and
hostnames you expect, and whether one load balancer per Gateway is a cost
problem for you.

### B5. Security features

Pick what you would use in production:

| Feature | How | Scenario |
|---|---|---|
| WAF (Coraza, OWASP CRS) | `WafPolicy` + ExtensionRef filter; WASM module via `proxy.initContainers` | [04](./scenarios/04-waf/), [05](./scenarios/05-waf-owasp-crs/) |
| Client certificates (mTLS) | Gateway `spec.tls.frontend` with a CA ConfigMap | [06](./scenarios/06-zero-trust-mtls/) |
| Authorization (Cedar) | `AuthzPolicy` + ExtensionRef filter | [06](./scenarios/06-zero-trust-mtls/) |
| External auth (OAuth2/OIDC) | `ExtAuthFilter` + ExtensionRef filter | — |
| TLS to backends | `BackendTLSPolicy` (Gateway API) | [10](./scenarios/10-backend-tls/) |
| CORS | HTTPRoute `CORS` filter | [11](./scenarios/11-cors/) |

**Expect:** a filter that cannot be applied (a missing policy, a WAF module
that does not load) fails the rule **closed** with 500, it never serves the
route unprotected. Please try to break that and tell us if you succeed.

### B6. Resilience

[Scenario 14](./scenarios/14-resilience/) does this on kind (no failed
request in our runs). On your cluster, run steady traffic against a route (e.g. `while true; do curl -s -o /dev/null
-w '%{http_code}\n' ...; sleep 0.2; done | uniq -c`) while you:

1. **Delete a proxy pod:** `kubectl delete pod -l gateway.networking.k8s.io/gateway-name=web`.
   With `proxy.replicaCount` ≥ 2 (the default), expect no failed requests.
2. **Restart the controller:** `kubectl -n zenoingress-system rollout restart deploy`.
   Traffic must not notice; the controller only programs the proxies.
3. **Scale the controller:** `helm upgrade ... --reset-then-reuse-values --set controller.replicaCount=2`.
   Only one replica reconciles at a time (leader election, Lease
   `zenoingress-controller-leader`); delete the leader pod and see the other
   take over within a few seconds (a leader that is killed without shutting
   down is replaced after the 15 s lease expires):
   `kubectl -n zenoingress-system get lease zenoingress-controller-leader`.
4. **Drain the node** a proxy runs on.

**Tell us:** any failed requests (count, status code, how long).

### B7. Observability

```bash
# Proxy metrics (Prometheus format), per Gateway proxy:
kubectl port-forward deploy/web-zenoingress 9091:9091 &  curl -s localhost:9091/metrics | grep ^zenoingress_ | head
# Controller metrics:
kubectl -n zenoingress-system port-forward deploy/zenoingress-zenoingress-chart-controller 9090:9090 &
curl -s localhost:9090/metrics | grep ^zenoingress_
```

Useful series: `zenoingress_requests_total`, `zenoingress_request_duration_seconds`,
`zenoingress_backend_health`, `zenoingress_connections_active`,
`zenoingress_config_version` (proxy: which config it serves; controller: what
it published), `zenoingress_reconcile_errors_total`.

Optional: the read-only **Insights API** (`--set controller.insights.enabled=true
--set controller.insights.token=<random>`; ClusterIP only, reach it with
`kubectl port-forward`) shows routing topology, backend health and
certificate expiry.

**Tell us:** which metrics or logs you missed while testing.

### B8. Load (optional)

If you compare zenoingress with your current ingress under load, run the load
generator inside the cluster so you measure the ingress, not your network:

```bash
kubectl run fortio --image=fortio/fortio --restart=Never --rm -i -- \
  load -c 100 -qps 0 -t 60s -H "Host: hello.example.com" \
  http://web-zenoingress.default.svc/
```

`-qps 0` finds the maximum; a fixed rate (`-qps 20000`) shows tail latency at
a load you expect. Use a fast backend: a slow one measures the backend. For a
fair comparison:

- **No CPU limit on the proxy** (the chart default) or the same limit on both
  ingresses: a CPU-limited proxy is throttled in bursts.
- **`proxy.limits.upstreamKeepalive`** (default 512) above the number of
  requests in flight to one backend pod.
- **Log level:** leave it at the default `info`; it costs no more than
  `warn`. `debug` logs every request and slows the proxy down.

Our own numbers against nginx, HAProxy, Envoy, ingress-nginx and Envoy
Gateway are available on request.

**Tell us:** requests per second, p99 latency, errors, and the proxy's
memory (`kubectl top pod -l gateway.networking.k8s.io/gateway-name=web`)
next to your current ingress at the same load.

### B9. Gateway API conformance on your cluster (optional)

zenoingress passes the v1.6.1 GATEWAY-HTTP profile (Core 37/37, Extended
53/53) on kind. If you want to see that on your cluster, we can send the exact
command; it needs about 30 minutes and a load balancer.

### B10. Upgrade and rollback

From 0.1.5 ([scenario 13](./scenarios/13-upgrade-from-0.1.5/) shows the whole
path):

```bash
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.1/standard-install.yaml
helm show crds oci://ghcr.io/citiumsoftware/zenoingress-chart --version 0.2.0 | kubectl apply --server-side --force-conflicts -f -
helm upgrade zenoingress oci://ghcr.io/citiumsoftware/zenoingress-chart --version 0.2.0 \
  -n zenoingress-system --reset-then-reuse-values
```

**Before you upgrade:** move client-certificate validation from listener
`tls.frontendValidation` to the Gateway's `spec.tls.frontend` (the new CRDs
drop the old field).

**Expect:** the shared proxy keeps its address; Gateways stay `Programmed`.

**Rollback** (`helm rollback zenoingress -n zenoingress-system`) returns to
0.1.5 with the same address, and HTTP routes keep working (we tested this).
The CRDs stay at v1.6.1, which 0.1.5 only partly understands: its TCP, TLS and
UDP routes stop working (it looks for them at `v1alpha2`), its controller logs
`404 page not found` warnings, and client-certificate validation is not
applied. Tell us how the upgrade and, if you try it, the rollback went.

### B11. Clean up

```bash
kubectl delete gateway --all -A          # removes the per-Gateway proxies
helm uninstall zenoingress -n zenoingress-system
kubectl delete namespace zenoingress-system
```

CRDs are left in place (Helm never deletes them). Remove them with
`helm show crds ... | kubectl delete -f -` if nothing else uses them.

**Questions for Track B**

1. What took longer than you expected, and why?
2. What would stop you from running this in production today?
3. Which of your current ingress features did you miss?
4. How did zenoingress compare with what you run now (latency, memory, ease)?

## Track C — a cluster with no inbound access (optional)

For sovereign or air-gapped clusters: the proxy dials **out** to an edge on
public infrastructure, and the cluster opens no inbound port. Start with
[scenario 07](./scenarios/07-hybrid-edge-tunnel/) and
[scenario 08](./scenarios/08-ha-multi-edge/), then talk to us about running an
edge on your own infrastructure (a hardened VM image is in preparation). The edge
authenticates tunnels with a token or client certificates; it refuses
unauthenticated tunnels.

## Known limitations

We would rather you hear these from us:

- **Client IP over the tunnel:** in tunnel mode the proxy sees the edge as the
  source address. Put client-IP rules at the edge.
- **Retries:** HTTPRoute retry settings are not implemented yet.
- **TCP, TLS and UDP routes:** when a backend's pods change, these routes
  pick up the new pod addresses at the next periodic resync (up to 5
  minutes); HTTP and gRPC routes follow within seconds.
- **Static addresses:** `Gateway.spec.addresses` is reported on the Gateway but
  not applied to its proxy Service; request a fixed IP through your load
  balancer's annotations (`proxy.service.annotations`).
- **Conformance scope:** GRPCRoute, TLSRoute, TCPRoute and UDPRoute work and are
  covered by our tests, but their conformance profiles have not been run yet.
- **Upgrading from 0.1.5:** for about 30 seconds the old and new controllers
  both run (0.1.5 accepts `--leader-election` but does not act on it); the logs
  show a burst of reconciles. Traffic is not affected.
- **GitOps (`helm template`, Argo CD):** set `provisioning` explicitly; without
  cluster access the chart cannot see which mode an existing install uses.

## What to send us

Email **support@citiumsoftware.com** with:

- the `scenarios/results/` folder from Track A;
- for Track B, your answers, your Kubernetes distribution and version, and
  anything that failed: `kubectl get gateway,httproute -A -o yaml` and
  `kubectl -n zenoingress-system logs deploy/zenoingress-zenoingress-chart-controller`;
- anything you think we should know.

Remove hostnames, IPs or certificates you do not want to share. Thank you!
