# Evidence: node drain and rolling update (Extension D)

Both tests run against **`prod`** (`replicaCount: 2`, spread across the 2
worker nodes, `PodDisruptionBudget minAvailable: 1`) — `dev` only has 1
replica, so draining its node would trivially cause an outage; testing
against `prod` is the only way to actually validate the Task 3 requirement
("stay available across the loss of a single node").

## How it was run

```sh
# terminal 1: continuous load
./load.sh http://localhost:8081/ evidence/drain-load.csv

# terminal 2, while load is running
kubectl drain greeter-worker --ignore-daemonsets --delete-emptydir-data \
  --context kind-greeter
# ... wait for the replacement pod to be Ready, then stop the load script ...
kubectl uncordon greeter-worker --context kind-greeter

./summarize.sh evidence/drain-load.csv
```

Same pattern for the rolling update, replacing the drain/uncordon step with:

```sh
kubectl rollout restart deployment/greeter-prod-greeter -n prod \
  --context kind-greeter
```

## Results

**Node drain** (`drain-load.csv`): 433 requests, **all 200**, max latency
10.1ms. The evicted Pod's replacement was rescheduled onto the remaining
worker node (`greeter-worker2`) while the pre-existing replica there stayed
`Ready` throughout — the Service never dropped to zero available endpoints.

**Rolling update** (`rollout-load.csv`): 464 requests, **all 200**, max
latency 6.2ms. Old Pods only started `Terminating` once their replacements
were `Ready` (standard `RollingUpdate` behavior with `maxUnavailable: 25%`
rounding to 0 for 2 replicas), so there was no window with fewer than 2
Ready replicas.

Zero failed requests in both cases is the direct result of three things
working together: the readiness probe flips to `NotReady` fast enough
(`periodSeconds: 2, failureThreshold: 1`) that Kubernetes stops routing to a
terminating Pod well inside its `SHUTDOWN_DELAY_SECONDS` window, the
`PodDisruptionBudget` prevents voluntary disruptions from ever taking the
last replica, and `terminationGracePeriodSeconds` is large enough that the
app's own drain logic always finishes before Kubernetes would force-kill it.

## An honest observation, not just a success story

After both tests, both replicas ended up on the **same** node
(`greeter-worker` after the rollout, `greeter-worker2` after the drain)
instead of spread one-per-node. `podAntiAffinity` here is `preferred`, not
`required` — it only influences the scheduler's choice among *currently
available* nodes at schedule time, it does not proactively rebalance
existing Pods afterward, and during these tests only one node was
schedulable at a time. This doesn't affect the availability result above,
but it does mean the cluster is temporarily back to single-node risk until
something (a later scheduling event, or a tool like a descheduler) spreads
the replicas apart again. Noted in `DECISIONS.md`.
