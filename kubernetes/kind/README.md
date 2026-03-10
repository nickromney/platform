# kind

Local Kubernetes cluster work (kind, k3s, etc.).

## Preferred command syntax

Run from `/Users/nickromney/Developer/personal/platform/kubernetes/kind`:

```bash
make kind plan 100
make kind apply 100 AUTO_APPROVE=1
make kind apply 900 AUTO_APPROVE=1

make k3s plan 100
make k3s apply 900 AUTO_APPROVE=1
```

`kind` and `k3s` both run the same Terraform stack (`../../terraform/kubernetes`) with different backend profile inputs:

- `targets/kind.tfvars` (provisions Kind)
- `targets/k3s.tfvars` (uses existing kubeconfig cluster)

## Existing cluster mode

Override kubeconfig details for `k3s` with env vars:

```bash
KUBECONFIG_PATH=/path/to/kubeconfig KUBECONFIG_CONTEXT=my-context make k3s plan 100
KUBECONFIG_PATH=/path/to/kubeconfig KUBECONFIG_CONTEXT=my-context make k3s apply 900 AUTO_APPROVE=1
```

Reset examples:

```bash
make reset TARGET=kind AUTO_APPROVE=1
make reset TARGET=k3s KUBECONFIG_CONTEXT=my-context K3S_RESET_CMD='limactl delete my-k3s-vm' AUTO_APPROVE=1
make stop-kind
make start-kind
```

## Useful troubleshooting command

```bash
./scripts/preload-images.sh --cluster kind-local --parallelism 4 2>&1 | tee /tmp/preload.log
```
