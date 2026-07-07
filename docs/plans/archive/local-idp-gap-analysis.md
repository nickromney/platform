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
Docker. The 16GB local IDP shape is now implemented as a stage-900 workflow
preset, not a new cumulative stage:

```bash
scripts/platform-workflow.sh apply --execute \
  --variant kind \
  --stage 900 \
  --action apply \
  --preset resource-profile=local-idp-16gb \
  --preset image-distribution=local-cache \
  --auto-approve
```

This mechanism keeps the stage ladder monotonic while letting operators layer a
documented resource profile through generated operator tfvars.
