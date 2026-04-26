# Identity Provider Roadmap

This is a platform implementation plan, not end-user documentation. It captures
the identity questions that should not sit in the learning journeys.

## Current State

- Kubernetes stage 900 uses Dex as the in-cluster OIDC issuer and places
  `oauth2-proxy` in front of platform routes.
- The Sentiment compose stack already uses Keycloak 26.6.1 with a templated
  realm import and an `oauth2-proxy` client.
- Demo identities now carry groups:
  - `platform-admins`
  - `platform-viewers`
- Argo CD now maps those groups into admin and read-only roles.
- Kubernetes API server OIDC setup, Headlamp OIDC, and `oauth2-proxy` route
  protection are still Dex-shaped in `terraform/kubernetes/sso.tf`.
- SigNoz is optional and disabled in the local stage tfvars. Older SigNoz
  auth-proxy manifests still exist, but they should not drive the identity
  provider decision.

## Assessment

Keycloak is capable of covering the differences that matter for the platform
identity journey:

- OIDC clients for `oauth2-proxy`, Argo CD, Headlamp, and app routes.
- Users, groups, realm roles, client roles, and token claim mapping.
- User lifecycle demonstrations: create, disable, remove, reset credentials,
  and observe token/session effects.
- Session, refresh-token, cookie, brute-force, password, and login policy
  exercises.
- Richer authorization modelling than Dex, including RBAC, ABAC, contextual
  policy, and reusable policy/permission objects.
- Realm import/export for reproducible local bootstrap.

The main tradeoff is operational weight. Keycloak is a JVM service with higher
startup time and memory needs than Dex. The official operator documentation
defaults to materially larger memory values than the current Dex path. Keycloak
also needs an explicit persistence story if the platform wants lifecycle
exercises beyond throwaway demo users.

## Recommendation

Keep Dex as the smallest first-run SSO path until Keycloak has a validated
Kubernetes profile. Add Keycloak as an opt-in stage-900 identity provider, then
make the default decision based on measured local runtime cost.

If the project no longer uses SigNoz and the platform now enforces restricted
pod defaults, Keycloak is a realistic candidate for the richer identity path.
The decision should be evidence-based:

| Question | Dex default | Keycloak candidate |
| --- | --- | --- |
| Fast local SSO bootstrap | Strong | Weaker |
| User lifecycle learning | Weak | Strong |
| Group and role modelling | Basic | Strong |
| App and platform tool OIDC | Good | Good |
| Kubernetes API OIDC | Good | Good after issuer wiring |
| Memory footprint | Small | Larger |
| Realm portability | Simple static config | Strong import/export model |
| Production-like IdP behaviour | Limited | Better |

## Implementation Plan

1. Add an explicit provider switch:
   - `sso_provider = "dex" | "keycloak"`
   - Keep `enable_sso` as the high-level feature flag.
   - Derive issuer URL, internal token URL, JWKS URL, and userinfo URL from the
     selected provider.

2. Introduce a Kubernetes Keycloak slice:
   - Start with a single-node local profile.
   - Use the official image and an optimized startup path where practical.
   - Mount a realm import generated from Terraform values or a checked-in
     template.
   - Use Postgres or another explicit persistence option if the journey covers
     user lifecycle beyond ephemeral bootstrap.

3. Prove the restricted pod profile:
   - `runAsNonRoot: true`
   - `seccompProfile.type: RuntimeDefault`
   - `allowPrivilegeEscalation: false`
   - `capabilities.drop: ["ALL"]`
   - no writable root filesystem unless Keycloak proves it needs one
   - explicit writable mounts for `/tmp`, import data, and any cache/data path

4. Wire existing consumers through provider-neutral locals:
   - `oauth2-proxy-*`
   - Argo CD `oidc.config`
   - Headlamp OIDC
   - kind/lima/slicer API server OIDC scripts
   - browser E2E helpers that currently recognise Dex and Keycloak forms

5. Model groups once:
   - `platform-admins`
   - `platform-viewers`
   - optional app-specific groups such as `sentiment-dev-users` and
     `sentiment-uat-users`
   - group claim emitted consistently for Argo CD, Headlamp, apps, and
     Kubernetes API authn/authz checks

6. Add acceptance checks:
   - issuer discovery responds through the gateway
   - login works for admin and viewer identities
   - Argo CD admin/viewer checks differ as expected
   - `kubectl auth can-i` checks prove Kubernetes RBAC mapping
   - user disable invalidates future logins
   - session expiry and logout behave predictably
   - Keycloak pod passes Kyverno restricted runtime tests

7. Remove or quarantine SigNoz-specific identity baggage:
   - Keep only if `enable_signoz=true` still has a supported path.
   - Do not require SigNoz auth bridge behaviour for the Keycloak decision.

## Open Decisions

- Use the Keycloak Operator or a direct local Deployment?
  - Operator gives a stronger Kubernetes-native model, resources, scheduling,
    network policy, ServiceMonitor, and realm import jobs.
  - Direct Deployment is closer to the existing Argo CD chart style and may be
    simpler for the local workbench.
- Use persistent Postgres from the start, or begin with a dev-file/demo profile?
  - Dev-file is easy, but weak for user lifecycle and recovery exercises.
  - Postgres is heavier, but makes lifecycle behaviour honest.
- Keep Dex forever as the compact path, or switch the default once Keycloak is
  measured and stable?

## Source Notes

- Current Kubernetes Dex path: `terraform/kubernetes/sso.tf`
- Current Argo CD group mapping: `terraform/kubernetes/locals.tf`
- Current SSO feature flag: `terraform/kubernetes/variables.tf`
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
