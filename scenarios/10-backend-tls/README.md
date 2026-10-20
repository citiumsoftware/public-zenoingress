# Scenario 10 — TLS to the backend (BackendTLSPolicy)

The proxy re-encrypts to an HTTPS backend and **verifies** it, configured with
the Gateway API **BackendTLSPolicy** (Standard since v1.4).

```
curl ──HTTP──▶ ZenoIngress proxy ──TLS, certificate verified──▶ Caddy :8443
```

## Run

```bash
./up.sh        # kind + CRDs + demo PKI + ZenoIngress + TLS backend + policies
./verify.sh    # status and traffic checks below
./down.sh      # delete the kind cluster
```

## What it shows

Four Services point at the same TLS backend, each with its own policy:

| Host | Policy | Result |
|---|---|---|
| `secure.test` | CA ConfigMap `backend-ca`, hostname `backend.secure.test` | **200**, certificate verified |
| `wrong-name.secure.test` | expects `someone-else.secure.test` | **502**: the certificate does not carry that name |
| `no-ca.secure.test` | CA ConfigMap that does not exist | **502**, and the policy is `Accepted=False` (`NoValidCACertificate`), `ResolvedRefs=False` (`InvalidCACertificateRef`) |
| `spiffe.secure.test` | `subjectAltNames: [spiffe://secure.test/backend]` | **200**: the URI SAN matches, so the hostname need not |

A failing policy never falls back to plain HTTP or to an unverified
connection: the request fails.

## How it works

- `gen-certs.sh` mints a CA and a backend certificate (DNS
  `backend.secure.test`, URI `spiffe://secure.test/backend`). `up.sh` stores the
  certificate in a Secret the backend mounts, and the CA in a ConfigMap
  (`ca.crt`) the policies reference.
- **`BackendTLSPolicy`** targets a Service (or one of its ports, with
  `sectionName`), in its own namespace:
  - `validation.caCertificateRefs` — the CAs to trust (ConfigMap with
    `ca.crt`), or `wellKnownCACertificates: System` for public CAs;
  - `validation.hostname` — the SNI sent to the backend, and the name its
    certificate must carry;
  - `validation.subjectAltNames` — DNS names or URIs (e.g. SPIFFE IDs); when
    set, one of them must match instead of the hostname.
- **Status** is reported per Gateway whose routes use the Service
  (`status.ancestors`): `Accepted` and `ResolvedRefs`. Two policies for the same
  Service and port conflict; the older one wins and the other is
  `Accepted=False` (`Conflicted`).
- ZenoIngress's own `BackendTLSPolicy` (`zenoingress.io/v1alpha1`) is still
  supported, and adds a client certificate for mutual TLS to the backend. When
  both target a Service, ZenoIngress's own wins.
