# Scenario 12 — A Gateway per team

Each Gateway gets **its own proxy and its own address**: two teams, two
Gateways, the same hostname, fully isolated. This is the default for new
installs.

```
team-red  Gateway "web" ─▶ web-zenoingress (Deployment + Service, team-red)  ─▶ red app
team-blue Gateway "web" ─▶ web-zenoingress (Deployment + Service, team-blue) ─▶ blue app
```

## Run

```bash
./up.sh        # kind + CRDs + ZenoIngress + two teams, each with a Gateway
./verify.sh    # checks below; it deletes and restores team-blue's Gateway
./down.sh      # delete the kind cluster
```

## What it shows

- Two Gateways, two different addresses (`kubectl get gateway -A`).
- `shop.example.test` reaches the red app through team-red's Gateway and the
  blue app through team-blue's: separate data planes, no hostname contest.
- `spec.infrastructure.labels` (here `cost-center`) are copied onto the
  generated Deployment, Service and pods.
- The proxy objects are owned by the Gateway: deleting team-blue's Gateway
  removes its proxy, and team-red keeps serving.

## How it works

For each Gateway the controller creates, in the Gateway's namespace (GEP-1762):

| Object | Name | Purpose |
|---|---|---|
| Deployment, Service | `<gateway>-<gatewayclass>` | the proxy and its address |
| ServiceAccount, Role, RoleBinding | `<gateway>-<gatewayclass>` | lets the proxy read its own config, nothing else |
| Secret | `<gateway>-<gatewayclass>-config` | that Gateway's configuration only (its listeners, routes, backends, certificates) |

`Programmed=True` means that proxy runs and its Service has an address. The
proxies are sized from the chart's `proxy` values (`replicaCount`,
`resources`, `service.type`, `initContainers`, ...).

**Shared mode.** With `provisioning: shared` (Helm), or the annotation
`zenoingress.io/provisioning: shared` on a GatewayClass, all Gateways of the
class are served by one proxy on one address, as releases before 0.2.0 did.
Upgrades keep the mode they had; see [scenario 13](../13-upgrade-from-0.1.5/).
On a shared proxy, a hostname claimed by two Gateways goes to the older
Gateway, and the newer listener reports `Conflicted=True`
(`HostnameConflict`).
