# Running this from a clean clone

## Prerequisites

- Docker
- [kind](https://kind.sigs.k8s.io/)
- kubectl
- helm (v3+)
- terraform (>= 1.9, for native S3-style locking support if you later move
  to a remote backend not required for this local setup)

## 1. Build the Docker image

```sh
cd app
CGO_ENABLED=0 go test ./...
cd ..
docker build -t greeter:1.0.0 app/
```

Verify it locally before moving on:

```sh
docker run --rm -e GREETING_NAME=Test -p 8080:8080 greeter:1.0.0 &
curl localhost:8080/
```

## 2. Provision the local cluster

```sh
./cluster/create-cluster.sh
```

This does two things:
1. `kind create cluster` using `cluster/kind-config.yaml` — 1 control-plane +
   2 worker nodes, with host ports `8080`/`8081` mapped in for the `dev`/
   `prod` NodePort Services (Task 4).
2. `kind load docker-image greeter:1.0.0` — loads the image you just built
   directly into the cluster's nodes. kind runs each node as its own
   container with its own containerd image store, separate from your host's
   Docker daemon, so this step is required — without it, Pods would try to
   pull `greeter:1.0.0` from a registry and fail (`ImagePullBackOff`), since
   this tag only exists on your machine.

If you build a different tag, pass it as an argument:
`./cluster/create-cluster.sh greeter:2.0.0`.

Verify:

```sh
kubectl get nodes --context kind-greeter
```

All 3 nodes should show `Ready` within about 30 seconds.

## 3. Deploy the Helm chart directly (manual, optional)

Not required if you're going straight to Terraform below (Terraform installs
the chart for you) — useful if you just want to sanity-check the chart on
its own first.

```sh
helm lint charts/greeter
helm install greeter charts/greeter \
  --set deployment.greetingName=Test \
  --kube-context kind-greeter

kubectl get pods -o wide --context kind-greeter
curl localhost:8080/
```

`deployment.greetingName` is required and has no default (mirrors the app's
own fail-fast behavior) — `helm install` without it fails loudly instead of
deploying silently. Clean up before moving to Terraform, since Terraform's
`dev` release also wants NodePort `30080`/host port `8080`:

```sh
helm uninstall greeter --kube-context kind-greeter
```

## 4. Deploy dev and prod with Terraform

Each environment is a separate Terraform root module calling the shared
`terraform/modules/greeter` module. **You must `cd` into the environment
directory and run Terraform from there** — not via `-chdir=...` from
elsewhere — because the environment name (`dev`/`prod`, used for the
namespace and NodePort) is derived from `path.cwd`. See `DECISIONS.md` for
why, and the trade-off.

```sh
cd terraform/greeter/dev
terraform init
terraform apply
```

```sh
cd terraform/greeter/prod
terraform init
terraform apply
```

Verify both are up and distinct:

```sh
curl localhost:8080/   # dev  -> "Hello Thong (dev), ..."
curl localhost:8081/   # prod -> "Hello Thong (prod), ..."
kubectl get pods -n dev -o wide --context kind-greeter
kubectl get pods -n prod -o wide --context kind-greeter
```

`prod` has 2 replicas spread across the 2 worker nodes; `dev` has 1.

## 5. Extensions

### B — Observability (Prometheus)

```sh
kubectl apply -f extensions/b-observability/rbac.yaml \
  -f extensions/b-observability/configmap.yaml \
  -f extensions/b-observability/deployment.yaml \
  -f extensions/b-observability/service.yaml \
  --context kind-greeter
```

View the UI and demo the alert firing:

```sh
kubectl port-forward svc/prometheus 9090:9090 --context kind-greeter
# in another terminal:
for i in $(seq 1 20); do curl -sS localhost:8080/boom > /dev/null; sleep 3; done
```

Open `http://localhost:9090/alerts` — `GreeterHighErrorRate` should go
`Pending` then `Firing` within about 90 seconds. Full details in
`extensions/b-observability/README.md`.

### D — Prove it survives (node drain / rolling update)

Run against `prod` (`localhost:8081`), not `dev` — `dev` only has 1 replica,
so draining its node would trivially cause an outage; see `DECISIONS.md`.

```sh
cd extensions/d-prove-it-survives
./load.sh http://localhost:8081/ evidence/my-run.csv &

kubectl drain greeter-worker --ignore-daemonsets --delete-emptydir-data \
  --context kind-greeter
# ... wait for the replacement Pod to be Ready ...
kubectl uncordon greeter-worker --context kind-greeter

# stop load.sh (kill the background job), then:
./summarize.sh evidence/my-run.csv
```

Full write-up and the original evidence in
`extensions/d-prove-it-survives/README.md`.

### A — CI pipeline (GitHub Actions)

Nothing to run locally — `.github/workflows/ci.yml` triggers on push to any
branch, but **only when files under `app/` change** (`on.push.paths`). Push
a change under `app/` and check the Actions tab. Details on what actually
runs vs. what's gated on secrets you won't have in
`DECISIONS.md`.

### C — GitOps (Argo CD)

```sh
kubectl create namespace argocd --context kind-greeter
kubectl apply --server-side --force-conflicts -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.2/manifests/install.yaml \
  --context kind-greeter

kubectl apply -f extensions/c-gitops/application.yaml --context kind-greeter
```

This deploys into its **own namespace (`gitops`)**, deliberately separate
from Terraform's `dev`/`prod` — see `DECISIONS.md` for why. View the UI:

```sh
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
kubectl port-forward svc/argocd-server 8443:443 -n argocd --context kind-greeter
```

Open `https://localhost:8443` (self-signed cert warning is expected), log
in as `admin`. **Don't use local port `8081`** for this port-forward — it's
already mapped to `prod`'s NodePort.

To prove a commit changes the cluster: edit
`charts/greeter/values.yaml` (e.g. `deployment.replicaCount`), commit, push,
and watch `kubectl get application greeter-gitops -n argocd --context
kind-greeter` pick up the new revision on its own within a few minutes
(`selfHeal` + `automated` sync — no `kubectl apply` needed for chart
changes). Full write-up in `extensions/c-gitops/README.md`.
