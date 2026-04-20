# Compose Architecture

This document explains how `subnetcalc` works when it is run directly
from the compose files in this app directory rather than through the
Kubernetes/Terraform platform stack.

## Scope

- [`compose.yml`](../compose.yml) is the main local topology and defines the
  numbered local stacks. By default it now starts only the baseline
  container-app family; the heavier function, OIDC, and mock Easy Auth families
  are opt-in via compose profiles.
- [`compose.tls.yml`](../compose.tls.yml) adds a TLS 1.3 front door in front of
  one compose slice.
- [`compose.azurite.yml`](../compose.azurite.yml) adds local Azure Storage
  emulation for the Function-style backends.
- The standalone `compose.yml` files under individual component directories are
  narrower entry points for working on one backend or frontend in isolation.

## Compose File Map

| File | Role |
| --- | --- |
| [`compose.yml`](../compose.yml) | Main local runtime. Default `compose up` starts the baseline container-app family; `function-family`, `oidc`, and `mock-easyauth` profiles opt into the heavier slices. |
| [`compose.tls.yml`](../compose.tls.yml) | Optional TLS 1.3 overlay, currently wired for the static frontend plus container-app API path. |
| [`compose.azurite.yml`](../compose.azurite.yml) | Optional Azurite overlay for the Function-based paths. |
| `*/compose.yml` | Narrow per-component stacks used for focused local work. |

## Stack Matrix

| Stack | Browser entry | Auth model | Main backend path |
| --- | --- | --- | --- |
| 01 | `frontend-html-static` on `:8001` | none | `frontend-html-static -> api-fastapi-container-app` |
| 02 | `frontend-python-flask-container-app` on `:8002` | none | `frontend-python-flask -> api-fastapi-container-app` |
| 03 | `frontend-python-flask` on `:8000` | JWT in app | `frontend-python-flask -> api-fastapi-azure-function` |
| 04 | `frontend-typescript-vite` on `:8003` | none | `frontend-typescript-vite -> api-fastapi-container-app` |
| 05 | `frontend-typescript-vite-jwt` on `:3001` | JWT in SPA | `frontend-typescript-vite-jwt -> api-fastapi-azure-function` |
| 06 | `frontend-react` on `:8004` | none | `frontend-react -> api-fastapi-container-app` |
| 07 | `frontend-react-jwt` on `:3002` | JWT in SPA | `frontend-react-jwt -> api-fastapi-azure-function` |
| 08 | `frontend-react-msal` on `:3003` | MSAL / Azure AD style | `frontend-react-msal -> api-fastapi-azure-function` |
| 09 | `frontend-react-server-jwt` on `:3004` | JWT with runtime config | `frontend-react-server-jwt -> api-fastapi-azure-function` |
| 10 | `frontend-react-proxy` on `:3005` | JWT plus frontend-side proxy | `frontend-react-proxy -> api-fastapi-azure-function` |
| 11 | `frontend-react-keycloak` on `:3006` | OIDC in SPA | `frontend-react-keycloak -> api-fastapi-keycloak` |
| 12 | `oauth2-proxy-frontend` on `:3007` and admin on `:3008` | OIDC at proxy front door | `oauth2-proxy -> protected frontend -> apim-simulator -> api-fastapi-keycloak` |
| 13 | `easyauth-router` on `:3012` | mocked Easy Auth | `easyauth-router -> frontend-react-easyauth-mock` |

## Local Stack Families

