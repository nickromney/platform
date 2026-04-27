# Headlamp - Kubernetes Dashboard

Notes for implementing Headlamp as an in-cluster GUI for viewing workloads.

## Overview

[Headlamp](https://headlamp.dev/) is a CNCF sandbox project providing a modern Kubernetes dashboard with:

- Real-time cluster visualization
- Plugin architecture for extensibility
- OIDC/SSO support
- Helm chart for easy deployment

## Helm Chart

```text
Repository: https://headlamp-k8s.github.io/headlamp/
Chart: headlamp
```

Docs: <https://headlamp.dev/docs/latest/installation/in-cluster/>

## Implementation Plan

### 1. ArgoCD Application

Create `apps/headlamp/` in the policies repo with ArgoCD Application pointing to the Helm chart.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: headlamp
  namespace: argocd
spec:
  project: default
  destination:
    namespace: headlamp
    server: https://kubernetes.default.svc
  source:
    repoURL: https://headlamp-k8s.github.io/headlamp/
    chart: headlamp
    targetRevision: <version>
    helm:
      releaseName: headlamp
      values: |
        # See values below
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### 2. Helm Values

Key configuration options:

```yaml
# Basic config
replicaCount: 1

# Service account with cluster-wide read access
clusterRoleBinding:
  create: true

# OIDC integration
config:
  oidc:
    clientID: "headlamp"
    clientSecret: "<from-oidc-provider-config>"
    issuerURL: "https://keycloak.127.0.0.1.sslip.io/realms/platform"
    scopes: "openid profile email groups"

# Or use service account token auth (simpler, no SSO)
# Users create tokens via: kubectl create token headlamp -n headlamp
```

### 3. Gateway Integration

Add HTTPRoute for platform gateway:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: headlamp
  namespace: headlamp
spec:
  parentRefs:
    - name: platform-gateway
      namespace: platform-gateway
  hostnames:
    - headlamp.admin.127.0.0.1.sslip.io
  rules:
    - backendRefs:
        - name: headlamp
          port: 80
```

### 4. SSO Integration Options

#### Option A: Keycloak OIDC (stage `900` default)

Terraform renders a Keycloak `headlamp` client in the local `platform` realm:

```yaml
clientId: headlamp
redirectUris:
  - https://headlamp.admin.127.0.0.1.sslip.io/oidc-callback
protocolMappers:
  - name: groups
```

Headlamp points at the selected provider via Terraform locals. Kubernetes API
authorization is group-based: `platform-admins` receives the local demo admin
role, and `platform-viewers` receives read-only bindings for selected
namespaces. Dex remains available only when the explicit compatibility provider
is selected.

#### Option B: Service Account Token

No SSO - users authenticate with kubectl-generated tokens:

```bash
kubectl create token headlamp -n headlamp --duration=24h
```

Simpler but less convenient for regular use.

### 5. RBAC

Headlamp needs cluster-wide read access. The Helm chart can create:

```yaml
clusterRoleBinding:
  create: true
  # Uses view ClusterRole by default
```

For write access (editing resources via UI), bind to `edit` or `admin` ClusterRole.

### 6. Files to Create

```text
apps/headlamp/
├── kustomization.yaml
├── namespace.yaml
└── httproute.yaml

# HTTPRoute additions:
apps/platform-gateway-routes/httproute-headlamp.yaml
apps/platform-gateway-routes-sso/httproute-headlamp.yaml

# Terraform:
main.tf - Add kubectl_manifest.argocd_app_headlamp
variables.tf - Add enable_headlamp variable
```

### 7. Terraform Variable

```hcl
variable "enable_headlamp" {
  description = "Deploy Headlamp Kubernetes dashboard"
  type        = bool
  default     = false
}
```

## References

- Headlamp docs: <https://headlamp.dev/docs/latest/>
- Helm chart: <https://github.com/headlamp-k8s/headlamp/tree/main/charts/headlamp>
- OIDC setup: <https://headlamp.dev/docs/latest/installation/in-cluster/oidc/>
