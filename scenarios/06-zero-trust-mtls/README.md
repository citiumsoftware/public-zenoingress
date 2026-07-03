# Scenario 06 — Zero-trust (mTLS + Cedar)

![Zero-trust: mTLS + Cedar; payments SVID gets 200, analytics 403, no client cert is refused](diagram.svg)

A network position buys an attacker nothing. Every request must present a valid
client **SPIFFE SVID** (mTLS), and an in-process **Cedar** policy authorizes on
that cryptographic identity — deny-by-default, no sidecar, no external PDP.

```
mTLS client SVID ─▶ ZenoIngress proxy ─▶ [Cedar AuthzPolicy] ─▶ api
      │                    │                      │
 GEP-91 frontend      TLS terminate    x-spiffe-id (from the cert) = principal
 (no cert → 🚫)                        permit: payments SVID + POST /api/payments
```

`up.sh` is self-contained: it creates a local `kind` cluster, mints a throwaway
demo PKI, and installs zenoingress from the public chart.

## Prerequisites

- `docker`, [`kind`](https://kind.sigs.k8s.io/), `kubectl`, [`helm`](https://helm.sh/) 3.8+, and `openssl`
- Internet access from the cluster (public images + Gateway API CRDs)

## Run

```bash
./up.sh        # kind + experimental Gateway API CRDs + PKI + ZenoIngress + mTLS Gateway + Cedar
./verify.sh    # payments→200, analytics→403, wrong-method→403, no-cert→handshake refused
./down.sh      # delete the kind cluster
```

## What it shows

| Request | Result | Why |
|---|---|---|
| `payments` SVID, `POST /api/payments` | **200** | in `Group::"payments"`, method+path permitted |
| `analytics` SVID, `POST /api/payments` | **403** | valid cert, but not in the payments group |
| `payments` SVID, `GET /api/payments` | **403** | method not permitted (deny-by-default) |
| no client cert | **handshake refused** | GEP-91 `frontendValidation` requires a valid cert |

## How it works

- **`gen-certs.sh`** mints a CA, a server cert, and two client SVIDs with
  `spiffe://demo.zeno/{payments,analytics}` URI SANs. `up.sh` loads the server
  cert and client CA as Secrets. The generated `certs/` are throwaway and are
  git-ignored — never commit them.
- The **Gateway** listener terminates TLS and sets GEP-91
  `tls.frontendValidation.caCertificateRefs` → a client cert chaining to that CA
  is mandatory (`mode` defaults to `AllowValidOnly`). This needs the Gateway API
  **experimental** channel, which `up.sh` installs.
- The proxy extracts the verified client cert's SPIFFE URI SAN and sets it as
  `x-spiffe-id` (stripping any inbound value). The **`AuthzPolicy`** reads that
  header as the Cedar principal and evaluates group membership + method + path.

## Notes / caveats

- `frontendValidation` is Gateway-API **experimental** at v1.2.0 (Standard from
  v1.5) — hence `experimental-install.yaml`.
- SVIDs are minted with `openssl` (no SPIRE) so the scenario stays self-contained.
- This scenario exercises mTLS + Cedar + experimental CRDs together — run it once
  to confirm the flow on your cluster/build.
