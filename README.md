# Platform

Infrastructure and platform-engineering experiments, grouped by outcome first and implementation second.

For instance, over time, is likely to contain groupings by

Public clouds:

- aws
- azure

Technologies:

- kubernetes
- sd-wan

Tooling:

- lima (virtual machines on Mac)
- slicer (micro VMs on Linux and Mac)

## Quick start

I spent several months making a "useful to me" local kubernetes cluster using kind (Kubernetes IN Docker):

```shell
make -C kubernetes/kind prereqs
make -C kubernetes/kind 900 plan
make -C kubernetes/kind 900 apply AUTO_APPROVE=1
make -C kubernetes/kind check-health
```

Stages are cumulative: `100` creates the cluster, `900` brings up the full local platform stack.

See [kubernetes/kind/README.md](kubernetes/kind/README.md) for the stage model, prerequisites, diagrams, ports, and troubleshooting.

For the Lima-based SD-WAN lab:

```shell
make -C sd-wan/lima prereqs
make -C sd-wan/lima up
make -C sd-wan/lima show-urls
make -C sd-wan/lima test
```

Expected outcome: open the frontend URL from `make -C sd-wan/lima show-urls`, then run a lookup and compare the `Frontend Diagnostics (cloud1 viewpoint)` and `Backend Diagnostics (cloud2 viewpoint)` panels.

See [sd-wan/lima/README.md](sd-wan/lima/README.md) for the lab walkthrough, topology notes, and browser checks.
