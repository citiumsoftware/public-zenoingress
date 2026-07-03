# Scenario 01 — Basic HTTP routing

![Basic HTTP routing: client to Gateway to HTTPRoute to Service](diagram.svg)

Expose a simple HTTP service through zenoingress using the Gateway API.

## Prerequisites

- zenoingress installed (see the [root README](../../README.md#quick-start))
- Gateway API v1.2.0 CRDs installed
- `kubectl` access to the cluster

## Steps

1. Deploy a sample app:

   ```bash
   kubectl create deployment hello --image=nginxdemos/hello --port=80
   kubectl expose deployment hello --port=80
   ```

2. Create a `Gateway` served by the `zenoingress` GatewayClass:

   ```yaml
   # gateway.yaml
   apiVersion: gateway.networking.k8s.io/v1
   kind: Gateway
   metadata:
     name: web
     namespace: default
   spec:
     gatewayClassName: zenoingress
     listeners:
       - name: http
         port: 80
         protocol: HTTP
   ```

3. Route traffic to the service with an `HTTPRoute`:

   ```yaml
   # httproute.yaml
   apiVersion: gateway.networking.k8s.io/v1
   kind: HTTPRoute
   metadata:
     name: hello
     namespace: default
   spec:
     parentRefs:
       - name: web
     hostnames:
       - "hello.example.com"
     rules:
       - matches:
           - path:
               type: PathPrefix
               value: /
         backendRefs:
           - name: hello
             port: 80
   ```

   ```bash
   kubectl apply -f gateway.yaml -f httproute.yaml
   ```

4. Verify and test:

   ```bash
   kubectl get gateway web
   GATEWAY_IP=$(kubectl get gateway web -o jsonpath='{.status.addresses[0].value}')
   curl -H "Host: hello.example.com" "http://$GATEWAY_IP/"
   ```

## Cleanup

```bash
kubectl delete httproute hello
kubectl delete gateway web
kubectl delete service hello
kubectl delete deployment hello
```
