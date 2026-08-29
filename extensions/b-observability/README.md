# Observability (Extension B)

Minimal Prometheus, deployed as plain manifests (not part of the `greeter`
Helm chart - it's a shared platform tool, not something being "packaged" for
Task 3).

## Deploy

```sh
kubectl apply -f extensions/b-observability/rbac.yaml \
  -f extensions/b-observability/configmap.yaml \
  -f extensions/b-observability/deployment.yaml \
  -f extensions/b-observability/service.yaml \
  --context kind-greeter
```

Prometheus discovers every `greeter` Pod across all namespaces (`dev`,
`prod`, or any other environment) via `kubernetes_sd_configs` (role: pod),
filtered to Pods labelled `app.kubernetes.io/name: greeter`.

## View the UI

The Service is `ClusterIP` (adding another NodePort would require recreating
the kind cluster just to add a port mapping):

```sh
kubectl port-forward svc/prometheus 9090:9090 --context kind-greeter
```

Then open http://localhost:9090.

## The alert

`GreeterHighErrorRate` (`configmap.yaml`, `alerts.yml`):

```
sum(rate(greeter_http_requests_total{status="500"}[1m])) > 0
for: 1m
```

Fires on any sustained 5xx rate over 1 minute. See `DECISIONS.md` for why
this metric/threshold was chosen over the alternatives (`greeter_ready`,
latency histogram, error-ratio instead of absolute rate).

## Demonstrating it firing

```sh
for i in $(seq 1 20); do curl -sS localhost:8080/boom > /dev/null; sleep 3; done
```

Then check:

```sh
curl -sS localhost:9090/api/v1/rules
```

Evidence from an actual run is saved in `evidence/`:
- `targets.json` - all three `greeter` Pods (dev + prod) discovered and `up`.
- `alert-firing.json` - `GreeterHighErrorRate` in `state: "firing"` after ~90s
  of sustained `/boom` traffic.
