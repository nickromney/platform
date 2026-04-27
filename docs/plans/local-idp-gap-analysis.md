# Local IDP Gap Analysis

The platform already has a strong local Kubernetes substrate: kind in Docker,
Cilium, Argo CD, Gitea, Gateway API, Keycloak, oauth2-proxy, policy,
observability, sample apps, a service catalog, and IDP read-model commands.

The remaining gap to Backstage or Port portal parity is one product surface
above those tools. The repo as a whole is the IDP; the developer portal is only
the browser-facing surface for catalog discovery, golden paths, self-service
actions, deployment visibility, scorecards, docs links, and clear ownership.

This layer must not reinvent Terraform. Terraform/OpenTofu/Terragrunt remains
the infrastructure reconciler, while Argo CD and Gitea remain the GitOps
deployment loop. FastAPI, the developer portal, SDK, TUI, and MCP expose
validated requests and status over those existing boundaries.

The launch-default path remains `kubernetes/kind` because it runs Kubernetes in
Docker. A 16GB machine should use an `idp-lite` profile before the full stage
900 teaching stack.
