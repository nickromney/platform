# Identity Provider Completion Notes

This is a platform implementation plan, not end-user documentation. It captures
the identity-provider completion state that should not sit in the learning
journeys.

## Current State

- Kubernetes stage 900 now uses Keycloak as the local OIDC issuer and places
  `oauth2-proxy` in front of platform and app routes.
- Dex remains in the code as a supported provider shape behind
  `sso_provider`, but it is no longer the local stage-900 teaching path.
- The Sentiment compose stack already uses Keycloak 26.6.1 with a templated
  realm import and an `oauth2-proxy` client.
- Demo identities now carry groups:
  - `platform-admins`
  - `platform-viewers`
- App/environment access groups are modeled in the realm:
  - `app-subnetcalc-dev`
  - `app-subnetcalc-uat`
  - `app-sentiment-dev`
  - `app-sentiment-uat`
- Argo CD maps platform groups into admin and read-only roles through the
  `groups` claim.
- Headlamp OIDC, Kubernetes API OIDC wiring, and `oauth2-proxy` route
  protection consume provider-neutral SSO locals.
- Keycloak runs with Postgres and a checked-in/generated realm import path.
- Identity secret material is split between generated Terraform passwords
  (OIDC client secrets, cookie secret, Keycloak Postgres password) and
  operator-supplied demo credentials.
- SigNoz is optional and disabled in the local stage tfvars. Older SigNoz
  auth-proxy manifests still exist, but they should not drive the identity
  provider decision.

## Completed Domain Decisions

- **Identity provider:** Keycloak is the default stage-900 provider for local
  Kubernetes paths; Dex is a compatibility/provider-switch option.
- **Application spec/catalog:** app surfaces are modeled as
  app/environment pairs and projected into Argo CD apps, route hostnames,
  SSO callbacks, and Launchpad tiles.
- **Environment lifecycle:** `dev`, `sit`, and `uat` are application
  namespaces. `admin` is a route band for platform tools. Namespace-role
  labels (`application`, `shared`, `platform`) drive policy inheritance.
- **Deployment read model:** Argo CD sync/health, Kubernetes deployment
  readiness, Prometheus metrics, Grafana Launchpad tiles, and local
  `platform status` are read-side projections, not sources of desired state.
- **RBAC:** `platform-admins` and `platform-viewers` are the stable platform
  groups. App groups are scoped by app/environment. Argo CD uses the platform
  groups directly; Kubernetes API authorization is checked through OIDC group
  claims and `kubectl auth can-i`.
- **Secrets lifecycle:** generated credentials are created at apply time and
  projected through Kubernetes Secrets. The current lifecycle is
  apply-driven replacement, not a separate rotation workflow.
- **Portal/status surfaces:** Grafana Launchpad is the operator portal
  projection. Argo CD Applications and `platform status` remain the sharper
  status surfaces for reconciliation and local runtime ownership.

## Retained Tradeoff

| Question | Dex default | Keycloak candidate |
| --- | --- | --- |
| Fast local SSO bootstrap | Strong | Heavier |
| User lifecycle learning | Weak | Strong, now modeled |
| Group and role modelling | Basic | Strong, now used |
| App and platform tool OIDC | Good | Good, now wired |
| Kubernetes API OIDC | Good | Wired through provider-neutral locals |
| Memory footprint | Small | Larger |
| Realm portability | Simple static config | Realm import model |
| Production-like IdP behaviour | Limited | Better |

The remaining reason to keep Dex is local footprint. The reason to prefer
Keycloak is the richer identity lifecycle and RBAC model now used by the
stage-900 path.

## Completion Checklist

- [x] explicit provider switch: `sso_provider = "dex" | "keycloak"`
- [x] provider-neutral issuer, token, JWKS, and userinfo locals
- [x] Kubernetes Keycloak deployment with Postgres
- [x] realm import with OIDC clients, users, groups, and claim mapping
- [x] restricted pod settings for Keycloak
- [x] Argo CD OIDC and group-to-role mapping
- [x] Headlamp OIDC wiring
- [x] `oauth2-proxy` protection for admin and app routes
- [x] Launchpad portal tile for Keycloak and protected app surfaces
- [x] keep SigNoz identity baggage quarantined unless `enable_signoz=true`
  remains a supported path

## Open Decisions

- Keep Dex indefinitely as the compact path, or retire it after Keycloak has
  enough runtime evidence on all local variants?
- Promote secret rotation into an explicit operator workflow, or keep the
  current apply-driven replacement model?
- Promote the application catalog into a single first-class file, or continue
  deriving it from Terraform locals, Argo CD apps, and Launchpad inventory?

## Source Notes

- Current Kubernetes SSO path: `terraform/kubernetes/sso.tf`
- Current Argo CD group mapping: `terraform/kubernetes/locals.tf`
- Current SSO feature flag: `terraform/kubernetes/variables.tf`
- Current stage-900 selections: `kubernetes/kind/stages/900-sso.tfvars`,
  `kubernetes/lima/stages/900-sso.tfvars`,
  `kubernetes/slicer/stages/900-sso.tfvars`
- Current Launchpad inventory:
  `terraform/kubernetes/config/platform-launchpad.apps.json`
- Existing Keycloak compose example: `apps/sentiment/compose.yml`
- Existing Keycloak realm template: `apps/sentiment/keycloak/realm-export.json`
- Official Keycloak container guide:
  <https://www.keycloak.org/server/containers>
- Official Keycloak production guide:
  <https://www.keycloak.org/server/configuration-production>
- Official Keycloak authorization services guide:
  <https://www.keycloak.org/docs/24.0.5/authorization_services/>
- Keycloak Operator resource and network-policy notes:
  <https://docs.redhat.com/en/documentation/red_hat_build_of_keycloak/26.4/html-single/operator_guide/index>
