# Sentiment Compose Architecture

This document explains how `sentiment` works when run directly from the
compose files in this app directory, without Kubernetes or Terraform.

## Scope

- `compose.yml` is the primary local runtime.
- `compose.tls.yml` is a thin overlay that adds a TLS 1.3 front door.
- The runtime path is `sentiment-api -> in-process SST classifier`.

## Compose Files

| File | Role |
| --- | --- |
| [`compose.yml`](../compose.yml) | Main authenticated local stack: Keycloak, oauth2-proxy, edge router, API, UI, and SST inference. |
| [`compose.tls.yml`](../compose.tls.yml) | Optional TLS 1.3 overlay in front of `oauth2-proxy`. |

## System Context

```mermaid
flowchart LR
    Browser["Browser"]
    TLS["tls-proxy<br/>compose.tls.yml<br/>8443/8444"]
    OAuth["oauth2-proxy<br/>8304"]
    KC["Keycloak<br/>8300<br/>realm: sentiment"]
    Edge["edge nginx<br/>internal router"]
    UI["sentiment-auth-frontend<br/>static SPA"]
    API["sentiment-api"]
    SST["SST classifier<br/>loaded inside sentiment-api"]

    Browser -->|"default HTTP"| OAuth
    Browser -->|"optional TLS"| TLS
    TLS --> OAuth
    OAuth <-->|"OIDC login / callback"| KC
    OAuth --> Edge
    Edge -->|" / "| UI
    Edge -->|" /api/* "| API
    API --> SST
```

## Runtime Slices

- `oauth2-proxy` is the browser-facing gate. It handles login and cookie
  management, then forwards all authenticated traffic upstream.
- `edge` is the internal application router. It sends `/api/*` to
  `sentiment-api` and everything else to the static UI.
- `sentiment-api` owns inference directly. The browser never chooses the model
  path.
- The local setup is fully self-contained inside `sentiment-api`.

## Backend State Diagram

```mermaid
stateDiagram-v2
    [*] --> Start
    Start --> LoadClassifier
    LoadClassifier --> WarmClassifier: SENTIMENT_WARM_ON_START=true
    LoadClassifier --> Ready: SENTIMENT_WARM_ON_START=false
    WarmClassifier --> Ready
    Ready --> ClassifyRequest
    ClassifyRequest --> Ready
```

## Authenticated Request Journey

```mermaid
sequenceDiagram
    participant B as Browser
    participant O as oauth2-proxy
    participant K as Keycloak
    participant E as edge
    participant UI as sentiment-auth-frontend
    participant API as sentiment-api
    participant S as SST classifier

    B->>O: GET /
    O-->>B: Redirect to Keycloak login
    B->>K: Authenticate
    K-->>B: Redirect with auth code
    B->>O: /oauth2/callback
    O->>K: Redeem code and validate user
    O->>E: Forward authenticated request
    E->>UI: Serve SPA assets

    B->>O: GET /api/...
    O->>E: Forward authenticated API request
    E->>API: Route /api/*
    API->>S: Classify sentiment in-process
    S-->>API: Label + confidence
    API-->>B: JSON result
```

## TLS Overlay

```mermaid
flowchart LR
    Browser["Browser"]
    TLS["tls-proxy<br/>8443 / 8444"]
    OAuth["oauth2-proxy<br/>4180 internal"]
    Edge["edge nginx"]
    App["UI + API path"]

    Browser -->|"HTTPS 8443"| TLS
    Browser -->|"HTTP 8444"| TLS
    TLS -->|"HTTP upstream"| OAuth
    OAuth --> Edge
    Edge --> App
```

## Request Ownership Cheatsheet

| Hop | Owner in compose runtime | Why it exists |
| --- | --- | --- |
| Browser -> `oauth2-proxy` | OIDC front door | Forces login before the app is reachable. |
| `oauth2-proxy` -> `keycloak` | Identity provider | Handles the local OIDC flow. |
| `oauth2-proxy` -> `edge` | Authenticated upstream | Keeps auth separate from the app router. |
| `edge` -> `sentiment-auth-frontend` | UI split | Static assets and API stay separate. |
| `edge` -> `sentiment-api` | API split | `/api/*` stays on the backend path. |
| `sentiment-api` -> in-process SST classifier | Inference path | Fully local and self-contained. |

## Practical Reading Guide

- Use the system context diagram when you want to know which containers matter.
- Use the state diagram when you want to know when the SST classifier is loaded.
- Use the sequence diagram when debugging auth, routing, or upstream latency.
