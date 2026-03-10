# Namespace Consolidation & Service Mesh Plan

## Target Namespace Structure

| Namespace | Contents | Purpose |
|-----------|----------|---------|
| `sso` | dex, oauth2-proxy-* | Authentication/identity (unchanged) |
| `apim` | apim-simulator | Shared API management simulation (NEW) |
| `dev` | sentiment-*, subnetcalc-* | Development workloads |
| `uat` | sentiment-*, subnetcalc-* | UAT workloads |
| `platform-gateway` | nginx-gateway | Ingress (unchanged) |
| `observability` | signoz, otel-collector | Monitoring (unchanged) |
| `argocd` | argocd | GitOps (unchanged) |

## Labels Schema

| Label Key | Values | Purpose |
|-----------|--------|---------|
| `project` | `sentiment`, `subnetcalc` | Primary isolation boundary |
| `role` | `frontend`, `gateway`, `backend`, `apim` | L7 policy granularity |

### Label Mapping

| Component | project | role |
|-----------|---------|------|
| sentiment-router | sentiment | gateway |
| sentiment-api | sentiment | backend |
| sentiment-auth-ui | sentiment | frontend |
| subnetcalc-router | subnetcalc | gateway |
| subnetcalc-apim-simulator | subnetcalc | apim |
| subnetcalc-frontend | subnetcalc | frontend |
| subnetcalc-api | subnetcalc | backend |

---

## Phase 1: ArgoCD Applications

### Delete (4 files)
- [ ] `apps/argocd-apps/74-sentiment-dev.application.yaml`
- [ ] `apps/argocd-apps/76-sentiment-uat.application.yaml`
- [ ] `apps/argocd-apps/70-subnetcalc-dev.application.yaml`
- [ ] `apps/argocd-apps/72-subnetcalc-uat.application.yaml`

### Create (3 files)
- [ ] `apps/argocd-apps/74-dev.application.yaml` → namespace: `dev`, path: `apps/dev`
- [ ] `apps/argocd-apps/76-uat.application.yaml` → namespace: `uat`, path: `apps/uat`
- [ ] `apps/argocd-apps/72-apim.application.yaml` → namespace: `apim`, path: `apps/apim`

---

## Phase 2: Kubernetes Manifests

### Create (3 files)
- [ ] `apps/dev/all.yaml` → sentiment + subnetcalc (dev versions) with labels
- [ ] `apps/uat/all.yaml` → sentiment + subnetcalc (uat versions) with labels
- [ ] `apps/apim/all.yaml` → apim-simulator with labels

### Update references in subnetcalc configs
- [ ] Update `subnetcalc-router-nginx` ConfigMap to point to `apim-simulator.apim.svc`

### Delete (4 directories)
- [ ] `apps/sentiment-dev/`
- [ ] `apps/sentiment-uat/`
- [ ] `apps/subnetcalc-dev/`
- [ ] `apps/subnetcalc-uat/`

---

## Phase 3: Platform Gateway Routes

### HTTPRoute files (no changes needed)
The HTTPRoutes already point to oauth2-proxy in sso namespace, which proxies to the actual service.

### Manual: Update oauth2-proxy Helm values
**DONE in code** - Updated `sso.tf`:
- `oauth2-proxy-sentiment-dev`: `sentiment-router.sentiment-dev` → `sentiment-router.dev`
- `oauth2-proxy-sentiment-uat`: `sentiment-router.sentiment-uat` → `sentiment-router.uat`
- `oauth2-proxy-subnetcalc-dev`: `subnetcalc-router.subnetcalc-dev` → `subnetcalc-router.dev`
- `oauth2-proxy-subnetcalc-uat`: `subnetcalc-router.subnetcalc-uat` → `subnetcalc-router.uat`

### Add ReferenceGrant for cross-namespace access (if needed)
- [ ] `apps/platform-gateway-routes-sso/referencegrant-apim.yaml`

---

## Phase 4: Cilium Policies

### Baseline policies (3 files)
- [ ] `cluster-policies/cilium/dev-baseline.yaml` (allow DNS, sso, observability)
- [ ] `cluster-policies/cilium/uat-baseline.yaml` (allow DNS, sso, observability)
- [ ] `cluster-policies/cilium/apim-baseline.yaml` (allow DNS, kube-apiserver)

### Project isolation (2 files)
- [ ] `cluster-policies/cilium/dev-project-isolation.yaml` (deny sentiment ↔ subnetcalc)
- [ ] `cluster-policies/cilium/uat-project-isolation.yaml` (deny sentiment ↔ subnetcalc)

### L7 HTTP policies (2 files)
- [ ] `cluster-policies/cilium/sentiment-router-l7-dev.yaml`
- [ ] `cluster-policies/cilium/sentiment-router-l7-uat.yaml`

### Delete old policies (~14 files)
- [ ] All `sentiment-dev-*`, `sentiment-uat-*`, `subnetcalc-dev-*`, `subnetcalc-uat-*` policies

---

## Phase 5: Scripts

### Update (1 file)
- [ ] `apps/subnet-calculator/scripts/update-subnetcalc-image-tags.sh`:
  - `apps/subnetcalc-dev/all.yaml` → `apps/dev/all.yaml`
  - `apps/subnetcalc-uat/all.yaml` → `apps/uat/all.yaml`
  - Add `apps/apim/all.yaml` for apim-simulator

---

## Implementation Notes

### Sub-agent Tasks
The following can be parallelized using sub-agents:
- Phase 1: ArgoCD creates/deletes (3 creates, 4 deletes)
- Phase 2: Kubernetes manifests (3 creates, 4 deletes)
- Phase 3: HTTPRoute updates (4 files)
- Phase 4: Cilium policies (can batch create/delete)

### Dependencies
1. Phase 1 (ArgoCD) must complete before Phase 2 (manifests apply)
2. Phase 2 (manifests) must complete before Phase 3 (routes can reference new namespaces)
3. Phase 4 (Cilium policies) can run in parallel with Phase 2/3 but policies won't apply until pods exist
4. Phase 5 (scripts) should run last to ensure paths are correct

### Rollback Plan
If issues occur:
1. Restore deleted ArgoCD applications
2. Restore deleted Kubernetes manifests
3. Restore deleted Cilium policies
4. Restore HTTPRoute backendRefs
5. Restore script paths
