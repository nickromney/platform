# platform

Platform is a home for infrastructure and platform-engineering experiments, grouped by outcome first and implementation second.

The initial import in this repo is the local Kubernetes stack:

- `kubernetes/kind` contains the stage-driven `make` workflow for bringing up and checking a local Kind-based teaching cluster.
- `terraform/kubernetes` contains the OpenTofu/Terragrunt stack, GitOps manifests, policies, and helper scripts that back that workflow.
- `apps/` contains the teaching workloads that feed the later Gitea, Argo CD, Kyverno, and Cilium stages.
- `tests/kubernetes/sso` contains the Playwright checks used by the Kind stack for the SSO flow.

That stack is intentionally coupled to teaching workloads as the stages progress: the later stages demonstrate Gitea-backed CI/CD, Argo CD delivery, and policy enforcement with Kyverno and Cilium.

The intent here is local platform learning rather than cloud-provider-specific demos. More platform areas can be added later under focused top-level groups such as `kubernetes/`, `terraform/`, or vendor/platform-specific directories when they become clear enough to stand on their own.

Primary verification command:

```bash
make -C kubernetes/kind 900 check-health
```

Start with:

```bash
cd /Users/nickromney/Developer/personal/platform/kubernetes/kind
make help
make check-stage-monotonicity
make 900 check-health
```
