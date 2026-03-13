# Platform

Infrastructure and platform-engineering experiments, grouped by outcome first and implementation second.

## Local Kubernetes in Docker cluster

I spent several months making a "useful to me" local kubernetes cluster using kind (Kubernetes IN Docker):

From the project root:

```shell
make -C kubernetes/kind prereqs
make -C kubernetes/kind 900 plan
make -C kubernetes/kind 900 apply AUTO_APPROVE=1
make -C kubernetes/kind check-health
```

Stages are cumulative: `100` creates the cluster, `900` brings up the full local platform stack, but you could apply `500` if you "only" wanted Cilium, Hubble, ArgoCD, and Gitea running in-cluster.

See [kubernetes/kind/README.md](kubernetes/kind/README.md) for the stage model, prerequisites, diagrams, ports, and troubleshooting.

## SD-WAN 3-cloud simulation, on Lima Virtual Machines.

This was a thought experiment of whether I could use Lima virtual machines to simulate public clouds, where the RFC1918 ranges "mean" something different dependent on context, showing how a frontend served from cloud1 can consume an API served from cloud2.

```shell
make -C sd-wan/lima prereqs
make -C sd-wan/lima up
make -C sd-wan/lima show-urls
make -C sd-wan/lima test
```

Expected outcome: open the frontend URL from `make -C sd-wan/lima show-urls`, then run a lookup and compare the `Frontend Diagnostics (cloud1 viewpoint)` and `Backend Diagnostics (cloud2 viewpoint)` panels.

See [sd-wan/lima/README.md](sd-wan/lima/README.md) for the lab walkthrough, topology notes, and browser checks.

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
