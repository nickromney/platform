# Solution Variant Comparison

This is a DDD-oriented comparison of the three Kubernetes solution variants:

- `kubernetes/kind`
- `kubernetes/lima`
- `kubernetes/slicer`

The goal is not to treat them as three business domains.
The goal is to understand how much of their language is:

- shared local-platform language
- variant-specific operator language
- accidental implementation language

## Current Synthesis

The strongest current read is:

- `platform` is the repo/theme word, not the sharp path taxonomy term
- `kubernetes` is the solution grouping
- `kind`, `lima`, and `slicer` are variants beneath that solution
- the bounded context is still `Local Stack Operations`, not three separate
  domains
- `kind` is the reference teaching variant
- `lima` and `slicer` are closer to existing-cluster or substrate-adapter
  variants than to separate stack models

That means the durable domain language should mostly sit above the specific
variant names.

## Shared Model Across All Three Variants

These concepts are stable across `kubernetes/kind`, `kubernetes/lima`, and
`kubernetes/slicer`:

- `solution` means the first path segment, such as `kubernetes`
- `variant` means the concrete operable path under that solution
- `target` remains a Makefile and workflow term
- `stage` means the cumulative `100` through `900` ladder
- `stack` means the whole collection of capabilities and apps realized on a
  variant
- `environment` means `dev`, `sit`, `uat`, and `admin`
- `prereqs`, `apply`, `check-*`, and `reset` form the operator workflow
- `200` through `900` describe roughly the same staged stack even when the
  substrate differs

Shared preferred stage language:

| Stage | Preferred operator-facing label | Notes |
| --- | --- | --- |
| `100` | cluster available | Prefer the outcome over the bootstrap mechanism. |
| `200` | Cilium | Product label is preferred here over a generic CNI term. |
| `300` | Hubble | Product label is preferred because it is the concept operators actually use. |
| `400` | Argo CD | This stage is already understood through the product name. |
| `500` | Gitea | This stage is already understood through the product name. |
| `600` | policies | Still the clearest short label. |
| `700` | app repos | This is the point where app sources become provisionable through GitOps. |
| `800` | observability | The current implementation also turns on gateway TLS and Headlamp here. |
| `900` | SSO | This stage also carries the Headlamp-ready API trust wiring. |

The important distinction is that product labels are acceptable when they are
the real operator language. The current preference is not “generalize at all
costs”, but “avoid overloaded abstractions where the concrete product name is
what people actually mean”.

## Variant Comparison

| Variant | Best current role | Strongest promise | Main variant-specific concerns |
| --- | --- | --- | --- |
| `kind` | reference teaching variant | full localhost-verified confidence path | Docker host, NodePorts, image distribution modes, split kubeconfig, host-port ownership |
| `lima` | fallback or adapter variant | converge the shared stack onto a Lima-backed k3s cluster | VM lifecycle, k3s bootstrap, host-gateway proxy, local image cache, `port-forward` access |
| `slicer` | optional personal adapter variant | converge the shared stack onto a Slicer-backed k3s cluster with localhost parity | daemon and socket health, VM sizing, host forwards, privileged-port proxying, network-profile variants |

## Important Differences

### 1. Stage `100` does not mean the same mechanism

The outcome is similar across all three variants, but the mechanism is not:

- `kind`: create the Docker-backed cluster, intentionally without the final CNI
- `lima`: create or start Lima VMs, bootstrap k3s, write split kubeconfig
- `slicer`: ensure daemon and VM health, bootstrap k3s, write split kubeconfig

The stable concept looks more like `bootstrap boundary` or `cluster available`
than any one variant's implementation steps.

### 2. `kind` is the only full self-hosting reference variant

`kind` still carries the strongest “platform-in-a-box” promise:

- verified localhost reachability
- stage `900` as a confidence path
- optional in-cluster build and repo-seeding story

By contrast, `lima` and `slicer` disable kind-only plumbing and read more like
adapters over the shared Terraform stack.

### 3. Stage `700` currently reads best as `app repos`

This is the strongest current collision.

`kind` talks as if stage `700` means app repos plus the in-cluster runner.
But the current default image-distribution path can disable the runner.

`lima` and `slicer` are cleaner:

- stage `700` means app workloads from local or cached images
- not “runner-based in-cluster supply chain”

So the preferred operator term here is `app repos`.

That is narrower and clearer than `supply chain`, and it also explains why the
stage can still make sense even when `enable_app_of_apps = false`: the point of
the stage is that app sources are now available to GitOps, not that one
specific repo orchestration pattern is enabled.

### 4. Stage `900` is still `SSO`, but not only `SSO`

All three variants still present stage `900` as the identity-access stage.
But `lima` and `slicer` also use that stage to configure Kubernetes API trust
for Headlamp-facing OIDC.

So the right reading is:

- stage `800` is `observability`
- stage `900` is `SSO`
- stage `900` also carries Headlamp-ready API trust as part of that access path

## Vocabulary Collisions

These are the main collisions surfaced by the tree walk.

| Colliding term | Problem |
| --- | --- |
| `profile` | means variant profile, network profile, and profiling/trace mode |
| `default` | means default teaching variant in one place and default-CNI mode in another |
| `proxy` | mixes host-gateway proxy, auth proxy, and generic forwarding language |
| `external images` | often means “images pulled from the local host cache”, not truly external |
| `platform` | means repo theme, shared stack, env file, image namespace, and sometimes repo owner |

## Terms This Comparison Supports

These seem like the strongest terms so far:

- `solution`
  the first-level grouping, such as `kubernetes`
- `variant`
  the operable path under a solution, such as `kubernetes/kind`
- `reference variant`
  the canonical teaching or confidence variant
- `adapter variant`
  a variant that converges the shared stack onto an existing or separately
  bootstrapped cluster
- `target`
  a Makefile-facing workflow noun that should stay implementation-facing
- `bootstrap boundary`
  the point where the cluster becomes available for later stages
- `confidence path`
  the stronger apply flow that includes real verification, not only
  reconciliation
- `app repos`
  the preferred operator label for stage `700`
- `observability`
  the preferred operator label for stage `800`
- `SSO`
  the preferred operator label for stage `900`
- `host access path`
  the stable concept behind port-forwards, host-gateway proxies, and host
  forwards

## DDD Read

The stack-operations domain is not “Kind” or “Lima” or “Slicer”.
It is the operation of a staged local stack across more than one variant.

That suggests:

- keep `kind`, `lima`, and `slicer` as implementation-facing variant names
- keep `target` in Makefiles and workflow syntax where it already means
  something concrete
- move the ubiquitous language upward to capabilities and operator promises
- use the variant names when the implementation distinction genuinely matters

## Ratified Answers

- Stage `100` should be named by outcome, so `cluster available` is better than
  `bootstrap`.
- Stage `700` currently reads best as `app repos`.
- Stage `800` is `observability`.
- Stage `900` is `SSO`.
- Product names such as `Cilium`, `Hubble`, `Argo CD`, `Gitea`, and `Headlamp`
  should stay in the stage language where they are the real operator nouns.

## Resolved Open Question

`host access path` is kept as a documentation umbrella for `proxy`,
`port-forward`, and `host forwards`. It does not replace those terms in
Makefiles, scripts, or status output. See
[ubiquitous-language.md](./ubiquitous-language.md#resolved-questions) for the
final form.
