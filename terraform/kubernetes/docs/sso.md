## SSO (optional)

SSO is an optional add-on for this stack (stage `900`).

High-level design:

- **Dex** provides an in-cluster OIDC IdP (static demo users)
- **oauth2-proxy** sits in front of the UIs (Argo CD, Gitea, Hubble, SigNoz)
- **Argo CD** uses native OIDC integration against Dex

## Decisions

1. **Scope**: SSO is enabled for **all UIs** (`argocd`, `gitea`, `hubble`, `signoz`).
2. **IdP**: **Dex** with **static users**.

## Demo login

- Email: `demo@example.com`
- Password: `password123`

1. Do you want SSO for **all** UIs (`argocd`, `gitea`, `hubble`, `signoz`) — or just ArgoCD/Gitea?
2. Which IdP do you want: **Keycloak**, **Authentik**, or **Dex with static users**?
