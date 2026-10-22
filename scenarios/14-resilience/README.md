# Scenario 14 — Resilience under change

Keep requests flowing through a Gateway while its proxy and the controllers are
replaced, and count the failures. Expected: **none**.

## Run

```bash
./up.sh        # kind + CRDs + ZenoIngress (2 controllers, 2 proxy replicas) + app
./verify.sh    # 2 minutes of traffic while things break (DURATION=300 ./verify.sh for longer)
./down.sh      # delete the kind cluster
```

## What it does

A pod in the cluster sends a request every 50 ms to the Gateway's proxy
Service (as in-cluster clients and load balancers do), while `verify.sh`:

1. **deletes one of the two proxy pods** — the Service keeps sending to the
   other while Kubernetes replaces it;
2. **restarts the controller** (rolling) — the proxies keep serving their last
   configuration; the controller only programs them;
3. **deletes the leading controller** — the other replica takes over the Lease
   `zenoingress-controller-leader`. A controller that shuts down normally
   releases the Lease, so the other takes over at once; one that dies without
   shutting down is replaced after the 15 s lease expires.

Then it prints how many requests got which status code. In our runs: about
2,150 requests, all `200`.

## Notes

- Run it a few times, or longer (`DURATION=300`), on your own cluster too:
  failures there usually point at the load balancer's health checks or
  connection draining, which kind does not have.
- With one proxy replica (`proxy.replicaCount=1`) a deleted pod does cost
  requests until the new one is ready; keep at least two in production.
