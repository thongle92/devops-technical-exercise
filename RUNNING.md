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