```mermaid
flowchart TB
    Browser["Browser"]

    subgraph ContainerApp["Container App family"]
        HTML["frontend-html-static :8001"]
        FlaskCA["frontend-python-flask-container-app :8002"]
        Vite["frontend-typescript-vite :8003"]
        React["frontend-react :8004"]
        CAAPI["api-fastapi-container-app :8090"]

        HTML --> CAAPI
        FlaskCA --> CAAPI
        Vite --> CAAPI
        React --> CAAPI
    end

    subgraph FunctionApp["Azure Function family"]
        FlaskFn["frontend-python-flask :8000"]
        ViteJWT["frontend-typescript-vite-jwt :3001"]
        ReactJWT["frontend-react-jwt :3002"]
        ReactMSAL["frontend-react-msal :3003"]
        ReactServer["frontend-react-server-jwt :3004"]
        ReactProxy["frontend-react-proxy :3005"]
        FnAPI["api-fastapi-azure-function :8080"]

        FlaskFn --> FnAPI
        ViteJWT --> FnAPI
        ReactJWT --> FnAPI
        ReactMSAL --> FnAPI
        ReactServer --> FnAPI
        ReactProxy --> FnAPI
    end

    subgraph IdentityAndGateway["OIDC / gateway family"]
        KC["Keycloak :8300"]
        OIDCAPI["api-fastapi-keycloak :8301"]
        KeycloakSPA["frontend-react-keycloak :3006"]
        Protected["frontend-react-keycloak-protected"]
        ProtectedAdmin["frontend-react-keycloak-protected-admin"]
        ProxyUser["oauth2-proxy-frontend :3007"]
        ProxyAdmin["oauth2-proxy-frontend-admin :3008"]
        APIM["apim-simulator :8302"]

        KeycloakSPA --> OIDCAPI
        KC --> OIDCAPI
        ProxyUser --> Protected
        ProxyAdmin --> ProtectedAdmin
        KC --> ProxyUser
        KC --> ProxyAdmin
        Protected --> APIM
        ProtectedAdmin --> APIM
        APIM --> OIDCAPI
    end

    subgraph MockEasyAuth["Mock Easy Auth family"]
        EasyAuth["easyauth-router :3012"]
        MockFE["frontend-react-easyauth-mock"]
        MockPrincipal["/.auth/me and /.auth/logout"]

        EasyAuth --> MockFE
        EasyAuth --> MockPrincipal
    end

    Browser --> ContainerApp
    Browser --> FunctionApp
    Browser --> IdentityAndGateway
    Browser --> MockEasyAuth
```

## Auth And Routing State Diagram

```mermaid
stateDiagram-v2
    [*] --> ChooseEntry

    ChooseEntry --> Anonymous: stacks 01, 02, 04, 06
    ChooseEntry --> AppJWT: stacks 03, 05, 07, 09, 10
    ChooseEntry --> MSAL: stack 08
    ChooseEntry --> OIDCSPA: stack 11
    ChooseEntry --> ProxyOIDC: stack 12
    ChooseEntry --> MockEasyAuth: stack 13

    ProxyOIDC --> APIMGate
    APIMGate --> UserProduct: /api
    APIMGate --> AdminProduct: /admin/api
    UserProduct --> OIDCBackend
    AdminProduct --> OIDCBackend
```

## Anonymous Container-App Journey

This is the simplest non-Kubernetes path and is the easiest place to reason
about the core application behavior.

```mermaid
sequenceDiagram
    participant B as Browser
    participant F as frontend-html-static or Vite/React
    participant API as api-fastapi-container-app

    B->>F: Load app
    F-->>B: Static assets
    B->>F: Request /api/v1/...
    F->>API: Forward or call backend
    API-->>B: Subnet calculation result
```

## OIDC Plus APIM Journey

Stack 12 is the local compose topology that most closely mirrors the layered
gateway pattern used in the platform stack.

```mermaid
sequenceDiagram
    participant B as Browser
    participant P as oauth2-proxy
    participant K as Keycloak
    participant FE as protected frontend
    participant A as apim-simulator
    participant API as api-fastapi-keycloak

    B->>P: GET /
    P-->>B: Redirect to Keycloak
    B->>K: Authenticate
    K-->>B: Redirect with auth code
    B->>P: /oauth2/callback
    P->>K: Redeem code and fetch user info
    P->>FE: Forward authenticated browser request
    FE-->>B: SPA assets
    B->>A: GET /api/... with bearer token and subscription key
    A->>K: Validate token via JWKS / issuer config
    A->>API: Forward authorized request
    API-->>B: JSON result
```

## Overlay Topology

```mermaid
flowchart LR
    Browser["Browser"]
    TLS["tls-proxy<br/>8443 / 8444"]
    Static["frontend-html-static"]
    CAAPI["api-fastapi-container-app"]
    Azurite["azurite<br/>10000-10002"]
    FnAPI["api-fastapi-azure-function"]
    OIDCAPI["api-fastapi-keycloak"]

    Browser -->|"optional TLS front door"| TLS --> Static -->|" /api/* "| CAAPI
    FnAPI -. "AzureWebJobsStorage overlay" .-> Azurite
    OIDCAPI -. "AzureWebJobsStorage overlay" .-> Azurite
```

## What The Compose Runtime Is Proving

- The same application logic can be exercised through several hosting and auth
  shapes without Kubernetes.
- Frontend choice, auth style, and backend style are intentionally mixed and
  matched rather than hidden behind one blessed local stack.
- Stack 12 is the closest compose analogue to the layered platform path:
  identity gate, frontend, API-management hop, then backend API.
