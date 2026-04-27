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

## Demo login

- Admin email: `demo@admin.test`
- Dev viewer email: `demo@dev.test`
- UAT viewer email: `demo@uat.test`
- Password: your `PLATFORM_DEMO_PASSWORD` value from the repo root `.env`

Useful checks:

```bash
make -C kubernetes/kind check-sso
make -C kubernetes/kind check-rbac
make -C kubernetes/kind idp-catalog
make -C kubernetes/kind idp-deployments
```
