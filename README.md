# Platform

Infrastructure and platform-engineering experiments, grouped by outcome first
and implementation second.

## Local Kubernetes in Docker cluster

I spent several months making a "useful to me" local kubernetes cluster using
kind (Kubernetes IN Docker):

From the project root:

```shell
make -C kubernetes/kind prereqs
make -C kubernetes/kind 900 plan
make -C kubernetes/kind 900 apply AUTO_APPROVE=1
make -C kubernetes/kind check-health
```

Stages are cumulative: `100` creates the cluster, `900` brings up the full
local platform stack, but you could apply `500` if you "only" wanted Cilium,
Hubble, ArgoCD, and Gitea running in-cluster.

See [kubernetes/kind/README.md](kubernetes/kind/README.md) for the stage
model, prerequisites, diagrams, ports, and troubleshooting.

## Local Kubernetes on Lima virtual machines

There is also a fallback path for the same platform stack on a k3s cluster
running inside Lima virtual machines:

```shell
make -C kubernetes/lima prereqs
make -C kubernetes/lima 100 apply
make -C kubernetes/lima 900 plan
make -C kubernetes/lima 900 apply AUTO_APPROVE=1
make -C kubernetes/lima check-health
```

This keeps the same cumulative stage ladder as `kubernetes/kind`, but stage
`100` bootstraps k3s on Lima and stages `200+` apply the shared Terraform stack
against that kubeconfig-backed cluster.

See [kubernetes/lima/README.md](kubernetes/lima/README.md) for the Lima
workflow, prerequisites, and operator targets.

## Local Kubernetes on Slicer microVMs

There is also a Slicer-backed path in the repository.

As of March 14, 2026, a fresh `slicer-1` built from the on-device
[`~/slicer-mac/slicer-mac.yaml`](/Users/nickromney/slicer-mac/slicer-mac.yaml)
image can complete stages `100` through `900`, including Cilium, Hubble, Argo
CD, Gitea, and Dex SSO, provided the VM has enough disk. The validated shape
for that run was `8GiB` RAM and a `25G` root disk.

The intended operator shape is:

```shell
export SLICER_VM_GROUP=slicer
make -C kubernetes/slicer prereqs
make -C kubernetes/slicer 100 apply
make -C kubernetes/slicer 900 plan
make -C kubernetes/slicer 900 apply AUTO_APPROVE=1
make -C kubernetes/slicer check-health
```

This keeps the same cumulative stage ladder as `kubernetes/kind`, but stage
`100` bootstraps k3s on Slicer and stages `200+` apply the shared Terraform
stack against that kubeconfig-backed cluster.

One Slicer-specific detail: the localhost HTTPS gateway uses `:8443`, so
browser URLs are `https://*.127.0.0.1.sslip.io:8443/...` rather than bare
`443`.

See [kubernetes/slicer/README.md](kubernetes/slicer/README.md) for the current
status, host-forwarding model, and operator targets.

## SD-WAN 3-cloud simulation, on Lima Virtual Machines

This was a thought experiment of whether I could use Lima virtual machines to
simulate public clouds, where the RFC1918 ranges "mean" something different
dependent on context, showing how a frontend served from cloud1 can consume an
API served from cloud2.

```shell
make -C sd-wan/lima prereqs
make -C sd-wan/lima up
make -C sd-wan/lima show-urls
make -C sd-wan/lima test
```

Expected outcome: open the frontend URL from
`make -C sd-wan/lima show-urls`, then run a lookup and compare the
`Frontend Diagnostics (cloud1 viewpoint)` and
`Backend Diagnostics (cloud2 viewpoint)` panels.

See [sd-wan/lima/README.md](sd-wan/lima/README.md) for the lab walkthrough,
topology notes, and browser checks.

## Plans

Over time, this repository is likely to contain groupings by

Public clouds:

- aws
- azure

Technologies:

- kubernetes
- sd-wan

Tooling:

- lima (virtual machines on Mac)
- slicer (micro VMs on Linux and Mac)

## Project docs

- [CONTRIBUTING.md](CONTRIBUTING.md)
- [AI_POLICY.md](AI_POLICY.md)
- [LICENSE.md](LICENSE.md)

## License

This repository is source-available under the Functional Source License 1.1,
with MIT as the future licence.

In practical terms, the code is here so you can read it, learn from it, run
it, and adapt it for permitted purposes. What you cannot do during the first
two years after a given version is published is turn that version into a
competing commercial product or service. After that two-year delay, that
version becomes available under MIT.

The intent of this licence choice is simple: people should be able to learn
from the examples and projects in this repository without using them as a
shortcut to run a competing commercial operation during the delayed-open
period.

This summary is informational only. The actual legal terms are in
[LICENSE.md](LICENSE.md).
