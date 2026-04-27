## SSO (optional)

SSO is an optional add-on for this stack (stage `900`).

High-level design:

- **Keycloak** provides the Kubernetes stage `900` OIDC IdP, realm, users, groups, and clients
- **oauth2-proxy** sits in front of browser UIs and app routes
- **Argo CD** uses native OIDC integration against Keycloak for group RBAC
- **Dex** remains the lightweight Docker Compose proof path and an explicit compatibility provider

## Decisions

1. **Scope**: SSO is enabled for admin UIs and selected app routes (`argocd`, `gitea`, `grafana`, `headlamp`, `hubble`, `kyverno`, `sentiment`, `subnetcalc`, `hello-platform`).
2. **IdP**: **Keycloak** with reproducible local users and groups.
3. **Authorization proof**: org groups (`platform-admins`, `platform-viewers`) and app/environment groups (`app-*-dev`, `app-*-uat`) are distinct checks.
4. **SigNoz**: optional observability path only; it is not part of the active SSO/RBAC success story.
5. **APIM audience**: the Kubernetes APIM simulator validates Keycloak tokens
   as a resource server with the dedicated `apim-simulator` audience. It does
   not treat `oauth2-proxy` as the API audience.
6. **Portability**: subnetcalc keeps its non-Keycloak auth modes for other
   platforms. The Keycloak wiring lives in the Kubernetes stage path, not in
   the subnetcalc domain core or the standalone APIM simulator contract.

## Demo login

- Admin email: `demo@admin.test`
- Dev viewer email: `demo@dev.test`
- UAT viewer email: `demo@uat.test`
- Password: your `PLATFORM_DEMO_PASSWORD` value from the repo root `.env`

The Keycloak administration console is part of the platform realm journey:
open `https://keycloak.127.0.0.1.sslip.io/admin/platform/console/#/platform/users`
and sign in as `demo@admin.test`. That user is a member of `platform-admins`,
which carries the Keycloak `realm-management:realm-admin` role for the
`platform` realm, so it can inspect and administer `demo@dev.test` and
`demo@uat.test`. The separate `keycloak-admin` account is a permanent
master-realm break-glass account, not the normal IDP demo persona.
`/realms/platform` is OIDC realm metadata.

Useful checks:

```bash
make -C kubernetes/kind check-sso
make -C kubernetes/kind check-rbac
make -C kubernetes/kind idp-catalog
make -C kubernetes/kind idp-deployments
```

`check-rbac` first proves the Kubernetes RBAC rules with impersonation, then,
when Keycloak is present, obtains real Keycloak ID tokens for the admin and
viewer demo users and asks the Kubernetes API to authorize those tokens. Set
`PLATFORM_RBAC_REAL_TOKEN_CHECK=off` only when deliberately testing a legacy or
non-Keycloak compatibility path.
