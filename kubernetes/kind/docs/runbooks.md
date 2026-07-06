# Kind Platform Alert Runbooks

These runbooks cover the starter Prometheus alerts for the local kind platform.
Use the split kind kubeconfig when running direct `kubectl` checks:
`~/.kube/kind-kind-local.yaml` with context `kind-kind-local`.

## PlatformPodCrashLooping

Meaning: a container has a sustained increase in
`kube_pod_container_status_restarts_total`, which usually means the process is
crashing after start, failing probes, or being killed for resources.

First checks:

- Run `make -C kubernetes/kind check-health`.
- Run `make -C kubernetes/kind audit-bootstrap`.
- Inspect the affected pod with `kubectl --kubeconfig ~/.kube/kind-kind-local.yaml --context kind-kind-local -n <namespace> describe pod <pod>`.
- Check current and previous logs with `kubectl --kubeconfig ~/.kube/kind-kind-local.yaml --context kind-kind-local -n <namespace> logs <pod> -c <container>` and `--previous`.

## PlatformDeploymentReplicasUnavailable

Meaning: a Deployment has reported unavailable replicas for more than 10
minutes. This usually points to image pulls, scheduling, readiness probes, or a
dependency that prevents pods from becoming Ready.

First checks:

- Run `make -C kubernetes/kind check-health`.
- For app workloads, run `make -C kubernetes/kind check-app APP=<name>`.
- Inspect rollout state with `kubectl --kubeconfig ~/.kube/kind-kind-local.yaml --context kind-kind-local -n <namespace> rollout status deploy/<deployment>`.
- Describe the Deployment and newest ReplicaSet events.

## PlatformPersistentVolumeClaimFilling

Meaning: kubelet volume stats report a PVC above 85 percent used. In kind this
is usually local-path storage or a teaching workload retaining more data than
expected.

First checks:

- Run `make -C kubernetes/kind check-health`.
- Identify the owner pod with `kubectl --kubeconfig ~/.kube/kind-kind-local.yaml --context kind-kind-local -n <namespace> get pod -o wide`.
- Inspect PVC and PV state with `kubectl --kubeconfig ~/.kube/kind-kind-local.yaml --context kind-kind-local -n <namespace> describe pvc <persistentvolumeclaim>`.
- If the PVC belongs to observability, reduce retention or reset the local stack only after confirming the data is disposable.

## PlatformNodeMemoryPressure

Meaning: node-exporter reports less than 10 percent available memory on a kind
node for more than 10 minutes. Local Docker Desktop memory limits are a common
cause.

First checks:

- Run `make -C kubernetes/kind status`.
- Run `make -C kubernetes/kind check-health`.
- Inspect pod placement and requests with `kubectl --kubeconfig ~/.kube/kind-kind-local.yaml --context kind-kind-local top pod -A` when metrics are available.
- Check Docker Desktop or Docker Engine memory allocation before changing Kubernetes manifests.

## PlatformCertificateExpiringSoon

Meaning: cert-manager reports a Certificate with less than 14 days until
expiration. The alert is silent when cert-manager metrics are absent.

First checks:

- Run `make -C kubernetes/kind check-gateway-stack`.
- Run `make -C kubernetes/kind check-gateway-urls`.
- Inspect certificates with `kubectl --kubeconfig ~/.kube/kind-kind-local.yaml --context kind-kind-local get certificates -A`.
- Describe the affected Certificate, CertificateRequest, Order, or Challenge resources in the reported namespace.
