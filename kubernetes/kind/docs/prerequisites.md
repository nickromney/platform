# Prerequisites

This kind path is macOS-first and Docker-Desktop-first.

## Install

Install Docker Desktop separately, then install the CLI tools with Homebrew.

Core tools:

```bash
brew install jq kind kubernetes-cli make opentofu terragrunt
```

Optional tools:

```bash
brew install cilium-cli helm hubble kubectx mkcert yq
mkcert -install
```

If you install Homebrew `make`, the binary is `gmake` unless you add GNU Make's `gnubin` directory to `PATH`.

## What The Core Tools Do

- `make` runs the workflow entrypoints in [`Makefile`](../Makefile).
- Docker Desktop plus the `docker` CLI runs the kind node containers.
- `jq` is used by the health and audit scripts.
- `kubectl` talks to the cluster during applies and checks.
- `kind` creates and deletes the local cluster.
- OpenTofu (`tofu`) runs the Terraform-compatible infrastructure plan.
- `terragrunt` provides the wrapper layer over that OpenTofu/Terraform stack.

## What The Optional Tools Do

- `cilium` is useful for manual Cilium inspection and troubleshooting.
- `hubble` is useful for manual flow inspection once stage `300` is up.
- `helm` is useful for version and chart debugging.
- `kubectx` is just a convenience tool for context switching.
- `mkcert` is useful once HTTPS and local trust matter.
- `yq` is helpful for ad hoc YAML inspection while debugging.

## What `make prereqs` Checks

`make prereqs` is the fastest sanity check after installation. It verifies:

- expected binaries are on `PATH`
- Docker Desktop is reachable through `docker info`
- versions for the main tools can be queried
- kubeconfig files and contexts look sane

Run it from this directory with:

```bash
make prereqs
```

## Extra Requirement For The Sentiment Demo

From stage `700` onward, the shipped kind stages use:

- `llm_gateway_mode = "direct"`
- `llm_gateway_external_name = "host.docker.internal"`

That means the sentiment demo expects a host-side LLM endpoint to be reachable from Docker Desktop via `host.docker.internal`.

In practice, that means you need one of:

- LM Studio exposing an OpenAI-compatible endpoint on the host
- your own host-side gateway that fronts Apple MLX or another local model runtime with an OpenAI-compatible API

The current kind stages do not default to the in-cluster LiteLLM plus `llama.cpp` path. That mode exists in the repo, but it is not what the `700`, `800`, and `900` stage tfvars select.
