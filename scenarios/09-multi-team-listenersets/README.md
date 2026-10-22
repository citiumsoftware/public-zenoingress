# Scenario 09 — Many teams, one Gateway (ListenerSet)

One shared Gateway, run by a platform team, on **one address**. Application
teams add their own hostnames from their own namespaces with **ListenerSets**
(Gateway API v1.5+), and route to their own apps, without ever editing the
Gateway.

```
                           ┌ www.shop.test ─ platform app      (Gateway listener)
client ─▶ shop proxy ──────┼ a.shop.test   ─ team-a app        (ListenerSet team-a)
         (one address)     └ b.shop.test   ─ team-b app        (ListenerSet team-b)
```

## Run

```bash
./up.sh        # kind + Gateway API CRDs + ZenoIngress + platform Gateway + three teams
./verify.sh    # status and traffic checks below
./down.sh      # delete the kind cluster
```

## What it shows

| Check | Result |
|---|---|
| `www.shop.test`, `a.shop.test`, `b.shop.test` | each team's own app, through the one Gateway proxy |
| team-b's second listener claims `a.shop.test` | `Conflicted=True`, reason `HostnameConflict`; team-a keeps the hostname |
| team-c (namespace without the label) | ListenerSet `Accepted=False`, reason `NotAllowed`; `c.shop.test` is not served (404) |
| Gateway `status.attachedListenerSets` | `2` |
| proxy Services | one, for the whole Gateway |

## How it works

- **The platform team decides who may attach.** The Gateway's
  `spec.allowedListeners.namespaces` selects namespaces labelled
  `shop.test/gateway-access: "true"` (`Same`, `All` and `None`, the default,
  also work). A ListenerSet from any other namespace is not attached.
- **A ListenerSet** lives in the team's namespace, names the Gateway in
  `spec.parentRef`, and lists listeners with the same fields as a Gateway's
  (hostname, port, protocol, TLS certificates, allowedRoutes).
- **Routes attach to the ListenerSet**, not the Gateway:
  `parentRefs: [{kind: ListenerSet, name: team-a}]`. A route attached to the
  Gateway only serves the Gateway's own listeners.
- **Conflicts are decided by precedence:** the Gateway's own listeners first,
  then ListenerSets oldest first. A later listener that claims a hostname
  already served on the same port (or uses a different protocol on it) is
  `Conflicted` and is not served, so one team cannot take over another team's
  hostname. A ListenerSet whose listeners are all conflicted or invalid is
  `Accepted=False` (`ListenersNotValid`).
- **TLS:** a ListenerSet's HTTPS listener references certificates in its own
  namespace. A certificate in another namespace needs a ReferenceGrant from
  kind `ListenerSet`. Client-certificate validation set on the Gateway
  (`spec.tls.frontend`) also applies to the ListenerSets' listeners on that
  port.

## Notes

- With the proxy per Gateway (the default), the Gateway's proxy Service also
  exposes the ListenerSets' ports.
- `kubectl get listenersets -A` shows every team's ListenerSet;
  `kubectl -n team-b get listenerset team-b -o yaml` shows each listener's
  conditions and attached routes.
