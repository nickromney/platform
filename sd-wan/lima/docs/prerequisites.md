# Prerequisites

This SD-WAN path is macOS-first and Lima-first.

This document is the host-readiness gate for the lab. Read [what-is-sd-wan.md](what-is-sd-wan.md) first if you want the concept, or [architecture.md](architecture.md) if you want the overlapping-address design and request path.

## Install

Install the host tools with Homebrew.

Core tools:

```bash
brew install lima node
```

Optional tool:

```bash
brew install socket_vmnet
```

If you install Homebrew `make`, the binary is `gmake` unless you add GNU Make's `gnubin` directory to `PATH`.

## What The Core Tools Do

- `make` runs the workflow entrypoints in [../Makefile](../Makefile).
- `limactl` creates, starts, stops, and deletes the three Lima VMs.
- `node` and `npm` build the cloud1 subnetcalc frontend before it is staged into `/tmp/lima/frontend`.

## What The Optional Tool Does

- `socket_vmnet` is not required for this lab because the templates use Lima's named `user-v2` network, but many Lima hosts have it installed and misconfigured global Lima networking can still cause confusion. The prereq check still calls that out when it sees an invalid configured path.

## What `make prereqs` Checks

Run this first:

```bash
make -C sd-wan/lima prereqs
```

That check currently verifies:

- the host is macOS, which matches the `vmType: vz` templates
- `limactl` is installed and reachable in `PATH`
- `node` and `npm` are installed and reachable in `PATH`
- `~/.lima/_config/networks.yaml` exists and defines a `user-v2` named network
- planned host ports for the explicit Lima `portForwards` are free
- Lima networking config does not point at a missing `socket_vmnet` binary

The intent is the same as the `kubernetes/kind` prereq gate: catch obvious host-side problems before any long-running bring-up starts.

## What `make prereqs` Does Not Check Yet

- it does not preflight whether Apple Virtualization is available beyond Lima being installed
- it does not verify browser tooling for `make test-e2e`
- it does not inspect whether an already-running Lima instance was created from an older template; after template changes, recreate the VMs

## Intended Host Bindings

Only these host bindings are part of the lab contract:

| Purpose | Host bind | Guest target |
| --- | --- | --- |
| cloud1 demo UI | `127.0.0.1:58081/tcp` | `cloud1:8080/tcp` |

The intent is:

- the browser-visible demo stays on `127.0.0.1:58081`
- the inter-VM WireGuard endpoints stay inside the Lima `user-v2` guest network rather than depending on host UDP rendezvous
- there are no host-wide WireGuard listeners in the lab contract
- inside the guests, peer discovery uses shared `user-v2` underlay state written into `/tmp/lima/wireguard`

## Why The Templates Ignore Other Ports

Lima appends a fallback rule that auto-forwards guest listeners to matching host ports unless the template overrides that behavior. For this lab that is too broad, because guest nginx listens on `:80` and Docker or other local services may already be using host `:80`.

Each `cloud*.yaml` therefore adds an explicit ignore rule after the declared forwards:

```yaml
- guestIP: 0.0.0.0
  guestIPMustBeZero: false
  guestPortRange: [1, 65535]
  proto: any
  ignore: true
```

That keeps the lab constrained to the declared host ports instead of opportunistically binding whatever the guest happens to listen on.

## Expected Workflow

```bash
make -C sd-wan/lima prereqs
make -C sd-wan/lima up
make -C sd-wan/lima test
make -C sd-wan/lima down
```

If you change the Lima templates or the guest bootstrap shape, recreate the VMs so the new config is actually applied:

```bash
make -C sd-wan/lima destroy
make -C sd-wan/lima up
```

Read next: [architecture.md](architecture.md) for the address plan and resolver-viewpoint diagrams, or [network-verification.md](network-verification.md) for a live worked example.
