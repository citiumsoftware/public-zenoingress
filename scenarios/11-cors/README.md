# Scenario 11 — CORS for a browser-facing API

A web app on `https://app.example.test` calls an API on `api.example.test`
from the browser. The gateway handles CORS with the HTTPRoute **CORS filter**
(Standard since Gateway API v1.5), so the API does not have to.

## Run

```bash
./up.sh        # kind + CRDs + ZenoIngress + a JSON API + an HTTPRoute with a CORS filter
./verify.sh    # plays the browser: preflights and requests from three origins
./down.sh      # delete the kind cluster
```

## What it shows

| Request | Result |
|---|---|
| preflight from `https://app.example.test` | `204` from the proxy, with `Access-Control-Allow-Origin`, `-Methods`, `-Max-Age` |
| preflight from `https://pr-42.preview.example.test` | allowed by the `https://*.preview.example.test` pattern |
| preflight or request from `https://evil.test` | no CORS headers: the browser blocks the response |
| `GET` from the app's origin | the API's response, plus `Access-Control-Allow-Origin`, `-Allow-Credentials`, `-Expose-Headers` |

## How it works

```yaml
filters:
  - type: CORS
    cors:
      allowOrigins: [https://app.example.test, "https://*.preview.example.test"]
      allowMethods: [GET, POST, DELETE]
      allowHeaders: [authorization, content-type]
      exposeHeaders: [x-request-id]
      allowCredentials: true
      maxAge: 600
```

- **Preflights are answered by the proxy**, before authentication filters
  (browsers send preflights without credentials), and never reach the API.
- An allowed origin is echoed in `Access-Control-Allow-Origin` (never `*`),
  with `Vary: Origin`. `*` in `allowMethods` or `allowHeaders` echoes what the
  preflight asked for.
- Origins match on scheme, host and port (`https` defaults to 443). `*` in the
  host matches one or more labels to its left.
