# Local IDP Runtime Portability

The developer portal, SDK, MCP, and TUI are runtime-agnostic surfaces over the
IDP. Runtime-specific behavior belongs behind the Go IDP core adapter
interface.

```text
Developer portal / SDK / MCP / TUI
            |
        Go IDP Core
            |
    Runtime Adapter Interface
            |
kind | lima | lima | generic-k8s | aks | eks | bare-metal
```

Adapters own kubeconfig discovery, health checks, ingress and DNS strategy,
registry strategy, Git provider location, Argo CD access, OIDC setup, storage
classes, load balancer or port-forward behavior, resource budgets, and cloud or
bare-metal identity integration.

The first portable baseline is `generic_kubernetes`: given kubeconfig, Argo CD
URL, registry config, gateway domain, and catalog path, it can expose the same
Portal API contract without a developer portal rewrite. Kind remains the
default local Docker-backed runtime, while Lima prove the same
portal can target VM-backed k3s runtimes.
