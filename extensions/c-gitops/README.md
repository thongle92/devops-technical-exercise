# GitOps with Argo CD (Extension C)

## Why a separate namespace, not dev/prod

Task 4's `dev`/`prod` environments are already owned by Terraform (via the
`helm` provider). If Argo CD also reconciled those same releases, two
controllers would both claim ownership of the same resources — Terraform
enforcing state from `.tf`, Argo CD enforcing state from Git — and they
would fight each other on every apply/sync. Argo CD instead manages its own
release in its own namespace (`gitops`), proving the same mechanism
("a commit changes the cluster") without an ownership conflict. See
`DECISIONS.md`.

## Setup

Since this repo is public, Argo CD pulls over HTTPS with **no credentials
needed** — this sidesteps the "repository authentication turns into a time
sink" risk the brief calls out.

```sh
kubectl create namespace argocd --context kind-greeter
kubectl apply --server-side --force-conflicts -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.2/manifests/install.yaml \
  --context kind-greeter

kubectl apply -f extensions/c-gitops/application.yaml --context kind-greeter
```

`application.yaml` points at `charts/greeter` on the `solution` branch, sets
`deployment.greetingName` and overrides `service.type` to `ClusterIP`
(reason below), and turns on `automated` sync with `selfHeal`.

## Two real bugs found while actually running this, not simulating it

**NodePort collision.** The chart's `service.yaml` unconditionally set
`nodePort: {{ .Values.service.nodePort }}` regardless of `service.type`. The
chart's default nodePort (`30080`) is already claimed by the `dev`
Terraform release — NodePort is cluster-scoped, not per-namespace, so the
Argo CD-managed Service failed to create at all
(`provided port is already allocated`). Setting `service.type=ClusterIP` to
dodge the collision then hit a second, harder failure: Kubernetes rejects a
`nodePort` field on a non-NodePort Service outright. Fixed the chart itself
(`{{- if eq .Values.service.type "NodePort" }}` around the `nodePort`
line) — this was a real, previously-undiscovered gap in the chart's support
for `ClusterIP`, not a workaround.

**Stale manifest cache after a parameter change.** After fixing the chart
and updating the Application's `service.type` parameter, Argo CD kept
retrying with the *old* rendered manifest (still trying `nodePort: 30080`)
even after a `argocd.argoproj.io/refresh: hard` annotation. Deleting and
recreating the `Application` resource cleared it. Not fully root-caused —
noted honestly rather than papered over.

## Proof a commit changes the cluster

With both bugs fixed and the Application `Synced`/`Healthy` at 2 replicas,
committed a one-line change to `charts/greeter/values.yaml`
(`deployment.replicaCount: 2` → `3`) and pushed — **no `kubectl` command of
any kind** for this step. `dev`/`prod` are unaffected: Terraform's module
always passes `replica_count` explicitly via a Helm `set` parameter,
regardless of the chart's own default.

Observed Argo CD detect the new commit on its normal poll interval and
scale the Deployment to 3 replicas on its own (`selfHeal` + `automated`
sync, no manual sync triggered). Evidence in `evidence/`:
- `pods-after-autoscale.txt` — 3 Pods `Running`/`Ready`.
- `application-after-sync.yaml` — full `Application` status, `Synced` at
  the commit that made the change.
